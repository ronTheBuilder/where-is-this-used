# Documentation

## Delivered (finalized)

Finalized artifacts that informed the project. See [delivered/README.md](delivered/README.md).

| Document | Status | Description |
|----------|--------|-------------|
| [delivered/prd-v1.md](delivered/prd-v1.md) | Delivered | v1 MVP — Dependency Finder, Blast Radius, Data Journey, Process Flow Map |
| [delivered/prd-v2-blast-radius.md](delivered/prd-v2-blast-radius.md) | Delivered | Blast Radius feature PRD |
| [delivered/prd-v2-data-journey.md](delivered/prd-v2-data-journey.md) | Delivered | Data Journey feature PRD |
| [delivered/prd-v2-process-flow-mapper.md](delivered/prd-v2-process-flow-mapper.md) | Delivered | Process Flow Mapper feature PRD |
| [delivered/prd-extended-metadata-types.md](delivered/prd-extended-metadata-types.md) | Delivered | Record Types, Custom Labels, Platform Events, Validation Rules, Custom Metadata Types, Formula Fields |
| [delivered/prd-export-and-deep-links.md](delivered/prd-export-and-deep-links.md) | Delivered | CSV export, Setup deep links, clipboard formats |
| [delivered/setup-guide.md](delivered/setup-guide.md) | Delivered | Tooling API Self-Callout Setup Guide (External Client App approach) |
| [delivered/discussion.md](delivered/discussion.md) | Delivered | Landscape research, API analysis, architecture decisions |
| [delivered/design-mockup.html](delivered/design-mockup.html) | Delivered | Interactive UI mockup (open in browser) |
| [delivered/metadata-retrieval-analysis.md](delivered/metadata-retrieval-analysis.md) | Delivered | Metadata retrieval bugs — mitigated via ToolingApiClient fallback chains |
| [delivered/d3-visualization-research.md](delivered/d3-visualization-research.md) | Delivered | D3.js library evaluation |
| [delivered/d3-implementation-plan.md](delivered/d3-implementation-plan.md) | Delivered | D3 integration plan — all 4 components have D3 views (force/tree/radial, Sankey, arc, radial tree) |

## Roadmap PRDs (unimplemented)

| Document | Status | Description |
|----------|--------|-------------|
| [prd-granular-dependency-context.md](prd-granular-dependency-context.md) | Partial | Foundation done: FlowFieldAnalyzer (field read/write detection), DependencyRecord.accessType with badge UI. Missing: ReferenceContextService, element-level drill-down UI, Apex source lazy loading |
| [prd-performance-and-caching.md](prd-performance-and-caching.md) | Not started | No Platform Cache usage. Only LWC `@AuraEnabled(cacheable=true)` response caching (default 30s). PRD proposes Session/Org cache tiers, subflow batching, query optimization |
| [prd-bulk-analysis-and-org-hygiene.md](prd-bulk-analysis-and-org-hygiene.md) | Partial | `findUnusedCustomFields()` exists in DependencyService; JS has cleanup tab getters but tab not rendered in HTML. Missing: BulkAnalysisController, UnusedMetadataDetector, org health reports |
| [prd-scheduled-analysis-and-change-detection.md](prd-scheduled-analysis-and-change-detection.md) | Not started | No Schedulable Apex, no snapshot custom objects, no change detection logic |
