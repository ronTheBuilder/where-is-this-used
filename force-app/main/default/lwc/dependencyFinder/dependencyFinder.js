import { LightningElement, track } from 'lwc';

export default class DependencyFinder extends LightningElement {
    @track activeTab = 'finder';
    @track searchResponse;
    @track isLoading = false;
    @track error;

    get isFinderTab() {
        return this.activeTab === 'finder';
    }

    get isSetupTab() {
        return this.activeTab === 'setup';
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

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleSearch(event) {
        this.searchResponse = event.detail;
        this.error = null;
    }

    handleSearchError(event) {
        this.error = event.detail;
        this.searchResponse = null;
    }

    handleLoading(event) {
        this.isLoading = event.detail;
    }
}
