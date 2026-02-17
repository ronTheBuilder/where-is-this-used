import { LightningElement, api, track } from 'lwc';

const TYPE_ICONS = {
    ApexClass: 'custom:custom24',
    ApexTrigger: 'custom:custom24',
    Flow: 'standard:flow',
    ValidationRule: 'standard:record',
    Layout: 'standard:record_lookup',
    LightningComponentBundle: 'standard:lightning_component',
    AuraDefinitionBundle: 'standard:lightning_component',
    Page: 'standard:visualforce_page',
    EmailTemplate: 'standard:email',
    CustomField: 'standard:custom_notification',
    FlowDefinition: 'standard:flow'
};

const BADGE_VARIANTS = {
    Read: 'success',
    Write: 'warning',
    'Read & Write': 'error'
};

export default class DependencyResults extends LightningElement {
    @api searchResponse;
    @track activeFilter = 'all';
    @track expandedGroups = {};

    get componentName() {
        return this.searchResponse?.componentName || '';
    }

    get metadataType() {
        return this.searchResponse?.metadataType || '';
    }

    get totalCount() {
        return this.searchResponse?.totalCount || 0;
    }

    get groupCount() {
        return this.searchResponse?.groups?.length || 0;
    }

    get limitReached() {
        return this.searchResponse?.limitReached || false;
    }

    get warningMessage() {
        return this.searchResponse?.warningMessage;
    }

    get filterBadges() {
        const groups = this.searchResponse?.groups || [];
        const all = { label: 'All', value: 'all', count: this.totalCount, isActive: this.activeFilter === 'all', badgeClass: this.activeFilter === 'all' ? 'slds-m-right_xx-small slds-badge_inverse' : 'slds-m-right_xx-small' };
        const typeBadges = groups.map(g => ({
            label: g.componentType,
            value: g.componentType,
            count: g.count,
            isActive: this.activeFilter === g.componentType,
            badgeClass: this.activeFilter === g.componentType ? 'slds-m-right_xx-small slds-badge_inverse' : 'slds-m-right_xx-small'
        }));
        return [all, ...typeBadges];
    }

    get filteredGroups() {
        const groups = this.searchResponse?.groups || [];
        return groups
            .filter(g => this.activeFilter === 'all' || g.componentType === this.activeFilter)
            .map(g => ({
                ...g,
                isExpanded: this.expandedGroups[g.componentType] !== false,
                chevronIcon: this.expandedGroups[g.componentType] !== false ? 'utility:chevrondown' : 'utility:chevronright',
                iconName: TYPE_ICONS[g.componentType] || 'standard:default',
                records: g.records.map(r => ({
                    ...r,
                    key: r.metadataComponentId + '_' + r.metadataComponentName,
                    badgeLabel: r.accessType || (r.isSubflowReference ? 'Subflow' : ''),
                    badgeVariant: BADGE_VARIANTS[r.accessType] || 'inverse',
                    hasBadge: !!(r.accessType || r.isSubflowReference),
                    hasSetupUrl: !!r.setupUrl
                }))
            }));
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.value;
    }

    handleToggleGroup(event) {
        const type = event.currentTarget.dataset.type;
        this.expandedGroups = {
            ...this.expandedGroups,
            [type]: this.expandedGroups[type] === false
        };
    }

    handleOpenSetup(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleShowBlastRadius() {
        this.dispatchEvent(new CustomEvent('blastradius', {
            detail: {
                metadataType: this.metadataType,
                componentName: this.componentName
            },
            bubbles: true,
            composed: true
        }));
    }
}
