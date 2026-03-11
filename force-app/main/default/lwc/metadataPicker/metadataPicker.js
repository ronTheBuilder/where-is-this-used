import { LightningElement, wire, track } from "lwc";
import getMetadataTypes from "@salesforce/apex/DependencyController.getMetadataTypes";
import getObjects from "@salesforce/apex/MetadataPickerController.getObjects";
import getFields from "@salesforce/apex/MetadataPickerController.getFields";
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

/** Debounce delay for Apex class search (ms) */
const APEX_SEARCH_DEBOUNCE_MS = 300;

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

export default class MetadataPicker extends LightningElement {
    @track metadataType = "";
    @track selectedObject = "";
    @track selectedComponent = "";
    @track apexSearchTerm = "";
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
    _apexSearchTimeout = null;
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

    /** Apex Class uses search-as-you-type instead of static dropdown */
    get showApexSearch() {
        return this.metadataType === "Apex Class";
    }

    /** Component picker for types that use a single combobox (not Apex search) */
    get showComponentPickerNonApex() {
        return this.metadataType !== "" && this.metadataType !== "Apex Class";
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

    loadRecentSearches() {
        try {
            const stored = window.localStorage.getItem("witu_recent_searches");
            this.recentSearches = stored ? JSON.parse(stored) : [];
        } catch (e) {
            this.recentSearches = [];
        }
    }

    saveRecentSearch(metadataType, componentName, objectName) {
        const entry = {
            key: metadataType + ":" + componentName,
            metadataType,
            componentName,
            objectName: objectName || null,
            label: componentName + " (" + metadataType + ")",
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

    handleRecentSearchClick(event) {
        const key = event.currentTarget.dataset.key;
        const entry = this.recentSearches.find((s) => s.key === key);
        if (!entry) {
            return;
        }

        this.metadataType = entry.metadataType;
        this.selectedComponent = entry.componentName;
        if (entry.objectName) {
            this.selectedObject = entry.objectName;
        }
        this.updateSearchState();
        this.handleSearch();
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
        this.apexSearchTerm = "";
        this.componentOptions = [];
        this.updateSearchState();

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
    }

    handleApexSearchChange(event) {
        this.apexSearchTerm = event.target.value;
        if (this._apexSearchTimeout !== null) {
            window.clearTimeout(this._apexSearchTimeout);
        }
        this._apexSearchTimeout = window.setTimeout(() => {
            this.loadApexClasses(this.apexSearchTerm);
            this._apexSearchTimeout = null;
        }, APEX_SEARCH_DEBOUNCE_MS);
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
            const data = await getFields({ objectName });
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
            const term = typeof searchTerm === "string" ? searchTerm : this.apexSearchTerm;
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

