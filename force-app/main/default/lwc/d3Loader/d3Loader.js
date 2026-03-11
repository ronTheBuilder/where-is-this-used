import D3_RESOURCE from '@salesforce/resourceUrl/d3';
import { loadScript } from 'lightning/platformResourceLoader';

let d3Promise = null;
let d3SankeyPromise = null;

/**
 * Loads D3 v7 and caches the reference. Prevents double-loading when
 * multiple D3 components coexist on the same page.
 * @param {LightningElement} component - The calling component (required by loadScript)
 */
export function loadD3(component) {
    if (!d3Promise) {
        d3Promise = loadScript(component, D3_RESOURCE + '/d3.min.js').then(
            () => window.d3
        );
    }
    return d3Promise;
}

/**
 * Loads D3 core + d3-sankey plugin. Returns the d3Sankey namespace.
 * @param {LightningElement} component - The calling component
 */
export function loadD3Sankey(component) {
    if (!d3SankeyPromise) {
        d3SankeyPromise = loadD3(component).then(() =>
            loadScript(component, D3_RESOURCE + '/d3-sankey.min.js').then(
                () => window.d3Sankey
            )
        );
    }
    return d3SankeyPromise;
}
