import { LightningElement, api, track } from 'lwc';
import getBlastRadius from '@salesforce/apex/BlastRadiusController.getBlastRadius';
import { loadD3 } from 'c/d3Loader';

const SVG_NS = 'http://www.w3.org/2000/svg';
const NODE_WIDTH = 188;
const NODE_HEIGHT = 54;
const ROOT_X = 220;
const MIN_CANVAS_HEIGHT = 520;
const MIN_CANVAS_WIDTH = 980;
const MAX_LABEL_LENGTH = 24;
const MIN_ZOOM = 0.55;
const MAX_ZOOM = 2.2;

const TYPE_COLORS = {
    Flow: '#1B96FF',
    FlowDefinition: '#1B96FF',
    ApexClass: '#9050E9',
    ApexTrigger: '#BA01FF',
    ValidationRule: '#FE5C4C',
    Layout: '#04844B',
    LightningComponentBundle: '#0D9DDA',
    AuraDefinitionBundle: '#0D9DDA'
};

const TYPE_ICONS = {
    Flow: '⚡',
    FlowDefinition: '⚡',
    ApexClass: '<>',
    ApexTrigger: '<>',
    ValidationRule: '✓',
    Layout: '▤',
    LightningComponentBundle: '◇',
    AuraDefinitionBundle: '◇'
};

const LEGEND = [
    { label: 'Flow', type: 'Flow', icon: '⚡' },
    { label: 'Apex', type: 'ApexClass', icon: '<>' },
    { label: 'Validation', type: 'ValidationRule', icon: '✓' },
    { label: 'Layout', type: 'Layout', icon: '▤' },
    { label: 'LWC/Aura', type: 'LightningComponentBundle', icon: '◇' },
    { label: 'Root', color: '#FF538A', icon: '●' },
    { label: 'Cycle', color: '#FE9339', icon: '↺' }
];

export default class BlastRadiusGraph extends LightningElement {
    _metadataType;
    _componentName;
    _resizeHandler;
    _pointerDown;
    _dragStartX;
    _dragStartY;
    _dragOriginX;
    _dragOriginY;
    _viewportWheelHandler;
    _viewportMouseDownHandler;
    _windowMouseMoveHandler;
    _windowMouseUpHandler;
    _viewportBound = false;
    d3 = null;
    simulation = null;
    _d3RenderKey = null;

    @track viewMode = 'radial';
    @track maxDepth = 3;
    @track isLoading = false;
    @track error;
    @track response;
    @track selectedNodeId;
    @track hoveredNodeId;
    @track zoomScale = 1;
    @track panX = 0;
    @track panY = 0;
    @track searchQuery = '';
    @track typeFilterState = {};

    nodeById = new Map();
    childrenById = new Map();
    parentsById = new Map();
    adjacentById = new Map();
    outgoingById = new Map();
    collapsedNodeIds = new Set();
    visibleNodeIds = new Set();
    lastLayout;
    lastRenderKey;

    @api
    get metadataType() {
        return this._metadataType;
    }

    set metadataType(value) {
        this._metadataType = value;
        this.tryLoad();
    }

    @api
    get componentName() {
        return this._componentName;
    }

    set componentName(value) {
        this._componentName = value;
        this.tryLoad();
    }

    connectedCallback() {
        this._resizeHandler = () => {
            this.lastRenderKey = null;
            this._d3RenderKey = null;
            this.renderGraph();
        };
        window.addEventListener('resize', this._resizeHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._resizeHandler);
        if (this._viewportBound) {
            const viewport = this.template.querySelector('.graph-viewport');
            if (viewport) {
                viewport.removeEventListener('wheel', this._viewportWheelHandler);
                viewport.removeEventListener('mousedown', this._viewportMouseDownHandler);
            }
            window.removeEventListener('mousemove', this._windowMouseMoveHandler);
            window.removeEventListener('mouseup', this._windowMouseUpHandler);
        }
        if (this.simulation) {
            this.simulation.stop();
            this.simulation = null;
        }
    }

    renderedCallback() {
        this.bindViewportInteractions();
        this.renderGraph();
    }

    get hasData() {
        return !!this.response?.nodes?.length;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && this.response && !this.hasData;
    }

    get depthButtons() {
        return [1, 2, 3, 4, 5].map(value => ({
            value,
            variant: this.maxDepth === value ? 'brand' : 'neutral'
        }));
    }

    get isRadialView() {
        return this.viewMode === 'radial';
    }

    get isForceView() {
        return this.viewMode === 'force';
    }

    get isTreeView() {
        return this.viewMode === 'tree';
    }

    get viewModeButtons() {
        return [
            { value: 'radial', label: 'Radial', variant: this.viewMode === 'radial' ? 'brand' : 'neutral' },
            { value: 'force', label: 'Force', variant: this.viewMode === 'force' ? 'brand' : 'neutral' },
            { value: 'tree', label: 'Tree', variant: this.viewMode === 'tree' ? 'brand' : 'neutral' }
        ];
    }

    get selectedNode() {
        return this.selectedNodeId ? this.nodeById.get(this.selectedNodeId) : null;
    }

    get selectedNodeType() {
        return this.selectedNode?.componentType || 'Unknown';
    }

    get selectedNodeDepth() {
        return this.selectedNode?.depth ?? 0;
    }

    get selectedNodeSetupUrl() {
        return this.selectedNode?.setupUrl;
    }

    get selectedNodeConnectionCount() {
        return this.adjacentById.get(this.selectedNodeId)?.size || 0;
    }

    get selectedDirectionLabel() {
        if (!this.selectedNode) {
            return 'Select a node to inspect dependencies.';
        }
        if (this.selectedNode.isRoot) {
            return 'Root component. Outgoing arrows point to components that use this root.';
        }
        return 'This component uses an upstream dependency in this blast radius chain.';
    }

    get legendItems() {
        return LEGEND.map((item, idx) => {
            const color = item.color || TYPE_COLORS[item.type] || '#5F6A7D';
            const slug = (item.type || item.label || 'item').replace(/\s+/g, '-').toLowerCase();
            return {
                ...item,
                key: `legend-${idx}-${slug}`,
                color,
                pillClass: `legend-pill-icon legend-pill-icon-${slug}`
            };
        });
    }

    get statNodes() {
        return this.response?.stats?.totalNodes ?? 0;
    }

    get statEdges() {
        return this.response?.stats?.totalEdges ?? 0;
    }

    get statDepth() {
        return this.response?.stats?.maxDepthReached ?? 0;
    }

    get statCycles() {
        const nodes = this.response?.nodes || [];
        return nodes.filter(node => node.isCycleNode).length;
    }

    get warningMessage() {
        return this.response?.warningMessage;
    }

    get typeFilterOptions() {
        const nodesByType = this.response?.stats?.nodesByType || {};
        return Object.keys(nodesByType)
            .sort((a, b) => a.localeCompare(b))
            .map(type => ({
                type,
                checked: this.typeFilterState[type] !== false,
                label: `${this.toTypeLabel(type)} (${nodesByType[type]})`
            }));
    }

    async tryLoad() {
        if (!this._metadataType || !this._componentName) {
            return;
        }

        this.isLoading = true;
        this.error = null;
        this.response = null;

        try {
            const data = await getBlastRadius({
                metadataType: this._metadataType,
                componentName: this._componentName,
                maxDepth: this.maxDepth
            });

            this.response = data;
            this.nodeById = new Map((data.nodes || []).map(node => [node.id, node]));
            this.selectedNodeId = this.getDefaultSelectedNodeId(data.nodes || []);
            this.searchQuery = '';
            this.collapsedNodeIds = new Set();
            this.zoomScale = 1;
            this.panX = 0;
            this.panY = 0;
            this._hasFittedInitialView = false;
            this.initializeTypeFilters();
            this.reindexGraph();
            this.lastRenderKey = null;
            this._d3RenderKey = null;
        } catch (error) {
            this.error = this.reduceError(error);
            this.response = null;
            this.nodeById = new Map();
            this.selectedNodeId = null;
            this.hoveredNodeId = null;
            this.childrenById = new Map();
            this.parentsById = new Map();
            this.adjacentById = new Map();
            this.outgoingById = new Map();
        } finally {
            this.isLoading = false;
        }
    }

    initializeTypeFilters() {
        const nextState = {};
        const nodesByType = this.response?.stats?.nodesByType || {};

        Object.keys(nodesByType).forEach(type => {
            nextState[type] = this.typeFilterState[type] !== false;
        });

        this.typeFilterState = nextState;
    }

    reindexGraph() {
        const nextChildren = new Map();
        const nextParents = new Map();
        const nextAdjacent = new Map();
        const nextOutgoing = new Map();

        (this.response?.nodes || []).forEach(node => {
            nextChildren.set(node.id, []);
            nextParents.set(node.id, []);
            nextAdjacent.set(node.id, new Set());
            nextOutgoing.set(node.id, []);
        });

        (this.response?.edges || []).forEach(edge => {
            if (!nextChildren.has(edge.sourceId) || !nextChildren.has(edge.targetId)) {
                return;
            }

            nextChildren.get(edge.sourceId).push(edge.targetId);
            nextParents.get(edge.targetId).push(edge.sourceId);
            nextAdjacent.get(edge.sourceId).add(edge.targetId);
            nextAdjacent.get(edge.targetId).add(edge.sourceId);
            nextOutgoing.get(edge.sourceId).push(edge);
        });

        this.childrenById = nextChildren;
        this.parentsById = nextParents;
        this.adjacentById = nextAdjacent;
        this.outgoingById = nextOutgoing;
    }

    getDefaultSelectedNodeId(nodes) {
        const root = nodes.find(node => node.isRoot);
        return (root || nodes[0] || {}).id;
    }

    handleDepthClick(event) {
        const nextDepth = Number(event.currentTarget.dataset.depth);
        if (nextDepth === this.maxDepth) {
            return;
        }

        this.maxDepth = nextDepth;
        this.tryLoad();
    }

    handleViewModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.viewMode) {
            return;
        }

        if (this.simulation) {
            this.simulation.stop();
            this.simulation = null;
        }

        this.viewMode = mode;
        this.lastRenderKey = null;
        this._d3RenderKey = null;

        const layer = this.template.querySelector('.graph-content');
        if (layer) {
            layer.replaceChildren();
        }

        this.renderGraph();
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleZoomFit() {
        if (!this.hasData) {
            return;
        }

        this.fitGraphToViewport();
    }

    handleSearchInput(event) {
        this.searchQuery = String(event.target.value || '');
        this.lastRenderKey = null;
        this._d3RenderKey = null;
        this.renderGraph();
    }

    handleTypeFilterChange(event) {
        const type = event.currentTarget.dataset.type;
        const checked = event.target.checked;
        this.typeFilterState = {
            ...this.typeFilterState,
            [type]: checked
        };

        this.lastRenderKey = null;
        this._d3RenderKey = null;
        this.renderGraph();
    }

    async handleExportSelect(event) {
        const action = event.detail.value;
        if (action === 'mermaid') {
            await this.copyMermaid();
        }
        if (action === 'svg') {
            this.downloadSvg();
        }
    }

    async copyMermaid() {
        const lines = ['graph LR'];
        const nodes = this.response?.nodes || [];
        const edges = this.response?.edges || [];
        const safeId = value => `n_${String(value).replace(/[^a-zA-Z0-9_]/g, '_')}`;

        nodes.forEach(node => {
            lines.push(`    ${safeId(node.id)}["${String(node.name).replace(/"/g, '\\"')}"]`);
        });

        edges.forEach(edge => {
            lines.push(`    ${safeId(edge.sourceId)} --> ${safeId(edge.targetId)}`);
        });

        try {
            await navigator.clipboard.writeText(lines.join('\n'));
        } catch (error) {
            this.error = 'Unable to copy Mermaid to clipboard.';
        }
    }

    downloadSvg() {
        const svg = this.template.querySelector('svg');
        if (!svg) {
            return;
        }

        const serializer = new XMLSerializer();
        const source = serializer.serializeToString(svg);
        const blob = new Blob([source], { type: 'image/svg+xml;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = `${this._componentName || 'blast-radius'}.svg`;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        URL.revokeObjectURL(url);
    }

    handleOpenSetup() {
        if (this.selectedNodeSetupUrl) {
            window.open(this.selectedNodeSetupUrl, '_blank', 'noopener,noreferrer');
        }
    }

    bindViewportInteractions() {
        if (this._viewportBound) {
            return;
        }

        const viewport = this.template.querySelector('.graph-viewport');
        if (!viewport) {
            return;
        }

        this._viewportWheelHandler = event => this.handleWheel(event);
        this._viewportMouseDownHandler = event => this.handlePointerDown(event);
        this._windowMouseMoveHandler = event => this.handlePointerMove(event);
        this._windowMouseUpHandler = () => this.handlePointerUp();

        viewport.addEventListener('wheel', this._viewportWheelHandler, { passive: false });
        viewport.addEventListener('mousedown', this._viewportMouseDownHandler);
        window.addEventListener('mousemove', this._windowMouseMoveHandler);
        window.addEventListener('mouseup', this._windowMouseUpHandler);
        this._viewportBound = true;
    }

    handleWheel(event) {
        if (!this.hasData) {
            return;
        }

        event.preventDefault();
        const delta = event.deltaY > 0 ? -0.08 : 0.08;
        this.zoomScale = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, this.zoomScale + delta));
        this.updateGraphTransform();
        this.lastRenderKey = null;
    }

    handlePointerDown(event) {
        if (!this.hasData || event.button !== 0) {
            return;
        }

        if (event.target?.closest('.node-group')) {
            return;
        }

        this._pointerDown = true;
        this._dragStartX = event.clientX;
        this._dragStartY = event.clientY;
        this._dragOriginX = this.panX;
        this._dragOriginY = this.panY;
    }

    handlePointerMove(event) {
        if (!this._pointerDown) {
            return;
        }

        const dx = (event.clientX - this._dragStartX) / this.zoomScale;
        const dy = (event.clientY - this._dragStartY) / this.zoomScale;
        this.panX = this._dragOriginX + dx;
        this.panY = this._dragOriginY + dy;
        this.updateGraphTransform();
    }

    handlePointerUp() {
        this._pointerDown = false;
    }

    updateGraphTransform() {
        const layer = this.template.querySelector('.graph-content');
        if (!layer) {
            return;
        }

        layer.setAttribute(
            'transform',
            `translate(${this.panX} ${this.panY}) scale(${this.zoomScale})`
        );
    }

    fitGraphToViewport() {
        const viewport = this.template.querySelector('.graph-viewport');
        if (!viewport || !this.lastLayout) {
            return;
        }

        const pad = 32;
        const nextScale = Math.min(
            (viewport.clientWidth - pad) / this.lastLayout.width,
            (viewport.clientHeight - pad) / this.lastLayout.height,
            1
        );

        this.zoomScale = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, nextScale));
        this.panX = ((viewport.clientWidth / this.zoomScale) - this.lastLayout.width) / 2;
        this.panY = ((viewport.clientHeight / this.zoomScale) - this.lastLayout.height) / 2;
        this.updateGraphTransform();
        this.lastRenderKey = null;
    }

    renderGraph() {
        if (this.viewMode === 'force') {
            this.renderForceGraph();
            return;
        }
        if (this.viewMode === 'tree') {
            this.renderTreeView();
            return;
        }

        // --- Radial layout (existing) ---
        const svg = this.template.querySelector('svg');
        const layer = this.template.querySelector('.graph-content');
        const viewport = this.template.querySelector('.graph-viewport');

        if (!svg || !layer || !viewport || !this.hasData) {
            if (layer) {
                layer.replaceChildren();
            }
            return;
        }

        const visible = this.computeVisibleGraph();
        const key = JSON.stringify({
            viewMode: this.viewMode,
            selectedNodeId: this.selectedNodeId,
            hoveredNodeId: this.hoveredNodeId,
            zoomScale: this.zoomScale,
            panX: Math.round(this.panX),
            panY: Math.round(this.panY),
            searchTerm: this.normalizedSearchTerm,
            collapsedCount: this.collapsedNodeIds.size,
            visibleNodeCount: visible.nodes.length,
            width: viewport.clientWidth,
            height: viewport.clientHeight
        });

        if (key === this.lastRenderKey) {
            return;
        }

        this.lastRenderKey = key;

        const layout = this.buildRadialLayout(visible.nodes, viewport.clientHeight);
        this.lastLayout = layout;

        svg.setAttribute('viewBox', `0 0 ${layout.width} ${layout.height}`);
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', String(layout.height));

        layer.replaceChildren();
        this.drawDefs(layer);
        this.drawEdges(layer, visible.edges, layout.positions);
        this.drawNodes(layer, visible.nodes, layout.positions);

        this.updateGraphTransform();

        if (!this._hasFittedInitialView) {
            this._hasFittedInitialView = true;
            this.fitGraphToViewport();
        }
    }

    async renderForceGraph() {
        const svg = this.template.querySelector('svg');
        const layer = this.template.querySelector('.graph-content');
        const viewport = this.template.querySelector('.graph-viewport');

        if (!svg || !layer || !viewport || !this.hasData) {
            if (layer) layer.replaceChildren();
            return;
        }

        if (!this.d3) {
            try {
                this.d3 = await loadD3(this);
            } catch (e) {
                this.error = 'Failed to load D3 library.';
                return;
            }
        }

        const d3 = this.d3;
        const visible = this.computeVisibleGraph();

        // Only do a full rebuild when structural data has changed, not on hover/select
        const structKey = `force:${visible.nodes.length}:${visible.edges.length}:${this.collapsedNodeIds.size}:${this.normalizedSearchTerm}:${viewport.clientWidth}:${viewport.clientHeight}`;
        if (structKey === this._d3RenderKey) {
            return;
        }
        this._d3RenderKey = structKey;
        const width = Math.max(viewport.clientWidth, MIN_CANVAS_WIDTH);
        const height = Math.max(viewport.clientHeight, MIN_CANVAS_HEIGHT);

        // Seed positions from radial layout so graph doesn't explode from origin
        const seedLayout = this.buildRadialLayout(visible.nodes, height);

        svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', String(height));
        this.lastLayout = { width, height, positions: seedLayout.positions };

        // Reset transform for D3-managed pan/zoom
        layer.setAttribute('transform', 'translate(0,0) scale(1)');

        layer.replaceChildren();

        // Draw arrow defs
        this.drawDefs(layer);

        // D3 data
        const nodeData = visible.nodes.map(node => {
            const seed = seedLayout.positions.get(node.id) || { x: width / 2, y: height / 2 };
            return { ...node, x: seed.x, y: seed.y, fx: null, fy: null };
        });

        const nodeIndex = new Map(nodeData.map((n, i) => [n.id, i]));

        const linkData = visible.edges
            .filter(e => nodeIndex.has(e.sourceId) && nodeIndex.has(e.targetId))
            .map(e => ({
                source: nodeIndex.get(e.sourceId),
                target: nodeIndex.get(e.targetId),
                sourceId: e.sourceId,
                targetId: e.targetId
            }));

        // Stop any previous simulation
        if (this.simulation) {
            this.simulation.stop();
            this.simulation = null;
        }

        const SVG_NS_LOCAL = 'http://www.w3.org/2000/svg';

        // Create link elements
        const linkEls = linkData.map(link => {
            const path = document.createElementNS(SVG_NS_LOCAL, 'path');
            path.setAttribute('class', 'd3-link edge');
            path.setAttribute('stroke-width', '1.5');
            path.setAttribute('marker-end', 'url(#edge-arrow)');
            path.setAttribute('data-source-id', link.sourceId);
            path.setAttribute('data-target-id', link.targetId);
            layer.appendChild(path);
            return { el: path, link };
        });

        // Create node groups
        const nodeEls = nodeData.map(node => {
            const group = document.createElementNS(SVG_NS_LOCAL, 'g');
            group.setAttribute('class', 'node-group');
            group.setAttribute('data-node-id', node.id);
            this.buildNodeGroup(group, node);
            layer.appendChild(group);
            return { el: group, node };
        });

        const updateNodeVisuals = () => {
            const focusNodeId = this.hoveredNodeId || this.selectedNodeId;
            const connectedSet = this.adjacentById.get(focusNodeId) || new Set();
            const normalizedSearch = this.normalizedSearchTerm;
            const hasSearch = Boolean(normalizedSearch);

            nodeEls.forEach(({ el, node }) => {
                const isFocused = node.id === focusNodeId;
                const isNeighbor = connectedSet.has(node.id);
                const dimmed = focusNodeId && !isFocused && !isNeighbor;
                const selected = this.selectedNodeId === node.id;
                const searchMatch = hasSearch && node.name.toLowerCase().includes(normalizedSearch);

                const baseRect = el.querySelector('.node-body');
                if (baseRect) {
                    baseRect.setAttribute(
                        'class',
                        selected
                            ? 'node-body node-selected'
                            : dimmed
                              ? 'node-body node-dim'
                              : searchMatch
                                ? 'node-body node-search'
                                : 'node-body'
                    );
                }

                const focusNodeIdForEdges = this.hoveredNodeId || this.selectedNodeId;
                linkEls.forEach(({ el: lel, link }) => {
                    const isFocusedEdge = link.sourceId === focusNodeIdForEdges || link.targetId === focusNodeIdForEdges;
                    const isNeighborEdge = connectedSet.has(link.sourceId) || connectedSet.has(link.targetId);
                    const shouldDim = focusNodeIdForEdges && !isFocusedEdge && !isNeighborEdge;
                    lel.setAttribute(
                        'class',
                        shouldDim ? 'd3-link edge edge-dim' : isFocusedEdge ? 'd3-link edge edge-focus' : 'd3-link edge'
                    );
                });
            });
        };

        // D3 simulation
        const sim = d3.forceSimulation(nodeData)
            .force('link', d3.forceLink(linkData).distance(180))
            .force('charge', d3.forceManyBody().strength(-400))
            .force('center', d3.forceCenter(width / 2, height / 2))
            .force('collision', d3.forceCollide().radius(100));

        this.simulation = sim;

        let tickCount = 0;

        sim.on('tick', () => {
            tickCount++;

            nodeEls.forEach(({ el, node }) => {
                el.setAttribute('transform', `translate(${node.x} ${node.y})`);
            });

            linkEls.forEach(({ el, link }) => {
                // After first tick, D3 forceLink replaces source/target indices with node objects
                const s = typeof link.source === 'object' ? link.source : nodeData[link.source];
                const t = typeof link.target === 'object' ? link.target : nodeData[link.target];
                if (!s || !t) return;
                const startX = s.x + NODE_WIDTH / 2 - 8;
                const startY = s.y;
                const endX = t.x - NODE_WIDTH / 2 + 8;
                const endY = t.y;
                const dist = Math.max(120, Math.abs(endX - startX));
                const cx1 = startX + dist * 0.42;
                const cx2 = endX - dist * 0.42;
                el.setAttribute('d', `M ${startX} ${startY} C ${cx1} ${startY} ${cx2} ${endY} ${endX} ${endY}`);
            });

            if (tickCount >= 300) {
                sim.stop();
            }
        });

        // D3 zoom (replace manual pan/zoom for force view)
        const svgEl = this.template.querySelector('.graph-svg');
        if (svgEl) {
            const zoom = d3.zoom()
                .scaleExtent([MIN_ZOOM, MAX_ZOOM])
                .on('zoom', event => {
                    layer.setAttribute('transform', event.transform.toString());
                });

            d3.select(svgEl).call(zoom);
        }

        // D3 drag
        const drag = d3.drag()
            .on('start', (event, d) => {
                if (!event.active) sim.alphaTarget(0.3).restart();
                d.fx = d.x;
                d.fy = d.y;
            })
            .on('drag', (event, d) => {
                d.fx = event.x;
                d.fy = event.y;
            })
            .on('end', (event, d) => {
                if (!event.active) sim.alphaTarget(0);
                d.fx = null;
                d.fy = null;
            });

        nodeEls.forEach(({ el, node }) => {
            d3.select(el).datum(node).call(drag);

            el.addEventListener('mouseenter', () => {
                this.hoveredNodeId = node.id;
                updateNodeVisuals();
            });
            el.addEventListener('mouseleave', () => {
                this.hoveredNodeId = null;
                updateNodeVisuals();
            });
            el.addEventListener('click', () => {
                this.selectedNodeId = node.id;
                updateNodeVisuals();
            });
            el.addEventListener('dblclick', event => {
                event.stopPropagation();
                this.handleNodeRecentering(node);
            });
        });

        updateNodeVisuals();
    }

    async renderTreeView() {
        const svg = this.template.querySelector('svg');
        const layer = this.template.querySelector('.graph-content');
        const viewport = this.template.querySelector('.graph-viewport');

        if (!svg || !layer || !viewport || !this.hasData) {
            if (layer) layer.replaceChildren();
            return;
        }

        if (!this.d3) {
            try {
                this.d3 = await loadD3(this);
            } catch (e) {
                this.error = 'Failed to load D3 library.';
                return;
            }
        }

        const d3 = this.d3;
        const visible = this.computeVisibleGraph();

        if (!visible.nodes.length) {
            layer.replaceChildren();
            return;
        }

        // Only do a full rebuild when structural data has changed, not on hover/select
        const structKey = `tree:${visible.nodes.length}:${visible.edges.length}:${this.collapsedNodeIds.size}:${this.normalizedSearchTerm}:${viewport.clientWidth}:${viewport.clientHeight}`;
        if (structKey === this._d3RenderKey) {
            return;
        }
        this._d3RenderKey = structKey;

        const SVG_NS_LOCAL = 'http://www.w3.org/2000/svg';

        // Build parent map: each node gets its first parent (or null for root)
        const firstParentMap = new Map();
        visible.nodes.forEach(node => firstParentMap.set(node.id, null));
        visible.edges.forEach(edge => {
            // edge: sourceId → targetId (source uses target upstream)
            // For tree hierarchy: sourceId is the child referencing its parent targetId
            if (firstParentMap.get(edge.sourceId) === null) {
                firstParentMap.set(edge.sourceId, edge.targetId);
            }
        });

        // Ensure root has no parent; detect roots (nodes with no incoming edges)
        const hasIncoming = new Set(visible.edges.map(e => e.sourceId));
        const rootNodes = visible.nodes.filter(n => !hasIncoming.has(n.id) || n.isRoot);

        // Use single root or create synthetic root
        let hierarchyData;
        if (rootNodes.length === 1) {
            hierarchyData = visible.nodes;
            firstParentMap.set(rootNodes[0].id, null);
        } else {
            const syntheticRoot = { id: '__synthetic_root__', name: 'Root', componentType: 'Root', depth: -1, isRoot: true };
            hierarchyData = [syntheticRoot, ...visible.nodes];
            firstParentMap.set(syntheticRoot.id, null);
            rootNodes.forEach(n => firstParentMap.set(n.id, syntheticRoot.id));
        }

        let root;
        try {
            root = d3.stratify()
                .id(d => d.id)
                .parentId(d => firstParentMap.get(d.id) || null)(hierarchyData);
        } catch (_e) {
            // Fallback: single root from isRoot
            const fallbackRoot = visible.nodes.find(n => n.isRoot) || visible.nodes[0];
            const fallbackParentMap = new Map([[fallbackRoot.id, null]]);
            visible.edges.forEach(edge => {
                if (!fallbackParentMap.has(edge.sourceId)) {
                    fallbackParentMap.set(edge.sourceId, edge.targetId);
                }
            });
            const fallbackNodes = visible.nodes.filter(n => fallbackParentMap.has(n.id));
            try {
                root = d3.stratify()
                    .id(d => d.id)
                    .parentId(d => fallbackParentMap.get(d.id) || null)(fallbackNodes);
            } catch (_e2) {
                this.error = 'Could not build tree layout for this graph.';
                return;
            }
        }

        const NODE_W = NODE_WIDTH;
        const NODE_H = NODE_HEIGHT;
        const H_GAP = 240;
        const V_GAP = 80;

        const treeLayout = d3.tree()
            .nodeSize([NODE_H + V_GAP, NODE_W + H_GAP]);

        treeLayout(root);

        // Horizontal tree: swap x and y (x becomes depth/column, y becomes row)
        const allTreeNodes = root.descendants();
        const minY = d3.min(allTreeNodes, d => d.x) || 0;
        const maxY = d3.max(allTreeNodes, d => d.x) || 0;
        const minX = d3.min(allTreeNodes, d => d.y) || 0;
        const maxX = d3.max(allTreeNodes, d => d.y) || 0;

        const pad = 80;
        const canvasW = Math.max(MIN_CANVAS_WIDTH, maxX - minX + NODE_W + pad * 2);
        const canvasH = Math.max(MIN_CANVAS_HEIGHT, maxY - minY + NODE_H + pad * 2);

        svg.setAttribute('viewBox', `0 0 ${canvasW} ${canvasH}`);
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', String(canvasH));
        this.lastLayout = { width: canvasW, height: canvasH, positions: new Map() };

        layer.setAttribute('transform', 'translate(0,0) scale(1)');
        layer.replaceChildren();

        this.drawDefs(layer);

        // Translate so tree starts with padding
        const offsetX = pad - minX;
        const offsetY = pad - minY + (canvasH - (maxY - minY) - NODE_H) / 2;

        const treeGroup = document.createElementNS(SVG_NS_LOCAL, 'g');
        treeGroup.setAttribute('transform', `translate(${offsetX} ${offsetY})`);
        layer.appendChild(treeGroup);

        // Draw links
        allTreeNodes.forEach(d => {
            if (!d.parent) return;
            const px = d.parent.y;
            const py = d.parent.x;
            const cx = d.y;
            const cy = d.x;

            const startX = px + NODE_W / 2 - 8;
            const startY = py;
            const endX = cx - NODE_W / 2 + 8;
            const endY = cy;
            const dist = Math.max(60, Math.abs(endX - startX));

            const path = document.createElementNS(SVG_NS_LOCAL, 'path');
            path.setAttribute('d', `M ${startX} ${startY} C ${startX + dist * 0.42} ${startY} ${endX - dist * 0.42} ${endY} ${endX} ${endY}`);
            path.setAttribute('class', 'd3-link edge');
            path.setAttribute('stroke-width', '1.5');
            path.setAttribute('marker-end', 'url(#edge-arrow)');
            treeGroup.appendChild(path);
        });

        // Draw nodes
        const focusNodeId = this.hoveredNodeId || this.selectedNodeId;
        const connectedSet = this.adjacentById.get(focusNodeId) || new Set();
        const normalizedSearch = this.normalizedSearchTerm;
        const hasSearch = Boolean(normalizedSearch);

        allTreeNodes.forEach(d => {
            const node = d.data;
            if (node.id === '__synthetic_root__') return;

            const group = document.createElementNS(SVG_NS_LOCAL, 'g');
            group.setAttribute('class', 'node-group');
            group.setAttribute('data-node-id', node.id);
            group.setAttribute('transform', `translate(${d.y} ${d.x})`);

            const isFocused = node.id === focusNodeId;
            const isNeighbor = connectedSet.has(node.id);
            const dimmed = focusNodeId && !isFocused && !isNeighbor;
            const selected = this.selectedNodeId === node.id;
            const searchMatch = hasSearch && node.name.toLowerCase().includes(normalizedSearch);

            const bodyClass = selected
                ? 'node-body node-selected'
                : dimmed
                  ? 'node-body node-dim'
                  : searchMatch
                    ? 'node-body node-search'
                    : 'node-body';

            this.buildNodeGroup(group, node, bodyClass);

            // Collapse toggle (D3 tree collapse)
            if (d.children || d._children) {
                const toggle = document.createElementNS(SVG_NS_LOCAL, 'g');
                toggle.setAttribute('class', 'collapse-toggle');
                const tc = document.createElementNS(SVG_NS_LOCAL, 'circle');
                tc.setAttribute('cx', String(NODE_W / 2 - 16));
                tc.setAttribute('cy', String(NODE_H / 2 - 12));
                tc.setAttribute('r', '10');
                const tl = document.createElementNS(SVG_NS_LOCAL, 'text');
                tl.setAttribute('x', String(NODE_W / 2 - 16));
                tl.setAttribute('y', String(NODE_H / 2 - 8));
                tl.setAttribute('text-anchor', 'middle');
                tl.textContent = d._children ? '+' : '-';
                toggle.appendChild(tc);
                toggle.appendChild(tl);
                toggle.addEventListener('click', event => {
                    event.stopPropagation();
                    if (d.children) {
                        d._children = d.children;
                        d.children = null;
                    } else {
                        d.children = d._children;
                        d._children = null;
                    }
                    this.renderTreeView();
                });
                group.appendChild(toggle);
            }

            group.addEventListener('mouseenter', () => {
                this.hoveredNodeId = node.id;
                this.lastRenderKey = null;
                this.renderTreeView();
            });
            group.addEventListener('mouseleave', () => {
                this.hoveredNodeId = null;
                this.lastRenderKey = null;
                this.renderTreeView();
            });
            group.addEventListener('click', () => {
                this.selectedNodeId = node.id;
                this.lastRenderKey = null;
                this.renderTreeView();
            });
            group.addEventListener('dblclick', event => {
                event.stopPropagation();
                this.handleNodeRecentering(node);
            });

            treeGroup.appendChild(group);
        });

        // D3 zoom
        const svgEl = this.template.querySelector('.graph-svg');
        if (svgEl) {
            const zoom = d3.zoom()
                .scaleExtent([MIN_ZOOM, MAX_ZOOM])
                .on('zoom', event => {
                    layer.setAttribute('transform', event.transform.toString());
                });

            d3.select(svgEl).call(zoom);
        }

        if (!this._hasFittedInitialView) {
            this._hasFittedInitialView = true;
        }
    }

    // Shared helper: builds SVG elements inside a node group (without transform — caller sets it)
    buildNodeGroup(group, node, bodyClassOverride) {
        const SVG_NS_LOCAL = 'http://www.w3.org/2000/svg';
        const focusNodeId = this.hoveredNodeId || this.selectedNodeId;
        const connectedSet = this.adjacentById.get(focusNodeId) || new Set();
        const normalizedSearch = this.normalizedSearchTerm;
        const hasSearch = Boolean(normalizedSearch);

        const isFocused = node.id === focusNodeId;
        const isNeighbor = connectedSet.has(node.id);
        const dimmed = focusNodeId && !isFocused && !isNeighbor;
        const selected = this.selectedNodeId === node.id;
        const searchMatch = hasSearch && node.name.toLowerCase().includes(normalizedSearch);

        const resolvedBodyClass = bodyClassOverride || (
            selected
                ? 'node-body node-selected'
                : dimmed
                  ? 'node-body node-dim'
                  : searchMatch
                    ? 'node-body node-search'
                    : 'node-body'
        );

        const baseRect = document.createElementNS(SVG_NS_LOCAL, 'rect');
        baseRect.setAttribute('x', String(-NODE_WIDTH / 2));
        baseRect.setAttribute('y', String(-NODE_HEIGHT / 2));
        baseRect.setAttribute('width', String(NODE_WIDTH));
        baseRect.setAttribute('height', String(NODE_HEIGHT));
        baseRect.setAttribute('rx', '10');
        baseRect.setAttribute('class', resolvedBodyClass);

        const stripe = document.createElementNS(SVG_NS_LOCAL, 'rect');
        stripe.setAttribute('x', String(-NODE_WIDTH / 2));
        stripe.setAttribute('y', String(-NODE_HEIGHT / 2));
        stripe.setAttribute('width', '7');
        stripe.setAttribute('height', String(NODE_HEIGHT));
        stripe.setAttribute('rx', '10');
        stripe.setAttribute('class', 'node-stripe');
        stripe.setAttribute('fill', this.getNodeColor(node));

        const iconText = document.createElementNS(SVG_NS_LOCAL, 'text');
        iconText.setAttribute('x', String(-NODE_WIDTH / 2 + 18));
        iconText.setAttribute('y', '4');
        iconText.setAttribute('class', 'node-icon');
        iconText.textContent = this.getTypeIcon(node.componentType);

        const label = document.createElementNS(SVG_NS_LOCAL, 'text');
        label.setAttribute('x', String(-NODE_WIDTH / 2 + 36));
        label.setAttribute('y', '4');
        label.setAttribute('class', 'node-label');
        label.textContent = this.truncate(node.name, MAX_LABEL_LENGTH);

        const depthBadge = document.createElementNS(SVG_NS_LOCAL, 'circle');
        depthBadge.setAttribute('cx', String(NODE_WIDTH / 2 - 14));
        depthBadge.setAttribute('cy', String(-NODE_HEIGHT / 2 + 14));
        depthBadge.setAttribute('r', '10');
        depthBadge.setAttribute('class', 'depth-badge');

        const depthText = document.createElementNS(SVG_NS_LOCAL, 'text');
        depthText.setAttribute('x', String(NODE_WIDTH / 2 - 14));
        depthText.setAttribute('y', String(-NODE_HEIGHT / 2 + 18));
        depthText.setAttribute('text-anchor', 'middle');
        depthText.setAttribute('class', 'depth-text');
        depthText.textContent = String(node.depth ?? 0);

        const title = document.createElementNS(SVG_NS_LOCAL, 'title');
        title.textContent = `${node.name} | ${this.toTypeLabel(node.componentType)} | depth ${node.depth || 0} | ${this.adjacentById.get(node.id)?.size || 0} connections`;

        group.appendChild(baseRect);
        group.appendChild(stripe);
        group.appendChild(iconText);
        group.appendChild(label);
        group.appendChild(depthBadge);
        group.appendChild(depthText);
        group.appendChild(title);
    }

    computeVisibleGraph() {
        const allNodes = this.response?.nodes || [];
        const allEdges = this.response?.edges || [];

        const includeSet = new Set();
        const roots = allNodes.filter(node => node.isRoot);

        allNodes.forEach(node => {
            const typeAllowed = this.typeFilterState[node.componentType] !== false;
            if (typeAllowed || node.isRoot) {
                includeSet.add(node.id);
            }
        });

        this.collapsedNodeIds.forEach(nodeId => {
            const hidden = this.findDescendants(nodeId);
            hidden.forEach(descendantId => includeSet.delete(descendantId));
        });

        roots.forEach(root => includeSet.add(root.id));

        if (this.selectedNodeId && !includeSet.has(this.selectedNodeId)) {
            this.selectedNodeId = roots[0]?.id || null;
        }
        if (this.hoveredNodeId && !includeSet.has(this.hoveredNodeId)) {
            this.hoveredNodeId = null;
        }

        const visibleNodes = allNodes.filter(node => includeSet.has(node.id));
        const visibleEdges = allEdges.filter(edge => includeSet.has(edge.sourceId) && includeSet.has(edge.targetId));

        this.visibleNodeIds = includeSet;
        return { nodes: visibleNodes, edges: visibleEdges };
    }

    findDescendants(nodeId) {
        const hidden = new Set();
        const queue = [...(this.childrenById.get(nodeId) || [])];

        while (queue.length) {
            const current = queue.shift();
            if (hidden.has(current)) {
                continue;
            }

            hidden.add(current);
            (this.childrenById.get(current) || []).forEach(next => {
                if (!hidden.has(next)) {
                    queue.push(next);
                }
            });
        }

        return hidden;
    }

    buildRadialLayout(nodes, viewportHeight) {
        const positions = new Map();
        const layers = new Map();

        nodes.forEach(node => {
            const depth = node.depth ?? 0;
            if (!layers.has(depth)) {
                layers.set(depth, []);
            }
            layers.get(depth).push(node);
        });

        const orderedDepths = [...layers.keys()].sort((a, b) => a - b);
        const maxDepth = orderedDepths.length ? Math.max(...orderedDepths) : 0;
        const maxLayer = Math.max(1, ...orderedDepths.map(depth => layers.get(depth).length));

        const width = Math.max(MIN_CANVAS_WIDTH, ROOT_X + maxDepth * 250 + 360);
        const height = Math.max(MIN_CANVAS_HEIGHT, viewportHeight || 0, maxLayer * 84 + 240);
        const rootY = height / 2;

        const rootNode = nodes.find(node => node.isRoot) || nodes[0];
        if (rootNode) {
            positions.set(rootNode.id, { x: ROOT_X, y: rootY });
        }

        orderedDepths
            .filter(depth => depth > 0)
            .forEach(depth => {
                const layerNodes = (layers.get(depth) || [])
                    .filter(node => !node.isRoot)
                    .sort((a, b) => a.name.localeCompare(b.name));

                const spread = Math.min(Math.PI * 0.88, Math.PI * (0.34 + layerNodes.length * 0.05));
                const radius = 200 + depth * 178;

                layerNodes.forEach((node, index) => {
                    const denominator = Math.max(layerNodes.length - 1, 1);
                    const t = layerNodes.length === 1 ? 0.5 : index / denominator;
                    const angle = -spread / 2 + spread * t;

                    const x = ROOT_X + radius * Math.cos(angle);
                    const y = rootY + radius * Math.sin(angle);
                    positions.set(node.id, { x, y });
                });
            });

        return { positions, width, height };
    }

    drawDefs(layer) {
        const defs = document.createElementNS(SVG_NS, 'defs');

        const arrow = document.createElementNS(SVG_NS, 'marker');
        arrow.setAttribute('id', 'edge-arrow');
        arrow.setAttribute('viewBox', '0 0 10 10');
        arrow.setAttribute('refX', '10');
        arrow.setAttribute('refY', '5');
        arrow.setAttribute('markerWidth', '7');
        arrow.setAttribute('markerHeight', '7');
        arrow.setAttribute('orient', 'auto-start-reverse');

        const arrowPath = document.createElementNS(SVG_NS, 'path');
        arrowPath.setAttribute('d', 'M 0 0 L 10 5 L 0 10 z');
        arrowPath.setAttribute('class', 'edge-arrow');
        arrow.appendChild(arrowPath);

        defs.appendChild(arrow);
        layer.appendChild(defs);
    }

    drawEdges(layer, edges, positions) {
        const focusNodeId = this.hoveredNodeId || this.selectedNodeId;
        const connectedSet = this.adjacentById.get(focusNodeId) || new Set();

        edges.forEach(edge => {
            const source = positions.get(edge.sourceId);
            const target = positions.get(edge.targetId);
            const sourceNode = this.nodeById.get(edge.sourceId);

            if (!source || !target) {
                return;
            }

            const path = document.createElementNS(SVG_NS, 'path');
            const startX = source.x + NODE_WIDTH / 2 - 8;
            const startY = source.y;
            const endX = target.x - NODE_WIDTH / 2 + 8;
            const endY = target.y;
            const distance = Math.max(120, Math.abs(endX - startX));
            const controlX1 = startX + distance * 0.42;
            const controlX2 = endX - distance * 0.42;
            const d = `M ${startX} ${startY} C ${controlX1} ${startY} ${controlX2} ${endY} ${endX} ${endY}`;

            const isFocused = edge.sourceId === focusNodeId || edge.targetId === focusNodeId;
            const isNeighbor = connectedSet.has(edge.sourceId) || connectedSet.has(edge.targetId);
            const shouldDim = focusNodeId && !isFocused && !isNeighbor;
            const strokeWidth = Math.max(1.25, 3.1 - ((sourceNode?.depth || 0) * 0.45));

            path.setAttribute('d', d);
            path.setAttribute('class', shouldDim ? 'edge edge-dim' : isFocused ? 'edge edge-focus' : 'edge');
            path.setAttribute('stroke-width', String(strokeWidth));
            path.setAttribute('marker-end', 'url(#edge-arrow)');
            path.setAttribute('data-source-id', edge.sourceId);
            path.setAttribute('data-target-id', edge.targetId);
            layer.appendChild(path);
        });
    }

    drawNodes(layer, nodes, positions) {
        const focusNodeId = this.hoveredNodeId || this.selectedNodeId;
        const connectedSet = this.adjacentById.get(focusNodeId) || new Set();
        const normalizedSearch = this.normalizedSearchTerm;
        const hasSearch = Boolean(normalizedSearch);

        nodes.forEach(node => {
            const point = positions.get(node.id);
            if (!point) {
                return;
            }

            const group = document.createElementNS(SVG_NS, 'g');
            group.setAttribute('class', 'node-group');
            group.setAttribute('data-node-id', node.id);
            group.setAttribute('transform', `translate(${point.x} ${point.y})`);

            const isFocused = node.id === focusNodeId;
            const isNeighbor = connectedSet.has(node.id);
            const dimmed = focusNodeId && !isFocused && !isNeighbor;
            const selected = this.selectedNodeId === node.id;
            const searchMatch = hasSearch && node.name.toLowerCase().includes(normalizedSearch);

            const baseRect = document.createElementNS(SVG_NS, 'rect');
            baseRect.setAttribute('x', String(-NODE_WIDTH / 2));
            baseRect.setAttribute('y', String(-NODE_HEIGHT / 2));
            baseRect.setAttribute('width', String(NODE_WIDTH));
            baseRect.setAttribute('height', String(NODE_HEIGHT));
            baseRect.setAttribute('rx', '10');
            baseRect.setAttribute(
                'class',
                selected
                    ? 'node-body node-selected'
                    : dimmed
                      ? 'node-body node-dim'
                      : searchMatch
                        ? 'node-body node-search'
                        : 'node-body'
            );

            const stripe = document.createElementNS(SVG_NS, 'rect');
            stripe.setAttribute('x', String(-NODE_WIDTH / 2));
            stripe.setAttribute('y', String(-NODE_HEIGHT / 2));
            stripe.setAttribute('width', '7');
            stripe.setAttribute('height', String(NODE_HEIGHT));
            stripe.setAttribute('rx', '10');
            stripe.setAttribute('class', 'node-stripe');
            stripe.setAttribute('fill', this.getNodeColor(node));

            const iconText = document.createElementNS(SVG_NS, 'text');
            iconText.setAttribute('x', String(-NODE_WIDTH / 2 + 18));
            iconText.setAttribute('y', '4');
            iconText.setAttribute('class', 'node-icon');
            iconText.textContent = this.getTypeIcon(node.componentType);

            const label = document.createElementNS(SVG_NS, 'text');
            label.setAttribute('x', String(-NODE_WIDTH / 2 + 36));
            label.setAttribute('y', '4');
            label.setAttribute('class', 'node-label');
            label.textContent = this.truncate(node.name, MAX_LABEL_LENGTH);

            const depthBadge = document.createElementNS(SVG_NS, 'circle');
            depthBadge.setAttribute('cx', String(NODE_WIDTH / 2 - 14));
            depthBadge.setAttribute('cy', String(-NODE_HEIGHT / 2 + 14));
            depthBadge.setAttribute('r', '10');
            depthBadge.setAttribute('class', 'depth-badge');

            const depthText = document.createElementNS(SVG_NS, 'text');
            depthText.setAttribute('x', String(NODE_WIDTH / 2 - 14));
            depthText.setAttribute('y', String(-NODE_HEIGHT / 2 + 18));
            depthText.setAttribute('text-anchor', 'middle');
            depthText.setAttribute('class', 'depth-text');
            depthText.textContent = String(node.depth ?? 0);

            const title = document.createElementNS(SVG_NS, 'title');
            title.textContent = `${node.name} | ${this.toTypeLabel(node.componentType)} | depth ${node.depth || 0} | ${this.adjacentById.get(node.id)?.size || 0} connections`;

            group.appendChild(baseRect);
            group.appendChild(stripe);
            group.appendChild(iconText);
            group.appendChild(label);
            group.appendChild(depthBadge);
            group.appendChild(depthText);
            group.appendChild(title);

            const childCount = (this.childrenById.get(node.id) || []).filter(childId => this.visibleNodeIds.has(childId)).length;
            if (childCount > 0) {
                const toggle = document.createElementNS(SVG_NS, 'g');
                toggle.setAttribute('class', 'collapse-toggle');

                const toggleCircle = document.createElementNS(SVG_NS, 'circle');
                toggleCircle.setAttribute('cx', String(NODE_WIDTH / 2 - 16));
                toggleCircle.setAttribute('cy', String(NODE_HEIGHT / 2 - 12));
                toggleCircle.setAttribute('r', '10');

                const toggleLabel = document.createElementNS(SVG_NS, 'text');
                toggleLabel.setAttribute('x', String(NODE_WIDTH / 2 - 16));
                toggleLabel.setAttribute('y', String(NODE_HEIGHT / 2 - 8));
                toggleLabel.setAttribute('text-anchor', 'middle');
                toggleLabel.textContent = this.collapsedNodeIds.has(node.id) ? '+' : '-';

                toggle.appendChild(toggleCircle);
                toggle.appendChild(toggleLabel);
                toggle.addEventListener('click', event => {
                    event.stopPropagation();
                    this.toggleNodeCollapse(node.id);
                });
                group.appendChild(toggle);
            }

            group.addEventListener('mouseenter', () => {
                this.hoveredNodeId = node.id;
                this.lastRenderKey = null;
                this.renderGraph();
            });
            group.addEventListener('mouseleave', () => {
                this.hoveredNodeId = null;
                this.lastRenderKey = null;
                this.renderGraph();
            });
            group.addEventListener('click', () => {
                this.selectedNodeId = node.id;
                this.lastRenderKey = null;
                this.renderGraph();
            });
            group.addEventListener('dblclick', event => {
                event.stopPropagation();
                this.handleNodeRecentering(node);
            });

            layer.appendChild(group);
        });
    }

    handleNodeRecentering(node) {
        if (!node || node.isRoot) {
            return;
        }

        this._metadataType = node.componentType;
        this._componentName = node.name;
        this.maxDepth = Math.max(1, this.maxDepth);
        this._hasFittedInitialView = false;
        this.tryLoad();
    }

    toggleNodeCollapse(nodeId) {
        const next = new Set(this.collapsedNodeIds);
        if (next.has(nodeId)) {
            next.delete(nodeId);
        } else {
            next.add(nodeId);
        }

        this.collapsedNodeIds = next;
        this.lastRenderKey = null;
        this.renderGraph();
    }

    getNodeColor(node) {
        if (node.isRoot) {
            return '#FF538A';
        }
        if (node.isCycleNode) {
            return '#FE9339';
        }
        return TYPE_COLORS[node.componentType] || '#5F6A7D';
    }

    getTypeIcon(type) {
        return TYPE_ICONS[type] || '*';
    }

    truncate(value, size) {
        const text = String(value || '');
        if (text.length <= size) {
            return text;
        }
        return `${text.slice(0, Math.max(size - 3, 1))}...`;
    }

    toTypeLabel(type) {
        if (!type) {
            return 'Unknown';
        }

        const labels = {
            FlowDefinition: 'Flow',
            ApexClass: 'Apex Class',
            ApexTrigger: 'Apex Trigger',
            ValidationRule: 'Validation Rule',
            LightningComponentBundle: 'LWC',
            AuraDefinitionBundle: 'Aura'
        };

        return labels[type] || type;
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }

    get normalizedSearchTerm() {
        return String(this.searchQuery || '').trim().toLowerCase();
    }
}
