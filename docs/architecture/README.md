# Architecture — Agent and Developer Index

**Purpose**: Single entry point for how WITU is built and how metadata is retrieved. **Agents**: read this first when changing retrieval logic, adding metadata types, or refactoring services.

---

## Where to look

| Need | Document | Contents |
|------|----------|----------|
| **How we retrieve each metadata type** (APIs, fallbacks, pickers) | [metadata-retrieval-by-type.md](metadata-retrieval-by-type.md) | Per-type matrix: Tooling vs Schema, which methods, which fallbacks, limits and caveats. |
| **Where logic lives and what to use when** | [decisions.md](decisions.md) | Architectural decisions: shared client, URL resolution, flow parsing, deduplication rules. |
| **Code quality and simplification** | [../CODEBASE-ASSESSMENT.md](../CODEBASE-ASSESSMENT.md) | Assessment of complexity, duplication, and recommendations. |
| **Existing retrieval bugs and mitigations** | [../delivered/metadata-retrieval-analysis.md](../delivered/metadata-retrieval-analysis.md) | Flow 400, RefMetadataComponentName, callout limits, etc. |

---

## Golden rules (for agents)

1. **Metadata retrieval**  
   Do not invent new ways to fetch a type. Follow [metadata-retrieval-by-type.md](metadata-retrieval-by-type.md). All Tooling query/GET usage goes through `ToolingApiClient`; flow indexing uses `queryFlowVersionsWithFallback`, dependency lookups use `queryDependenciesWithNameFallback`.

2. **Setup URLs**  
   All Setup links must be built via `SetupUrlResolver.resolve(metadataType, componentId, componentName)`. Do not add new hardcoded `/lightning/setup/...` paths; extend `SetupUrlResolver` and document the new type in the resolver and in metadata-retrieval-by-type if it’s a new metadata kind.

3. **Flow metadata**  
   Flow JSON parsing (fields read/written, subflows) is done only in `FlowFieldAnalyzer`. Any new flow-based logic that needs field or subflow data must use `FlowFieldAnalyzer`, not ad-hoc JSON walks.

4. **Adding a metadata type**  
   - Add the type and its retrieval method to [metadata-retrieval-by-type.md](metadata-retrieval-by-type.md) (API, fallback, picker source, RefMetadataComponentType if applicable).  
   - Implement in code (prefer one place, e.g. DependencyService or a small helper).  
   - Use `ToolingApiClient` for all Tooling calls; use `SetupUrlResolver` for any Setup URLs.

5. **Validation Rule formula**  
   Formula text comes from Tooling API `ValidationRule` by Id (`Metadata.errorConditionFormula` / `ErrorConditionFormula`). There should be a single shared retrieval for this (currently duplicated in DependencyService and ProcessFlowService); new code must not add another copy.

---

## Code map (quick reference)

- **ToolingApiClient** — All Tooling API HTTP: query, composite, getFlowMetadata, getToolingRecord, queryFlowVersionsWithFallback, queryDependenciesWithNameFallback. Auth, retry, callout budget.
- **FlowFieldAnalyzer** — Parse Flow metadata Map into fieldsRead, fieldsWritten, subflows; formula parsing for field refs.
- **SetupUrlResolver** — metadataType + id + name → Setup URL; extend for new types.
- **DependencyService** — Dependency Finder: searchDependencies (dispatches by type), pickers (flows, Apex, fields, record types, labels, validation rules), supplementary Layout/FlexiPage/Flow field scan.
- **BlastRadiusService** — Recursive dependency graph via queryDependenciesWithNameFallback only.
- **DataJourneyService** — Field-centric upstream/downstream; dependency API + Flow metadata via FlowFieldAnalyzer.
- **ProcessFlowService** — Execution order (triggers, validation rules, record-triggered flows); ApexTrigger/ValidationRule/FlowVersionView + getFlowMetadata + FlowFieldAnalyzer.
