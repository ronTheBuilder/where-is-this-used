# D3.js Visualization Research for WITU

> **Date:** 2026-03-11
> **Source:** [Observable D3 Gallery](https://observablehq.com/@d3/gallery)
> **Purpose:** Evaluate D3 visualization techniques to improve dependency visualizations

---

## Feasibility: D3 in LWC Managed Package

### Verdict: Fully feasible. Salesforce-endorsed pattern.

**Loading D3 v7 in LWC:**
- D3 v7 ships a **UMD bundle** (`d3.min.js`, ~280KB) alongside its ESM modules
- Download from [D3 GitHub releases](https://github.com/d3/d3/releases), zip it, upload as Static Resource
- LWC's `loadScript()` loads UMD globals — `window.d3` becomes available
- Salesforce's own [lwc-recipes](https://github.com/trailheadapps/lwc-recipes) includes D3 examples

```javascript
import D3_RESOURCE from '@salesforce/resourceUrl/d3';
import { loadScript } from 'lightning/platformResourceLoader';

// In renderedCallback():
await loadScript(this, D3_RESOURCE + '/d3.min.js');
// window.d3 is now available
```

**d3-sankey plugin:** Does NOT ship UMD — requires a Rollup/Webpack build to create a single `d3-with-sankey.min.js` bundle (~290KB total). Straightforward build step.

**lwc:dom="manual" compatibility:**
- D3 freely manipulates DOM inside `<div lwc:dom="manual">` — this is exactly our existing pattern
- `d3.drag()` and `d3.zoom()` work because they attach listeners to D3-created elements
- CSS styles must be applied inline via D3's `.style()` (Shadow DOM blocks external CSS on dynamic elements)
- Must use `this.template.querySelector()` to get container, not `document.querySelector()`

**Locker Service / LWS:** D3 is explicitly listed as Locker-compliant by Salesforce. LWS (the newer security model) is even less restrictive. `d3-force` simulation uses `requestAnimationFrame` with pure math — no blocked APIs.

**Static resource limits:** 5MB per resource, 250MB org total. D3+Sankey = ~290KB — trivial.

**AppExchange:** No restrictions on JS libraries beyond security review (no `eval()`, no `Function()` constructor — D3 uses neither). Multiple published apps use D3.

---

## Current State — What We Actually Have

### Blast Radius Graph
- **Rendering:** Full `lwc:dom="manual"` SVG — `document.createElementNS()` for every element
- **Layout:** Custom radial/concentric — nodes at `radius = 200 + depth * 178`, angular spread `π * (0.34 + nodeCount * 0.05)`
- **Nodes:** 188×54px rounded rects with color stripe, emoji icon, label (max 24 chars), depth badge, collapse toggle
- **Edges:** Cubic Bézier with animated dashes, width decays by depth (`3.1 - depth * 0.45`)
- **Interaction:** Pan, zoom (0.55–2.2×), click select, hover highlight/dim, search filter, type filter, collapse/expand, double-click re-root, fit-to-viewport
- **Data:** `{nodes: [{id, name, componentType, depth, isRoot, isCycleNode, setupUrl}], edges: [{sourceId, targetId}], stats: {totalNodes, totalEdges, maxDepthReached, nodesByType}}`
- **Limits:** MAX_NODES=500, MAX_API_CALLS=50, MAX_DEPTH=5
- **Problem:** Inner rings crowd badly at >20 nodes per layer. No collision avoidance. ~700 lines of layout/render code.

### Data Journey View
- **Rendering:** Hybrid — SVG `lwc:dom="manual"` for connector paths only, LWC template for node cards (buttons)
- **Layout:** Fixed 3-column grid — upstream (x=260), root (x=500), downstream (x=740+indent). ROW_HEIGHT=86px.
- **Connectors:** Cubic Bézier from column to column, arrowhead markers
- **Data:** `{nodes: [{id, name, nodeType, direction, accessType, depth, setupUrl, detail}], edges: [{sourceId, targetId, relationship, detail}]}`
- **Node types:** field, flow, apex, validationRule, formula, workflowUpdate
- **Relationships:** writes_to, read_by, triggers, feeds_into
- **Limits:** Max 200 downstream, 50 upstream, depth 1–3
- **Problem:** Fixed grid doesn't adapt to asymmetric data (50 downstream vs 2 upstream). No flow metaphor — just lines connecting cards.

### Process Flow Map
- **Rendering:** Pure HTML/CSS — no SVG at all. Vertical timeline with `<ol>` and CSS borders.
- **Layout:** 12 hardcoded phases in Salesforce execution order, each collapsible, steps listed inside
- **Data:** `{phases: [{phaseNumber, phaseName, phaseDescription, steps: [{id, name, automationType, isActive, triggerContext, description, setupUrl}]}], totalAutomations}`
- **Note:** `fieldsReferenced` and `fieldsModified` exist in the data model but are **never populated** — this is the missing piece for showing inter-automation dependencies
- **Problem:** Shows execution order but zero information about which automations interact (share fields, trigger each other). This is a timeline, not a dependency view.

### Dependency Results
- **Rendering:** LWC template — accordion with grouped records, filter badges, search
- **Data:** `{groups: [{componentType, count, records: [{metadataComponentId, metadataComponentName, metadataComponentType, metadataComponentNamespace, accessType, setupUrl, isSubflowReference}]}], totalCount, limitReached}`
- **Structure:** Single hub → many spokes. Queried component at center, all referencing components grouped by type.
- **Problem:** List-only view. Can't see the "shape" — how many reads vs writes, which types dominate, clusters.

---

## Concrete Recommendations

### 1. Blast Radius: Force-Directed Graph

**Value added:** Replaces ~700 lines of manual radial layout with ~150 lines of D3 force simulation. Nodes automatically find optimal positions based on connectivity. Drag-to-rearrange lets users organize the graph mentally. Collision avoidance eliminates the crowding problem at inner rings.

**Example:** [Force-Directed Graph](https://observablehq.com/@d3/force-directed-graph/2)

**Data mapping — zero transformation needed:**
```
Apex GraphNode          →  D3 node: { id, name, group: componentType, depth }
Apex GraphEdge          →  D3 link: { source: sourceId, target: targetId }
componentType           →  color via d3.scaleOrdinal()
depth                   →  node size or ring constraint
```

**What you keep:** All existing interaction code (search, type filter, collapse, re-root, export). Only the layout algorithm and SVG construction change.

**What changes:**
- Replace `buildRadialLayout()` (~50 lines) with `d3.forceSimulation()` (~30 lines)
- Replace `drawNodes()`/`drawEdges()` (~200 lines) with D3 selections (~60 lines)
- Add `simulation.on('tick', updatePositions)` for animation
- Add `d3.drag()` for node dragging (replaces manual mousedown/mousemove)
- Add `simulation.stop()` in `disconnectedCallback()` to prevent memory leaks

**Risk:** Force simulations are non-deterministic — same data produces slightly different layouts each time. Users may find this disorienting if they expect consistent positions. Mitigation: seed the initial positions using the current radial algorithm, then let force refine.

**Alternatives considered:**

| Chart | Example | Why not primary |
|---|---|---|
| Collapsible Tree | [collapsible-tree](https://observablehq.com/@d3/collapsible-tree) | Can't handle cycles (blast radius has `isCycleNode`). Good as secondary view for acyclic subsets. |
| Force-Directed Tree | [force-directed-tree](https://observablehq.com/@d3/force-directed-tree) | Tree-specific — doesn't handle the graph (multi-parent) structure of dependencies. |
| Hierarchical Edge Bundling | [hierarchical-edge-bundling](https://observablehq.com/@d3/hierarchical-edge-bundling) | Beautiful for dense graphs but requires hierarchical grouping. High complexity. Future "advanced" view. |
| Disjoint Force-Directed | [disjoint-force-directed-graph](https://observablehq.com/@d3/disjoint-force-directed-graph/2) | Useful if blast radius returns disconnected subgraphs — worth noting as an enhancement. |
| Mobile Patent Suits | [mobile-patent-suits](https://observablehq.com/@d3/mobile-patent-suits) | Shows labeled directed edges. Useful technique for showing edge types if we ever add `edgeType` detail. |

---

### 2. Data Journey: Sankey Diagram

**Value added:** The Sankey is purpose-built for exactly what Data Journey shows — data flowing through a system. Link width can encode the number of field references. The left-to-right flow immediately communicates "upstream writes → field → downstream reads." This is a significant UX upgrade from the current flat 3-column grid.

**Example:** [Sankey Diagram](https://observablehq.com/@d3/sankey/2)

**Data mapping:**
```
Apex DataJourneyNode    →  Sankey node: { id, name, nodeType }
Apex DataJourneyEdge    →  Sankey link: { source: sourceId, target: targetId, value: 1 }
direction (upstream/downstream) →  Sankey alignment handles this automatically
relationship (writes_to/read_by) →  Link color (orange for writes, blue for reads)
```

**What changes:**
- Replace fixed 3-column layout with `d3.sankey()` layout computation
- Replace hybrid SVG+LWC cards with full SVG (or keep cards and just use Sankey for connector routing)
- Downstream indentation (`chainDepth * 1.25rem`) becomes unnecessary — Sankey positions nodes automatically

**Realistic concern:** d3-sankey is an external plugin requiring a custom build. If this is a dealbreaker, the **Tidy Tree** ([tree](https://observablehq.com/@d3/tree/2)) is a core-D3-only alternative that handles the hierarchical chain well, though it lacks the "flow width" metaphor.

**Alternatives considered:**

| Chart | Example | Why not primary |
|---|---|---|
| Tidy Tree (horizontal) | [tree](https://observablehq.com/@d3/tree/2) | Core D3, no plugin needed. Clean layout. But no link width encoding, and doesn't show flow direction as intuitively. Good fallback. |
| Tangled Tree | [tangled-tree-visualization-ii](https://observablehq.com/@nitaku/tangled-tree-visualization-ii) | Handles multi-parent flows (a field written by Flow A and Apex B). Visually complex but powerful. |
| Sequences Sunburst | [sequences-sunburst](https://observablehq.com/@kerryrodden/sequences-sunburst) | Shows breadcrumb path on hover — great technique to add to any solution for tracing a specific data path. |

---

### 3. Process Flow Map: Arc Diagram + Chord Diagram

#### Gap to close first: Populate `fieldsReferenced`/`fieldsModified`

The `AutomationStep` Apex wrapper already has `fieldsReferenced` and `fieldsModified` properties (lines 36-37 of `ProcessFlowService.cls`), but they're initialized as empty lists (lines 358-359) and never populated.

**The fix is small.** `ProcessFlowService` already fetches Flow metadata at line 301 (`getFlowMetadata(flowVersionId)`), and `FlowFieldAnalyzer.analyzeFlow()` already exists and extracts `fieldsRead`/`fieldsWritten` from that exact metadata format — it's used by `DataJourneyService`. The missing connection is roughly 3 lines of Apex:

```apex
// After line 301 in ProcessFlowService.cls:
FlowFieldAnalyzer.FlowFieldAnalysis fieldAnalysis = FlowFieldAnalyzer.analyzeFlow(metadata);
// Then in the step creation:
step.fieldsReferenced = fieldAnalysis.fieldsRead;
step.fieldsModified = fieldAnalysis.fieldsWritten;
```

For Triggers and Validation Rules, field extraction would require parsing Apex source or formula expressions — more effort, but Flows are the majority of automations in most orgs and cover the highest-value case.

Once field data is populated, three visualizations become viable:

#### Option A: Arc Diagram (recommended)

**Example:** [Arc Diagram](https://observablehq.com/@d3/arc-diagram)

**Value added:** Automations laid out linearly in execution order (left to right). Arcs connect automations that share fields — an arc from "Before-Save Flow A" to "After-Save Flow B" means they both touch the same field. Arc color can distinguish: orange = "A writes a field that B reads" (causal dependency), blue = "both read the same field" (no conflict), red = "both write the same field" (potential conflict/overwrite).

This answers the #1 question admins have about Process Flow: **"which of my automations interact with each other?"**

**Data mapping:**
```
AutomationStep[]        →  D3 nodes (ordered by executionPhase)
fieldsModified ∩ fieldsReferenced between steps  →  D3 links (arcs)
Arc height              →  distance between connected steps (execution gap)
Arc color               →  write→read (causal), read→read (shared), write→write (conflict)
```

**Complexity:** Low-Medium (~100 lines D3). Arc diagrams are among the simplest D3 network visualizations — circles on a horizontal line with quadratic Bézier curves.

#### Option B: Chord Dependency Diagram

**Example:** [Chord Dependency Diagram](https://observablehq.com/@d3/chord-dependency-diagram/2)

**Value added:** Shows the full N×N relationship matrix between all automations on an object. Each automation gets a segment on the circle; ribbons connect automations that share fields. Ribbon thickness = number of shared fields. Directional arrows show write→read flow.

Best for orgs with 10-30 automations on an object where field overlap is the key diagnostic question. Answers: "which automations are most coupled?"

**Data mapping:**
```javascript
// Build matrix from field data:
matrix[i][j] = count of fields that step[i] writes AND step[j] reads
```

**Complexity:** High (~150 lines D3 + matrix construction logic).

#### Option C: Sankey Diagram (vertical, phase-based)

**Example:** [Sankey Diagram](https://observablehq.com/@d3/sankey/2)

**Value added:** Shows the record's journey through execution phases. Nodes are individual automations, grouped into phase columns. Links between phases show field data flowing from one automation's write to another's read. Link width = number of fields.

This reuses the same Sankey infrastructure as Data Journey (shared code).

**Complexity:** Medium. Same Sankey approach as Data Journey.

#### Option D: Swim Lane Diagram (no D3 needed)

Even without the field data, the current timeline could be improved by showing **concurrency within phases** — multiple automations in the same phase render side-by-side rather than stacked, making it visually clear that "Before Trigger A" and "Before Trigger B" run in the same phase and their order is not guaranteed.

This is a CSS/HTML layout change, no D3 required. Can be done independently.

---

### 4. Dependency Results: Radial Tree or Sunburst

**Value added:** Transforms a flat list into a visual that shows the "shape" of dependencies — how many Flows vs Apex classes reference the component, the relative weight of each type, and the hub-and-spoke relationship.

#### Option A: Radial Tree (simpler, clearer)

**Example:** [Radial Tidy Tree](https://observablehq.com/@d3/radial-tree/2)

Queried component at center, branches by type, leaves are individual referencing components. Labels auto-rotate for readability. ~80 lines of D3.

**Data mapping:**
```javascript
// Transform flat groups into hierarchy
{
  name: "Account.CustomField__c",       // root
  children: [
    { name: "Flow", children: [
      { name: "MyFlow", accessType: "Read" },
      { name: "OtherFlow", accessType: "Write" }
    ]},
    { name: "ApexClass", children: [
      { name: "AccountService", accessType: "Read & Write" }
    ]}
  ]
}
```

#### Option B: Zoomable Sunburst (information-dense)

**Example:** [Zoomable Sunburst](https://observablehq.com/@d3/zoomable-sunburst)

Inner ring = metadata types, outer ring = individual components. Arc area = count. Click a type segment to zoom in and see just those components. Encodes proportions better than a tree.

#### Option C: Circle Packing (grouped clusters)

**Example:** [Circle Packing](https://observablehq.com/@d3/pack/2)

Groups dependencies as colored circles within type-circles. Size = count. Visually shows which type dominates at a glance. Simple and attractive.

**Recommendation:** Start with Radial Tree — lowest effort, most readable. Add as a toggle alongside the existing accordion (don't replace it — the list is better for scanning/searching).

---

## What NOT to Use (and Why)

| Chart | Why it doesn't fit |
|---|---|
| Treemap | Dependency data isn't deeply nested — it's mostly 2 levels (type → components). Treemaps waste space on shallow hierarchies. |
| Icicle | Same problem as treemap — too few levels. |
| Bar chart variants | The data is relational (graph), not categorical. A bar chart of "5 Flows, 3 Apex Classes" adds nothing over the existing badges. |
| Chord diagram for Dependencies | The hub-spoke structure (1 component → N references) isn't a matrix relationship. Chord diagrams need N×N relationships. |
| Force-directed for Dependencies | Overkill for a single-level fan-out. Force simulation adds animation delay without layout benefit. |

---

## Priority Ranking — What Actually Adds Value

| # | Feature | Chart | Value | Effort | Needs D3 | Verdict |
|---|---|---|---|---|---|---|
| 1 | **Blast Radius** | Force-Directed Graph | **High** — fixes real layout/crowding problems | Medium | Yes (`d3-force`) | **Do this first** |
| 2 | **Data Journey** | Sankey Diagram | **High** — transforms UX with flow metaphor | Medium | Yes (`d3-sankey`) | **Do this second** (or Tidy Tree if avoiding plugin) |
| 3 | **Process Flow Map** | Arc Diagram | **High** — answers "which automations interact?" | Low (Apex) + Low-Med (D3) | Yes (`d3-scale`) | **Populate field data first** (~3 lines Apex via existing `FlowFieldAnalyzer`), then Arc Diagram |
| 4 | **Process Flow Map** | Chord Diagram | **Medium** — shows full coupling matrix | Low (Apex) + High (D3) | Yes (`d3-chord`) | **Advanced view** after Arc Diagram |
| 5 | **Process Flow Map** | Sankey (vertical) | **Medium** — shows record journey through phases | Low (Apex) + Medium (D3) | Yes (`d3-sankey`) | **Shares infra** with Data Journey Sankey |
| 6 | **Dependency Results** | Radial Tree (toggle) | **Medium** — adds visual insight to flat list | Low | Yes (`d3-hierarchy`) | **Quick win** |
| 7 | **Dependency Results** | Sunburst | **Medium** — proportional type breakdown | Low-Med | Yes (`d3-hierarchy`) | **Alt view** alongside Radial Tree |
| 8 | **Dependency Results** | Circle Packing | **Low-Med** — grouped cluster view | Low-Med | Yes (`d3-hierarchy`) | **Alt view** option |
| 9 | **Blast Radius** | Collapsible Tree (alt) | **Medium** — best for deep acyclic chains | Medium | Yes (`d3-hierarchy`) | **Alt view mode** |
| 10 | **Blast Radius** | Edge Bundling (alt) | **Medium** — reduces clutter in dense graphs | High | Yes (`d3-hierarchy`) | **Power user view** |
| 11 | **Process Flow Map** | Swim Lane | **Low-Med** — shows phase concurrency | Low | No | **CSS-only improvement**, independent of D3 |

---

## Implementation: Shared D3 Infrastructure

```
Static Resources:
  d3/d3.min.js              (~280KB, UMD from GitHub release)
  d3/d3-sankey.min.js       (~10KB, custom Rollup build)

Shared LWC Module (d3Loader.js):
  - loadD3() → loadScript() once, returns window.d3 reference
  - Prevents double-loading when multiple D3 components coexist

Shared Constants (d3Constants.js):
  - TYPE_COLORS (already duplicated across 3 components)
  - TYPE_ICONS
  - Tooltip rendering helper
```

---

## References — All Observable Examples

### Networks (most relevant)
- [Force-Directed Graph](https://observablehq.com/@d3/force-directed-graph/2) — Physics-based node layout, drag & zoom *(Blast Radius)*
- [Disjoint Force-Directed Graph](https://observablehq.com/@d3/disjoint-force-directed-graph/2) — Handles disconnected subgraphs *(Blast Radius)*
- [Sankey Diagram](https://observablehq.com/@d3/sankey/2) — Flow visualization with link widths *(Data Journey)*
- [Arc Diagram](https://observablehq.com/@d3/arc-diagram) — Linear layout with arc connections *(Process Flow future)*
- [Hierarchical Edge Bundling](https://observablehq.com/@d3/hierarchical-edge-bundling) — Grouped edge routing *(Blast Radius advanced)*
- [Hierarchical Edge Bundling (variant)](https://observablehq.com/@d3/hierarchical-edge-bundling/2) — Alternative style
- [Chord Dependency Diagram](https://observablehq.com/@d3/chord-dependency-diagram/2) — Circular dependency matrix *(Process Flow future)*
- [Directed Chord Diagram](https://observablehq.com/@d3/directed-chord-diagram/2) — With directional arrows
- [Chord Diagram](https://observablehq.com/@d3/chord-diagram/2) — Basic chord layout
- [Mobile Patent Suits](https://observablehq.com/@d3/mobile-patent-suits) — Directed graph with labeled edges

### Hierarchies
- [Collapsible Tree](https://observablehq.com/@d3/collapsible-tree) — Click-to-expand, animated transitions *(Blast Radius alt)*
- [Tidy Tree](https://observablehq.com/@d3/tree/2) — Clean hierarchical layout *(Data Journey fallback)*
- [Radial Tidy Tree](https://observablehq.com/@d3/radial-tree/2) — Hub-and-spoke layout *(Dependency Results)*
- [Force-Directed Tree](https://observablehq.com/@d3/force-directed-tree) — Tree with physics simulation
- [Tangled Tree](https://observablehq.com/@nitaku/tangled-tree-visualization-ii) — Multi-parent hierarchies
- [Sunburst](https://observablehq.com/@d3/sunburst/2) — Zoomable partition layout *(Dependency Results alt)*
- [Zoomable Sunburst](https://observablehq.com/@d3/zoomable-sunburst) — Click-to-zoom sunburst
- [Indented Tree](https://observablehq.com/@d3/indented-tree) — File-explorer style tree
- [Circle Packing](https://observablehq.com/@d3/pack/2) — Nested circles by group *(Dependency Results alt)*
- [Zoomable Circle Packing](https://observablehq.com/@d3/zoomable-circle-packing) — Click-to-zoom circles
- [Cluster Dendrogram](https://observablehq.com/@d3/cluster/2) — Leaf-aligned tree
- [Radial Dendrogram](https://observablehq.com/@d3/radial-cluster/2) — Radial cluster layout

### Animation & Interaction (techniques)
- [Smooth Zooming](https://observablehq.com/@d3/smooth-zooming) — Animated zoom transitions
- [Zoom to Bounding Box](https://observablehq.com/@d3/zoom-to-bounding-box) — Click-to-zoom regions
- [Sequences Sunburst](https://observablehq.com/@kerryrodden/sequences-sunburst) — Breadcrumb trail on hover
- [Temporal Force-Directed Graph](https://observablehq.com/@d3/temporal-force-directed-graph) — Time-based graph evolution

### Full Gallery
- [D3 Gallery](https://observablehq.com/@d3/gallery) — Complete catalog of all D3 examples
