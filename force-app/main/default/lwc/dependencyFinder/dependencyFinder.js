import { LightningElement, track } from 'lwc';

export default class DependencyFinder extends LightningElement {
    @track activeTab = 'finder';
    @track searchResponse;
    @track isLoading = false;
    @track error;
    @track blastMetadataType = '';
    @track blastComponentName = '';

    get isFinderTab() {
        return this.activeTab === 'finder';
    }

    get isSetupTab() {
        return this.activeTab === 'setup';
    }

    get isBlastRadiusTab() {
        return this.activeTab === 'blastRadius';
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
