import { LightningElement, wire, track } from 'lwc';
import getMetadataTypes from '@salesforce/apex/DependencyController.getMetadataTypes';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import getFields from '@salesforce/apex/MetadataPickerController.getFields';
import getFlows from '@salesforce/apex/MetadataPickerController.getFlows';
import getAllFlows from '@salesforce/apex/MetadataPickerController.getAllFlows';
import getApexClasses from '@salesforce/apex/MetadataPickerController.getApexClasses';
import searchDependencies from '@salesforce/apex/DependencyController.searchDependencies';

// Suffixes/patterns for non-business objects (history tracking, sharing, feeds, etc.)
const NOISE_SUFFIXES = ['changeevent', 'history', 'share', 'feed', 'tag'];

function isNoiseObject(apiName) {
    if (!apiName) return false;
    const lower = apiName.toLowerCase();
    // Custom objects (__c) are never noise
    if (lower.endsWith('__c')) return false;
    // Platform events & custom metadata handled by their own pickers
    if (lower.endsWith('__e') || lower.endsWith('__mdt') || lower.endsWith('__b')) return true;
    // Standard & custom object system children
    for (const suffix of NOISE_SUFFIXES) {
        if (lower.endsWith(suffix)) return true;
        if (lower.endsWith('__' + suffix)) return true;
    }
    return false;
}

export default class MetadataPicker extends LightningElement {
    @track metadataType = '';
    @track selectedObject = '';
    @track selectedComponent = '';
    @track metadataTypeOptions = [];
    @track objectOptions = [];
    @track componentOptions = [];
    @track isSearchDisabled = true;

    // Filter toggles
    @track hideNoiseObjects = true;
    @track activeFlowsOnly = true;

    // Recent searches
    @track recentSearches = [];

    // Raw unfiltered data
    _allObjectOptions = [];
    _allFlowOptions = [];
    _activeFlowOptions = [];

    // Show object picker for field types
    get showObjectPicker() {
        return this.metadataType === 'Standard Field' || this.metadataType === 'Custom Field';
    }

    // Show the object filter toggle
    get showObjectFilter() {
        return this.showObjectPicker && this._allObjectOptions.length > 0;
    }

    // Show the flow filter toggle
    get showFlowFilter() {
        return this.metadataType === 'Flow';
    }

    // Show component picker (field, flow, or class)
    get showComponentPicker() {
        return this.metadataType !== '';
    }

    get componentLabel() {
        if (this.metadataType === 'Standard Field' || this.metadataType === 'Custom Field') return 'Field';
        if (this.metadataType === 'Flow') return 'Flow';
        if (this.metadataType === 'Apex Class') return 'Apex Class';
        return 'Component';
    }

    get hasRecentSearches() {
        return this.recentSearches.length > 0;
    }

    connectedCallback() {
        this.loadRecentSearches();
    }

    loadRecentSearches() {
        try {
            const stored = localStorage.getItem('witu_recent_searches');
            this.recentSearches = stored ? JSON.parse(stored) : [];
        } catch (e) {
            this.recentSearches = [];
        }
    }

    saveRecentSearch(metadataType, componentName, objectName) {
        const entry = {
            key: metadataType + ':' + componentName,
            metadataType,
            componentName,
            objectName: objectName || null,
            label: componentName + ' (' + metadataType + ')',
            timestamp: Date.now()
        };
        // Remove duplicate, add to front, cap at 10
        let searches = this.recentSearches.filter(s => s.key !== entry.key);
        searches.unshift(entry);
        searches = searches.slice(0, 10);
        this.recentSearches = searches;
        try {
            localStorage.setItem('witu_recent_searches', JSON.stringify(searches));
        } catch (e) { /* quota exceeded — ignore */ }
    }

    handleRecentSearchClick(event) {
        const key = event.currentTarget.dataset.key;
        const entry = this.recentSearches.find(s => s.key === key);
        if (!entry) return;

        this.metadataType = entry.metadataType;
        this.selectedComponent = entry.componentName;
        if (entry.objectName) {
            this.selectedObject = entry.objectName;
        }
        this.updateSearchState();
        // Auto-trigger search
        this.handleSearch();
    }

    handleClearRecent() {
        this.recentSearches = [];
        try {
            localStorage.removeItem('witu_recent_searches');
        } catch (e) { /* ignore */ }
    }

    get objectFilterLabel() {
        const total = this._allObjectOptions.length;
        const shown = this.objectOptions.length;
        return `Hide system objects (${shown}/${total})`;
    }

    get flowFilterLabel() {
        return 'Active flows only';
    }

    @wire(getMetadataTypes)
    wiredMetadataTypes({ data, error }) {
        if (data) {
            this.metadataTypeOptions = data.map(t => ({ label: t, value: t }));
        }
        if (error) {
            this.fireError('Failed to load metadata types: ' + this.reduceError(error));
        }
    }

    handleMetadataTypeChange(event) {
        this.metadataType = event.detail.value;
        this.selectedObject = '';
        this.selectedComponent = '';
        this.componentOptions = [];
        this.updateSearchState();

        if (this.showObjectPicker) {
            this.loadObjects();
        } else if (this.metadataType === 'Flow') {
            this.loadFlows();
        } else if (this.metadataType === 'Apex Class') {
            this.loadApexClasses();
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedComponent = '';
        this.componentOptions = [];
        this.updateSearchState();

        if (this.selectedObject) {
            this.loadFields(this.selectedObject);
        }
    }

    handleComponentChange(event) {
        this.selectedComponent = event.detail.value;
        this.updateSearchState();
    }

    handleObjectFilterToggle(event) {
        this.hideNoiseObjects = event.target.checked;
        this.applyObjectFilter();
        // Reset selection if current object is now hidden
        if (this.selectedObject && !this.objectOptions.find(o => o.value === this.selectedObject)) {
            this.selectedObject = '';
            this.selectedComponent = '';
            this.componentOptions = [];
            this.updateSearchState();
        }
    }

    handleFlowFilterToggle(event) {
        this.activeFlowsOnly = event.target.checked;
        this.applyFlowFilter();
        // Reset selection if current flow is now hidden
        if (this.selectedComponent && !this.componentOptions.find(o => o.value === this.selectedComponent)) {
            this.selectedComponent = '';
            this.updateSearchState();
        }
    }

    applyObjectFilter() {
        if (this.hideNoiseObjects) {
            this.objectOptions = this._allObjectOptions.filter(o => !isNoiseObject(o.value));
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
            this._allObjectOptions = data.map(o => ({ label: o.label, value: o.value }));
            this.applyObjectFilter();
        } catch (error) {
            this.fireError('Failed to load objects: ' + this.reduceError(error));
        }
    }

    async loadFields(objectName) {
        try {
            const data = await getFields({ objectName });
            const typeFilter = this.metadataType;
            this.componentOptions = data
                .filter(f => f.metadataType === typeFilter)
                .map(f => ({ label: f.label + ' (' + f.value + ')', value: this.selectedObject + '.' + f.value }));
        } catch (error) {
            this.fireError('Failed to load fields: ' + this.reduceError(error));
        }
    }

    async loadFlows() {
        try {
            // Load active flows
            const activeData = await getFlows();
            this._activeFlowOptions = activeData.map(f => ({ label: f.label, value: f.value }));

            // Load all flows (with status in label)
            try {
                const allData = await getAllFlows();
                this._allFlowOptions = allData.map(f => ({ label: f.label, value: f.value }));
            } catch (err) {
                // Fallback: all = active if getAllFlows fails
                this._allFlowOptions = [...this._activeFlowOptions];
            }

            this.applyFlowFilter();
        } catch (error) {
            this.fireError('Failed to load flows: ' + this.reduceError(error));
        }
    }

    async loadApexClasses() {
        try {
            const data = await getApexClasses();
            this.componentOptions = data.map(c => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError('Failed to load Apex classes: ' + this.reduceError(error));
        }
    }

    updateSearchState() {
        this.isSearchDisabled = !this.metadataType || !this.selectedComponent;
    }

    async handleSearch() {
        if (this.isSearchDisabled) return;

        this.fireLoading(true);
        try {
            const response = await searchDependencies({
                metadataType: this.metadataType,
                componentName: this.selectedComponent
            });
            this.saveRecentSearch(this.metadataType, this.selectedComponent, this.selectedObject);
            this.dispatchEvent(new CustomEvent('search', { detail: response }));
        } catch (error) {
            this.fireError(this.reduceError(error));
        } finally {
            this.fireLoading(false);
        }
    }

    fireError(message) {
        this.dispatchEvent(new CustomEvent('searcherror', { detail: message }));
    }

    fireLoading(isLoading) {
        this.dispatchEvent(new CustomEvent('loading', { detail: isLoading }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
