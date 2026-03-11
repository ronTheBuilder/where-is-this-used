# Metadata Retrieval Analysis & Feature Roadmap

**Version**: 1.0
**Date**: 2026-02-17
**Status**: Analysis

---

## Table of Contents

1. [Current State Summary](#1-current-state-summary)
2. [Implementation Bugs — Flow 400 Error Analysis](#2-implementation-bugs--flow-400-error-analysis)
3. [Metadata Retrieval Issues — Non-Field Types](#3-metadata-retrieval-issues--non-field-types)
4. [Architectural Issues Affecting All Metadata Retrieval](#4-architectural-issues-affecting-all-metadata-retrieval)
5. [Proposed New Features](#5-proposed-new-features)
6. [Prioritized Roadmap](#6-prioritized-roadmap)

---

## 1. Current State Summary

WITU currently supports 4 metadata types via the Dependency Finder, plus 3 advanced features:

| Feature | Data Source | Status |
|---------|------------|--------|
| Standard Field lookup | MetadataComponentDependency | Implemented |
| Custom Field lookup | MetadataComponentDependency | Implemented |
| Flow (subflow detection) | MetadataComponentDependency + FlowVersionView + Flow metadata parsing | Implemented |
| Apex Class lookup | MetadataComponentDependency | Implemented |
| Blast Radius graph | Recursive MetadataComponentDependency traversal | Implemented |
| Data Journey tracing | MetadataComponentDependency + FlowFieldAnalyzer | Implemented |
| Process Flow Mapper | ApexTrigger + ValidationRule + FlowVersionView queries | Implemented |

All features rely on the Tooling API via Named Credential (`WITU_ToolingAPI`).

---

## 2. Implementation Bugs — Flow 400 Error Analysis

**Reported symptom**: HTTP 400 (Bad Request) error when retrieving flow metadata.

When a user selects "Flow" in the Dependency Finder, two code paths execute in `DependencyService.searchDependencies()`:

1. **Path A** (line 106-111): MetadataComponentDependency query with `RefMetadataComponentType = 'Flow'`
2. **Path B** (line 128-130): `findSubflowUsages()` — queries FlowVersionView + retrieves individual flow metadata

Either path can produce a 400. Here are the likely causes, ordered by probability:

### Bug 1: Wrong RefMetadataComponentType value for Flows (Path A)

**File**: `DependencyService.cls:327-333`

The `getRefMetadataType()` map returns `'Flow'` for the Flow metadata type:
```apex
'Flow' => 'Flow'
```

However, `MetadataComponentDependency` may use `'FlowDefinition'` as the `RefMetadataComponentType` for flow references — not `'Flow'`. The value `'Flow'` refers to a specific flow version, while `'FlowDefinition'` refers to the flow itself. When other components (Apex, Lightning Pages) reference a flow, they reference the FlowDefinition, not a specific version.

If `'Flow'` is not a recognized filter value for `RefMetadataComponentType`, the Tooling API returns HTTP 400.

**Fix**: Try `'FlowDefinition'` instead. If uncertain, query without the type filter and inspect actual `RefMetadataComponentType` values returned:
```sql
SELECT RefMetadataComponentType, RefMetadataComponentName
FROM MetadataComponentDependency
WHERE RefMetadataComponentName = 'Your_Flow_Api_Name'
```

### Bug 2: FlowDefinitionView relationship not filterable in WHERE (Path B)

**File**: `DependencyService.cls:209-214`

The subflow query uses `FlowDefinitionView.ApiName` in a `WHERE` clause:
```sql
WHERE Status = 'Active'
  AND FlowDefinitionView.ApiName != 'MyFlowName'
ORDER BY FlowDefinitionView.ApiName
```

On some orgs or API versions, `FlowDefinitionView.ApiName` may not be filterable or sortable via the Tooling API. The Tooling API has different filter rules than standard SOQL — relationship fields are often not filterable in WHERE clauses.

**Fix**: Remove `FlowDefinitionView.ApiName` from the WHERE and ORDER BY clauses. Filter client-side instead:
```sql
SELECT Id, FlowDefinitionView.ApiName, FlowDefinitionView.Label
FROM FlowVersionView
WHERE Status = 'Active'
```
Then skip flows matching the target name in Apex code.

### Bug 3: ORDER BY on MetadataComponentDependency may not be supported (Path A)

**File**: `DependencyService.cls:111`

The query includes `ORDER BY MetadataComponentType, MetadataComponentName`. MetadataComponentDependency is a Beta Tooling API object and may not support ORDER BY on all fields. If the API doesn't support sorting on these columns, it returns 400.

**Fix**: Remove the ORDER BY clause and sort in Apex code after retrieving results.

### Bug 4: Flow metadata GET for corrupted/incompatible flow versions (Path B)

**File**: `DependencyService.cls:249-253`

The `getFlowMetadata()` method calls:
```
GET /services/data/v65.0/tooling/sobjects/Flow/{flowVersionId}
```

This can return 400 if:
- The flow version is corrupted or in an invalid state
- The flow was created with a newer API version than v65.0 supports
- The flow uses features not available at API v65.0 (e.g., Orchestrator flows, AI flows)
- The flow version ID is from a deleted or superseded version

There's no try/catch around `getFlowMetadata()` — a single bad flow version kills the entire subflow scan.

**Fix**: Wrap `getFlowMetadata()` in a try/catch inside the loop:
```apex
for (Object recordObj : flowQuery.records) {
    // ...
    Map<String, Object> flowMetadata;
    try {
        flowMetadata = getFlowMetadata(flowVersionId);
    } catch (DependencyServiceException ex) {
        // Log and skip this flow, continue scanning others
        System.debug(LoggingLevel.WARN, 'Skipping flow ' + parentApiName + ': ' + ex.getMessage());
        continue;
    }
    // ...
}
```

### Bug 5: Callout governor limit exhaustion (Path B)

**File**: `DependencyService.cls:216-246`

The `findSubflowUsages()` method:
1. Makes 1 callout for the FlowVersionView query
2. Makes 1 callout per flow for metadata retrieval

Salesforce allows 100 callouts per transaction. Path A already consumes 1+ callouts (pagination can add more). If the org has 95+ active flows, Path B will exceed 100 callouts and throw `System.CalloutException`, which may surface as an unhandled error rather than a clean 400.

However, the 400 the user sees is likely from the Tooling API itself (Bugs 1-4), not a governor limit.

### Bug 6: Error messages swallow the actual API error

**File**: `DependencyService.cls:296-311`

When a 400 occurs, the actual Tooling API error message (which contains the specific reason) is only written to `System.debug()`. The user sees:
```
Tooling API request failed (HTTP 400). Check Setup > Debug Logs for details.
```

There's no specific handling for 400 (Bad Request). The API response body typically contains a JSON error like:
```json
[{"message": "field 'RefMetadataComponentName' is not filterable", "errorCode": "INVALID_FIELD"}]
```

This error message is critical for debugging but is discarded.

**Fix**: For 400 errors specifically, parse the response body and include the API error message:
```apex
} else if (status == 400) {
    String apiError = extractApiErrorMessage(response.getBody());
    userMessage = 'Tooling API query error: ' + apiError;
}
```

### Summary: Most Likely Cause

The most probable cause of the 400 error is **Bug 1** (wrong `RefMetadataComponentType` value `'Flow'` should be `'FlowDefinition'`) or **Bug 2** (`FlowDefinitionView.ApiName` not filterable in WHERE). To confirm, enable Debug Logs in the org and check the `System.debug` output for the actual API error response.

### Diagnostic Steps

1. In Setup > Debug Logs, enable logs for the running user
2. Reproduce the error by searching for a flow in WITU
3. Check the debug log for: `Tooling API error (400): ...`
4. The response body will contain the exact Tooling API error message
5. Match the error to one of the bugs above

---

## 3. Metadata Retrieval Issues — Non-Field Types

### 3.1 Flow Metadata Retrieval

**Severity: High — this is the most problematic area.**

#### Issue: N+1 HTTP callout pattern for subflow detection

`DependencyService.findSubflowUsages()` (line 202) queries all active flows, then makes a **separate HTTP GET** for each flow to retrieve its metadata:

```
FlowVersionView query → returns N flows → N individual GET /sobjects/Flow/{id} calls
```

For an org with 200 active flows, this is 201 HTTP callouts per single subflow search. Salesforce enforces a **100 callout limit** per transaction, meaning this will fail for orgs with more than ~99 active flows (the initial query takes 1 callout).

**Current mitigation**: `MAX_FLOW_SCAN = 200` cap, but this doesn't solve the callout limit — it will still hit the 100-callout governor limit before reaching 200.

**Impact**: Subflow detection silently returns incomplete results or throws a callout limit exception in orgs with many flows.

**Recommended fix**:
- Use Composite API to batch flow metadata retrievals (up to 25 per request)
- Or query `FlowVersionView` with additional filters to narrow the scan (e.g., filter by `ProcessType` to exclude Screen Flows that can't contain subflows)
- Cache flow metadata within the transaction using a static map (partially done in `DataJourneyService` via `TraceContext.flowAnalysisByVersionId`, but not in `DependencyService`)

#### Issue: Flow metadata JSON structure varies by flow type

The Tooling API returns flow metadata as JSON, but the structure differs based on flow type (Record-Triggered, Screen, Autolaunched, Scheduled, Platform Event-Triggered). Key differences:

| Flow Type | Has `subflows` key | Has `start` element | Has `triggerType` | Has `screens` |
|-----------|-------------------|---------------------|-------------------|---------------|
| Record-Triggered | Yes | Yes | Yes | No |
| Screen Flow | Yes | No | No | Yes |
| Autolaunched | Yes | No | No | No |
| Scheduled | Yes | Yes (with schedule) | No | No |
| Platform Event | Yes | Yes | Yes | No |

`FlowFieldAnalyzer` handles this reasonably well by scanning all keys recursively, but `ProcessFlowService.inferTriggerTypeFromMetadata()` uses fragile heuristics — serializing the entire metadata to JSON and searching for string matches like `"before"` or `"after"` (line 457-467). This can produce false positives if those strings appear in flow element labels or descriptions.

#### Issue: No detection of Screen Flow embedding

When a Screen Flow is embedded in a Lightning Page, Record Page, or another Screen Flow, `MetadataComponentDependency` may not track this relationship. The current subflow detection only looks for the `flowName` key inside `subflows` elements, missing:
- Screen Flows embedded via `lightning:flow` in Aura components
- Screen Flows added to Lightning Pages via Flow component
- Screen Flows launched via `NavigationMixin` in LWC

#### Issue: FlowVersionView query doesn't filter by ProcessType

`DependencyService.getActiveFlows()` (line 144) retrieves ALL active flow versions without filtering by `ProcessType`. This means the list includes Screen Flows, Scheduled Flows, and Platform Event flows — all of which return in the picker but may not yield useful dependency results for subflow detection.

### 3.2 Apex Class Metadata Retrieval

**Severity: Medium**

#### Issue: 2,000-row limit on Apex class picker

`DependencyService.getApexClasses()` (line 179) queries `ApexClass` with a 2,000-row cap. Large enterprise orgs can have 3,000+ Apex classes (including managed package classes). Classes beyond this limit won't appear in the picker.

**Recommended fix**: Add search-as-you-type with a `LIKE` filter instead of loading all classes upfront:
```sql
SELECT Id, Name FROM ApexClass WHERE Name LIKE '%searchTerm%' ORDER BY Name LIMIT 50
```

#### Issue: No distinction between managed and unmanaged Apex

The Apex class picker returns all classes including those from managed packages (namespace prefixed). Users typically want to analyze their own org's classes, not managed package internals. The `MetadataComponentNamespace` field is available but not used for filtering in the picker.

#### Issue: Dynamic references undetectable

As documented, `Type.forName()`, dynamic SOQL, and reflection-based references are inherently undetectable by static dependency analysis. This is a known limitation with no workaround, but the UI should communicate this more clearly.

### 3.3 MetadataComponentDependency General Issues

**Severity: High — affects all metadata types.**

#### Issue: Client-side filtering downloads entire type

The most critical performance issue: `RefMetadataComponentName` is not filterable in `WHERE` clauses on all orgs. The workaround (querying by `RefMetadataComponentType` only, then filtering client-side) means:

- A query for `Account.Industry` (StandardEntity type) downloads ALL standard field dependencies in the entire org
- A query for a single custom field downloads ALL custom field dependencies
- For orgs with thousands of fields across hundreds of objects, this can hit the 2,000-row limit before even reaching the target field

**Impact**: For a large org with 5,000 custom field dependencies, searching for one field may:
1. Return only the first 2,000 rows (none of which may match the target field)
2. Show "limit reached" warning even though the target field has only 3 dependencies
3. Miss the target field's dependencies entirely

**This is the biggest data accuracy issue in the app.**

**Recommended fix**:
- Try the `WHERE RefMetadataComponentName = '...'` filter first (it works on many orgs)
- If it fails (400 error), fall back to client-side filtering with an explicit warning
- Consider using Composite Batch API to query in smaller chunks

#### Issue: Inconsistent RefMetadataComponentType values

The Tooling API returns different `RefMetadataComponentType` values depending on the org edition and API version:

| Expected Type | Possible Actual Values |
|---------------|----------------------|
| `StandardEntity` | `StandardEntity`, `EntityDefinition` |
| `CustomField` | `CustomField`, `FieldDefinition` |
| `Flow` | `Flow`, `FlowDefinition`, `FlowVersion` |
| `ApexClass` | `ApexClass` (consistent) |

The current code hardcodes exact string matches in `getRefMetadataType()`, which may miss results on orgs that return alternative type names.

#### Issue: MetadataComponentDependency is still Beta

Although stable since Summer '18 (7+ years), the Beta status means:
- No contractual SLA on response format
- Fields/behavior can change without deprecation notice
- No guarantee of complete coverage across metadata types

The current `DependencyService` abstraction is well-designed for a future swap, but there's no runtime detection of API behavior changes.

---

## 4. Architectural Issues Affecting All Metadata Retrieval

### 4.1 Duplicated Tooling API infrastructure

Four service classes (`DependencyService`, `BlastRadiusService`, `DataJourneyService`, `ProcessFlowService`) each contain their own copies of:
- `ToolingQueryResponse` inner class
- `queryToolingRecords()` method
- `sendGet()` method
- `resolveEndpoint()` method
- `enforceAccess()` method
- `validateComponentName()` method
- `buildSetupUrl()` method

This means a bug fix or improvement (e.g., adding retry logic, improving error messages) must be applied in 4 places. It also means inconsistencies: `DependencyService.queryToolingRecords()` accepts a `maxRows` parameter, while `BlastRadiusService.queryToolingRecords()` does not.

**Recommended fix**: Extract a shared `ToolingApiClient` utility class with:
- HTTP callout handling (with retry for 429/503)
- Query execution and pagination
- Response parsing
- Error handling
- Security gate (`enforceAccess`)

### 4.2 No cross-feature flow metadata caching

`DataJourneyService` caches flow analysis results within a single `traceDataJourney()` call via `TraceContext.flowAnalysisByVersionId`. But if the user runs a dependency search AND a data journey on the same flow, the metadata is fetched twice (separate transactions). There's no session-level or platform cache.

**Recommended fix**: Use Salesforce Platform Cache (org partition) to cache flow metadata for 5-10 minutes. This significantly reduces API calls for users who explore multiple features in one session.

### 4.3 No callout limit awareness

None of the services check `Limits.getCallouts()` vs `Limits.getLimitCallouts()` before making HTTP requests. They rely on hardcoded caps (`MAX_FLOW_SCAN = 200`, `MAX_API_CALLS = 50`) but don't account for callouts already consumed earlier in the same transaction.

**Recommended fix**: Add a callout budget check before each HTTP request:
```apex
if (Limits.getCallouts() >= Limits.getLimitCallouts() - 1) {
    // Stop and return partial results with warning
}
```

### 4.4 No timeout/retry handling

All services set `request.setTimeout(120000)` (2 minutes) but have no retry logic. A transient 500 or 503 from the Tooling API causes an immediate failure. The error handling strategy in the PRD mentions "Retry once, then show error with Try Again button" but this isn't implemented.

---

## 5. Proposed New Features

### 5.1 Extended Metadata Types (High Value, Medium Effort)

#### Record Type Dependencies

**Problem**: Admins frequently need to know where a Record Type is used before renaming, deactivating, or deleting it. Record Types are referenced in Flows (decision criteria, record creates), Apex (RecordTypeInfo), page layout assignments, compact layouts, and assignment rules.

**Approach**:
- Query `MetadataComponentDependency WHERE RefMetadataComponentType = 'RecordType'`
- Supplement with `RecordType` SOQL for page layout assignments
- Parse Flow metadata for Record Type references in decision elements and record create/update elements

**Picker**: Object → Record Type dropdown (from `Schema.SObjectType.getDescribe().getRecordTypeInfos()`)

#### Custom Label Dependencies

**Problem**: Custom Labels are used across Apex, Visualforce, LWC, and Aura components. Before editing or deleting a label, admins need to know what references it.

**Approach**:
- Query `MetadataComponentDependency WHERE RefMetadataComponentType = 'CustomLabel'`
- This is well-tracked by the API — straightforward to implement

**Picker**: Searchable list from `ExternalString` Tooling API object or `CustomLabel` metadata

#### Custom Metadata Type Dependencies

**Problem**: CMDT records are increasingly used for configuration. Understanding what references a specific CMDT type helps with governance.

**Approach**:
- Query `MetadataComponentDependency WHERE RefMetadataComponentType = 'CustomObject'` filtered to `__mdt` suffix
- Supplement with Apex body search for CMDT SOQL patterns

**Picker**: Filter `Schema.getGlobalDescribe()` for `__mdt` objects

#### Platform Event Dependencies

**Problem**: Platform Events connect disparate parts of an org. Understanding publishers and subscribers is critical for debugging and change management.

**Approach**:
- Query `MetadataComponentDependency` for Platform Event references
- Supplement with `EventRelayConfig` and trigger queries

**Picker**: Filter `Schema.getGlobalDescribe()` for `__e` objects

### 5.2 Unused Metadata Detection (High Value, High Effort)

**Problem**: Orgs accumulate hundreds of custom fields, flows, and classes over years. Many become unused but nobody knows which ones are safe to delete. This is the #1 request from architects doing org cleanup.

**Approach**:
- For a given object, query all custom fields via `Schema.getGlobalDescribe()`
- For each field, run a `MetadataComponentDependency` query
- Fields with zero results are candidates for deletion
- Must exclude fields used in: Reports (blind spot), List Views (blind spot), Profile/PermSet FLS (blind spot)

**Challenges**:
- Very API-intensive: each field requires at least 1 Tooling API call
- Must handle governor limits via Queueable chaining or Batch Apex
- Results need to be stored (custom object or Platform Cache) since the scan takes too long for real-time
- High false-positive risk due to API blind spots (Reports, List Views, Sharing Rules)

**UX**: Separate tab. Select object → "Scan for Unused Fields" → progress bar → results table with "Potentially Unused" and "Confirmed Used" columns.

### 5.3 Cross-Object Impact Analysis (Medium Value, Medium Effort)

**Problem**: When a field is referenced via a lookup relationship (e.g., `Account.Industry` is accessed from Contact via `Account.Industry` in a formula), the current tool may not connect these dots clearly.

**Approach**:
- When displaying results for a field, also search for `ObjectName.FieldName` patterns across lookup paths
- Parse formula fields that reference related objects
- Show cross-object references in a separate results group

### 5.4 CSV/Excel Export (Medium Value, Low Effort)

**Problem**: Architects need to include dependency analysis in change management documentation, code review artifacts, and audit reports.

**Approach**:
- Add "Export CSV" button to each results view
- Generate CSV client-side in LWC (no additional Apex needed)
- Include columns: Component Name, Component Type, Namespace, Access Type, Setup URL

### 5.5 Deep Links to Components (Medium Value, Medium Effort)

**Problem**: After finding a dependency, users want to navigate directly to that component in Setup to inspect or modify it.

**Approach**:
- Build accurate Setup URLs using `MetadataComponentId`
- Current implementation uses generic setup page URLs (e.g., `/lightning/setup/Flows/home`)
- Upgrade to record-specific URLs (e.g., `/builder_platform_interaction/flowBuilder.app?flowId={id}`)
- Requires mapping each `MetadataComponentType` to its specific URL pattern

### 5.6 Dependency Diff / Change Tracking (High Value, Very High Effort)

**Problem**: "What changed since last week?" — architects want to compare dependency snapshots over time to detect unintended coupling or track org evolution.

**Approach**:
- Store dependency snapshots in a custom object (requires package to include storage)
- Scheduled Apex runs periodic scans
- UI shows diff: added dependencies, removed dependencies, changed access types

**Challenges**: Significantly increases package complexity. Requires custom objects (currently zero). Storage limits for large orgs.

### 5.7 Validation Rule Reverse Lookup (Medium Value, Low Effort)

**Problem**: "What fields does this validation rule depend on?" — the reverse question. Currently WITU shows which validation rules reference a field, but not what a specific validation rule references.

**Approach**:
- Query `ValidationRule` by Id via Tooling API
- Parse `ErrorConditionFormula` for field references using the same token extraction as `FlowFieldAnalyzer`
- Display referenced fields as results

**Picker**: Object → Validation Rule dropdown

### 5.8 Formula Field Dependency Analysis (Medium Value, Low Effort)

**Problem**: Formula fields create hidden dependencies. Changing a field that a formula references breaks the formula. Salesforce's native UI shows this, but only for one formula at a time.

**Approach**:
- Query `CustomField` via Tooling API where `Metadata.formula` is not null
- Parse formula text for field references
- Show all fields a formula depends on, and all formulas that depend on a given field

---

## 6. Prioritized Roadmap

### Priority 1 — Fix Critical Bugs (before next release)

| Item | Effort | Impact | Ref |
|------|--------|--------|-----|
| Fix `RefMetadataComponentType` value for Flows (`'Flow'` → `'FlowDefinition'`) | Low | **Fixes 400 error** on flow dependency search | Bug 1 |
| Remove `FlowDefinitionView.ApiName` from WHERE/ORDER BY, filter client-side | Low | **Fixes 400 error** on subflow detection | Bug 2 |
| Remove ORDER BY from MetadataComponentDependency queries | Low | **Fixes potential 400** on unsupported sort | Bug 3 |
| Add try/catch around `getFlowMetadata()` inside loop | Low | Prevents one bad flow from killing entire scan | Bug 4 |
| Add 400 error response parsing to `sendGet()` | Low | Shows actual API error instead of generic message | Bug 6 |
| Add callout limit awareness (`Limits.getCallouts()`) to all services | Low | Prevents governor limit exceptions | Bug 5 |
| Try server-side `RefMetadataComponentName` filter first, fall back to client-side | Low | Massive performance improvement on compatible orgs | Sec 3.3 |
| Add `ProcessType` filter to flow queries in subflow detection | Low | Reduces unnecessary flow scans | Sec 3.1 |
| Extract shared `ToolingApiClient` class | Medium | Eliminates code duplication, enables consistent fixes | Sec 4.1 |

### Priority 2 — Quick Wins (next release)

| Feature | Effort | Impact |
|---------|--------|--------|
| Custom Label dependencies | Low | New metadata type, straightforward API coverage |
| CSV Export | Low | High user value, no new Apex needed |
| Record Type dependencies | Medium | Fills a very common admin need |
| Search-as-you-type for Apex class picker | Low | Solves 2,000-row picker limit |

### Priority 3 — High-Value Features (subsequent releases)

| Feature | Effort | Impact |
|---------|--------|--------|
| Validation Rule reverse lookup | Low | New perspective on existing data |
| Formula Field dependency analysis | Low | Leverages existing parsing infrastructure |
| Custom Metadata Type dependencies | Medium | Growing use case with CMDT adoption |
| Platform Event dependencies | Medium | Critical for event-driven architectures |
| Deep links to components | Medium | Major UX improvement |

### Priority 4 — Strategic Features (future)

| Feature | Effort | Impact |
|---------|--------|--------|
| Unused metadata detection | High | #1 architect request, needs async processing |
| Cross-object impact analysis | Medium | Advanced dependency tracing |
| Dependency diff / change tracking | Very High | Requires custom objects, scheduled jobs |
| Platform Cache for flow metadata | Medium | Performance improvement across all features |

---

*This document should be reviewed alongside `docs/prd.md` (v1 scope) and the delivered v2 PRDs in `docs/delivered/`.*
