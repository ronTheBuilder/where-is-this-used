# PRD: Blast Radius — Interactive Dependency Graph

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU) v2
**Status**: Draft

---

## 1. Problem Statement

WITU v1 shows dependencies as a flat list grouped by type. This answers "what uses this?" but doesn't answer:
- **How deep does the chain go?** (A field is used in a Flow, which is called as a subflow by 3 other Flows, which are invoked from Apex...)
- **What's the total blast radius if I change/delete this component?**
- **Which dependencies are direct vs. transitive?**

Admins making changes need to see the full chain reaction, not just first-level dependents.

## 2. Solution

Add a **"Blast Radius"** view to WITU that recursively follows dependencies and renders them as an interactive directed graph (DAG) — all within Salesforce, using LWC.

### User Flow
1. User searches for a component in WITU v1 (e.g., `Account.Industry`)
2. Results appear as usual (list view)
3. User clicks **"Show Blast Radius"** button
4. LWC fetches recursive dependencies (depth-limited)
5. Interactive graph renders:
   - Root node = selected component (highlighted)
   - First-level dependents = direct references
   - Second/third-level = transitive dependencies
   - Edges show direction (A depends on B)
   - Node color = metadata type (Flow = blue, Apex = purple, VR = orange, etc.)
   - Click node → show detail panel (name, type, link to Setup)

## 3. Technical Architecture

### 3.1 Recursive Dependency Resolution

New Apex service: `BlastRadiusService.cls`

```
Input: componentName, componentType, maxDepth (default 3, max 5)
Output: List<GraphNode>, List<GraphEdge>

Algorithm:
1. Query MetadataComponentDependency WHERE Ref = input → level 1 dependents
2. For each level 1 dependent, query MetadataComponentDependency WHERE Ref = dependent → level 2
3. Repeat up to maxDepth
4. Deduplicate nodes (same component found via multiple paths)
5. Detect cycles (component A → B → A) and mark them
6. Return flattened node + edge lists
```

**Limits & Safety:**
- Max depth: 5 levels
- Max total nodes: 500 (stop expanding after this)
- Max API calls per blast radius: 50 (each level query = 1 call)
- Timeout: 120s (Apex transaction limit)
- If limits hit: return partial graph with `limitReached` flag + warning

### 3.2 Data Model

```apex
public class GraphNode {
    @AuraEnabled public String id;           // MetadataComponentId
    @AuraEnabled public String name;         // MetadataComponentName
    @AuraEnabled public String componentType; // MetadataComponentType
    @AuraEnabled public Integer depth;       // 0 = root, 1 = direct, 2+ = transitive
    @AuraEnabled public Boolean isRoot;
    @AuraEnabled public Boolean isCycleNode; // Part of a circular dependency
    @AuraEnabled public String setupUrl;
}

public class GraphEdge {
    @AuraEnabled public String sourceId;
    @AuraEnabled public String targetId;
    @AuraEnabled public String edgeType;     // 'direct' | 'subflow' | 'invocation'
}

public class BlastRadiusResponse {
    @AuraEnabled public List<GraphNode> nodes;
    @AuraEnabled public List<GraphEdge> edges;
    @AuraEnabled public Integer totalDepth;
    @AuraEnabled public Boolean limitReached;
    @AuraEnabled public String warningMessage;
    @AuraEnabled public GraphStats stats;
}

public class GraphStats {
    @AuraEnabled public Integer totalNodes;
    @AuraEnabled public Integer totalEdges;
    @AuraEnabled public Integer maxDepthReached;
    @AuraEnabled public Map<String, Integer> nodesByType; // 'Flow' => 12, 'ApexClass' => 3
}
```

### 3.3 LWC Graph Rendering

New component: `blastRadiusGraph`

**Rendering approach**: Pure SVG + LWC (no external JS libraries for AppExchange compatibility)

- **Layout algorithm**: Simple layered/hierarchical layout (root at center or left, levels expand right/down)
- **SVG elements**: `<circle>` for nodes, `<line>` or `<path>` for edges, `<text>` for labels
- **Interactivity**: Click node → highlight connected edges + show detail panel, hover → tooltip
- **Color legend**: SLDS-aligned colors per metadata type
- **Zoom/pan**: CSS transform-based (scale + translate on container)
- **Responsive**: Auto-fit to container width, zoom to fit button

**Why not D3.js or external libs?**
AppExchange security review flags external libraries heavily. Pure SVG + LWC is the safest path. The graph will be simpler but fully compliant.

### 3.4 Force-directed vs Hierarchical Layout

Use **hierarchical (layered) layout** because:
- Dependencies have natural direction (A → B)
- Depth levels map cleanly to visual layers
- Simpler to implement in pure SVG
- More readable for admin audience

Algorithm (Sugiyama-style simplified):
1. Assign layers by depth (root = layer 0)
2. Order nodes within layers to minimize edge crossings (simple heuristic: sort by parent position)
3. Position: x = layer * horizontalSpacing, y = index * verticalSpacing
4. Draw edges as straight lines or simple bezier curves

## 4. UI Design

### Layout
```
┌─────────────────────────────────────────────────────┐
│ [← Back to Results]    Blast Radius: Account.Industry│
│                                                      │
│  Depth: [1] [2] [3▪] [4] [5]    [Zoom Fit] [Export] │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │                                                 │ │
│  │              ┌──→ [VR] Account_Validation       │ │
│  │              │                                  │ │
│  │    [SF]──────┼──→ [FL] Route_By_Industry ──→ ...│ │
│  │  Account.    │                                  │ │
│  │  Industry    ├──→ [AP] AccountService ──→ ...   │ │
│  │              │                                  │ │
│  │              └──→ [LO] Account Layout           │ │
│  │                                                 │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌──── Detail Panel ──────────────────────────────┐  │
│  │ Route_By_Industry (Flow)                       │  │
│  │ Type: Record-Triggered Flow                    │  │
│  │ Depth: 1 (direct dependency)                   │  │
│  │ [Open in Setup ↗]                              │  │
│  │ Dependents: 3 components                       │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  Legend: 🟦 Flow  🟣 Apex  🟠 VR  🟢 Layout  ⬜ Other │
│  Stats: 14 nodes · 18 edges · depth 3 · 0 cycles    │
└─────────────────────────────────────────────────────┘
```

### Color Mapping (SLDS tokens)
| Type | Color | SLDS Token |
|------|-------|------------|
| Flow | `#1B96FF` | `--slds-g-color-brand-base-50` |
| Apex Class | `#9050E9` | `--slds-g-color-purple-base-50` |
| Apex Trigger | `#BA01FF` | purple variant |
| Validation Rule | `#FE5C4C` | `--slds-g-color-error-base-50` |
| Layout | `#04844B` | `--slds-g-color-success-base-50` |
| LWC/Aura | `#0D9DDA` | teal |
| Root node | `#FF538A` | `--slds-g-color-pink-base-50` |
| Cycle node | `#FE9339` | `--slds-g-color-warning-base-50` |

## 5. Export

- **Copy as Text**: Flat dependency chain text
- **Copy as Mermaid**: Mermaid.js diagram syntax (pasteable into docs/wikis)
- **Download SVG**: Direct export of the rendered graph

## 6. Files to Create

```
force-app/main/default/
├── classes/
│   ├── BlastRadiusService.cls
│   ├── BlastRadiusServiceTest.cls
│   ├── BlastRadiusController.cls
│   └── BlastRadiusControllerTest.cls
└── lwc/
    └── blastRadiusGraph/
        ├── blastRadiusGraph.html
        ├── blastRadiusGraph.js
        ├── blastRadiusGraph.css
        └── blastRadiusGraph.js-meta.xml
```

## 7. Integration with v1

- `dependencyResults` component gets a new button: **"Show Blast Radius"**
- Clicking it dispatches a custom event to `dependencyFinder`
- `dependencyFinder` switches view from results → blast radius graph
- Back button returns to list view
- Depth slider lets users control how deep to traverse

## 8. AppExchange Considerations

- No external JS libraries (pure LWC + SVG)
- All Apex `with sharing`
- CRUD/FLS checks via custom permission (reuse `WITU_Access`)
- Governor limit safety: max 50 callouts, 120s timeout, 500 node cap
- Test coverage: mock HTTP responses, test cycle detection, test limit handling

## 9. Success Metrics

| Metric | Target |
|--------|--------|
| Average graph render time | < 3s for depth 3 |
| User engagement | 40%+ of WITU users try Blast Radius |
| Graph accuracy | 100% match with v1 list results at depth 1 |
