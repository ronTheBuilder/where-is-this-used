# D3 Visualization Implementation Plan

> **Date:** 2026-03-11
> **Companion:** [d3-visualization-research.md](./d3-visualization-research.md)

---

## Phase 0: Foundation

### 0.1 — Download and bundle D3 static resources

**Files to create:**
- `force-app/main/default/staticresources/d3.resource-meta.xml`
- `force-app/main/default/staticresources/d3.zip` containing:
  - `d3.min.js` (v7 UMD build, ~280KB — download from [GitHub releases](https://github.com/d3/d3/releases))
  - `d3-sankey.min.js` (~10KB — custom Rollup build, see below)

**Building d3-sankey UMD bundle:**
```bash
mkdir d3-sankey-build && cd d3-sankey-build
npm init -y
npm install d3-sankey d3-array d3-shape @rollup/plugin-node-resolve @rollup/plugin-terser rollup

# entry.js:
# export { sankey, sankeyCenter, sankeyLeft, sankeyRight, sankeyJustify, sankeyLinkHorizontal } from 'd3-sankey';

npx rollup entry.js --file d3-sankey.min.js --format iife --name d3Sankey \
  --plugin @rollup/plugin-node-resolve --plugin @rollup/plugin-terser
```

**Static resource metadata:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<StaticResource xmlns="http://soap.sforce.com/2006/04/metadata">
    <cacheControl>Public</cacheControl>
    <contentType>application/zip</contentType>
</StaticResource>
```

### 0.2 — Create shared D3 loader module

**File:** `force-app/main/default/lwc/d3Loader/d3Loader.js`

Shared utility that loads D3 once and caches the reference. Prevents double-loading when multiple D3 components coexist on the same page (e.g., Blast Radius tab + Data Journey tab).

```javascript
import D3_RESOURCE from '@salesforce/resourceUrl/d3';
import { loadScript } from 'lightning/platformResourceLoader';

let d3Promise = null;
let d3SankeyPromise = null;

export function loadD3() {
    if (!d3Promise) {
        d3Promise = loadScript(undefined, D3_RESOURCE + '/d3.min.js')
            .then(() => window.d3);
    }
    return d3Promise;
}

export function loadD3Sankey() {
    if (!d3SankeyPromise) {
        d3SankeyPromise = loadD3().then(() =>
            loadScript(undefined, D3_RESOURCE + '/d3-sankey.min.js')
                .then(() => window.d3Sankey)
        );
    }
    return d3SankeyPromise;
}
```

> **Note:** `loadScript` requires a component context as first arg. The actual implementation may need to accept `this` from the calling component. Test in scratch org to confirm whether `undefined` works or if we need `loadScript(component, url)`.

### 0.3 — Extract shared constants module

**File:** `force-app/main/default/lwc/wituConstants/wituConstants.js`

Currently duplicated across components:
- `TYPE_COLORS` in `blastRadiusGraph.js` (line 14)
- `NODE_COLORS` in `dataJourneyView.js` (line 12)
- `TYPE_ICONS` in `dependencyResults.js`
- `ICON_BY_TYPE` in `processFlowMap.js`

Extract into one shared module:
```javascript
export const METADATA_TYPE_COLORS = {
    FlowDefinition: '#1B96FF',
    Flow: '#1B96FF',
    ApexClass: '#9050E9',
    ApexTrigger: '#9050E9',
    ValidationRule: '#FE5C4C',
    Layout: '#04844B',
    LightningComponentBundle: '#0D9DDA',
    AuraDefinitionBundle: '#0D9DDA',
    // Data Journey node types
    field: '#1B96FF',
    flow: '#9050E9',
    apex: '#04844B',
    validationRule: '#FE5C4C',
    formula: '#0D9DDA',
    workflowUpdate: '#FE9339'
};

export const ROOT_COLOR = '#FF538A';
export const CYCLE_COLOR = '#FE9339';
export const DEFAULT_COLOR = '#5F6A7D';
```

---

## Phase 1: Blast Radius — Force-Directed Graph

### 1.1 — Add D3 force layout alongside existing radial layout

**File to modify:** `force-app/main/default/lwc/blastRadiusGraph/blastRadiusGraph.js`

**Approach:** Add a view-mode toggle (Radial / Force). Keep the existing radial layout as default. The force layout is an alternative view using the same data.

**Steps:**

1. **Add view toggle property and UI button**
   - `this.viewMode = 'radial'` (default) | `'force'`
   - Toggle button in the toolbar area of `blastRadiusGraph.html`

2. **Load D3 on demand**
   ```javascript
   import { loadD3 } from 'c/d3Loader';

   async initForceLayout() {
       this.d3 = await loadD3();
       this.renderForceGraph();
   }
   ```

3. **Create `renderForceGraph()` method**

   Replace `buildRadialLayout()` + `drawNodes()`/`drawEdges()` with:

   ```javascript
   renderForceGraph() {
       const d3 = this.d3;
       const { nodes, edges } = this.computeVisibleGraph();  // existing method — keep as-is
       const container = this.template.querySelector('.graph-viewport');

       // Map to D3 format
       const d3Nodes = nodes.map(n => ({ ...n }));
       const d3Links = edges.map(e => ({
           source: e.sourceId,
           target: e.targetId
       }));

       // Create simulation
       this.simulation = d3.forceSimulation(d3Nodes)
           .force('link', d3.forceLink(d3Links).id(d => d.id).distance(180))
           .force('charge', d3.forceManyBody().strength(-400))
           .force('center', d3.forceCenter(width / 2, height / 2))
           .force('collision', d3.forceCollide().radius(100));

       // Render SVG using D3 selections
       const svg = d3.select(container).append('svg')...
       // Draw links as paths, nodes as groups (reuse existing node styling)

       this.simulation.on('tick', () => {
           // Update node/link positions
       });
   }
   ```

4. **Preserve existing interactions**
   - Search filter → `computeVisibleGraph()` already handles this, force graph re-renders on change
   - Type filter → same
   - Collapse/expand → same (`collapsedNodeIds` set), re-run simulation with filtered nodes
   - Node select/hover → attach same event handlers to D3-created SVG elements
   - Re-root (double-click) → same Apex call, then re-render force graph
   - Zoom/pan → replace manual implementation with `d3.zoom()`
   - Fit to viewport → `svg.transition().call(zoom.transform, d3.zoomIdentity.translate(...).scale(...))`

5. **Add drag behavior**
   ```javascript
   d3.drag()
       .on('start', (event, d) => { simulation.alphaTarget(0.3).restart(); })
       .on('drag', (event, d) => { d.fx = event.x; d.fy = event.y; })
       .on('end', (event, d) => { simulation.alphaTarget(0); d.fx = null; d.fy = null; });
   ```

6. **Lifecycle cleanup**
   ```javascript
   disconnectedCallback() {
       if (this.simulation) {
           this.simulation.stop();
           this.simulation = null;
       }
   }
   ```

**Key decisions:**
- Keep node visual design identical (188×54px rounded rects with color stripe, icon, label, depth badge, collapse toggle). Only the positions change.
- Seed initial positions from radial layout for deterministic start: `d3Nodes.forEach(n => { n.x = radialX; n.y = radialY; })` — this prevents the "explosion from center" animation on load.
- Cap simulation at ~300 ticks or 3 seconds, then freeze positions.

### 1.2 — Add Collapsible Tree as a third view mode

**Same file**, additional view mode: `this.viewMode = 'tree'`

**Steps:**

1. Convert flat `nodes`/`edges` to hierarchy using `d3.stratify()`:
   ```javascript
   const root = d3.stratify()
       .id(d => d.id)
       .parentId(d => this.parentsById.get(d.id)?.[0])  // first parent
       (nodes);
   ```
   - Nodes with multiple parents (cycles): pick first parent, skip cycle edges
   - `isCycleNode === true` nodes: show with orange indicator but don't create back-edges in tree

2. Render with `d3.tree()` layout, horizontal orientation (root on left)

3. Add click-to-collapse using the `children`/`_children` toggle pattern from [collapsible-tree](https://observablehq.com/@d3/collapsible-tree)

4. Animated transitions on expand/collapse using `d3.transition()`

**When this view is most useful:** Deep dependency chains (depth 3-5) where the full graph is overwhelming. The tree lets users progressively explore one branch at a time.

### 1.3 — (Future) Hierarchical Edge Bundling as a fourth view mode

**Deferred.** Only valuable for orgs with >100 nodes and dense cross-dependencies. Add when user feedback indicates the force graph becomes a hairball.

---

## Phase 2: Data Journey — Sankey Diagram

### 2.1 — Add Sankey view alongside existing 3-column layout

**File to modify:** `force-app/main/default/lwc/dataJourneyView/dataJourneyView.js` and `.html`

**Approach:** Add a view toggle (Grid / Sankey). Keep the existing 3-column layout as default.

**Steps:**

1. **Add view toggle**
   - `this.viewMode = 'grid'` (default) | `'sankey'`
   - Toggle button in header

2. **Load D3 + Sankey on demand**
   ```javascript
   import { loadD3Sankey } from 'c/d3Loader';

   async initSankey() {
       this.d3Sankey = await loadD3Sankey();
       this.renderSankey();
   }
   ```

3. **Transform data for Sankey**
   ```javascript
   buildSankeyData() {
       const nodes = this.response.nodes.map(n => ({
           id: n.id,
           name: n.name,
           nodeType: n.nodeType,
           direction: n.direction
       }));

       const links = this.response.edges.map(e => ({
           source: e.sourceId,
           target: e.targetId,
           value: 1,  // uniform width, or derive from relationship type
           relationship: e.relationship
       }));

       return { nodes, links };
   }
   ```

4. **Render Sankey**
   ```javascript
   renderSankey() {
       const { sankey, sankeyLinkHorizontal } = this.d3Sankey;
       const d3 = window.d3;

       const sankeyLayout = sankey()
           .nodeId(d => d.id)
           .nodeAlign(d3.sankeyLeft)  // upstream on left, downstream on right
           .nodeWidth(15)
           .nodePadding(10)
           .extent([[margin, margin], [width - margin, height - margin]]);

       const { nodes, links } = sankeyLayout(this.buildSankeyData());

       // Render nodes as rects with type-colored fill
       // Render links as paths with gradient or relationship-colored stroke
       // Add labels beside each node
   }
   ```

5. **Link coloring by relationship:**
   - `writes_to` → orange gradient
   - `read_by` → blue gradient
   - `triggers` → purple gradient
   - `feeds_into` → gray gradient

6. **Preserve interactions:**
   - Node click → show detail panel (reuse existing `handleNodeSelect`)
   - Depth selector → triggers new Apex call, re-render Sankey
   - Export → serialize Sankey SVG

### 2.2 — (Alternative) Tidy Tree if Sankey plugin is problematic

If the Rollup build for d3-sankey proves difficult or the plugin doesn't work under LWS:

**Fallback:** Horizontal Tidy Tree using only core D3 (`d3.tree()` + `d3.hierarchy()`).

```javascript
const root = d3.hierarchy(buildTreeFromJourneyData());
const treeLayout = d3.tree().size([height, width - 200]);
treeLayout(root);
// Render with d3.linkHorizontal() for curved connections
```

Less visually striking than Sankey (no link width encoding) but zero external dependencies.

---

## Phase 3: Process Flow Map — Field Data + Arc Diagram

### 3.1 — Populate `fieldsReferenced`/`fieldsModified` in Apex

**File to modify:** `force-app/main/default/classes/ProcessFlowService.cls`

**Change:** After line 301 where `metadata` is already fetched, call `FlowFieldAnalyzer`:

```apex
// Existing line 301:
Map<String, Object> metadata = getFlowMetadata(flowVersionId);

// ADD after this line:
FlowFieldAnalyzer.FlowFieldAnalysis fieldAnalysis = FlowFieldAnalyzer.analyzeFlow(metadata);

// Then when creating the step (around line 330), pass the field data:
step.fieldsReferenced = fieldAnalysis.fieldsRead;
step.fieldsModified = fieldAnalysis.fieldsWritten;
```

**Impact:** No new API calls — `metadata` is already fetched. `FlowFieldAnalyzer.analyzeFlow()` is pure CPU parsing. Minimal performance impact.

**Test:** Verify in `ProcessFlowServiceTest` that flow steps now contain field data. Add assertions for `fieldsReferenced` and `fieldsModified` on at least one flow step.

**Scope:** This only covers Flows (Record-Triggered). Triggers and Validation Rules would need separate parsing (Apex source analysis / formula parsing) — defer that to a later iteration.

### 3.2 — Add Arc Diagram visualization

**File to modify:** `force-app/main/default/lwc/processFlowMap/processFlowMap.js` and `.html`

**Approach:** Add a "Dependency View" toggle alongside the existing timeline. Shows only when field data is present.

**Steps:**

1. **Add view toggle**
   - `this.viewMode = 'timeline'` (default) | `'arc'`
   - Only enable arc view when at least one step has non-empty `fieldsReferenced` or `fieldsModified`

2. **Compute field overlap links**
   ```javascript
   computeFieldLinks() {
       const steps = this.response.phases.flatMap(p => p.steps);
       const links = [];

       for (let i = 0; i < steps.length; i++) {
           for (let j = i + 1; j < steps.length; j++) {
               const iWrites = new Set(steps[i].fieldsModified || []);
               const jReads = new Set(steps[j].fieldsReferenced || []);
               const jWrites = new Set(steps[j].fieldsModified || []);
               const iReads = new Set(steps[i].fieldsReferenced || []);

               // Causal: i writes a field that j reads
               const causal = [...iWrites].filter(f => jReads.has(f));
               // Conflict: both write the same field
               const conflict = [...iWrites].filter(f => jWrites.has(f));
               // Shared read: both read the same field
               const shared = [...iReads].filter(f => jReads.has(f));

               if (causal.length > 0) {
                   links.push({
                       source: i, target: j,
                       type: 'causal', fields: causal, value: causal.length
                   });
               }
               if (conflict.length > 0) {
                   links.push({
                       source: i, target: j,
                       type: 'conflict', fields: conflict, value: conflict.length
                   });
               }
               // Optionally show shared reads (usually less interesting)
           }
       }
       return links;
   }
   ```

3. **Render Arc Diagram**
   ```javascript
   renderArcDiagram() {
       const d3 = this.d3;
       const steps = this.response.phases.flatMap(p => p.steps);
       const links = this.computeFieldLinks();

       // X scale: steps in execution order
       const x = d3.scalePoint()
           .domain(steps.map((_, i) => i))
           .range([margin, width - margin]);

       // Draw step dots on horizontal line
       // Draw phase background bands (colored by phase)
       // Draw arcs as quadratic Bezier curves above the line

       // Arc color:
       //   causal (write→read): orange
       //   conflict (write→write): red
       //   shared read: light blue (optional, can be toggled off)

       // Arc thickness: proportional to shared field count
   }
   ```

4. **Hover interaction:** Hovering a step highlights all its arcs and shows the shared fields in a tooltip. Hovering an arc shows which fields are shared between the two steps.

### 3.3 — (Future) Chord Dependency Diagram

**Deferred.** Add as a third view mode when orgs have >15 automations on an object and the arc diagram becomes dense.

### 3.4 — Swim Lane improvement (CSS-only, independent)

**File to modify:** `force-app/main/default/lwc/processFlowMap/processFlowMap.html` and `.css`

Can be done independently of D3 work. Change the step list within each phase from a vertical stack to a horizontal flex/grid when multiple steps exist. This visually communicates that steps within a phase run concurrently (order not guaranteed by Salesforce).

---

## Phase 4: Dependency Results — Radial Tree

### 4.1 — Add Radial Tree toggle

**File to modify:** `force-app/main/default/lwc/dependencyResults/dependencyResults.js` and `.html`

**Approach:** Add a "Graph View" toggle button. When active, renders a radial tree below the filter badges (above or instead of the accordion).

**Steps:**

1. **Add view toggle and container**
   ```html
   <div class="view-toggle">
       <lightning-button-group>
           <lightning-button label="List" onclick={handleListView} variant={listVariant}></lightning-button>
           <lightning-button label="Graph" onclick={handleGraphView} variant={graphVariant}></lightning-button>
       </lightning-button-group>
   </div>
   <div lwc:dom="manual" class="radial-tree-container"></div>
   ```

2. **Transform data to hierarchy**
   ```javascript
   buildTreeData() {
       return {
           name: this.componentName,
           children: this.filteredGroups.map(group => ({
               name: group.componentType,
               children: group.records.map(r => ({
                   name: r.metadataComponentName,
                   accessType: r.accessType,
                   setupUrl: r.setupUrl,
                   isSubflow: r.isSubflowReference
               }))
           }))
       };
   }
   ```

3. **Render Radial Tree** (~80 lines)
   ```javascript
   renderRadialTree() {
       const d3 = this.d3;
       const data = this.buildTreeData();
       const root = d3.hierarchy(data);
       const treeLayout = d3.tree()
           .size([2 * Math.PI, radius])
           .separation((a, b) => (a.parent === b.parent ? 1 : 2) / a.depth);

       treeLayout(root);

       // Render links with d3.linkRadial()
       // Render nodes as circles, colored by type (inner) or accessType (leaves)
       // Render labels, auto-rotated based on angular position
   }
   ```

4. **Leaf node coloring by accessType:**
   - Read → blue circle
   - Write → orange circle
   - Read & Write → red circle
   - Subflow → purple circle

5. **Interaction:**
   - Hover leaf → tooltip with full name + accessType
   - Click leaf → open Setup URL (if available)
   - Click type branch → expand/collapse that group

### 4.2 — (Alternative) Sunburst view

Add as a third view option (`'sunburst'`). Same tree data structure, rendered with `d3.partition()` + `d3.arc()`. Arc area = count of components. Click to zoom into a type group.

More information-dense than radial tree (proportional areas) but harder to read individual labels.

### 4.3 — (Alternative) Circle Packing view

Same data, rendered with `d3.pack()`. Type groups as large circles, individual components as small circles inside. Colored by type. Visually appealing for showing relative sizes at a glance.

---

## Implementation Order Summary

```
Phase 0 (foundation)     ──── 0.1 Static resources
                          ├── 0.2 D3 loader module
                          └── 0.3 Shared constants

Phase 1 (blast radius)   ──── 1.1 Force-Directed Graph view toggle
                          └── 1.2 Collapsible Tree view toggle

Phase 2 (data journey)   ──── 2.1 Sankey Diagram view toggle
                          └── 2.2 Tidy Tree fallback (if Sankey plugin fails)

Phase 3 (process flow)   ──── 3.1 Populate fieldsReferenced/fieldsModified (Apex)
                          ├── 3.2 Arc Diagram view toggle
                          └── 3.4 Swim Lane CSS improvement (independent)

Phase 4 (dep. results)   ──── 4.1 Radial Tree view toggle
                          └── 4.2 Sunburst view toggle

Future                    ──── 1.3 Hierarchical Edge Bundling (blast radius)
                          ├── 3.3 Chord Dependency Diagram (process flow)
                          └── 4.3 Circle Packing (dep. results)
```

**Dependencies:**
- Phase 0 must complete before any other phase
- Phases 1, 2, 3, 4 are independent of each other (can be done in any order)
- 3.2 (Arc Diagram) depends on 3.1 (Apex field data)
- 3.4 (Swim Lane CSS) has no dependencies — can be done anytime
- 2.2 (Tidy Tree) is only needed if 2.1 (Sankey) fails

**Testing per phase:**
- Each new view mode must work with: empty results, single node, max data (500 nodes / 200 nodes / 50 automations / 2000 results)
- Existing view modes must be unaffected (regression test)
- `disconnectedCallback` must clean up D3 simulations/timers
- Test under both LWS and Locker Service in scratch orgs
