# WITU Capabilities

_What the app can do — the quick reference._

---

## Features

### 1. Dependency Finder
**"Where is this field/flow/class used?"**

Searches for all metadata components that reference a given component. Supports 10 metadata types:

| Type | What It Finds |
|------|--------------|
| Standard Field | Apex, Flows, Layouts, FlexiPages, VRs, Reports, Dashboards that use this field |
| Custom Field | Same as Standard Field |
| Flow | Apex, other Flows (subflow references), components that reference this flow |
| Apex Class | Other Apex, Flows, VF Pages, Lightning Components that reference this class |
| Record Type | Layouts, Apex, Flows, Profile/PermSet assignments using this record type |
| Custom Label | Apex, Flows, VF, LWC that reference this label |
| Platform Event | Apex triggers, Flows, Process Builders subscribed to this event |
| Validation Rule | Shows what the VR references (fields in its formula) + what references the VR |
| Custom Metadata Type | Apex, Flows, components using this CMT |
| Formula Field | Shows all fields referenced in the formula expression |

**Output:** Grouped list by component type + interactive radial tree graph.

### 2. Blast Radius
**"If I change this, what breaks?"**

Recursive multi-hop dependency traversal starting from any component. Shows the full impact chain.

- **Depth:** 1-5 hops (default 3)
- **Max nodes:** 500
- **Cycle detection:** Marks circular dependencies
- **3 layout modes:** Radial, Force-directed, Tree
- **Interactive:** Click to select, double-click to re-root, collapse/expand branches
- **Search + filter:** Find nodes by name, filter by component type
- **Export:** Mermaid diagram, SVG download

### 3. Data Journey
**"How does data flow through this field?"**

Traces a field's data lifecycle — what writes to it (upstream) and what consumes it (downstream).

- **Upstream:** Flows that assign to this field, Apex that references it
- **Downstream:** Components that read this field, flows that use it as input and what they write as output
- **Depth:** 1-3 hops (default 2)
- **2 views:** Grid (3-column: upstream → root → downstream) and Sankey diagram

### 4. Process Flow Map
**"What automation fires on this object?"**

Maps ALL automation on a Salesforce object in correct execution order:

| Phase | What |
|-------|------|
| 1 | System Validations |
| 2 | Before Triggers |
| 3 | Validation Rules |
| 4 | After Triggers |
| 5 | Assignment Rules |
| 6 | Auto-Response Rules |
| 7 | Before-Save Flows |
| 8 | Workflow Rules |
| 9 | Workflow Field Updates |
| 10 | After-Save Flows |
| 11 | Entitlement Rules |
| 12 | Async Flows |

- **Trigger contexts:** Insert, Update, Delete, or All
- **Field analysis:** Shows which fields each automation reads and writes
- **2 views:** Timeline (phase accordion) and Arc Diagram (shows field-level causal links between automations)

### 5. Unused Field Scanner
**"Which custom fields have zero references?"**

Scans all custom fields on an object against `MetadataComponentDependency` to find fields with no known consumers.

### 6. Setup Wizard
- Auth mode selection (Session ID vs Named Credential)
- Named Credential auto-creation (External Credential + Named Credential via Tooling API)
- Permission set management (search users, bulk assign/remove)
- Connection test

---

## Export Formats

All views support export:

| Format | Available In |
|--------|-------------|
| CSV | Dependencies, Blast Radius, Data Journey, Process Flow |
| Package.xml (download) | Dependencies |
| Package.xml (clipboard) | Dependencies |
| Plain Text | Dependencies |
| Markdown Table | Dependencies |
| Mermaid Diagram | Blast Radius |
| SVG | Blast Radius |
| Text Export | Data Journey, Process Flow |

---

## Technical Capabilities

### APIs Used
- **Tooling API REST** — `MetadataComponentDependency`, `EntityParticle`, `Layout`, `FlexiPage`, `FlowVersionView`, `FlowDefinitionView`, `Flow`, `ApexClass`, `ApexTrigger`, `ValidationRule`, `CustomField`, `ExternalString`
- **Schema API** — `getGlobalDescribe()`, `describeSObjects()`, `getCalculatedFormula()`, `getRecordTypeInfosByDeveloperName()`
- **Composite API** — Batch multiple Tooling queries in one callout
- **Custom Permission** — `WITU_Access` gates all functionality

### Resilience
- 4-level dependency query fallback (progressively relaxes filters)
- 5-level flow query fallback (handles API version differences across orgs)
- 503 retry (3 attempts)
- Callout budget guard (2-slot buffer before every per-record callout)
- Supplementary scans are best-effort (never abort main results)
- Cycle detection in Blast Radius prevents infinite traversal

### Security
- Custom Permission enforcement on every public method
- Field-Level Security checks in SetupController
- Permission Set assignment allowlisted to WITU perm sets only
- `String.escapeSingleQuotes()` on all user input in SOQL
- Input validation (regex, length) on all component names

### Limits
| Resource | Limit |
|----------|-------|
| Blast Radius nodes | 500 |
| Blast Radius depth | 5 |
| Blast Radius API calls | 50 |
| Data Journey downstream nodes | 200 |
| Data Journey upstream nodes | 50 |
| Flow metadata retrievals per journey | 50 |
| Layout scan per field search | 50 |
| FlexiPage scan per field search | 30 |
| Subflow scan | 200 active flows |
| Picker options visible | 500 |
| Apex class search results | 50 |
