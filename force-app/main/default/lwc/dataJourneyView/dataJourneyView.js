import { LightningElement, api, track } from 'lwc';
import traceDataJourney from '@salesforce/apex/DataJourneyController.traceDataJourney';

const DEFAULT_MAX_DEPTH = '2';
const ROW_HEIGHT = 86;
const SVG_WIDTH = 1000;
const CENTER_X = 500;
const LEFT_X = 260;
const RIGHT_X = 740;
const INDENT_PIXELS = 48;

const NODE_COLORS = {
    field: '#1B96FF',
    flow: '#9050E9',
    apex: '#04844B',
    validationRule: '#FE5C4C',
    formula: '#0D9DDA',
    workflowUpdate: '#FE9339'
};

const NODE_TYPE_LABELS = {
    field: 'Field',
    flow: 'Flow',
    apex: 'Apex',
    validationRule: 'Validation Rule',
    formula: 'Formula',
    workflowUpdate: 'Workflow Field Update'
};

const RELATIONSHIP_LABELS = {
    writes_to: 'writes to',
    read_by: 'reads from',
    triggers: 'triggers',
    feeds_into: 'feeds into'
};

export default class DataJourneyView extends LightningElement {
    @track loading = false;
    @track errorMessage;
    @track selectedDepth = DEFAULT_MAX_DEPTH;
    @track response;
    @track selectedNodeId;

    _objectName;
    _fieldName;
    _lastLoadKey;

    nodesById = {};
    incomingEdgesByTarget = {};

    @api
    get objectName() {
        return this._objectName;
    }

    set objectName(value) {
        this._objectName = value;
        this.tryLoadJourney();
    }

    @api
    get fieldName() {
        return this._fieldName;
    }

    set fieldName(value) {
        this._fieldName = value;
        this.tryLoadJourney();
    }

    get hasValidInput() {
        return Boolean(this._objectName && this._fieldName);
    }

    get headerTitle() {
        return `Data Journey: ${this._objectName || ''}.${this._fieldName || ''}`;
    }

    get depthOptions() {
        return [
            { label: 'Depth 1', value: '1' },
            { label: 'Depth 2', value: '2' },
            { label: 'Depth 3', value: '3' }
        ];
    }

    get hasResponse() {
        return Boolean(this.response);
    }

    get hasWarnings() {
        return Boolean(this.response?.warnings?.length);
    }

    get warningMessage() {
        return this.response?.warnings?.join(' | ') || '';
    }

    get rootNode() {
        return this.decorateNode(this.response?.nodes?.find(n => n.direction === 'root'));
    }

    get upstreamNodes() {
        const nodes = (this.response?.nodes || [])
            .filter(n => n.direction === 'upstream')
            .sort((a, b) => a.name.localeCompare(b.name));
        return nodes.map(node => this.decorateNode(node));
    }

    get downstreamNodes() {
        const nodes = (this.response?.nodes || []).filter(n => n.direction === 'downstream');
        if (!nodes.length) {
            return [];
        }

        const depthMap = this.computeDownstreamDepthMap();
        return nodes
            .map(node => {
                const hopDepth = depthMap[node.id] || 1;
                return {
                    ...this.decorateNode(node),
                    chainDepth: Math.max(hopDepth - 1, 0),
                    sortDepth: hopDepth,
                    indentStyle: `margin-left: ${Math.max(hopDepth - 1, 0) * 1.25}rem;`
                };
            })
            .sort((a, b) => {
                if (a.sortDepth !== b.sortDepth) {
                    return a.sortDepth - b.sortDepth;
                }
                return a.name.localeCompare(b.name);
            });
    }

    get selectedNode() {
        if (!this.selectedNodeId) {
            return null;
        }
        return this.nodesById[this.selectedNodeId] || null;
    }

    get selectedNodeTypeLabel() {
        const nodeType = this.selectedNode?.nodeType;
        return NODE_TYPE_LABELS[nodeType] || 'Metadata';
    }

    get selectedDirectionLabel() {
        const direction = this.selectedNode?.direction;
        if (direction === 'upstream') {
            return 'Upstream';
        }
        if (direction === 'downstream') {
            return 'Downstream';
        }
        return 'Root';
    }

    get selectedRelationshipSummary() {
        if (!this.selectedNode) {
            return '';
        }

        const edges = this.incomingEdgesByTarget[this.selectedNode.id] || [];
        if (!edges.length) {
            return this.deriveRelationshipLabel(this.selectedNode.accessType);
        }

        return [...new Set(edges.map(edge => RELATIONSHIP_LABELS[edge.relationship] || edge.relationship))].join(', ');
    }

    get selectedDetailText() {
        if (!this.selectedNode) {
            return '';
        }

        const edgeDetail = (this.incomingEdgesByTarget[this.selectedNode.id] || [])
            .map(edge => edge.detail)
            .filter(Boolean)
            .join(' | ');

        return this.selectedNode.detail || edgeDetail || 'No additional detail available.';
    }

    get canOpenSetup() {
        return Boolean(this.selectedNode?.setupUrl);
    }

    get totalNodeCount() {
        return this.response?.nodes?.length || 0;
    }

    get totalEdgeCount() {
        return this.response?.edges?.length || 0;
    }

    get canvasHeight() {
        const rows = Math.max(this.upstreamNodes.length, this.downstreamNodes.length, 1);
        return Math.max(260, rows * ROW_HEIGHT + 70);
    }

    get canvasStyle() {
        return `min-height: ${this.canvasHeight}px;`;
    }

    get svgViewBox() {
        return `0 0 ${SVG_WIDTH} ${this.canvasHeight}`;
    }

    get connectorPaths() {
        const centerY = this.canvasHeight / 2;
        const paths = [];

        this.upstreamNodes.forEach((node, index) => {
            const y = 36 + index * ROW_HEIGHT;
            const d = `M ${LEFT_X} ${y} C ${LEFT_X + 70} ${y} ${CENTER_X - 150} ${centerY} ${CENTER_X - 88} ${centerY}`;
            paths.push({ key: `u-${node.id}`, d, marker: 'url(#to-center)' });
        });

        this.downstreamNodes.forEach((node, index) => {
            const y = 36 + index * ROW_HEIGHT;
            const xEnd = RIGHT_X + node.chainDepth * INDENT_PIXELS;
            const d = `M ${CENTER_X + 88} ${centerY} C ${CENTER_X + 180} ${centerY} ${xEnd - 100} ${y} ${xEnd} ${y}`;
            paths.push({ key: `d-${node.id}`, d, marker: 'url(#to-node)' });
        });

        return paths;
    }

    handleDepthChange(event) {
        this.selectedDepth = event.detail.value;
        this.loadJourney();
    }

    handleNodeSelect(event) {
        this.selectedNodeId = event.currentTarget.dataset.id;
    }

    handleOpenSetup() {
        if (this.selectedNode?.setupUrl) {
            window.open(this.selectedNode.setupUrl, '_blank');
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleExportText() {
        if (!this.response) {
            return;
        }

        const sections = [
            `Data Journey: ${this.response.objectName}.${this.response.fieldName}`,
            `Depth: ${this.selectedDepth}`,
            `Nodes: ${this.totalNodeCount}`,
            `Edges: ${this.totalEdgeCount}`,
            ''
        ];

        if (this.response.warnings?.length) {
            sections.push('Warnings:');
            this.response.warnings.forEach(warning => sections.push(`- ${warning}`));
            sections.push('');
        }

        sections.push('Nodes:');
        (this.response.nodes || []).forEach(node => {
            sections.push(
                `- ${node.name} | type=${node.nodeType} | direction=${node.direction} | access=${node.accessType || 'n/a'} | depth=${node.depth}`
            );
        });

        sections.push('');
        sections.push('Edges:');
        (this.response.edges || []).forEach(edge => {
            const sourceName = this.nodesById[edge.sourceId]?.name || edge.sourceId;
            const targetName = this.nodesById[edge.targetId]?.name || edge.targetId;
            sections.push(`- ${sourceName} -> ${targetName} | ${edge.relationship} | ${edge.detail || ''}`);
        });

        const text = sections.join('\n');
        const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = `${this.response.objectName}_${this.response.fieldName}_data_journey.txt`;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        URL.revokeObjectURL(url);
    }

    async loadJourney() {
        if (!this.hasValidInput) {
            return;
        }

        this.loading = true;
        this.errorMessage = undefined;

        try {
            const result = await traceDataJourney({
                objectName: this._objectName,
                fieldName: this._fieldName,
                maxDepth: Number(this.selectedDepth)
            });

            this.response = result;
            this.reindexData();
            this.selectedNodeId = this.rootNode?.id || null;
            this._lastLoadKey = this.computeLoadKey();
        } catch (error) {
            this.response = undefined;
            this.nodesById = {};
            this.incomingEdgesByTarget = {};
            this.selectedNodeId = null;
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load data journey.';
        } finally {
            this.loading = false;
        }
    }

    tryLoadJourney() {
        if (!this.hasValidInput) {
            return;
        }

        const nextKey = this.computeLoadKey();
        if (this._lastLoadKey === nextKey) {
            return;
        }

        this.loadJourney();
    }

    computeLoadKey() {
        return `${this._objectName}::${this._fieldName}::${this.selectedDepth}`;
    }

    decorateNode(node) {
        if (!node) {
            return null;
        }

        const relationshipLabel = this.deriveRelationshipLabel(node.accessType);

        return {
            ...node,
            colorStyle: `background-color: ${NODE_COLORS[node.nodeType] || '#54698D'};`,
            relationshipLabel,
            relationshipClass: relationshipLabel.includes('write') ? 'relation relation-write' : 'relation relation-read',
            isSelected: this.selectedNodeId === node.id,
            cardClass: this.selectedNodeId === node.id ? 'node-card node-selected' : 'node-card'
        };
    }

    deriveRelationshipLabel(accessType) {
        const access = String(accessType || '').toLowerCase();
        if (access.includes('write') && access.includes('read')) {
            return 'reads/writes';
        }
        if (access.includes('write')) {
            return 'writes';
        }
        return 'reads';
    }

    reindexData() {
        const nodesById = {};
        (this.response?.nodes || []).forEach(node => {
            nodesById[node.id] = node;
        });
        this.nodesById = nodesById;

        const incomingEdgesByTarget = {};
        (this.response?.edges || []).forEach(edge => {
            if (!incomingEdgesByTarget[edge.targetId]) {
                incomingEdgesByTarget[edge.targetId] = [];
            }
            incomingEdgesByTarget[edge.targetId].push(edge);
        });
        this.incomingEdgesByTarget = incomingEdgesByTarget;
    }

    computeDownstreamDepthMap() {
        const edges = this.response?.edges || [];
        const rootId = this.rootNode?.id;
        const adjacency = {};
        const depthMap = {};

        edges.forEach(edge => {
            if (!adjacency[edge.sourceId]) {
                adjacency[edge.sourceId] = [];
            }
            adjacency[edge.sourceId].push(edge.targetId);
        });

        if (!rootId) {
            return depthMap;
        }

        const queue = [{ id: rootId, depth: 0 }];
        const visited = new Set();

        while (queue.length) {
            const current = queue.shift();
            if (visited.has(current.id)) {
                continue;
            }
            visited.add(current.id);

            const targets = adjacency[current.id] || [];
            targets.forEach(targetId => {
                const nextDepth = current.depth + 1;
                if (!depthMap[targetId] || nextDepth < depthMap[targetId]) {
                    depthMap[targetId] = nextDepth;
                }
                queue.push({ id: targetId, depth: nextDepth });
            });
        }

        return depthMap;
    }
}
