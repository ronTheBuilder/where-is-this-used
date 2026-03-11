import { LightningElement, track } from 'lwc';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import findUnusedCustomFields from '@salesforce/apex/MetadataPickerController.findUnusedCustomFields';

export default class DependencyFinder extends LightningElement {
    @track activeTab = 'finder';
    @track searchResponse;
    @track isLoading = false;
    @track error;
    @track blastMetadataType = '';
    @track blastComponentName = '';

    // Unused fields scanner
    @track unusedFieldsObject = '';
    @track unusedFieldsResults = [];
    @track unusedFieldsLoading = false;
    @track unusedFieldsError = '';
    @track unusedFieldsScanned = false;
    @track cleanupObjectOptions = [];

    get isFinderTab() {
        return this.activeTab === 'finder';
    }

    get isSetupTab() {
        return this.activeTab === 'setup';
    }

    get isBlastRadiusTab() {
        return this.activeTab === 'blastRadius';
    }

    get isCleanupTab() {
        return this.activeTab === 'cleanup';
    }

    get hasResults() {
        return this.searchResponse != null;
    }

    get finderTabClass() {
        return 'slds-tabs_default__item' + (this.isFinderTab ? ' slds-is-active' : '');
    }

    get setupTabClass() {
        return 'slds-tabs_default__item' + (this.isSetupTab ? ' slds-is-active' : '');
    }

    get blastRadiusTabClass() {
        return 'slds-tabs_default__item' + (this.isBlastRadiusTab ? ' slds-is-active' : '');
    }

    get hasBlastContext() {
        return !!this.blastMetadataType && !!this.blastComponentName;
    }

    get finderTabSelected() {
        return this.isFinderTab ? 'true' : 'false';
    }

    get setupTabSelected() {
        return this.isSetupTab ? 'true' : 'false';
    }

    get blastRadiusTabSelected() {
        return this.isBlastRadiusTab ? 'true' : 'false';
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleSearch(event) {
        this.searchResponse = event.detail;
        this.error = null;
        this.activeTab = 'finder';
    }

    handleSearchError(event) {
        this.error = event.detail;
        this.searchResponse = null;
    }

    handleLoading(event) {
        this.isLoading = event.detail;
    }

    handleBlastRadius(event) {
        this.blastMetadataType = event.detail.metadataType;
        this.blastComponentName = event.detail.componentName;
        this.activeTab = 'blastRadius';
    }

    handleBlastBack() {
        this.activeTab = 'finder';
    }
}
