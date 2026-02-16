import { LightningElement, wire, track } from 'lwc';
import getMetadataTypes from '@salesforce/apex/DependencyController.getMetadataTypes';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import getFields from '@salesforce/apex/MetadataPickerController.getFields';
import getFlows from '@salesforce/apex/MetadataPickerController.getFlows';
import getApexClasses from '@salesforce/apex/MetadataPickerController.getApexClasses';
import searchDependencies from '@salesforce/apex/DependencyController.searchDependencies';

export default class MetadataPicker extends LightningElement {
    @track metadataType = '';
    @track selectedObject = '';
    @track selectedComponent = '';
    @track metadataTypeOptions = [];
    @track objectOptions = [];
    @track componentOptions = [];
    @track isSearchDisabled = true;

    // Show object picker for field types
    get showObjectPicker() {
        return this.metadataType === 'Standard Field' || this.metadataType === 'Custom Field';
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
            // Filter based on metadata type selection
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
            const data = await getFlows();
            this.componentOptions = data.map(f => ({ label: f.label, value: f.value }));
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
