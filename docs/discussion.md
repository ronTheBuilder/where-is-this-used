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

| Area | HappySoup | This project (goals) |
|---|---|---|
| Standard fields | Unclear / limited | First-class support |
| Flow as subflow | Not clear | Explicit "which parent flows call this subflow" |
| Record types | Not highlighted | Show layouts, flows, Apex, assignment rules |
| UX | Web app, tree view | TBD - could be SF native (LWC), VS Code extension, CLI, or web |
| Granularity | Shows component name | Goal: show WHERE within the component |
| Supplemental APIs | Primarily MetadataComponentDependency | Combine with Metadata API reads, Flow parsing, Apex parsing |

### Technical approach options

**Option A: Pure MetadataComponentDependency queries**
- Simplest approach
- Limited by what the API returns (blind spots)
- Good starting point

**Option B: MetadataComponentDependency + metadata parsing**
- Query the dependency API for broad coverage
- Supplement by actually reading Flow XML, Apex code, VF pages, etc.
- Parse the metadata to find references the dependency API misses
- More accurate but more complex

**Option C: Build on sfdc-soup**
- Contribute to or fork the existing MIT-licensed library
- Add the missing type support
- Benefit from existing infrastructure

### Delivery format options

1. **SFDX/SF CLI Plugin** - Developers run it from their terminal
2. **VS Code Extension** - Integrated into the IDE
3. **Web App** (like HappySoup) - Accessible to admins too
4. **LWC in Salesforce** - Native Salesforce experience
5. **Combination** - Core library + multiple frontends

---

## Open Questions for Discussion

1. **Contribute vs. build new?**
   - HappySoup/sfdc-soup is MIT licensed and covers a lot of ground already. Should we contribute there, fork, or start fresh?
   - The dependencies-cli is archived - is there value in reviving it?

2. **Target audience?**
   - Developers only (CLI/VS Code) or also admins (web/in-Salesforce)?
   - This affects complexity significantly

3. **Scope for v1?**
   - Start with the biggest gaps (standard fields, flows/subflows, record types)?
   - Or try to be comprehensive from the start?

4. **How to handle the API's blind spots?**
   - Accept them and document what works/doesn't?
   - Supplement with metadata parsing (more work but more accurate)?
   - Both, with parsing as a "deep scan" option?

5. **What format for the tool?**
   - CLI plugin is easiest to build and distribute
   - Web app is most accessible
   - LWC would be the most "Salesforce-native" experience

---

## Next Steps

- [ ] Decide on contribute vs. new project
- [ ] Define target audience and delivery format
- [ ] Scope v1 feature set
- [ ] Create a PRD based on these decisions
- [ ] Set up the project foundation
