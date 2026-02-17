import { LightningElement, api, track } from 'lwc';
import getBlastRadius from '@salesforce/apex/BlastRadiusController.getBlastRadius';

const SVG_NS = 'http://www.w3.org/2000/svg';
const H_SPACING = 180;
const V_SPACING = 60;
const NODE_RADIUS = 14;
const PADDING_X = 70;
const PADDING_Y = 40;

const TYPE_COLORS = {
    Flow: '#1B96FF',
    ApexClass: '#9050E9',
    ApexTrigger: '#BA01FF',
    ValidationRule: '#FE5C4C',
    Layout: '#04844B',
    LightningComponentBundle: '#0D9DDA',
    AuraDefinitionBundle: '#0D9DDA'
};

const LEGEND = [
    { label: 'Flow', color: '#1B96FF' },
    { label: 'Apex Class', color: '#9050E9' },
    { label: 'Apex Trigger', color: '#BA01FF' },
    { label: 'Validation Rule', color: '#FE5C4C' },
    { label: 'Layout', color: '#04844B' },
    { label: 'LWC/Aura', color: '#0D9DDA' },
    { label: 'Root', color: '#FF538A' },
    { label: 'Cycle', color: '#FE9339' }
];

export default class BlastRadiusGraph extends LightningElement {
    _metadataType;
    _componentName;
    _resizeHandler;

    @track maxDepth = 3;
    @track isLoading = false;
    @track error;
    @track response;
    @track selectedNodeId;
    @track zoomScale = 1;

    nodeById = new Map();
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
        this._resizeHandler = () => this.renderGraph();
        window.addEventListener('resize', this._resizeHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._resizeHandler);
    }

    renderedCallback() {
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

    get legendItems() {
        return LEGEND.map(item => ({
            ...item,
            style: `background-color: ${item.color};`
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
            this.zoomScale = 1;
            this.lastRenderKey = null;
        } catch (error) {
            this.error = this.reduceError(error);
            this.response = null;
            this.nodeById = new Map();
            this.selectedNodeId = null;
        } finally {
            this.isLoading = false;
        }
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

        this.zoomScale = 1;
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

        const text = lines.join('\n');
        try {
            await navigator.clipboard.writeText(text);
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
            window.open(this.selectedNodeSetupUrl, '_blank');
        }
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

        const key = JSON.stringify({
            selectedNodeId: this.selectedNodeId,
            zoomScale: this.zoomScale,
            nodeCount: this.response.nodes.length,
            edgeCount: this.response.edges.length,
            width: viewport.clientWidth
        });

        if (key === this.lastRenderKey) {
            return;
        }

        this.lastRenderKey = key;

        const layout = this.buildLayout(this.response.nodes || []);
        const contentWidth = Math.max(layout.width, viewport.clientWidth);
        const contentHeight = Math.max(layout.height, 400);

        svg.setAttribute('viewBox', `0 0 ${contentWidth} ${contentHeight}`);
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', String(contentHeight));

        const fitScale = Math.min(viewport.clientWidth / layout.width, 1);
        const scale = this.zoomScale * fitScale;
        layer.setAttribute('transform', `scale(${scale})`);
        layer.replaceChildren();

        this.drawEdges(layer, this.response.edges || [], layout.positions);
        this.drawNodes(layer, this.response.nodes || [], layout.positions);
    }

    buildLayout(nodes) {
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
        const maxLayerSize = Math.max(
            1,
            ...orderedDepths.map(depth => layers.get(depth).length)
        );

        orderedDepths.forEach(depth => {
            const layerNodes = layers.get(depth).sort((a, b) => a.name.localeCompare(b.name));
            const topOffset = PADDING_Y + ((maxLayerSize - layerNodes.length) * V_SPACING) / 2;

            layerNodes.forEach((node, index) => {
                const x = PADDING_X + depth * H_SPACING;
                const y = topOffset + index * V_SPACING;
                positions.set(node.id, { x, y });
            });
        });

        const maxDepth = orderedDepths.length ? Math.max(...orderedDepths) : 0;
        const width = PADDING_X * 2 + maxDepth * H_SPACING + 220;
        const height = PADDING_Y * 2 + Math.max(1, maxLayerSize - 1) * V_SPACING + 100;

        return { positions, width, height };
    }

    drawEdges(layer, edges, positions) {
        edges.forEach(edge => {
            const source = positions.get(edge.sourceId);
            const target = positions.get(edge.targetId);
            if (!source || !target) {
                return;
            }

            const path = document.createElementNS(SVG_NS, 'path');
            const controlX = (source.x + target.x) / 2;
            const d = `M ${source.x + NODE_RADIUS} ${source.y} Q ${controlX} ${source.y} ${target.x - NODE_RADIUS} ${target.y}`;
            path.setAttribute('d', d);
            path.setAttribute('class', this.isEdgeSelected(edge) ? 'edge selected' : 'edge');
            layer.appendChild(path);
        });
    }

    drawNodes(layer, nodes, positions) {
        nodes.forEach(node => {
            const point = positions.get(node.id);
            if (!point) {
                return;
            }

            const group = document.createElementNS(SVG_NS, 'g');
            group.setAttribute('class', 'node-group');
            group.setAttribute('data-node-id', node.id);

            const circle = document.createElementNS(SVG_NS, 'circle');
            circle.setAttribute('cx', point.x);
            circle.setAttribute('cy', point.y);
            circle.setAttribute('r', NODE_RADIUS);
            circle.setAttribute('fill', this.getNodeColor(node));
            circle.setAttribute('class', this.selectedNodeId === node.id ? 'node selected' : 'node');

            const label = document.createElementNS(SVG_NS, 'text');
            label.setAttribute('x', String(point.x + NODE_RADIUS + 8));
            label.setAttribute('y', String(point.y + 4));
            label.setAttribute('class', 'node-label');
            label.textContent = node.name;

            group.appendChild(circle);
            group.appendChild(label);
            group.addEventListener('click', () => {
                this.selectedNodeId = node.id;
                this.lastRenderKey = null;
                this.renderGraph();
            });
            layer.appendChild(group);
        });
    }

    isEdgeSelected(edge) {
        return edge.sourceId === this.selectedNodeId || edge.targetId === this.selectedNodeId;
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

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
