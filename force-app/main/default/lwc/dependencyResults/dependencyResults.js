import { LightningElement, api, track } from 'lwc';
import { loadD3 } from 'c/d3Loader';

const SVG_NS = 'http://www.w3.org/2000/svg';

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

const METADATA_TYPE_COLORS = {
    Flow: '#1B96FF',
    FlowDefinition: '#1B96FF',
    ApexClass: '#9050E9',
    ApexTrigger: '#BA01FF',
    ValidationRule: '#FE5C4C',
    Layout: '#04844B',
    LightningComponentBundle: '#0D9DDA',
    AuraDefinitionBundle: '#0D9DDA',
    Page: '#706E6B',
    EmailTemplate: '#706E6B',
    CustomField: '#706E6B'
};

const ACCESS_TYPE_COLORS = {
    Read: '#1B96FF',
    Write: '#FE9339',
    'Read & Write': '#FE5C4C'
};

const ROOT_COLOR = '#FF538A';
const SUBFLOW_COLOR = '#9050E9';
const DEFAULT_LEAF_COLOR = '#706E6B';
const LINK_COLOR = '#d8dde6';

export default class DependencyResults extends LightningElement {
    _searchResponse;
    @track activeFilter = 'all';
    @track expandedGroups = {};
    @track searchText = '';
    @track viewMode = 'list';

    d3 = null;

    @api
    get searchResponse() {
        return this._searchResponse;
    }

    set searchResponse(value) {
        this._searchResponse = value;
        if (this.viewMode === 'graph') {
            this._scheduleGraphRender();
        }
    }

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

    get isListView() {
        return this.viewMode === 'list';
    }

    get isGraphView() {
        return this.viewMode === 'graph';
    }

    get viewModeButtons() {
        return [
            { value: 'list', label: 'List', variant: this.viewMode === 'list' ? 'brand' : 'neutral' },
            { value: 'graph', label: 'Graph', variant: this.viewMode === 'graph' ? 'brand' : 'neutral' }
        ];
    }

    get filterBadges() {
        const groups = this.searchResponse?.groups || [];
        const all = {
            label: 'All',
            value: 'all',
            count: this.totalCount,
            isActive: this.activeFilter === 'all',
            badgeClass: this.activeFilter === 'all'
                ? 'slds-var-m-right_xx-small slds-badge_inverse'
                : 'slds-var-m-right_xx-small'
        };
        const typeBadges = groups.map(g => ({
            label: g.componentType,
            value: g.componentType,
            count: g.count,
            isActive: this.activeFilter === g.componentType,
            badgeClass: this.activeFilter === g.componentType
                ? 'slds-var-m-right_xx-small slds-badge_inverse'
                : 'slds-var-m-right_xx-small'
        }));
        return [all, ...typeBadges];
    }

    get filteredResultCount() {
        return this.filteredGroups.reduce((sum, g) => sum + g.records.length, 0);
    }

    get hasSearchFilter() {
        return this.searchText.length > 0;
    }

    get filteredGroups() {
        const groups = this.searchResponse?.groups || [];
        const needle = this.searchText.toLowerCase();
        return groups
            .filter(g => this.activeFilter === 'all' || g.componentType === this.activeFilter)
            .map(g => {
                const records = g.records
                    .filter(r => !needle || (r.metadataComponentName && r.metadataComponentName.toLowerCase().includes(needle)))
                    .map(r => ({
                        ...r,
                        key: r.metadataComponentId + '_' + r.metadataComponentName,
                        badgeLabel: r.accessType || (r.isSubflowReference ? 'Subflow' : ''),
                        badgeVariant: BADGE_VARIANTS[r.accessType] || 'inverse',
                        hasBadge: !!(r.accessType || r.isSubflowReference),
                        hasSetupUrl: !!r.setupUrl
                    }));
                return {
                    ...g,
                    count: records.length,
                    isExpanded: this.expandedGroups[g.componentType] !== false,
                    chevronIcon: this.expandedGroups[g.componentType] !== false ? 'utility:chevrondown' : 'utility:chevronright',
                    iconName: TYPE_ICONS[g.componentType] || 'standard:default',
                    records
                };
            })
            .filter(g => g.records.length > 0);
    }

    handleSearchInput(event) {
        this.searchText = event.target.value || '';
        if (this.viewMode === 'graph') {
            this._scheduleGraphRender();
        }
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.value;
        if (this.viewMode === 'graph') {
            this._scheduleGraphRender();
        }
    }

    handleToggleGroup(event) {
        const type = event.currentTarget.dataset.type;
        this.expandedGroups = {
            ...this.expandedGroups,
            [type]: this.expandedGroups[type] === false
        };
    }

    handleToggleGroupKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleToggleGroup(event);
        }
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

    handleViewModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.viewMode) {
            return;
        }
        this.viewMode = mode;
        if (mode === 'graph') {
            // Render after template updates
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            Promise.resolve().then(() => this.renderRadialTree());
        }
    }

    _scheduleGraphRender() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => this.renderRadialTree());
    }

    // ── Tree data ──────────────────────────────────────────────────────────────

    buildTreeData() {
        return {
            name: this.componentName,
            type: 'root',
            children: this.filteredGroups.map(group => ({
                name: group.componentType,
                type: 'group',
                color: METADATA_TYPE_COLORS[group.componentType] || '#706E6B',
                children: group.records.map(r => ({
                    name: r.metadataComponentName,
                    type: 'leaf',
                    accessType: r.accessType,
                    setupUrl: r.setupUrl,
                    isSubflow: r.isSubflowReference,
                    namespace: r.metadataComponentNamespace
                }))
            }))
        };
    }

    // ── Render ─────────────────────────────────────────────────────────────────

    async renderRadialTree() {
        const container = this.template.querySelector('.radial-tree-container');
        if (!container) {
            return;
        }

        // Load D3
        if (!this.d3) {
            try {
                this.d3 = await loadD3(this);
            } catch (err) {
                container.innerHTML = '<p class="slds-text-color_error slds-var-p-around_medium">Failed to load D3 library.</p>';
                return;
            }
        }

        const d3 = this.d3;

        // Clear previous render
        while (container.firstChild) {
            container.removeChild(container.firstChild);
        }

        const groups = this.filteredGroups;
        if (!groups.length) {
            const empty = document.createElement('p');
            empty.className = 'slds-text-color_weak slds-var-p-around_medium slds-text-align_center';
            empty.textContent = 'No results to display.';
            container.appendChild(empty);
            return;
        }

        // Dimensions
        const containerWidth = container.clientWidth || 600;
        const size = Math.max(500, containerWidth);
        const width = size;
        const height = size;
        const radius = Math.min(width, height) / 2 - 120;

        // Build hierarchy
        const treeData = this.buildTreeData();
        const root = d3.hierarchy(treeData);

        // Radial tree layout
        const treeLayout = d3.tree()
            .size([2 * Math.PI, radius])
            .separation((a, b) => (a.parent === b.parent ? 1 : 2) / a.depth);

        treeLayout(root);

        // Create SVG
        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('width', String(width));
        svg.setAttribute('height', String(height));
        svg.setAttribute('class', 'radial-tree-svg');
        svg.setAttribute('viewBox', `0 0 ${width} ${height}`);

        // Centered group
        const g = document.createElementNS(SVG_NS, 'g');
        g.setAttribute('class', 'radial-tree-root-group');
        g.setAttribute('transform', `translate(${width / 2},${height / 2})`);
        svg.appendChild(g);

        // Links
        const linkGroup = document.createElementNS(SVG_NS, 'g');
        linkGroup.setAttribute('class', 'radial-tree-links');

        const linkGenerator = d3.linkRadial()
            .angle(d => d.x)
            .radius(d => d.y);

        root.links().forEach(link => {
            const path = document.createElementNS(SVG_NS, 'path');
            path.setAttribute('class', 'tree-link');
            path.setAttribute('d', linkGenerator(link));
            path.setAttribute('fill', 'none');
            path.setAttribute('stroke', LINK_COLOR);
            path.setAttribute('stroke-width', '1.5');
            linkGroup.appendChild(path);
        });

        g.appendChild(linkGroup);

        // Tooltip element (HTML, absolute positioned)
        const tooltip = document.createElement('div');
        tooltip.className = 'tree-tooltip';
        tooltip.style.display = 'none';
        container.appendChild(tooltip);

        // Nodes
        const nodeGroup = document.createElementNS(SVG_NS, 'g');
        nodeGroup.setAttribute('class', 'radial-tree-nodes');

        root.descendants().forEach(node => {
            const ng = document.createElementNS(SVG_NS, 'g');
            ng.setAttribute('class', 'tree-node');

            // Compute x/y from polar coordinates
            const x = node.y * Math.sin(node.x);
            const y = -node.y * Math.cos(node.x);
            ng.setAttribute('transform', `translate(${x},${y})`);

            // Node circle
            const circle = document.createElementNS(SVG_NS, 'circle');

            if (node.data.type === 'root') {
                circle.setAttribute('r', '8');
                circle.setAttribute('fill', ROOT_COLOR);
                circle.setAttribute('class', 'tree-node-circle tree-node-root');
            } else if (node.data.type === 'group') {
                circle.setAttribute('r', '6');
                circle.setAttribute('fill', node.data.color || '#706E6B');
                circle.setAttribute('class', 'tree-node-circle tree-node-group');
                circle.setAttribute('style', 'cursor: pointer;');

                // Collapse/expand: store _children for toggling
                circle.addEventListener('click', (ev) => {
                    ev.stopPropagation();
                    this._toggleGroupNode(node, d3, svg, g, root, radius, tooltip);
                });
            } else {
                // Leaf — color by accessType
                const leafColor = node.data.isSubflow
                    ? SUBFLOW_COLOR
                    : ACCESS_TYPE_COLORS[node.data.accessType] || DEFAULT_LEAF_COLOR;

                circle.setAttribute('r', '4');
                circle.setAttribute('fill', leafColor);
                circle.setAttribute('class', 'tree-node-circle tree-node-leaf');
                circle.setAttribute('style', node.data.setupUrl ? 'cursor: pointer;' : '');

                // Click: open setup URL
                if (node.data.setupUrl) {
                    circle.addEventListener('click', (ev) => {
                        ev.stopPropagation();
                        window.open(node.data.setupUrl, '_blank');
                    });
                }

                // Hover tooltip
                ng.addEventListener('mouseenter', (ev) => {
                    const ns = node.data.namespace ? ` [${node.data.namespace}]` : '';
                    const at = node.data.isSubflow ? 'Subflow' : (node.data.accessType || '');
                    tooltip.textContent = `${node.data.name}${ns}${at ? ' — ' + at : ''}`;
                    tooltip.style.display = 'block';
                    const rect = container.getBoundingClientRect();
                    tooltip.style.left = `${ev.clientX - rect.left + 12}px`;
                    tooltip.style.top = `${ev.clientY - rect.top - 8}px`;
                });

                ng.addEventListener('mousemove', (ev) => {
                    const rect = container.getBoundingClientRect();
                    tooltip.style.left = `${ev.clientX - rect.left + 12}px`;
                    tooltip.style.top = `${ev.clientY - rect.top - 8}px`;
                });

                ng.addEventListener('mouseleave', () => {
                    tooltip.style.display = 'none';
                });
            }

            ng.appendChild(circle);

            // Label
            const text = document.createElementNS(SVG_NS, 'text');

            // Angular position: determine left vs right half
            const angle = node.x; // radians, 0 = top
            // Right half: angle in (0, PI), left half: angle in (PI, 2PI) or negative
            const isRightHalf = angle > 0 && angle < Math.PI;

            if (node.data.type === 'root') {
                text.setAttribute('class', 'tree-label tree-label-root');
                text.setAttribute('text-anchor', 'middle');
                text.setAttribute('dy', '-14');
                text.setAttribute('font-weight', 'bold');
                text.setAttribute('font-size', '13');
                text.textContent = this._truncate(node.data.name, 35);
            } else if (node.data.type === 'group') {
                text.setAttribute('class', 'tree-label tree-label-group');
                text.setAttribute('text-anchor', isRightHalf ? 'start' : 'end');
                text.setAttribute('dy', '4');
                text.setAttribute('dx', isRightHalf ? '10' : '-10');
                text.setAttribute('font-size', '13');
                text.setAttribute('font-weight', '600');
                text.textContent = node.data.name;
            } else {
                text.setAttribute('class', 'tree-label tree-label-leaf');
                text.setAttribute('text-anchor', isRightHalf ? 'start' : 'end');
                text.setAttribute('dy', '4');
                text.setAttribute('dx', isRightHalf ? '8' : '-8');
                text.setAttribute('font-size', '11');
                text.textContent = this._truncate(node.data.name, 30);
            }

            ng.appendChild(text);
            nodeGroup.appendChild(ng);
        });

        g.appendChild(nodeGroup);

        // Zoom behavior via D3
        const zoom = d3.zoom()
            .scaleExtent([0.3, 3])
            .on('zoom', (event) => {
                g.setAttribute('transform', `translate(${width / 2 + event.transform.x},${height / 2 + event.transform.y}) scale(${event.transform.k})`);
            });

        d3.select(svg).call(zoom);

        container.insertBefore(svg, tooltip);

        // Legend
        this._renderLegend(container);
    }

    // Toggle group node children (collapse/expand)
    _toggleGroupNode(node, d3, svg, g, root, radius, tooltip) {
        if (node._children) {
            // Expand
            node.children = node._children;
            node._children = null;
        } else if (node.children) {
            // Collapse
            node._children = node.children;
            node.children = null;
        }

        // Recompute layout
        const treeLayout = d3.tree()
            .size([2 * Math.PI, radius])
            .separation((a, b) => (a.parent === b.parent ? 1 : 2) / a.depth);

        treeLayout(root);

        // Re-render inside existing g
        while (g.firstChild) {
            g.removeChild(g.firstChild);
        }

        const linkGenerator = d3.linkRadial()
            .angle(d => d.x)
            .radius(d => d.y);

        const linkGroup = document.createElementNS(SVG_NS, 'g');
        linkGroup.setAttribute('class', 'radial-tree-links');

        root.links().forEach(link => {
            const path = document.createElementNS(SVG_NS, 'path');
            path.setAttribute('class', 'tree-link');
            path.setAttribute('d', linkGenerator(link));
            path.setAttribute('fill', 'none');
            path.setAttribute('stroke', LINK_COLOR);
            path.setAttribute('stroke-width', '1.5');
            linkGroup.appendChild(path);
        });

        g.appendChild(linkGroup);

        const nodeGroup = document.createElementNS(SVG_NS, 'g');
        nodeGroup.setAttribute('class', 'radial-tree-nodes');

        root.descendants().forEach(n => {
            const ng = document.createElementNS(SVG_NS, 'g');
            ng.setAttribute('class', 'tree-node');

            const nx = n.y * Math.sin(n.x);
            const ny = -n.y * Math.cos(n.x);
            ng.setAttribute('transform', `translate(${nx},${ny})`);

            const circle = document.createElementNS(SVG_NS, 'circle');

            if (n.data.type === 'root') {
                circle.setAttribute('r', '8');
                circle.setAttribute('fill', ROOT_COLOR);
                circle.setAttribute('class', 'tree-node-circle tree-node-root');
            } else if (n.data.type === 'group') {
                circle.setAttribute('r', '6');
                circle.setAttribute('fill', n.data.color || '#706E6B');
                circle.setAttribute('class', 'tree-node-circle tree-node-group');
                circle.setAttribute('style', 'cursor: pointer;');
                const collapsed = !!n._children;
                if (collapsed) {
                    circle.setAttribute('stroke', '#706E6B');
                    circle.setAttribute('stroke-width', '2');
                    circle.setAttribute('stroke-dasharray', '3 2');
                }
                circle.addEventListener('click', (ev) => {
                    ev.stopPropagation();
                    this._toggleGroupNode(n, d3, svg, g, root, radius, tooltip);
                });
            } else {
                const leafColor = n.data.isSubflow
                    ? SUBFLOW_COLOR
                    : ACCESS_TYPE_COLORS[n.data.accessType] || DEFAULT_LEAF_COLOR;

                circle.setAttribute('r', '4');
                circle.setAttribute('fill', leafColor);
                circle.setAttribute('class', 'tree-node-circle tree-node-leaf');
                circle.setAttribute('style', n.data.setupUrl ? 'cursor: pointer;' : '');

                if (n.data.setupUrl) {
                    circle.addEventListener('click', (ev) => {
                        ev.stopPropagation();
                        window.open(n.data.setupUrl, '_blank');
                    });
                }

                ng.addEventListener('mouseenter', (ev) => {
                    const container = svg.parentElement;
                    const ns = n.data.namespace ? ` [${n.data.namespace}]` : '';
                    const at = n.data.isSubflow ? 'Subflow' : (n.data.accessType || '');
                    tooltip.textContent = `${n.data.name}${ns}${at ? ' — ' + at : ''}`;
                    tooltip.style.display = 'block';
                    const rect = container.getBoundingClientRect();
                    tooltip.style.left = `${ev.clientX - rect.left + 12}px`;
                    tooltip.style.top = `${ev.clientY - rect.top - 8}px`;
                });

                ng.addEventListener('mousemove', (ev) => {
                    const container = svg.parentElement;
                    const rect = container.getBoundingClientRect();
                    tooltip.style.left = `${ev.clientX - rect.left + 12}px`;
                    tooltip.style.top = `${ev.clientY - rect.top - 8}px`;
                });

                ng.addEventListener('mouseleave', () => {
                    tooltip.style.display = 'none';
                });
            }

            ng.appendChild(circle);

            const text = document.createElementNS(SVG_NS, 'text');
            const angle = n.x;
            const isRightHalf = angle > 0 && angle < Math.PI;

            if (n.data.type === 'root') {
                text.setAttribute('class', 'tree-label tree-label-root');
                text.setAttribute('text-anchor', 'middle');
                text.setAttribute('dy', '-14');
                text.setAttribute('font-weight', 'bold');
                text.setAttribute('font-size', '13');
                text.textContent = this._truncate(n.data.name, 35);
            } else if (n.data.type === 'group') {
                const collapsed = !!n._children;
                text.setAttribute('class', 'tree-label tree-label-group');
                text.setAttribute('text-anchor', isRightHalf ? 'start' : 'end');
                text.setAttribute('dy', '4');
                text.setAttribute('dx', isRightHalf ? '10' : '-10');
                text.setAttribute('font-size', '13');
                text.setAttribute('font-weight', '600');
                text.textContent = collapsed ? `${n.data.name} (+${n._children.length})` : n.data.name;
            } else {
                text.setAttribute('class', 'tree-label tree-label-leaf');
                text.setAttribute('text-anchor', isRightHalf ? 'start' : 'end');
                text.setAttribute('dy', '4');
                text.setAttribute('dx', isRightHalf ? '8' : '-8');
                text.setAttribute('font-size', '11');
                text.textContent = this._truncate(n.data.name, 30);
            }

            ng.appendChild(text);
            nodeGroup.appendChild(ng);
        });

        g.appendChild(nodeGroup);
    }

    _renderLegend(container) {
        const existing = container.querySelector('.radial-tree-legend');
        if (existing) {
            container.removeChild(existing);
        }

        const legend = document.createElement('div');
        legend.className = 'radial-tree-legend';

        const items = [
            { label: 'Read', color: ACCESS_TYPE_COLORS.Read },
            { label: 'Write', color: ACCESS_TYPE_COLORS.Write },
            { label: 'Read & Write', color: ACCESS_TYPE_COLORS['Read & Write'] },
            { label: 'Subflow', color: SUBFLOW_COLOR }
        ];

        items.forEach(item => {
            const pill = document.createElement('span');
            pill.className = 'radial-tree-legend-item';

            const dot = document.createElement('span');
            dot.className = 'radial-tree-legend-dot';
            dot.style.backgroundColor = item.color;

            const label = document.createElement('span');
            label.textContent = item.label;

            pill.appendChild(dot);
            pill.appendChild(label);
            legend.appendChild(pill);
        });

        container.appendChild(legend);
    }

    _truncate(value, maxLen) {
        const text = String(value || '');
        if (text.length <= maxLen) {
            return text;
        }
        return `${text.slice(0, Math.max(maxLen - 3, 1))}...`;
    }
}
