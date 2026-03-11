import { LightningElement, track } from 'lwc';
import getObjects from '@salesforce/apex/MetadataPickerController.getObjects';
import getProcessFlow from '@salesforce/apex/ProcessFlowController.getProcessFlow';
import { loadD3 } from 'c/d3Loader';
import { PROCESS_STEP_ICONS, PROCESS_STEP_COLORS } from 'c/wituConstants';

const CONTEXT_OPTIONS = [
    { label: 'Insert', value: 'Insert' },
    { label: 'Update', value: 'Update' },
    { label: 'Delete', value: 'Delete' },
    { label: 'All', value: 'All' }
];

const PHASE_COLORS = [
    'rgba(1, 118, 211, 0.06)',
    'rgba(144, 80, 233, 0.06)',
    'rgba(254, 147, 57, 0.06)',
    'rgba(27, 150, 255, 0.06)',
    'rgba(254, 92, 76, 0.06)',
    'rgba(109, 185, 239, 0.06)',
    'rgba(3, 195, 165, 0.06)',
    'rgba(255, 184, 0, 0.06)'
];

export default class ProcessFlowMap extends LightningElement {
    @track objectOptions = [];
    @track selectedObject = '';
    @track selectedContext = 'All';
    @track isLoading = false;
    @track error;
    @track response;
    @track expandedPhases = {};
    @track viewMode = 'timeline';

    contextOptions = CONTEXT_OPTIONS;
    d3 = null;

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

    get isTimelineView() {
        return this.viewMode === 'timeline';
    }

    get isArcView() {
        return this.viewMode === 'arc';
    }

    get hasFieldData() {
        const phases = this.response?.phases || [];
        return phases.some(phase =>
            (phase.steps || []).some(step =>
                (step.fieldsReferenced || []).length > 0 ||
                (step.fieldsModified || []).length > 0
            )
        );
    }

    get timelineClass() {
        return this.isTimelineView ? 'timeline' : 'timeline slds-hide';
    }

    get arcContainerClass() {
        return this.isArcView ? 'arc-container' : 'arc-container slds-hide';
    }

    get timelineViewVariant() {
        return this.isTimelineView ? 'brand' : 'neutral';
    }

    get arcViewVariant() {
        return this.isArcView ? 'brand' : 'neutral';
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
                    iconName: PROCESS_STEP_ICONS[step.automationType] || 'standard:default',
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

    handlePhaseHeaderKeydown(event) {
        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            this.handleTogglePhase(event);
        }
    }

    handleViewModeChange(event) {
        const newMode = event.currentTarget.dataset.mode;
        if (newMode === this.viewMode) {
            return;
        }
        this.viewMode = newMode;
        if (newMode === 'arc') {
            // Defer so the arc container is visible in the DOM before rendering
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.renderArcDiagram();
            }, 0);
        }
    }

    async handleAnalyze() {
        if (this.isAnalyzeDisabled) {
            return;
        }

        this.isLoading = true;
        this.error = null;
        this.response = null;
        this.expandedPhases = {};
        this.viewMode = 'timeline';

        try {
            const result = await getProcessFlow({
                objectName: this.selectedObject,
                triggerContext: this.selectedContext
            });

            this.response = result;
            this.initializePhaseExpansion(result?.phases || []);

            if (this.viewMode === 'arc') {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.renderArcDiagram();
                }, 0);
            }
        } catch (error) {
            this.error = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenSetup(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank', 'noopener,noreferrer');
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

    // ─── Arc Diagram ──────────────────────────────────────────────────────────

    computeFieldLinks() {
        const steps = (this.response?.phases || []).flatMap(p => p.steps || []);
        const links = [];
        for (let i = 0; i < steps.length; i++) {
            for (let j = i + 1; j < steps.length; j++) {
                const iWrites = new Set(steps[i].fieldsModified || []);
                const jReads = new Set(steps[j].fieldsReferenced || []);
                const jWrites = new Set(steps[j].fieldsModified || []);
                // iReads only needed if we add read-read links in future
                // const iReads = new Set(steps[i].fieldsReferenced || []);

                const causal = [...iWrites].filter(f => jReads.has(f));
                const conflict = [...iWrites].filter(f => jWrites.has(f));

                if (causal.length > 0) {
                    links.push({ source: i, target: j, type: 'causal', fields: causal, value: causal.length });
                }
                if (conflict.length > 0) {
                    links.push({ source: i, target: j, type: 'conflict', fields: conflict, value: conflict.length });
                }
            }
        }
        return links;
    }

    async renderArcDiagram() {
        const container = this.template.querySelector('.arc-container');
        if (!container) {
            return;
        }

        // Load D3 if not already loaded
        if (!this.d3) {
            try {
                this.d3 = await loadD3(this);
            } catch (err) {
                container.innerHTML = '<p class="arc-empty-state">Failed to load D3 library.</p>';
                return;
            }
        }

        const d3 = this.d3;

        // Gather steps in execution order
        const steps = (this.response?.phases || []).flatMap(p => p.steps || []);
        if (steps.length === 0) {
            container.innerHTML = '<p class="arc-empty-state">No automation steps found.</p>';
            return;
        }

        const links = this.computeFieldLinks();

        // Clear previous render
        container.innerHTML = '';

        // Dimensions
        const margin = { top: 60, right: 40, bottom: 90, left: 40 };
        const totalWidth = Math.max(container.clientWidth || 700, steps.length * 80 + margin.left + margin.right);
        const height = 300;
        const innerWidth = totalWidth - margin.left - margin.right;
        const innerHeight = height - margin.top - margin.bottom;
        const baselineY = margin.top + innerHeight;

        // Create SVG
        const svg = d3.create('svg')
            .attr('width', totalWidth)
            .attr('height', height)
            .attr('class', 'arc-svg');

        const g = svg.append('g')
            .attr('transform', `translate(${margin.left},0)`);

        // X scale — position for each step index
        const xScale = d3.scalePoint()
            .domain(steps.map((_, i) => i))
            .range([0, innerWidth])
            .padding(0.5);

        // ── Phase background bands ───────────────────────────────────────────
        const phases = this.response?.phases || [];
        let stepOffset = 0;
        phases.forEach((phase, phaseIdx) => {
            const phaseSteps = phase.steps || [];
            if (phaseSteps.length === 0) {
                return;
            }
            const firstIdx = stepOffset;
            const lastIdx = stepOffset + phaseSteps.length - 1;
            stepOffset += phaseSteps.length;

            const x1 = xScale(firstIdx) - (xScale.step() * 0.45);
            const x2 = xScale(lastIdx) + (xScale.step() * 0.45);
            const bandWidth = x2 - x1;

            const color = PHASE_COLORS[phaseIdx % PHASE_COLORS.length];

            g.append('rect')
                .attr('x', x1)
                .attr('y', margin.top - 20)
                .attr('width', bandWidth)
                .attr('height', innerHeight + 20)
                .attr('fill', color)
                .attr('rx', 4);

            g.append('text')
                .attr('x', x1 + bandWidth / 2)
                .attr('y', margin.top - 28)
                .attr('text-anchor', 'middle')
                .attr('class', 'arc-phase-label')
                .text(phase.phaseName || `Phase ${phase.phaseNumber}`);
        });

        // ── Baseline ────────────────────────────────────────────────────────
        g.append('line')
            .attr('x1', 0)
            .attr('x2', innerWidth)
            .attr('y1', baselineY)
            .attr('y2', baselineY)
            .attr('class', 'arc-baseline');

        // ── Arcs ────────────────────────────────────────────────────────────
        const arcGroup = g.append('g').attr('class', 'arc-links');

        links.forEach((link, linkIdx) => {
            const x1 = xScale(link.source);
            const x2 = xScale(link.target);
            const midX = (x1 + x2) / 2;
            const arcHeight = Math.min(Math.abs(x2 - x1) * 0.45, innerHeight * 0.9);
            const controlY = baselineY - arcHeight;
            const strokeWidth = Math.max(1, Math.min(4, link.value));
            const pathData = `M ${x1} ${baselineY} Q ${midX} ${controlY} ${x2} ${baselineY}`;

            const arcClass = link.type === 'causal' ? 'arc-path arc-path-causal' : 'arc-path arc-path-conflict';

            arcGroup.append('path')
                .attr('d', pathData)
                .attr('class', arcClass)
                .attr('stroke-width', strokeWidth)
                .attr('data-link-idx', linkIdx)
                .on('mouseenter', (event) => {
                    this.showArcTooltip(event, link, steps, container);
                    // Highlight arc
                    event.currentTarget.classList.add('arc-path-hover');
                    // Highlight endpoint dots
                    container.querySelectorAll(`.arc-dot[data-step-idx="${link.source}"], .arc-dot[data-step-idx="${link.target}"]`).forEach(el => {
                        el.classList.add('arc-dot-hover');
                    });
                })
                .on('mouseleave', () => {
                    this.hideTooltip(container);
                    container.querySelectorAll('.arc-path-hover').forEach(el => el.classList.remove('arc-path-hover'));
                    container.querySelectorAll('.arc-dot-hover').forEach(el => el.classList.remove('arc-dot-hover'));
                });
        });

        // ── Step dots ───────────────────────────────────────────────────────
        const dotGroup = g.append('g').attr('class', 'arc-dots');

        steps.forEach((step, i) => {
            const cx = xScale(i);
            const dotColor = PROCESS_STEP_COLORS[step.automationType] || '#9aa1a9';

            dotGroup.append('circle')
                .attr('cx', cx)
                .attr('cy', baselineY)
                .attr('r', 7)
                .attr('fill', dotColor)
                .attr('class', 'arc-dot')
                .attr('data-step-idx', i)
                .on('mouseenter', (event) => {
                    this.showDotTooltip(event, step, i, links, container);
                    event.currentTarget.classList.add('arc-dot-hover');
                    // Highlight connected arcs
                    container.querySelectorAll(`.arc-path[data-link-idx]`).forEach(el => {
                        const idx = parseInt(el.getAttribute('data-link-idx'), 10);
                        const lnk = links[idx];
                        if (lnk && (lnk.source === i || lnk.target === i)) {
                            el.classList.add('arc-path-hover');
                        }
                    });
                })
                .on('mouseleave', () => {
                    this.hideTooltip(container);
                    container.querySelectorAll('.arc-dot-hover').forEach(el => el.classList.remove('arc-dot-hover'));
                    container.querySelectorAll('.arc-path-hover').forEach(el => el.classList.remove('arc-path-hover'));
                });
        });

        // ── Step labels ──────────────────────────────────────────────────────
        const labelGroup = g.append('g').attr('class', 'arc-labels');

        steps.forEach((step, i) => {
            const cx = xScale(i);
            const displayName = (step.name || 'Unknown').length > 18
                ? (step.name || 'Unknown').substring(0, 17) + '…'
                : (step.name || 'Unknown');

            labelGroup.append('text')
                .attr('x', cx)
                .attr('y', baselineY + 14)
                .attr('transform', `rotate(45, ${cx}, ${baselineY + 14})`)
                .attr('class', 'arc-label')
                .text(displayName);
        });

        // ── Empty state for no links ─────────────────────────────────────────
        if (links.length === 0) {
            g.append('text')
                .attr('x', innerWidth / 2)
                .attr('y', baselineY - 30)
                .attr('text-anchor', 'middle')
                .attr('class', 'arc-empty-text')
                .text('No field dependencies found between these automation steps.');
        }

        // Append SVG to container
        container.appendChild(svg.node());

        // Tooltip element
        const tooltip = document.createElement('div');
        tooltip.className = 'arc-tooltip';
        tooltip.style.display = 'none';
        container.appendChild(tooltip);
    }

    showArcTooltip(event, link, steps, container) {
        const tooltip = container.querySelector('.arc-tooltip');
        if (!tooltip) {
            return;
        }
        const typeLabelMap = { causal: 'Data Flow', conflict: 'Write Conflict' };
        const typeLabel = typeLabelMap[link.type] || link.type;
        const srcName = steps[link.source]?.name || `Step ${link.source + 1}`;
        const tgtName = steps[link.target]?.name || `Step ${link.target + 1}`;
        tooltip.innerHTML = `
            <div class="arc-tooltip-title">${typeLabel}</div>
            <div class="arc-tooltip-row"><strong>From:</strong> ${this.escapeHtml(srcName)}</div>
            <div class="arc-tooltip-row"><strong>To:</strong> ${this.escapeHtml(tgtName)}</div>
            <div class="arc-tooltip-fields"><strong>Fields:</strong> ${link.fields.map(f => this.escapeHtml(f)).join(', ')}</div>
        `;
        this.positionTooltip(tooltip, event, container);
    }

    showDotTooltip(event, step, stepIdx, links, container) {
        const tooltip = container.querySelector('.arc-tooltip');
        if (!tooltip) {
            return;
        }
        const refs = (step.fieldsReferenced || []);
        const mods = (step.fieldsModified || []);
        const connectedCount = links.filter(l => l.source === stepIdx || l.target === stepIdx).length;

        let html = `<div class="arc-tooltip-title">${this.escapeHtml(step.name || 'Unknown')}</div>`;
        html += `<div class="arc-tooltip-row"><strong>Type:</strong> ${this.escapeHtml(step.automationType || '')}</div>`;
        if (refs.length > 0) {
            html += `<div class="arc-tooltip-row"><strong>Reads:</strong> ${refs.map(f => this.escapeHtml(f)).join(', ')}</div>`;
        }
        if (mods.length > 0) {
            html += `<div class="arc-tooltip-row"><strong>Writes:</strong> ${mods.map(f => this.escapeHtml(f)).join(', ')}</div>`;
        }
        if (connectedCount > 0) {
            html += `<div class="arc-tooltip-row"><strong>Connections:</strong> ${connectedCount}</div>`;
        }
        tooltip.innerHTML = html;
        this.positionTooltip(tooltip, event, container);
    }

    positionTooltip(tooltip, event, container) {
        tooltip.style.display = 'block';
        const containerRect = container.getBoundingClientRect();
        let left = event.clientX - containerRect.left + 12;
        let top = event.clientY - containerRect.top + 12;

        // Keep tooltip inside container width
        const tooltipWidth = 220;
        if (left + tooltipWidth > containerRect.width - 8) {
            left = left - tooltipWidth - 24;
        }

        tooltip.style.left = `${left}px`;
        tooltip.style.top = `${top}px`;
    }

    hideTooltip(container) {
        const tooltip = container.querySelector('.arc-tooltip');
        if (tooltip) {
            tooltip.style.display = 'none';
        }
    }

    escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ─── Export ───────────────────────────────────────────────────────────────

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
