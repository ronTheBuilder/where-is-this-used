# Codebase Assessment — Where Is This Used (WITU)

**Version**: 1.0  
**Date**: 2026-03-13  
**Purpose**: In-depth review of build quality, complexity, and correct use of components. Use this alongside `docs/architecture/` for refactoring and agent guidance.

---

## 1. Executive Summary

| Area | Verdict | Notes |
|------|---------|--------|
| **Architecture** | Good foundation, some sprawl | Controller → Service → ToolingApiClient is clear; metadata retrieval logic is spread across services with duplication. |
| **Complexity** | **Overly complex in places** | Multi-level fallbacks and per-type branching live in code instead of being documented and centralized. |
| **Correct use** | **Mixed** | Some pieces are wrongly used or bypassed (e.g. SetupUrlResolver, duplicated Validation Rule formula fetch). |
| **Maintainability** | Medium | Shared client exists; per-metadata-type behavior is hard to discover and change. |

**Recommendation**: Abstract "how we retrieve metadata per type" into documented rules and a single source of truth (see `docs/architecture/`). Reduce duplication (Validation Rule formula, flow indexing, Setup URLs) and route all URL resolution through `SetupUrlResolver`.

---

## 2. What’s Working Well

### 2.1 Layering and shared client

- **Controller → Service → ToolingApiClient** is consistent across all four features (Dependency Finder, Blast Radius, Data Journey, Process Flow Map).
- **ToolingApiClient** centralizes:
  - Auth (Named Credential vs session bridge)
  - Callout budget checks, retries (503), timeouts
  - Flow indexing fallback chain (`queryFlowVersionsWithFallback`)
  - Dependency query fallback (`queryDependenciesWithNameFallback`)
- **FlowFieldAnalyzer** is the single place for Flow metadata parsing (fields read/written, subflows); used by DependencyService, DataJourneyService, and ProcessFlowService.
- **SetupUrlResolver** exists and covers most metadata types with type/id/name → Setup URL mapping.

### 2.2 Security and validation

- `FeatureManagement.checkPermission('WITU_Access')` is enforced in ToolingApiClient and consistently used.
- Component name validation (regex, length) is centralized in `ToolingApiClient.validateComponentName()`.
- No raw SOQL concatenation without `String.escapeSingleQuotes()` for user input.

### 2.3 Documentation

- `docs/delivered/` holds PRDs, discussion, metadata-retrieval analysis, and setup guide.
- `metadata-retrieval-analysis.md` accurately describes bugs and mitigations (e.g. Flow 400, RefMetadataComponentName filtering).

---

## 3. Over-Complication and Wrong Use

### 3.1 Metadata retrieval logic embedded in services

- **Per-metadata-type behavior** is encoded in long `if (metadataType == '...')` branches in `DependencyService.searchDependencies()` (Formula Field, Validation Rule, Standard/Custom Field, Flow, Custom Label, etc.).
- **Flow indexing** is invoked in three different ways:
  - `DependencyService.getActiveFlows()` / `getAllFlows()` (picker + FlowDefinitionView try then fallback).
  - `DataJourneyService.queryActiveFlows()` (fallback chain only).
  - `ProcessFlowService.loadRecordTriggeredFlows()` (fallback chain with extra fields).
- **Correct approach**: Define “per metadata type: which API, which fallback, which shape” in docs (see `docs/architecture/metadata-retrieval-by-type.md`) and keep code as a thin implementation of those rules. New types or org quirks should be added by updating the doc and one place in code.

### 3.2 Duplication

| Duplication | Location A | Location B | Recommendation |
|------------|------------|------------|----------------|
| **Validation Rule formula** | `DependencyService.getValidationRuleFormulaReferences()` — queries ValidationRule by Id, reads Metadata.errorConditionFormula / ErrorConditionFormula | `ProcessFlowService.fetchValidationRuleFormula()` — same query and same field read | Extract shared method e.g. `ToolingApiClient` or a small `ValidationRuleMetadataService`; both call it. |
| **Flow metadata fetch** | `ProcessFlowService.getFlowMetadata(flowVersionId)` wraps `ToolingApiClient.getFlowMetadata()` | Direct use elsewhere | Remove wrapper; call `ToolingApiClient.getFlowMetadata()` everywhere. |
| **Field reference matching (Flow)** | `DependencyService` has logic to match flow field tokens to `object.field` | `DataJourneyService` has similar but not identical canonicalization | Unify in one place (e.g. FlowFieldAnalyzer or a small FieldReferenceMatcher); both services use it. |
| **Setup URLs** | `SetupUrlResolver.resolve()` used in DependencyService, BlastRadiusService, DataJourneyService | Hardcoded `/lightning/setup/...` in DependencyService (Layout/FlexiPage), ProcessFlowService (triggers, validation rules, flows), DataJourneyService (object home, flows) | Route all Setup URL construction through SetupUrlResolver; extend resolver if new patterns are needed. |

### 3.3 Bypassing shared abstractions

- **SetupUrlResolver**: Several places build URLs manually:
  - `DependencyService`: Layout → `/lightning/setup/ObjectManager/.../PageLayouts/view`, FlexiPage → `.../LightningPages/view`.
  - `ProcessFlowService`: ApexTrigger → `/lightning/setup/ApexTriggers/home`, Validation Rule → `/lightning/setup/ObjectManager/.../ValidationRules/view`, Flow → `/lightning/setup/Flows/home`.
  - `DataJourneyService`: Object manager home, Flows home.
- **Effect**: URL changes or new types require edits in multiple classes. All Setup links should go through SetupUrlResolver (and the doc that defines type → URL).

### 3.4 Unnecessary indirection

- `ProcessFlowService.getFlowMetadata(flowVersionId)` only calls `ToolingApiClient.getFlowMetadata(flowVersionId)`. This adds no value; call ToolingApiClient directly and delete the wrapper.

### 3.5 Complexity hotspots

- **ToolingApiClient**: Five-level flow fallback and four-level dependency fallback are correct for org variability but are not summarized in code comments or a single doc. The doc `metadata-retrieval-analysis.md` describes the “why”; the “what exactly runs at each level” should live in `docs/architecture/metadata-retrieval-by-type.md` so agents and developers don’t have to read Apex to understand behavior.
- **DependencyService.searchDependencies()**: Large method with many branches (Formula Field, Validation Rule, Field, Flow, Custom Label, supplementary scans). Consider splitting by metadata type into small methods that implement the documented retrieval strategy for that type.

---

## 4. Gaps and Risks

### 4.1 Callouts and limits

- `ToolingApiClient.checkCalloutBudget()` exists and is used before callouts. Good.
- No transaction-level “callout budget” passed into services: features that do many flow metadata GETs (e.g. subflow scan) can still approach 100 callouts. Document in architecture that flow-heavy operations must cap iterations or use batching/caching.

### 4.2 Error handling

- 400 response bodies are parsed and surfaced in `buildErrorMessage()` (metadata-retrieval-analysis fix applied). Good.
- `getFlowMetadata()` is not wrapped in try/catch in loops; one bad flow version can fail the whole scan. Recommended: catch per flow, log, skip, continue.

### 4.3 Inconsistencies across features

- **Blast Radius** uses only `MetadataComponentDependency` (no Schema, no Flow metadata); it’s the simplest and most consistent.
- **Data Journey** and **DependencyService** both interpret “which flow elements touch this field” with similar but separate logic; unifying would reduce bugs and maintenance.

---

## 5. Recommendations (Prioritized)

1. **Document retrieval by metadata type**  
   Use and maintain `docs/architecture/metadata-retrieval-by-type.md` as the single source of truth for “how we get data for each type.” Implement code to follow that doc.

2. **Route all Setup URLs through SetupUrlResolver**  
   Replace every hardcoded `/lightning/setup/...` with a call to `SetupUrlResolver` (extend the resolver for any missing type/URL patterns).

3. **Deduplicate Validation Rule formula retrieval**  
   Single shared method (e.g. in ToolingApiClient or a tiny helper) that returns formula text or field refs; DependencyService and ProcessFlowService both use it.

4. **Remove ProcessFlowService.getFlowMetadata wrapper**  
   Use `ToolingApiClient.getFlowMetadata()` directly everywhere.

5. **Unify field-reference matching for flows**  
   One place (e.g. FlowFieldAnalyzer or a dedicated utility) for “flow token → object.field”; DependencyService and DataJourneyService use it.

6. **Refactor searchDependencies by type**  
   Break into small methods per metadata type (e.g. `searchFormulaFieldDependencies`, `searchValidationRuleDependencies`, `searchFieldDependencies`, …) that align with the documented retrieval matrix.

7. **Add agent-facing index**  
   Keep `docs/architecture/README.md` (and pointer in CLAUDE.md) so agents know where to find retrieval rules and architectural decisions.

---

## 6. References

- **Architecture and retrieval**: `docs/architecture/README.md`, `docs/architecture/metadata-retrieval-by-type.md`, `docs/architecture/decisions.md`
- **Existing analysis**: `docs/delivered/metadata-retrieval-analysis.md`, `docs/delivered/discussion.md`
- **Project overview**: `CLAUDE.md`
