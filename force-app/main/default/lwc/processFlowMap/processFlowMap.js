import { LightningElement, track } from 'lwc';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import getProcessFlow from '@salesforce/apex/ProcessFlowController.getProcessFlow';

const CONTEXT_OPTIONS = [
    { label: 'Insert', value: 'Insert' },
    { label: 'Update', value: 'Update' },
    { label: 'Delete', value: 'Delete' },
    { label: 'All', value: 'All' }
];

const ICON_BY_TYPE = {
    BeforeTrigger: 'custom:custom24',
    AfterTrigger: 'custom:custom24',
    ValidationRule: 'utility:warning',
    Flow_BeforeSave: 'standard:flow',
    Flow_AfterSave: 'standard:flow',
    Flow_Async: 'utility:clock',
    WorkflowRule: 'utility:workflow',
    WorkflowFieldUpdate: 'utility:change_record_type',
    AssignmentRule: 'utility:user_role',
    AutoResponseRule: 'utility:email',
    EntitlementRule: 'utility:task'
};

export default class ProcessFlowMap extends LightningElement {
    @track objectOptions = [];
    @track selectedObject = '';
    @track selectedContext = 'All';
    @track isLoading = false;
    @track error;
    @track response;
    @track expandedPhases = {};

    contextOptions = CONTEXT_OPTIONS;

    connectedCallback() {
        this.loadObjects();
    }

    get hasResults() {
        return !!this.response;
    }

    get hasWarnings() {
        return (this.response?.warnings || []).length > 0;
    }

    get warnings() {
        return this.response?.warnings || [];
    }

    get isAnalyzeDisabled() {
        return !this.selectedObject || this.isLoading;
    }

    get phaseRows() {
        const phases = this.response?.phases || [];
        return phases.map(phase => {
            const phaseKey = String(phase.phaseNumber);
            const hasSteps = (phase.steps || []).length > 0;
            const isExpanded = this.expandedPhases[phaseKey] !== false;

            return {
                ...phase,
                key: phaseKey,
                hasSteps,
                isExpanded,
                toggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                phaseClass: hasSteps ? 'phase-card' : 'phase-card phase-empty',
                markerClass: hasSteps ? 'phase-marker' : 'phase-marker phase-marker-empty',
                steps: (phase.steps || []).map((step, index) => ({
                    ...step,
                    key: `${phaseKey}_${step.id || step.name || index}`,
                    iconName: ICON_BY_TYPE[step.automationType] || 'standard:default',
                    stateLabel: step.isActive ? 'Active' : 'Inactive',
                    stateClass: step.isActive
                        ? 'slds-badge slds-theme_success step-state-badge'
                        : 'slds-badge slds-theme_inverse step-state-badge',
                    hasSetupUrl: !!step.setupUrl
                }))
            };
        });
    }

    get stats() {
        const phaseList = this.response?.phases || [];
        const allSteps = [];

        phaseList.forEach(phase => {
            (phase.steps || []).forEach(step => allSteps.push(step));
        });

        let triggers = 0;
        let validationRules = 0;
        let flows = 0;
        let workflows = 0;

        allSteps.forEach(step => {
            const type = step.automationType || '';
            if (type === 'BeforeTrigger' || type === 'AfterTrigger') {
                triggers += 1;
            } else if (type === 'ValidationRule') {
                validationRules += 1;
            } else if (type.startsWith('Flow_')) {
                flows += 1;
            } else if (type === 'WorkflowRule' || type === 'WorkflowFieldUpdate') {
                workflows += 1;
            }
        });

        return {
            triggers,
            validationRules,
            flows,
            workflows
        };
    }

    get statsLabel() {
        const s = this.stats;
        return `${s.triggers} triggers, ${s.validationRules} VRs, ${s.flows} flows, ${s.workflows} workflows`;
    }

    get totalAutomations() {
        return this.response?.totalAutomations || 0;
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
    }

    handleContextChange(event) {
        this.selectedContext = event.detail.value;
    }

    handleTogglePhase(event) {
        const phaseKey = event.currentTarget.dataset.phase;
        this.expandedPhases = {
            ...this.expandedPhases,
            [phaseKey]: this.expandedPhases[phaseKey] === false
        };
    }

    async handleAnalyze() {
        if (this.isAnalyzeDisabled) {
            return;
        }

        this.isLoading = true;
        this.error = null;
        this.response = null;
        this.expandedPhases = {};

        try {
            const result = await getProcessFlow({
                objectName: this.selectedObject,
                triggerContext: this.selectedContext
            });

            this.response = result;
            this.initializePhaseExpansion(result?.phases || []);
        } catch (error) {
            this.error = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenSetup(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleExportText() {
        if (!this.response) {
            return;
        }

        const text = this.buildExportText();
        const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
        const link = document.createElement('a');

        link.href = URL.createObjectURL(blob);
        link.download = `process-flow-${this.selectedObject || 'object'}-${this.selectedContext.toLowerCase()}.txt`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(link.href);
    }

    async loadObjects() {
        try {
            const data = await getObjects();
            this.objectOptions = (data || []).map(option => ({
                label: option.label,
                value: option.value
            }));
        } catch (error) {
            this.error = 'Failed to load objects: ' + this.reduceError(error);
        }
    }

    initializePhaseExpansion(phases) {
        const expansion = {};
        (phases || []).forEach(phase => {
            expansion[String(phase.phaseNumber)] = true;
        });
        this.expandedPhases = expansion;
    }

    buildExportText() {
        const lines = [];
        lines.push('Process Flow Map');
        lines.push(`Object: ${this.response.objectName}`);
        lines.push(`Context: ${this.response.triggerContext}`);
        lines.push(`Total automations: ${this.totalAutomations}`);
        lines.push(`Summary: ${this.statsLabel}`);
        lines.push('');

        (this.response.phases || []).forEach(phase => {
            lines.push(`${phase.phaseNumber}. ${phase.phaseName}`);
            if (!(phase.steps || []).length) {
                lines.push('  [none]');
                lines.push('');
                return;
            }

            (phase.steps || []).forEach(step => {
                lines.push(`  - ${step.name || '[unnamed]'} [${step.isActive ? 'Active' : 'Inactive'}]`);
                lines.push(`    Context: ${step.triggerContext || 'n/a'}`);
                if (step.description) {
                    lines.push(`    Description: ${step.description}`);
                }
                if (step.setupUrl) {
                    lines.push(`    Setup: ${step.setupUrl}`);
                }
            });
            lines.push('');
        });

        if (this.hasWarnings) {
            lines.push('Warnings:');
            this.warnings.forEach(warning => lines.push(`- ${warning}`));
            lines.push('');
        }

        return lines.join('\n');
    }

    reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return JSON.stringify(error);
    }
}
