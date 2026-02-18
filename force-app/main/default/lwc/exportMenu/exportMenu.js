import { LightningElement, api } from 'lwc';
import {
    downloadFile,
    copyToClipboard,
    buildDependencyCsv,
    buildBlastRadiusCsv,
    buildDataJourneyCsv,
    buildProcessFlowCsv,
    buildPackageXml,
    buildMarkdownTable,
    buildMermaidDiagram,
    buildPlainText
} from 'c/exportUtils';

export default class ExportMenu extends LightningElement {
    /** @type {'dependencies'|'blastRadius'|'dataJourney'|'processFlow'} */
    @api viewType;

    /** The view-specific response data */
    @api data;

    /** Search context: { metadataType, componentName, objectName, fieldName } */
    @api searchContext;

    toastMessage = '';

    get showMermaid() {
        return this.viewType === 'blastRadius';
    }

    handleMenuSelect(event) {
        const action = event.detail.value;

        switch (action) {
            case 'csv':
                this.exportCsv();
                break;
            case 'package-xml-download':
                this.downloadPackageXml();
                break;
            case 'package-xml-copy':
                this.copyPackageXml();
                break;
            case 'text':
                this.copyText();
                break;
            case 'markdown':
                this.copyMarkdown();
                break;
            case 'mermaid':
                this.copyMermaid();
                break;
            default:
                break;
        }
    }

    exportCsv() {
        let csv;
        const prefix = this.searchContext?.componentName || 'witu';

        switch (this.viewType) {
            case 'dependencies':
                csv = buildDependencyCsv(this.data?.groups, this.searchContext);
                break;
            case 'blastRadius':
                csv = buildBlastRadiusCsv(this.data?.nodes);
                break;
            case 'dataJourney':
                csv = buildDataJourneyCsv(this.data?.nodes);
                break;
            case 'processFlow':
                csv = buildProcessFlowCsv(this.data?.phases);
                break;
            default:
                return;
        }

        downloadFile(`${prefix}-${this.viewType}.csv`, csv, 'text/csv');
        this.showToast('CSV exported');
    }

    downloadPackageXml() {
        const xml = buildPackageXml(this.data?.groups, this.searchContext);
        downloadFile('package.xml', xml, 'application/xml');
        this.showToast('package.xml downloaded');
    }

    copyPackageXml() {
        const xml = buildPackageXml(this.data?.groups, this.searchContext);
        copyToClipboard(xml).then(() => this.showToast('package.xml copied'));
    }

    copyText() {
        const text = buildPlainText(this.data?.groups, this.searchContext);
        copyToClipboard(text).then(() => this.showToast('Copied as text'));
    }

    copyMarkdown() {
        const md = buildMarkdownTable(this.data?.groups, this.searchContext);
        copyToClipboard(md).then(() => this.showToast('Copied as Markdown'));
    }

    copyMermaid() {
        const mermaid = buildMermaidDiagram(this.data?.nodes, this.data?.edges, this.searchContext);
        copyToClipboard(mermaid).then(() => this.showToast('Copied as Mermaid'));
    }

    showToast(message) {
        this.toastMessage = message;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.toastMessage = '';
        }, 2000);
    }
}
