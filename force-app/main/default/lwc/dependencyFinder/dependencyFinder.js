import { LightningElement, track } from 'lwc';

const FIELD_METADATA_TYPES = new Set(['Standard Field', 'Custom Field', 'Formula Field']);

export default class DependencyFinder extends LightningElement {
    @track activeTab = 'finder';
    @track searchResponse;
    @track isLoading = false;
    @track error;
    @track blastMetadataType = '';
    @track blastComponentName = '';
    @track selectedMetadataType = '';
    @track selectedObject = '';
    @track selectedComponent = '';

    get isFinderTab() {
        return this.activeTab === 'finder';
    }

    get isSetupTab() {
        return this.activeTab === 'setup';
    }

    get isBlastRadiusTab() {
        return this.activeTab === 'blastRadius';
    }

    get isDataJourneyTab() {
        return this.activeTab === 'dataJourney' && this.showDataJourneyTab;
    }

    get isProcessFlowTab() {
        return this.activeTab === 'processFlow';
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

    get dataJourneyTabClass() {
        return 'slds-tabs_default__item' + (this.isDataJourneyTab ? ' slds-is-active' : '');
    }

    get processFlowTabClass() {
        return 'slds-tabs_default__item' + (this.isProcessFlowTab ? ' slds-is-active' : '');
    }

    get showDataJourneyTab() {
        return FIELD_METADATA_TYPES.has(this.selectedMetadataType);
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

    get dataJourneyTabSelected() {
        return this.isDataJourneyTab ? 'true' : 'false';
    }

    get processFlowTabSelected() {
        return this.isProcessFlowTab ? 'true' : 'false';
    }

    handleTabClick(event) {
        const nextTab = event.currentTarget.dataset.tab;
        if (nextTab === 'dataJourney' && !this.showDataJourneyTab) {
            return;
        }
        this.activeTab = nextTab;
    }

    handleSearch(event) {
        this.searchResponse = event.detail;
        this.error = null;
        this.activeTab = 'finder';
        this.applySelectionState({
            metadataType: event.detail?.metadataType,
            selectedObject: event.detail?.objectName,
            selectedComponent: event.detail?.componentName
        });
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

    handleSelectionChange(event) {
        this.applySelectionState(event.detail || {});
    }

    applySelectionState(detail) {
        this.selectedMetadataType = detail.metadataType || '';

        const normalized = this.normalizeFieldSelection(
            this.selectedMetadataType,
            detail.selectedObject,
            detail.selectedComponent
        );
        this.selectedObject = normalized.objectName;
        this.selectedComponent = normalized.fieldName;

        if (!this.showDataJourneyTab && this.activeTab === 'dataJourney') {
            this.activeTab = 'finder';
        }
    }

    normalizeFieldSelection(metadataType, objectName, componentName) {
        if (!FIELD_METADATA_TYPES.has(metadataType)) {
            return { objectName: '', fieldName: '' };
        }

        const normalizedObject = (objectName || '').trim();
        const normalizedComponent = (componentName || '').trim();
        if (!normalizedComponent) {
            return { objectName: normalizedObject, fieldName: '' };
        }

        const fieldPrefix = normalizedObject ? `${normalizedObject}.` : '';
        if (fieldPrefix && normalizedComponent.startsWith(fieldPrefix)) {
            return {
                objectName: normalizedObject,
                fieldName: normalizedComponent.slice(fieldPrefix.length)
            };
        }

        if (normalizedComponent.includes('.')) {
            const separatorIndex = normalizedComponent.indexOf('.');
            return {
                objectName: normalizedObject || normalizedComponent.substring(0, separatorIndex),
                fieldName: normalizedComponent.substring(separatorIndex + 1)
            };
        }

        return {
            objectName: normalizedObject,
            fieldName: normalizedComponent
        };
    }
}
