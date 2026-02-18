/**
 * Export utility functions for WITU.
 * All export logic runs client-side — no Apex calls needed.
 */

// ═══════════════════════════════════════
// File Download
// ═══════════════════════════════════════

export function downloadFile(filename, content, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
}

export function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(text);
    }
    // Fallback
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    return Promise.resolve();
}

// ═══════════════════════════════════════
// CSV Formatting
// ═══════════════════════════════════════

function escapeCsvCell(value) {
    if (value == null) return '';
    const str = String(value);
    if (str.includes(',') || str.includes('"') || str.includes('\n')) {
        return '"' + str.replace(/"/g, '""') + '"';
    }
    return str;
}

function buildCsvRow(cells) {
    return cells.map(escapeCsvCell).join(',');
}

export function buildDependencyCsv(groups, searchContext) {
    const header = buildCsvRow(['Component Name', 'Component Type', 'Namespace', 'Access Type', 'Setup URL']);
    const rows = [header];

    for (const group of (groups || [])) {
        for (const rec of (group.records || [])) {
            rows.push(buildCsvRow([
                rec.metadataComponentName,
                rec.metadataComponentType,
                rec.metadataComponentNamespace || '',
                rec.accessType || '',
                rec.setupUrl || ''
            ]));
        }
    }
    return rows.join('\n');
}

export function buildBlastRadiusCsv(nodes) {
    const header = buildCsvRow(['Component Name', 'Component Type', 'Depth', 'Is Root', 'Is Cycle Node', 'Setup URL']);
    const rows = [header];

    for (const node of (nodes || [])) {
        rows.push(buildCsvRow([
            node.name,
            node.componentType,
            node.depth,
            node.isRoot,
            node.isCycleNode,
            node.setupUrl || ''
        ]));
    }
    return rows.join('\n');
}

export function buildDataJourneyCsv(nodes) {
    const header = buildCsvRow(['Node Name', 'Node Type', 'Direction', 'Access Type', 'Depth', 'Setup URL']);
    const rows = [header];

    for (const node of (nodes || [])) {
        rows.push(buildCsvRow([
            node.name,
            node.nodeType || '',
            node.direction || '',
            node.accessType || '',
            node.depth || 0,
            node.setupUrl || ''
        ]));
    }
    return rows.join('\n');
}

export function buildProcessFlowCsv(phases) {
    const header = buildCsvRow(['Phase', 'Phase Name', 'Automation Name', 'Automation Type', 'Is Active', 'Setup URL']);
    const rows = [header];

    for (const phase of (phases || [])) {
        for (const auto of (phase.automations || [])) {
            rows.push(buildCsvRow([
                phase.phaseNumber,
                phase.phaseName,
                auto.name,
                auto.automationType,
                auto.isActive,
                auto.setupUrl || ''
            ]));
        }
    }
    return rows.join('\n');
}

// ═══════════════════════════════════════
// Package.xml Generation
// ═══════════════════════════════════════

const TOOLING_TO_METADATA_TYPE = {
    'ApexClass': 'ApexClass',
    'ApexTrigger': 'ApexTrigger',
    'Flow': 'Flow',
    'FlowDefinition': 'Flow',
    'ValidationRule': 'ValidationRule',
    'Layout': 'Layout',
    'LightningComponentBundle': 'LightningComponentBundle',
    'AuraDefinitionBundle': 'AuraDefinitionBundle',
    'CustomField': 'CustomField',
    'CustomObject': 'CustomObject',
    'FlexiPage': 'FlexiPage',
    'QuickAction': 'QuickAction',
    'CustomLabel': 'CustomLabel',
    'RecordType': 'RecordType',
    'PermissionSet': 'PermissionSet',
    'Profile': 'Profile',
    'Page': 'ApexPage',
    'StaticResource': 'StaticResource',
    'EmailTemplate': 'EmailTemplate',
    'CustomTab': 'CustomTab',
    'WorkflowRule': 'WorkflowRule'
};

export function buildPackageXml(groups, searchContext) {
    const membersByType = {};

    for (const group of (groups || [])) {
        for (const rec of (group.records || [])) {
            const metaType = TOOLING_TO_METADATA_TYPE[rec.metadataComponentType] || rec.metadataComponentType;
            if (!membersByType[metaType]) {
                membersByType[metaType] = [];
            }
            membersByType[metaType].push(rec.metadataComponentName);
        }
    }

    const now = new Date().toISOString();
    let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
    xml += '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n';
    xml += `    <!-- Generated by Where Is This Used? (WITU) -->\n`;
    if (searchContext) {
        xml += `    <!-- Dependencies of: ${searchContext.componentName} (${searchContext.metadataType}) -->\n`;
    }
    xml += `    <!-- Generated: ${now} -->\n`;

    const sortedTypes = Object.keys(membersByType).sort();
    for (const typeName of sortedTypes) {
        xml += '    <types>\n';
        const sortedMembers = membersByType[typeName].sort();
        for (const member of sortedMembers) {
            xml += `        <members>${escapeXml(member)}</members>\n`;
        }
        xml += `        <name>${escapeXml(typeName)}</name>\n`;
        xml += '    </types>\n';
    }

    xml += '    <version>65.0</version>\n';
    xml += '</Package>\n';
    return xml;
}

function escapeXml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ═══════════════════════════════════════
// Markdown & Mermaid Formatters
// ═══════════════════════════════════════

export function buildMarkdownTable(groups, searchContext) {
    let md = '';
    if (searchContext) {
        md += `## Dependencies of ${searchContext.componentName} (${searchContext.metadataType})\n\n`;
    }
    md += '| Component Name | Type | Namespace | Access |\n';
    md += '|---|---|---|---|\n';

    for (const group of (groups || [])) {
        for (const rec of (group.records || [])) {
            md += `| ${rec.metadataComponentName} | ${rec.metadataComponentType} | ${rec.metadataComponentNamespace || ''} | ${rec.accessType || ''} |\n`;
        }
    }
    return md;
}

export function buildMermaidDiagram(nodes, edges, searchContext) {
    let mermaid = 'graph TD\n';

    for (const node of (nodes || [])) {
        const shape = node.isRoot ? `[["${node.name}"]]` : `["${node.name}"]`;
        mermaid += `    ${sanitizeMermaidId(node.id)}${shape}\n`;
    }

    for (const edge of (edges || [])) {
        mermaid += `    ${sanitizeMermaidId(edge.sourceId)} --> ${sanitizeMermaidId(edge.targetId)}\n`;
    }

    return mermaid;
}

function sanitizeMermaidId(id) {
    if (!id) return 'unknown';
    return id.replace(/[^a-zA-Z0-9_]/g, '_');
}

export function buildPlainText(groups, searchContext) {
    let text = '';
    if (searchContext) {
        text += `Dependencies of ${searchContext.componentName} (${searchContext.metadataType})\n`;
        text += '='.repeat(60) + '\n\n';
    }

    for (const group of (groups || [])) {
        text += `${group.componentType} (${group.count})\n`;
        text += '-'.repeat(40) + '\n';
        for (const rec of (group.records || [])) {
            text += `  • ${rec.metadataComponentName}`;
            if (rec.accessType) text += ` [${rec.accessType}]`;
            if (rec.metadataComponentNamespace) text += ` (${rec.metadataComponentNamespace})`;
            text += '\n';
        }
        text += '\n';
    }
    return text;
}
