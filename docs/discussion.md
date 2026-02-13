# Where Is This Used - Project Discussion

## The Problem

Salesforce's native "Where is this used?" button has significant gaps:

1. **Standard fields are not supported at all** - You can't see where `Opportunity.StageName` or `Account.Name` is used
2. **Only works for custom fields** - No support for flows, subflows, record types, custom labels, etc.
3. **No granular location data** - It tells you a flow uses a field, but not *which element* in the flow (screen? decision? assignment?)
4. **No reverse lookup for many types** - Can't ask "where is this Flow used as a subflow?" or "where is this Record Type referenced?"

There's a clear IdeaExchange demand for this:
- ["Expand Where is this used to standard fields"](https://ideas.salesforce.com/s/idea/a0B8W00000Gdc0zUAB)
- ["Expand Where is this Used for Flows / Subflows"](https://ideas.salesforce.com/s/idea/a0B8W00000H4Q9sUAF)

---

## The Underlying API: MetadataComponentDependency

Salesforce exposes a Tooling API object called `MetadataComponentDependency` that powers dependency analysis.

### Fields (9 total)

| Field | Description |
|---|---|
| `Id` | Unique row identifier |
| `MetadataComponentId` | ID of the dependent component (the "user") |
| `MetadataComponentName` | Name of the dependent component |
| `MetadataComponentNamespace` | Namespace of the dependent component |
| `MetadataComponentType` | Type of the dependent component |
| `RefMetadataComponentId` | ID of the referenced component (the "used") |
| `RefMetadataComponentName` | Name of the referenced component |
| `RefMetadataComponentNamespace` | Namespace of the referenced component |
| `RefMetadataComponentType` | Type of the referenced component |

### How to query it

```sql
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = 'CustomField'
  AND RefMetadataComponentName = 'Account.MyField__c'
```

Can also query in reverse (find what a component depends ON):
```sql
SELECT ... FROM MetadataComponentDependency
WHERE MetadataComponentId = '<some-id>'
```

### Known supported MetadataComponentType values

- CustomField
- CustomObject
- ApexClass
- AuraDefinitionBundle (Lightning Aura Components)
- LightningComponentBundle (LWC)
- Flow
- Page (Visualforce)
- StaticResource
- CustomLabel
- GlobalValueSet
- FieldSet
- CustomSetting
- OrchestrationContext

### Limitations

| Limitation | Detail |
|---|---|
| **2,000 record cap** (Tooling API) | Single SOQL query returns max 2,000 rows |
| **100,000 record cap** (Bulk API 2.0) | Can get up to 100K rows per job |
| **Reports excluded** | Reports are NOT included in dependency results |
| **Beta status** | Still labeled "Beta" - has been for years, but widely used |
| **Inconsistent coverage** | Not all types track all relationships (e.g., Flow->LWC component usage not tracked) |
| **No standard field "Where Used" natively** | But the API *does* return dependencies involving standard fields when other components reference them |

### The key insight

The API actually has more data than what Salesforce exposes through the UI. By querying it creatively (and supplementing with other Tooling API objects like FlowDefinition, Flow metadata reads, etc.), we can build a much richer "where is this used" experience.

---

## What Already Exists (Landscape)

### 1. HappySoup.io (open source, free)
- **Repo**: [pgonzaleznetwork/HappySoup.io](https://github.com/pgonzaleznetwork/HappySoup.io)
- **Engine**: [pgonzaleznetwork/sfdc-soup](https://github.com/pgonzaleznetwork/sfdc-soup) (NPM library)
- **What it does**: Impact analysis / "where is this used" for many metadata types
- **Strengths**: Free, web/local/Docker, good custom field coverage, Excel/CSV/package.xml export, shows read vs write for Apex, report column/filter detail
- **Limitations**: Unclear maintenance status (last significant activity ~2023), requires 18-digit IDs, enhanced report analysis capped at 100 reports
- **License**: MIT
- **Opportunity**: Could contribute here OR use sfdc-soup as a foundation

### 2. dependencies-cli (Salesforce official, ARCHIVED)
- **Repo**: [forcedotcom/dependencies-cli](https://github.com/forcedotcom/dependencies-cli)
- **Status**: **Archived May 2025** - read-only, no longer maintained
- **What it did**: SFDX plugin, D3.js graph visualization, object-level and package-level dependency analysis
- **Limitations**: 2,000 record cap, archived/dead
- **License**: BSD-3-Clause

### 3. Salto (commercial, not open source)
- Treats standard fields same as custom fields
- Shows exact location within metadata (which flow element, etc.)
- Paid product - not open source

### 4. afawcett/dependencies-sample
- Sample repo documenting which type relationships the API actually returns
- Reveals significant blind spots in the API's coverage
- Useful as a reference for what works and what doesn't

---

## Discussion: What could "Where Is This Used" do differently?

### Core value proposition
A free, open-source tool that answers **"where is this used?"** for metadata types that Salesforce's native UI doesn't support - especially:

1. **Standard fields** (the #1 gap)
2. **Flows / Subflows** (where is this flow invoked as a subflow?)
3. **Record Types** (which layouts, flows, Apex, page assignments reference this?)
4. **Custom Labels** (used in Apex, LWC, Aura, Flows, VF pages)
5. **Permission Sets / Profiles** (what do they grant access to?)
6. **Custom Metadata Types** (where are CMDT records referenced?)
7. **Platform Events** (what subscribes to / publishes this?)

### What sets it apart from HappySoup?

| Area | HappySoup | This project |
|---|---|---|
| Standard fields | Unclear / limited | First-class support |
| Flow as subflow | Not covered | Explicit "which parent flows call this subflow" via Flow metadata parsing |
| Record types | Not highlighted | Show layouts, flows, Apex, assignment rules |
| UX | External web app, tree view | **Native Salesforce LWC** — runs inside the org |
| Granularity | Shows component name | Shows WHERE within the component (flow element, Apex line, etc.) |
| Supplemental APIs | Primarily MetadataComponentDependency | MetadataComponentDependency + targeted Flow metadata parsing |
| Distribution | Web/local/Docker | **AppExchange managed package** (free) |

---

## Decisions Made

### 1. Build new vs. contribute to HappySoup
**Decision: Build new.**
- HappySoup is an external web app (Node.js / Heroku). We want a native Salesforce experience (LWC) that runs inside the org
- Different architecture (Apex + LWC vs. JavaScript + external hosting)
- AppExchange distribution gives admins one-click install
- HappySoup's sfdc-soup library remains a useful reference

### 2. Target audience
**Decision: Admins AND developers.**
- Native LWC app inside Salesforce makes it accessible to admins (no CLI knowledge needed)
- The type-first picker UX is admin-friendly
- Developers benefit from the same tool

### 3. Delivery format
**Decision: LWC + Apex managed package on AppExchange (free), source code on GitHub (MIT).**
- AppExchange listing: free, no security review fees for free apps
- Managed package: upgradeable, protected code in the installed org
- Open source on GitHub: transparency, community contributions
- This is the same model used by FormulaShare and Salesforce Labs apps

### 4. Technical approach
**Decision: MetadataComponentDependency API + targeted metadata parsing for blind spots.**
- Primary data source: Tooling API `MetadataComponentDependency` — one query gets most dependencies
- Supplemental parsing only where the API has known blind spots:
  - Flow→Flow (subflow) references: parse Flow metadata for `<subflow>` elements
  - Other gaps addressed as discovered
- `DependencyService` abstraction makes the data source swappable if the API ever dies

### 5. Data strategy
**Decision: Real-time queries for v1 (no caching/indexing).**
- Simpler architecture, always fresh data
- No custom object storage overhead
- The 2,000 row limit rarely hits for a single component lookup
- Indexing/caching can be added later if needed for large orgs

### 6. Metadata picker UX
**Decision: Type-first picker.**
- User selects metadata type first (Standard Field, Custom Field, Flow, Apex Class, etc.)
- Each type gets its own optimized sub-picker (object→field for fields, search for flows, etc.)
- Extensible: adding new types = adding a new picker variant
- Clear to the user what the app supports

### 7. Authentication
**Decision: Named Credential + setup wizard LWC.**
- `UserInfo.getSessionId()` does NOT work from Lightning context (security policy blocks it)
- Named Credential (Connected App + Auth Provider + Named Credential) is the Salesforce-approved approach
- Safest path for AppExchange security review
- Setup wizard LWC walks admins through the one-time configuration
- Includes a "Test Connection" button to verify setup

---

## API Coverage & Blind Spots

### What MetadataComponentDependency tracks well

| Looking up... | Found in... |
|---|---|
| Custom Fields | Validation Rules, Layouts, Formulas, VF, Apex, Triggers, Email Templates, Field Sets, Flows, LWC, Process Builder |
| Standard Fields | Same as custom fields (the API tracks them, the UI just doesn't expose the button) |
| Apex Classes | Other Apex, Triggers, VF, Lightning Components, Flow Actions |
| Custom Labels | Apex, Triggers, VF, Lightning Components |
| Lightning Components | Other LWC/Aura, Lightning Pages, Quick Actions |
| Flows | Process Builder, Apex, Lightning Pages |
| Custom Objects | VF, Apex, Triggers, Flows, LWC, Quick Actions, Lightning Pages |

### Known blind spots (API does NOT track)

| Looking up... | NOT found in... | Workaround |
|---|---|---|
| Flows | **Other Flows (subflow refs)** | Parse Flow metadata for `<subflow>` elements |
| Custom Fields | Reports, Sharing Rules, List Views, Profile/PermSet FLS | None for v1 (Reports are completely excluded from the API) |
| Custom Objects | Custom Tabs, Reports, Report Types | None for v1 |
| Global Value Sets | Custom Fields that use them | None for v1 |
| Lightning Components | Flows, Action Overrides | None for v1 |

### API fallback strategy

If Salesforce ever kills MetadataComponentDependency, the fallback is brute-force metadata parsing:
- Query all Apex class/trigger bodies via Tooling API and string-search for references
- Retrieve Flow metadata and parse XML for field/object references
- Retrieve VF page markup and search
- This is ~100x more API calls and would need async processing (Queueable/Batch)
- The `DependencyService` abstraction means only that one class changes

**Risk assessment**: The API has been "Beta" since Summer '18 (7+ years). Salesforce rarely kills widely-used beta APIs. More likely it stays in eternal beta or eventually GAs.

---

## Next Steps

- [x] Decide on contribute vs. new project → **Build new**
- [x] Define target audience and delivery format → **Admins + devs, LWC managed package**
- [x] Scope v1 feature set → **Standard Fields, Custom Fields, Flows, Apex Classes**
- [x] Design mockup → **Created: `docs/design-mockup.html`**
- [ ] Create a PRD in `docs/`
- [ ] Begin building
