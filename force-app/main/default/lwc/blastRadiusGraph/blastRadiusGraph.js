import { LightningElement, api, track } from 'lwc';
import getBlastRadius from '@salesforce/apex/BlastRadiusController.getBlastRadius';

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
        return LEGEND.map(item => ({
            ...item,
            color: item.color || TYPE_COLORS[item.type] || '#5F6A7D',
            style: `background-color: ${item.color || TYPE_COLORS[item.type] || '#5F6A7D'};`
        }));
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
