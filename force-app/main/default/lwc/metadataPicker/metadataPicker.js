import { LightningElement, wire, track } from 'lwc';
import getMetadataTypes from '@salesforce/apex/DependencyController.getMetadataTypes';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import getFields from '@salesforce/apex/MetadataPickerController.getFields';
import getFlows from '@salesforce/apex/MetadataPickerController.getFlows';
import searchApexClasses from '@salesforce/apex/MetadataPickerController.searchApexClasses';
import getRecordTypes from '@salesforce/apex/MetadataPickerController.getRecordTypes';
import getCustomLabels from '@salesforce/apex/MetadataPickerController.getCustomLabels';
import getValidationRules from '@salesforce/apex/MetadataPickerController.getValidationRules';
import getPlatformEvents from '@salesforce/apex/MetadataPickerController.getPlatformEvents';
import getCustomMetadataTypes from '@salesforce/apex/MetadataPickerController.getCustomMetadataTypes';
import getFormulaFields from '@salesforce/apex/MetadataPickerController.getFormulaFields';
import searchDependencies from '@salesforce/apex/DependencyController.searchDependencies';

/** Debounce delay for Apex class search (ms) */
const APEX_SEARCH_DEBOUNCE_MS = 300;

export default class MetadataPicker extends LightningElement {
    @track metadataType = '';
    @track selectedObject = '';
    @track selectedComponent = '';
    @track apexSearchTerm = '';
    @track metadataTypeOptions = [];
    @track objectOptions = [];
    @track componentOptions = [];
    @track isSearchDisabled = true;
    _apexSearchTimeout = null;

    /** Show object picker for types that require object selection first */
    get showObjectPicker() {
        const objectTypes = [
            'Standard Field',
            'Custom Field',
            'Record Type',
            'Validation Rule',
            'Formula Field'
        ];
        return objectTypes.includes(this.metadataType);
    }

    /** Show component picker (field, flow, class, etc.) */
    get showComponentPicker() {
        return this.metadataType !== '';
    }

    /** Apex Class uses search-as-you-type instead of static dropdown */
    get showApexSearch() {
        return this.metadataType === 'Apex Class';
    }

    /** Component picker for types that use a single combobox (not Apex search) */
    get showComponentPickerNonApex() {
        return this.metadataType !== '' && this.metadataType !== 'Apex Class';
    }

    get componentLabel() {
        const labels = {
            'Standard Field': 'Field',
            'Custom Field': 'Field',
            'Flow': 'Flow',
            'Apex Class': 'Apex Class',
            'Record Type': 'Record Type',
            'Custom Label': 'Custom Label',
            'Platform Event': 'Platform Event',
            'Validation Rule': 'Validation Rule',
            'Custom Metadata Type': 'Custom Metadata Type',
            'Formula Field': 'Formula Field'
        };
        return labels[this.metadataType] || 'Component';
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
        this.apexSearchTerm = '';
        this.componentOptions = [];
        this.updateSearchState();

        if (this.showObjectPicker) {
            this.loadObjects();
        } else if (this.metadataType === 'Flow') {
            this.loadFlows();
        } else if (this.metadataType === 'Apex Class') {
            this.loadApexClasses('');
        } else if (this.metadataType === 'Record Type') {
            this.componentOptions = [];
        } else if (this.metadataType === 'Custom Label') {
            this.loadCustomLabels();
        } else if (this.metadataType === 'Platform Event') {
            this.loadPlatformEvents();
        } else if (this.metadataType === 'Validation Rule') {
            this.componentOptions = [];
        } else if (this.metadataType === 'Formula Field') {
            this.componentOptions = [];
        } else if (this.metadataType === 'Custom Metadata Type') {
            this.loadCustomMetadataTypes();
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedComponent = '';
        this.componentOptions = [];
        this.updateSearchState();

        if (!this.selectedObject) return;

        if (this.metadataType === 'Standard Field' || this.metadataType === 'Custom Field') {
            this.loadFields(this.selectedObject);
        } else if (this.metadataType === 'Record Type') {
            this.loadRecordTypes(this.selectedObject);
        } else if (this.metadataType === 'Validation Rule') {
            this.loadValidationRules(this.selectedObject);
        } else if (this.metadataType === 'Formula Field') {
            this.loadFormulaFields(this.selectedObject);
        }
    }

    handleComponentChange(event) {
        this.selectedComponent = event.detail.value;
        this.updateSearchState();
    }

    handleApexSearchChange(event) {
        this.apexSearchTerm = event.target.value;
        if (this._apexSearchTimeout) {
            clearTimeout(this._apexSearchTimeout);
        }
        this._apexSearchTimeout = setTimeout(() => {
            this.loadApexClasses(this.apexSearchTerm);
            this._apexSearchTimeout = null;
        }, APEX_SEARCH_DEBOUNCE_MS);
    }

    async loadObjects() {
        try {
            const data = await getObjects();
            this.objectOptions = data.map(o => ({ label: o.label, value: o.value }));
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
                .map(f => ({
                    label: f.label + " (" + f.value + ")",
                    value: this.selectedObject + "." + f.value
                }));
        } catch (error) {
            this.fireError('Failed to load fields: ' + this.reduceError(error));
        }
    }

    async loadFlows() {
        try {
            const data = await getFlows();
            this.componentOptions = data.map(f => ({ label: f.label, value: f.value }));
        } catch (error) {
            this.fireError('Failed to load flows: ' + this.reduceError(error));
        }
    }

    async loadApexClasses(searchTerm) {
        try {
            const term = typeof searchTerm === "string" ? searchTerm : this.apexSearchTerm;
            const data = await searchApexClasses({ searchTerm: term || null });
            this.componentOptions = data.map(c => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError('Failed to search Apex classes: ' + this.reduceError(error));
        }
    }

    async loadRecordTypes(objectName) {
        try {
            const data = await getRecordTypes({ objectName });
            this.componentOptions = data.map(r => ({ label: r.label, value: r.value }));
        } catch (error) {
            this.fireError('Failed to load record types: ' + this.reduceError(error));
        }
    }

    async loadCustomLabels() {
        try {
            const data = await getCustomLabels();
            this.componentOptions = data.map(c => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError('Failed to load custom labels: ' + this.reduceError(error));
        }
    }

    async loadValidationRules(objectName) {
        try {
            const data = await getValidationRules({ objectName });
            this.componentOptions = data.map(v => ({ label: v.label, value: v.value }));
        } catch (error) {
            this.fireError('Failed to load validation rules: ' + this.reduceError(error));
        }
    }

    async loadFormulaFields(objectName) {
        try {
            const data = await getFormulaFields({ objectName });
            this.componentOptions = data.map(f => ({ label: f.label, value: f.value }));
        } catch (error) {
            this.fireError('Failed to load formula fields: ' + this.reduceError(error));
        }
    }

    async loadPlatformEvents() {
        try {
            const data = await getPlatformEvents();
            this.componentOptions = data.map(p => ({ label: p.label, value: p.value }));
        } catch (error) {
            this.fireError('Failed to load platform events: ' + this.reduceError(error));
        }
    }

    async loadCustomMetadataTypes() {
        try {
            const data = await getCustomMetadataTypes();
            this.componentOptions = data.map(c => ({ label: c.label, value: c.value }));
        } catch (error) {
            this.fireError('Failed to load custom metadata types: ' + this.reduceError(error));
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
