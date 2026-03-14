# WITU Metadata Routes & Architecture

_Generated: 2026-03-14 — based on codebase analysis + comparison with SF Inspector Reloaded and DLRS_

---

## Table of Contents

1. [Component Architecture](#1-component-architecture)
2. [Apex Class Overview](#2-apex-class-overview)
3. [LWC Component Overview](#3-lwc-component-overview)
4. [Metadata Retrieval Routes](#4-metadata-retrieval-routes)
5. [Dependency Detection Routes](#5-dependency-detection-routes)
6. [Comparison: SF Inspector & DLRS](#6-comparison-sf-inspector--dlrs)
7. [Gaps & Opportunities](#7-gaps--opportunities)

---

## 1. Component Architecture

### Class Dependency Map
```
DependencyController ──→ DependencyService ──→ ToolingApiClient
                                             ├─→ FlowFieldAnalyzer
                                             └─→ SetupUrlResolver

MetadataPickerController ──→ DependencyService (same chain)

BlastRadiusController ──→ BlastRadiusService ──→ DependencyService ──→ ToolingApiClient
                                               │                     ├─→ FlowFieldAnalyzer
                                               │                     └─→ SetupUrlResolver
                                               └─→ SetupUrlResolver

DataJourneyController ──→ DataJourneyService ──→ ToolingApiClient
                                               ├─→ FlowFieldAnalyzer
                                               └─→ SetupUrlResolver

ProcessFlowController ──→ ProcessFlowService ──→ ToolingApiClient
                                               └─→ FlowFieldAnalyzer

SetupController ──→ ToolingApiClient
                  └─→ DependencyService (testConnection only)
```

### LWC Component Hierarchy
```
dependencyFinder (root shell — 5-tab card)
├── metadataPicker          [Finder tab]
│   └── searchableCombobox  (2-3× per render)
├── dependencyResults       [Finder tab, when results exist]
├── blastRadiusGraph        [Blast Radius tab]
├── dataJourneyView         [Data Journey tab]
├── processFlowMap          [Process Flow tab]
└── setupWizard             [Setup tab]

Shared modules (no UI):
├── d3Loader                [singleton D3 loader from Static Resource]
├── exportUtils             [CSV, package.xml, Markdown, Mermaid builders]
└── wituConstants            [colors, icons, labels]
```

---

## 2. Apex Class Overview

### Service Classes (Business Logic)

| Class | Purpose | Lines |
|-------|---------|-------|
| **DependencyService** | Core engine — accepts metadata type + component name, queries MetadataComponentDependency + supplementary scans (layouts, FlexiPages, flows). Also provides all picker data methods. | ~900 |
| **BlastRadiusService** | Recursive multi-hop dependency traversal. DFS with cycle detection; uses `DependencyService.searchDependencies()` at each hop for multi-strategy dependency resolution (MetadataComponentDependency + field supplementary scans). | ~350 |
| **DataJourneyService** | Field-centric BFS — traces what reads/writes a field (upstream + downstream) via dependency queries + flow metadata analysis. | ~400 |
| **ProcessFlowService** | Maps all automation on an object in execution-order phases (triggers → VRs → flows → workflow). | ~300 |
| **FlowFieldAnalyzer** | Pure utility — recursive JSON tree walker for flow metadata. Extracts fieldsRead, fieldsWritten, subflowsCalled. Also parses formula text. | ~200 |
| **SetupUrlResolver** | Maps Tooling API component types to Lightning Setup URLs. Pure string manipulation. | ~150 |

### Controller Classes (LWC Bridge)

| Class | Pattern |
|-------|---------|
| DependencyController | Thin `@AuraEnabled` wrapper → DependencyService |
| MetadataPickerController | `@AuraEnabled` wrappers for all picker data + `getFieldsEnriched()` |
| BlastRadiusController | Single method → BlastRadiusService |
| DataJourneyController | Single method → DataJourneyService |
| ProcessFlowController | Single method → ProcessFlowService |
| SetupController | Auth mode, Named Credential setup, user search, perm set CRUD |

### Infrastructure

| Class | Purpose |
|-------|---------|
| **ToolingApiClient** | HTTP client for all Tooling API. Session ID via VF bridge, Named Credential support, pagination, 503 retry, composite API, 4-level dependency query fallback, 5-level flow query fallback. |

---

## 3. LWC Component Overview

| Component | Purpose | Apex Imports |
|-----------|---------|--------------|
| **dependencyFinder** | Root shell — tab navigation, event orchestration | None |
| **metadataPicker** | Search form — type/object/component pickers, recent searches (localStorage) | DependencyController, MetadataPickerController (12 methods) |
| **dependencyResults** | Results display — list accordion + D3 radial tree | None (data via @api) |
| **searchableCombobox** | Reusable dropdown with keyboard nav, client/server search modes | None |
| **blastRadiusGraph** | Interactive dependency graph — radial/force/tree layouts, collapse, search, filter | BlastRadiusController |
| **dataJourneyView** | Field data journey — grid + Sankey diagram | DataJourneyController |
| **processFlowMap** | Automation timeline + arc dependency diagram | MetadataPickerController, ProcessFlowController |
| **setupWizard** | Multi-step config — auth mode, Named Credential, perm sets, connection test | SetupController (9 methods) |
| **exportMenu** | Dropdown export menu (CSV, package.xml, text, Markdown, Mermaid) | None |
| **exportUtils** | Pure JS — all export format builders + download/clipboard utils | None |
| **d3Loader** | Singleton D3.js loader from Static Resource | None |
| **wituConstants** | Colors, icons, labels for all visualizations | None |

---

## 4. Metadata Retrieval Routes

### How WITU Gets Picker Data

| Metadata Type | API Used | Method Chain | Caching |
|---------------|----------|-------------|---------|
| **Objects** | `Schema.getGlobalDescribe()` | MetadataPickerController.getObjects() | `@AuraEnabled(cacheable=true)` |
| **Fields (Schema)** | `Schema.describeSObjects()` | MetadataPickerController.getFields() | `@AuraEnabled(cacheable=true)` |
| **Fields (Enriched)** | Schema + Tooling `EntityParticle` | MetadataPickerController.getFieldsEnriched() | Not cached (callout) |
| **Active Flows** | Tooling `FlowVersionView` (5-level fallback) | DependencyService.getActiveFlows() | Not cached |
| **All Flows** | Tooling `FlowDefinitionView` → active fallback | DependencyService.getAllFlows() | Not cached |
| **Apex Classes** | Tooling `ApexClass` SOQL | DependencyService.searchApexClasses() | `@AuraEnabled(cacheable=true)` |
| **Record Types** | `Schema.getRecordTypeInfosByDeveloperName()` | DependencyService.getRecordTypes() | `@AuraEnabled(cacheable=true)` |
| **Custom Labels** | Tooling `ExternalString` | DependencyService.getCustomLabels() | `@AuraEnabled(cacheable=true)` |
| **Formula Fields** | `Schema.getCalculatedFormula()` | DependencyService.getFormulaFields() | `@AuraEnabled(cacheable=true)` |
| **Validation Rules** | Tooling `ValidationRule` | DependencyService.getValidationRules() | `@AuraEnabled(cacheable=true)` |
| **Platform Events** | `Schema.getGlobalDescribe()` (filter `__e`) | DependencyService.getPlatformEvents() | `@AuraEnabled(cacheable=true)` |
| **Custom Metadata Types** | `Schema.getGlobalDescribe()` (filter `__mdt`) | DependencyService.getCustomMetadataTypes() | `@AuraEnabled(cacheable=true)` |

### Flow Query Fallback Chain (5 Levels)

ToolingApiClient handles org-to-org API compatibility:

1. `FlowVersionView` WITH `FlowDefinitionView.*` relationship fields
2. `FlowVersionView` WITHOUT relationship fields → enriched via separate `FlowDefinitionView` query
3. `FlowDefinitionView` only (reshaped as FlowVersionView records)
4. `FlowDefinition WHERE ActiveVersionId != null` (catches managed package flows)
5. `Flow` sObject directly with `MasterLabel` (last resort)

Each level triggers only when the previous throws a query error.

---

## 5. Dependency Detection Routes

### Per Metadata Type

| Type | Primary Strategy | Supplementary Scans |
|------|-----------------|---------------------|
| **Standard/Custom Field** | `MetadataComponentDependency` (4-level fallback) | + Layout scan (up to 50) + FlexiPage scan (up to 30) + Flow field scan (all active flows) |
| **Flow** | `MetadataComponentDependency` | + Subflow scan (JSON walk over all active flows, max 200) |
| **Apex Class** | `MetadataComponentDependency` | None |
| **Record Type** | `MetadataComponentDependency` | None |
| **Custom Label** | `MetadataComponentDependency` + ID-based fallback via `ExternalString` | None |
| **Platform Event** | `MetadataComponentDependency` | None |
| **Validation Rule** | Reverse dependency query (who refs the VR) + formula field-ref parsing | None |
| **Custom Metadata Type** | `MetadataComponentDependency` | None |
| **Formula Field** | `Schema.getCalculatedFormula()` + `FlowFieldAnalyzer.extractFieldReferencesFromFormula()` | None |

### Dependency Query Fallback Chain (4 Levels)

1. `WHERE RefMetadataComponentType = X AND RefMetadataComponentName = Y` (server-side filter)
2. `WHERE RefMetadataComponentType = X` only + client-side name filter
3. `WHERE RefMetadataComponentName = Y` only (when type value is unsupported)
4. No ref-field filters + full client-side filter (last resort)

### Supplementary Scans (Fields Only)

**Layout scan:** Lists all Layouts for the object → fetches each layout's JSON metadata → case-insensitive `contains(fieldName)` check.

**FlexiPage scan:** Same approach for Lightning Record Pages.

**Flow field scan:** Gets all active flow versions → fetches each flow's metadata JSON → `FlowFieldAnalyzer.analyzeFlow()` determines Read / Write / Read+Write access type.

### Blast Radius Resolution Route

Blast Radius no longer queries `MetadataComponentDependency` directly. Each traversal hop calls:

`BlastRadiusService.fetchDependents()` → `DependencyService.searchDependencies(metadataType, componentName)`

This reuses the same multi-strategy dependency logic as the Finder tab, including fallback query strategies and field-specific supplementary scans (Layout/FlexiPage/Flow), so blast-radius edges match dependency-search results.

### All Tooling API Queries

```sql
-- Primary dependency query
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       MetadataComponentNamespace, RefMetadataComponentName, RefMetadataComponentType
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = '{type}' AND RefMetadataComponentName = '{name}'

-- Layout list
SELECT Id, Name FROM Layout WHERE TableEnumOrId = '{objectName}'

-- FlexiPage list
SELECT Id, DeveloperName, MasterLabel FROM FlexiPage WHERE SobjectType = '{objectName}'

-- Individual layout/FlexiPage metadata
GET /tooling/sobjects/Layout/{id}
GET /tooling/sobjects/FlexiPage/{id}

-- Flow versions (via 5-level fallback)
SELECT Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label, ...
FROM FlowVersionView WHERE Status = 'Active'

-- Flow metadata (per-flow)
GET /tooling/sobjects/Flow/{flowVersionId}

-- EntityParticle (field enrichment)
SELECT QualifiedApiName, Label, DataType, NamespacePrefix
FROM EntityParticle WHERE EntityDefinition.QualifiedApiName = '{object}'

-- ApexClass search
SELECT Id, Name, NamespacePrefix FROM ApexClass WHERE Name LIKE '%{term}%'

-- Custom labels
SELECT Id, Name, NamespacePrefix, Value FROM ExternalString

-- Validation rules
SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName
FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '{object}'

-- Validation rule formula
SELECT Id, Metadata FROM ValidationRule WHERE Id = '{id}'

-- Unused fields: custom field list + dependency check
SELECT Id, DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId = '{object}'
SELECT RefMetadataComponentId FROM MetadataComponentDependency WHERE RefMetadataComponentId IN (...)

-- Custom label ID fallback
SELECT Id FROM ExternalString WHERE Name = '{labelName}' LIMIT 1
SELECT ... FROM MetadataComponentDependency WHERE RefMetadataComponentId = '{labelId}'

-- Connection test
SELECT Id FROM Organization LIMIT 1
```

### Callout Budget Management

Every per-record loop checks: `Limits.getCallouts() >= Limits.getLimitCallouts() - 2`
This leaves a 2-slot buffer and prevents governor limit exceptions.

---

## 6. Comparison: SF Inspector & DLRS

### How They Retrieve Metadata

| Capability | SF Inspector | DLRS | WITU |
|------------|-------------|------|------|
| **Get all objects** | REST `/sobjects/` | `Schema.getGlobalDescribe()` | `Schema.getGlobalDescribe()` |
| **Per-object fields** | REST `{obj.urls.describe}` (lazy) | `fields.getMap()` via fflib | `Schema.describeSObjects()` + `EntityParticle` |
| **EntityParticle** | ✅ For enriched field metadata | ❌ | ✅ For managed package fields |
| **Tooling API toggle** | Single `useToolingApi` boolean, dual-bucket | ❌ | Ad-hoc per call |
| **Caching** | In-memory Map, session-scoped, lazy | Apex request-scoped (fresh each transaction) | Request-scoped + `@AuraEnabled(cacheable=true)` |
| **keyPrefix resolution** | Client-side scan of global describe | Only for trigger naming | Not used |
| **Relationship discovery** | Shows childRelationships from describe | User-specified + validated | `MetadataComponentDependency` |
| **Cross-component deps** | ❌ | ❌ | ✅ `MetadataComponentDependency` |
| **Flow metadata** | ❌ | ❌ | ✅ FlowVersionView + JSON analysis |
| **Layout analysis** | REST `{urls.layouts}/{RecordTypeId}` | ❌ | Tooling API Layout query + JSON scan |
| **Batching** | ❌ One call per object | N/A | ✅ Composite API |
| **Field name normalization** | N/A (display tool) | ✅ `getDescribe().getName()` on save | ❌ Not done |
| **Case-insensitive field lookup** | N/A | ✅ via fflib lowercase Map | ❌ |

### Key Patterns Worth Noting

**SF Inspector:**
- URL-driven describe calls (uses `sobject.urls.describe` from global describe)
- Dual-bucket Tooling vs. Data API state (clean separation)
- Lazy per-object describe (global is cheap, per-object on demand)
- `reloadAll()` escape hatch for cache invalidation

**DLRS:**
- Field name canonicalization on write (`getDescribe().getName()`)
- Null-safe chained describe (returns null, doesn't throw)
- fflib `SObjectDescribe` wrapper for case-insensitive field access
- No dependency tracking — DLRS is self-contained (user specifies all references)

**WITU's Unique Differentiator:**
`MetadataComponentDependency` usage for cross-component dependency tracking is not found in either SF Inspector or DLRS. This is WITU's core innovation — neither project attempts to answer "where is this used?"

---

## 7. Gaps & Opportunities

### Currently Missing

| Gap | Impact | Effort |
|-----|--------|--------|
| **Field name canonicalization** | Case mismatches in component names could cause silent search misses | S — add `getDescribe().getName()` normalization |
| **Case-insensitive field lookup** | Managed package fields with mixed-case API names may not match | S — lowercase keys in field maps |
| **Persistent caching** | Every page load re-fetches all objects/flows/labels | M — Platform Cache for global describe + flow lists |
| **Workflow Rules in dependencies** | Process Flow Map shows them, but dependency search doesn't scan workflow rule references | M — add WorkflowRule to MetadataComponentDependency scan |
| **Apex Trigger content analysis** | We list triggers as dependencies but don't analyze which fields they reference | L — parse trigger metadata like we parse flow metadata |
| **Batch describe for multiple objects** | When scanning layouts across objects, each object is a separate describe | M — use Composite API for parallel object describes |

### Adoptable Patterns

| Pattern | From | How to Apply |
|---------|------|-------------|
| Dual-bucket Tooling toggle | SF Inspector | Clean separation in ToolingApiClient: `isTooling` parameter on all queries |
| Field name canonicalization | DLRS | Normalize `componentName` input in `searchDependencies()` using Schema describe |
| Case-insensitive field map | DLRS (fflib) | Wrap `Schema.describe().fields.getMap()` in lowercase key Map |
| URL-driven describe | SF Inspector | Less relevant in Apex context, but useful if we add REST-based fetching |
| Lazy per-object describe | SF Inspector | Already partially done — `getFieldsEnriched()` is on-demand |
