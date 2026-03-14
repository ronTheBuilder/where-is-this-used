import { LightningElement, wire, track } from "lwc";
import getMetadataTypes from "@salesforce/apex/DependencyController.getMetadataTypes";
import getObjects from "@salesforce/apex/MetadataPickerController.getObjects";
import getFieldsEnriched from "@salesforce/apex/MetadataPickerController.getFieldsEnriched";
import getFlows from "@salesforce/apex/MetadataPickerController.getFlows";
import getAllFlows from "@salesforce/apex/MetadataPickerController.getAllFlows";
import searchApexClasses from "@salesforce/apex/MetadataPickerController.searchApexClasses";
import getRecordTypes from "@salesforce/apex/MetadataPickerController.getRecordTypes";
import getCustomLabels from "@salesforce/apex/MetadataPickerController.getCustomLabels";
import getValidationRules from "@salesforce/apex/MetadataPickerController.getValidationRules";
import getPlatformEvents from "@salesforce/apex/MetadataPickerController.getPlatformEvents";
import getCustomMetadataTypes from "@salesforce/apex/MetadataPickerController.getCustomMetadataTypes";
import getFormulaFields from "@salesforce/apex/MetadataPickerController.getFormulaFields";
import searchDependencies from "@salesforce/apex/DependencyController.searchDependencies";

/** Debounce delay for server-side search (ms) */
const SEARCH_DEBOUNCE_MS = 300;

// Suffixes/patterns for non-business objects (history tracking, sharing, feeds, etc.)
const NOISE_SUFFIXES = ["changeevent", "history", "share", "feed", "tag"];

function isNoiseObject(apiName) {
    if (!apiName) {
        return false;
    }
    const lower = apiName.toLowerCase();
    // Custom objects (__c) are never noise
    if (lower.endsWith("__c")) {
        return false;
    }
    // Platform events & custom metadata handled by their own pickers
    if (lower.endsWith("__e") || lower.endsWith("__mdt") || lower.endsWith("__b")) {
        return true;
    }
    // Standard & custom object system children
    for (const suffix of NOISE_SUFFIXES) {
        if (lower.endsWith(suffix)) {
            return true;
        }
        if (lower.endsWith("__" + suffix)) {
            return true;
        }
    }
    return false;
}

function buildRecentSearchKey(metadataType, componentName, objectName) {
    return [metadataType || "", objectName || "", componentName || ""].join(":");
}

function buildRecentSearchLabel(metadataType, componentName, objectName) {
    let label = (metadataType || "") + ": " + (componentName || "");
    if (objectName) {
        label += " [" + objectName + "]";
    }
    return label;
}

export default class MetadataPicker extends LightningElement {
    @track metadataType = "";
    @track selectedObject = "";
    @track selectedComponent = "";
    @track metadataTypeOptions = [];
    @track objectOptions = [];
    @track componentOptions = [];
    @track isSearchDisabled = true;

    // Filter toggles
    @track hideNoiseObjects = true;
    @track activeFlowsOnly = true;

    // Recent searches
    @track recentSearches = [];

    // Internal state
    _searchTimeout = null;
    _recentSearchRequestId = 0;
    _allObjectOptions = [];
    _allFlowOptions = [];
    _activeFlowOptions = [];

    /** Show object picker for types that require object selection first */
    get showObjectPicker() {
        const objectTypes = [
            "Standard Field",
            "Custom Field",
            "Record Type",
            "Validation Rule",
            "Formula Field"
        ];
        return objectTypes.includes(this.metadataType);
    }

    // Show the object filter toggle
    get showObjectFilter() {
        return this.showObjectPicker && this._allObjectOptions.length > 0;
    }

    // Show the flow filter toggle
    get showFlowFilter() {
        return this.metadataType === "Flow";
    }

    /** Show component picker (field, flow, class, etc.) */
    get showComponentPicker() {
        return this.metadataType !== "";
    }

    /** Whether the current type is Apex Class (needs server-side search) */
    get isApexClass() {
        return this.metadataType === "Apex Class";
    }

    /** Column width: narrower when object picker is also shown */
    get componentPickerColClass() {
        return this.showObjectPicker
            ? "slds-col slds-size_1-of-1 slds-medium-size_3-of-12"
            : "slds-col slds-size_1-of-1 slds-medium-size_4-of-12";
    }

    get componentPlaceholder() {
        if (this.isApexClass) {
            return "Type to search...";
        }
        return "Search...";
    }

    get componentLabel() {
        const labels = {
            "Standard Field": "Field",
            "Custom Field": "Field",
            "Flow": "Flow",
            "Apex Class": "Apex Class",
            "Record Type": "Record Type",
            "Custom Label": "Custom Label",
            "Platform Event": "Platform Event",
            "Validation Rule": "Validation Rule",
            "Custom Metadata Type": "Custom Metadata Type",
            "Formula Field": "Formula Field"
        };
        return labels[this.metadataType] || "Component";
    }

    get hasRecentSearches() {
        return this.recentSearches.length > 0;
    }

    get objectFilterLabel() {
        const total = this._allObjectOptions.length;
        const shown = this.objectOptions.length;
        return `Hide system objects (${shown}/${total})`;
    }

    get flowFilterLabel() {
        return "Active flows only";
    }

    connectedCallback() {
        this.loadRecentSearches();
    }

    disconnectedCallback() {
        if (this._searchTimeout !== null) {
            window.clearTimeout(this._searchTimeout);
            this._searchTimeout = null;
        }
    }

    loadRecentSearches() {
        try {
            const stored = window.localStorage.getItem("witu_recent_searches");
            this.recentSearches = stored ? JSON.parse(stored) : [];
        } catch (e) {
            this.recentSearches = [];
        }
    }

    saveRecentSearch(metadataType, componentName, objectName) {
        const key = buildRecentSearchKey(metadataType, componentName, objectName);
        const entry = {
            key,
            metadataType,
            componentName,
            objectName: objectName || null,
            label: buildRecentSearchLabel(metadataType, componentName, objectName),
            timestamp: Date.now()
        };
        let searches = this.recentSearches.filter((s) => s.key !== entry.key);
        searches.unshift(entry);
        searches = searches.slice(0, 10);
        this.recentSearches = searches;
        try {
            window.localStorage.setItem("witu_recent_searches", JSON.stringify(searches));
        } catch (e) {
            // ignore quota errors
        }
    }

    async handleRecentSearchClick(event) {
        const key = event.currentTarget.dataset.key;
        const entry = this.recentSearches.find((s) => s.key === key);
        if (!entry) {
            return;
        }
        const requestId = this._recentSearchRequestId + 1;
        this._recentSearchRequestId = requestId;

        this.metadataType = entry.metadataType;
        this.selectedObject = entry.objectName || "";
        this.selectedComponent = "";
        this.componentOptions = [];

        if (this.showObjectPicker) {
            await this.loadObjects();
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
            if (entry.objectName) {
                this.selectedObject = entry.objectName;
                if (this.metadataType === "Standard Field" || this.metadataType === "Custom Field") {
                    await this.loadFields(entry.objectName);
                } else if (this.metadataType === "Record Type") {
                    await this.loadRecordTypes(entry.objectName);
                } else if (this.metadataType === "Validation Rule") {
                    await this.loadValidationRules(entry.objectName);
                } else if (this.metadataType === "Formula Field") {
                    await this.loadFormulaFields(entry.objectName);
                }
                if (requestId !== this._recentSearchRequestId) {
                    return;
                }
            }
        } else if (this.metadataType === "Flow") {
            await this.loadFlows();
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
        } else if (this.metadataType === "Apex Class") {
            await this.loadApexClasses("");
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
        } else if (this.metadataType === "Custom Label") {
            await this.loadCustomLabels();
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
        } else if (this.metadataType === "Platform Event") {
            await this.loadPlatformEvents();
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
        } else if (this.metadataType === "Custom Metadata Type") {
            await this.loadCustomMetadataTypes();
            if (requestId !== this._recentSearchRequestId) {
                return;
            }
        }

        this.selectedComponent = entry.componentName;
        this.updateSearchState();
        this.fireSelectionChange();
        if (requestId !== this._recentSearchRequestId) {
            return;
        }
        await this.handleSearch();
    }

    handleClearRecent() {
        this.recentSearches = [];
        try {
            window.localStorage.removeItem("witu_recent_searches");
        } catch (e) {
            // ignore
        }
    }

    @wire(getMetadataTypes)
    wiredMetadataTypes({ data, error }) {
        if (data) {
            this.metadataTypeOptions = data.map((t) => ({ label: t, value: t }));
        }
        if (error) {
            this.fireError("Failed to load metadata types: " + this.reduceError(error));
        }
    }

    handleMetadataTypeChange(event) {
        this.metadataType = event.detail.value;
        this.selectedObject = "";
        this.selectedComponent = "";
        this.componentOptions = [];
        this.updateSearchState();
        this.fireSelectionChange();

        if (this.showObjectPicker) {
            this.loadObjects();
        } else if (this.metadataType === "Flow") {
            this.loadFlows();
        } else if (this.metadataType === "Apex Class") {
            this.loadApexClasses("");
        } else if (this.metadataType === "Record Type") {
            this.componentOptions = [];
        } else if (this.metadataType === "Custom Label") {
            this.loadCustomLabels();
        } else if (this.metadataType === "Platform Event") {
            this.loadPlatformEvents();
        } else if (this.metadataType === "Validation Rule") {
            this.componentOptions = [];
        } else if (this.metadataType === "Formula Field") {
            this.componentOptions = [];
        } else if (this.metadataType === "Custom Metadata Type") {
            this.loadCustomMetadataTypes();
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedComponent = "";
        this.componentOptions = [];
        this.updateSearchState();
        this.fireSelectionChange();

        if (!this.selectedObject) {
            return;
        }

        if (this.metadataType === "Standard Field" || this.metadataType === "Custom Field") {
            this.loadFields(this.selectedObject);
        } else if (this.metadataType === "Record Type") {
            this.loadRecordTypes(this.selectedObject);
        } else if (this.metadataType === "Validation Rule") {
            this.loadValidationRules(this.selectedObject);
        } else if (this.metadataType === "Formula Field") {
            this.loadFormulaFields(this.selectedObject);
        }
    }

    handleComponentChange(event) {
        this.selectedComponent = event.detail.value;
        this.updateSearchState();
        this.fireSelectionChange();
    }

    handleComponentSearch(event) {
        const term = event.detail.searchTerm;
        if (this._searchTimeout !== null) {
            window.clearTimeout(this._searchTimeout);
        }
        this._searchTimeout = window.setTimeout(() => {
            this.loadApexClasses(term);
            this._searchTimeout = null;
        }, SEARCH_DEBOUNCE_MS);
    }

    handleObjectFilterToggle(event) {
        this.hideNoiseObjects = event.target.checked;
        this.applyObjectFilter();
        if (this.selectedObject && !this.objectOptions.find((o) => o.value === this.selectedObject)) {
            this.selectedObject = "";
            this.selectedComponent = "";
            this.componentOptions = [];
            this.updateSearchState();
        }
    }

    handleFlowFilterToggle(event) {
        this.activeFlowsOnly = event.target.checked;
        this.applyFlowFilter();
        if (this.selectedComponent && !this.componentOptions.find((o) => o.value === this.selectedComponent)) {
            this.selectedComponent = "";
            this.updateSearchState();
        }
    }

    applyObjectFilter() {
        if (this.hideNoiseObjects) {
            this.objectOptions = this._allObjectOptions.filter((o) => !isNoiseObject(o.value));
        } else {
            this.objectOptions = [...this._allObjectOptions];
        }
    }

    applyFlowFilter() {
        if (this.activeFlowsOnly) {
            this.componentOptions = [...this._activeFlowOptions];
        } else {
            this.componentOptions = [...this._allFlowOptions];
        }
    }

    async loadObjects() {
        try {
            const data = await getObjects();
            this._allObjectOptions = data.map((o) => ({ label: o.label, value: o.value }));
            this.applyObjectFilter();
        } catch (error) {
            this.fireError("Failed to load objects: " + this.reduceError(error));
        }
    }

    async loadFields(objectName) {
        try {
            const data = await getFieldsEnriched({ objectName });
            const typeFilter = this.metadataType;
            this.componentOptions = data
                .filter((f) => f.metadataType === typeFilter)
                .map((f) => ({
                    label: f.label + " (" + f.value + ")",
                    value: this.selectedObject + "." + f.value
                }));
        } catch (error) {
            this.fireError("Failed to load fields: " + this.reduceError(error));
        }
    }

    async loadFlows() {
        try {
            const activeData = await getFlows();
            this._activeFlowOptions = activeData.map((f) => ({ label: f.label, value: f.value }));
            try {
                const allData = await getAllFlows();
                this._allFlowOptions = allData.map((f) => ({ label: f.label, value: f.value }));
            } catch (err) {
                this._allFlowOptions = [...this._activeFlowOptions];
            }
            this.applyFlowFilter();
        } catch (error) {
            this.fireError("Failed to load flows: " + this.reduceError(error));
        }
    }

    async loadApexClasses(searchTerm) {
        try {
            const term = typeof searchTerm === "string" ? searchTerm : "";
            const data = await searchApexClasses({ searchTerm: term || null });
            this.componentOptions = data.map((c) => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError("Failed to search Apex classes: " + this.reduceError(error));
        }
    }

    async loadRecordTypes(objectName) {
        try {
            const data = await getRecordTypes({ objectName });
            this.componentOptions = data.map((r) => ({ label: r.label, value: r.value }));
        } catch (error) {
            this.fireError("Failed to load record types: " + this.reduceError(error));
        }
    }

    async loadCustomLabels() {
        try {
            const data = await getCustomLabels();
            this.componentOptions = data.map((c) => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError("Failed to load custom labels: " + this.reduceError(error));
        }
    }

    async loadValidationRules(objectName) {
        try {
            const data = await getValidationRules({ objectName });
            this.componentOptions = data.map((v) => ({ label: v.label, value: v.value }));
        } catch (error) {
            this.fireError("Failed to load validation rules: " + this.reduceError(error));
        }
    }

    async loadFormulaFields(objectName) {
        try {
            const data = await getFormulaFields({ objectName });
            this.componentOptions = data.map((f) => ({ label: f.label, value: f.value }));
        } catch (error) {
            this.fireError("Failed to load formula fields: " + this.reduceError(error));
        }
    }

    async loadPlatformEvents() {
        try {
            const data = await getPlatformEvents();
            this.componentOptions = data.map((p) => ({ label: p.label, value: p.value }));
        } catch (error) {
            this.fireError("Failed to load platform events: " + this.reduceError(error));
        }
    }

    async loadCustomMetadataTypes() {
        try {
            const data = await getCustomMetadataTypes();
            this.componentOptions = data.map((c) => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError("Failed to load custom metadata types: " + this.reduceError(error));
        }
    }

    updateSearchState() {
        this.isSearchDisabled = this.metadataType === "" || this.selectedComponent === "";
    }

    async handleSearch() {
        if (this.isSearchDisabled) {
            return;
        }

        this.fireLoading(true);
        try {
            const response = await searchDependencies({
                metadataType: this.metadataType,
                componentName: this.selectedComponent
            });
            this.saveRecentSearch(this.metadataType, this.selectedComponent, this.selectedObject);
            this.dispatchEvent(new CustomEvent("search", { detail: response }));
        } catch (error) {
            this.fireError(this.reduceError(error));
        } finally {
            this.fireLoading(false);
        }
    }

    fireError(message) {
        this.dispatchEvent(new CustomEvent("searcherror", { detail: message }));
    }

    fireLoading(isLoading) {
        this.dispatchEvent(new CustomEvent("loading", { detail: isLoading }));
    }

    fireSelectionChange() {
        this.dispatchEvent(
            new CustomEvent("selectionchange", {
                detail: {
                    metadataType: this.metadataType,
                    selectedObject: this.selectedObject,
                    selectedComponent: this.selectedComponent
                }
            })
        );
    }

    reduceError(error) {
        if (typeof error === "string") {
            return error;
        }
        if (error && error.body && typeof error.body.message === "string") {
            return error.body.message;
        }
        if (error && typeof error.message === "string") {
            return error.message;
        }
        try {
            return JSON.stringify(error);
        } catch (e) {
            return "Unknown error";
        }
    }
}
