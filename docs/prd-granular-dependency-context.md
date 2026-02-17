# PRD: Granular Dependency Context — Element-Level Reference Detail

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU v1 tells you **that** a component references something, but not **where** inside that component. When the dependency results say "Route_By_Industry (Flow) references Account.Industry", the admin still has to:

1. Open Flow Builder
2. Manually scan all elements (decisions, assignments, record updates, formulas...)
3. Figure out which element(s) actually use that field

This problem exists across all component types:

- **Flows**: Which specific element(s) — Decision, Assignment, Record Update, Get Records, Screen — reference the field? Is it a read or a write?
- **Apex Classes**: Which line(s) of code reference the field? Is it in a SOQL query (read), a DML statement (write), or just a variable assignment?
- **Validation Rules**: The dependency exists because the VR formula references the field — but the user can't see the formula without navigating to Setup.
- **Apex Triggers**: Same as Apex Classes, plus which trigger context (before insert, after update, etc.)

### The "Now What?" Problem

After finding 15 dependencies for `Account.Industry`, the admin knows the field is used in 15 places — but doesn't know the **nature** of each usage. Are they reading it? Writing it? Using it in a condition? Displaying it? This matters because:

- **Reads** are safe to observe — changing a field value won't break readers, just alter their behavior
- **Writes** mean the component modifies this field — critical for understanding data flow
- **Conditions** mean the component's logic path depends on this field's value — changing picklist values could break branching
- **Display** means a user sees this field — layout changes might be needed

## 2. Solution

Enhance dependency results with **element-level context** for each reference:

### For Flows
Show which Flow element(s) reference the component, what type of element it is, and whether it's a read or write:

```
Route_By_Industry (Flow)    [Read]
  ├─ Decision: "Check_Industry"         → reads Account.Industry in condition
  ├─ Get Records: "Get_Accounts"        → filters by Account.Industry
  └─ Assignment: "Set_Variables"        → reads Account.Industry into variable
```

### For Apex Classes
Show approximate line numbers and usage context:

```
AccountService (ApexClass)    [Read/Write]
  ├─ Line 42: SOQL query               → reads Account.Industry in WHERE clause
  ├─ Line 87: DML update               → writes Account.Industry
  └─ Line 103: Conditional             → reads Account.Industry in IF statement
```

### For Validation Rules
Show the formula text and highlight the field reference:

```
Require_Industry_For_Enterprise (ValidationRule)    [Read]
  Formula: IF(Type = 'Enterprise' && ISBLANK(Industry), true, false)
           Reads: Account.Industry, Account.Type
```

### For Triggers
Show trigger contexts and approximate usage:

```
AccountTrigger (ApexTrigger)    [Read/Write]
  Contexts: Before Insert, After Update
  ├─ Line 15: reads Account.Industry in conditional
  └─ Line 28: writes Account.Industry in assignment
```

## 3. Technical Architecture

### 3.1 Flow Element Context

**Already partially built**: `FlowFieldAnalyzer.cls` already parses Flow metadata and returns `fieldsRead` and `fieldsWritten` lists. This enhancement adds element-level detail.

#### Enhanced FlowFieldAnalysis

```apex
// Current:
public class FlowFieldAnalysis {
    @AuraEnabled public String flowApiName;
    @AuraEnabled public String flowLabel;
    @AuraEnabled public List<String> fieldsRead;
    @AuraEnabled public List<String> fieldsWritten;
    @AuraEnabled public List<String> subflowsCalled;
}

// Enhanced — add element-level detail:
public class FlowFieldReference {
    @AuraEnabled public String fieldName;         // 'Account.Industry'
    @AuraEnabled public String elementName;        // 'Check_Industry'
    @AuraEnabled public String elementType;        // 'Decision', 'Assignment', 'RecordUpdate', etc.
    @AuraEnabled public String accessType;         // 'Read' or 'Write'
    @AuraEnabled public String context;            // 'Condition formula', 'Record filter', 'Field assignment'
}

public class FlowFieldAnalysis {
    @AuraEnabled public String flowApiName;
    @AuraEnabled public String flowLabel;
    @AuraEnabled public List<String> fieldsRead;
    @AuraEnabled public List<String> fieldsWritten;
    @AuraEnabled public List<String> subflowsCalled;
    @AuraEnabled public List<FlowFieldReference> fieldReferences;  // NEW
}
```

#### Element Scanning Enhancement

Extend `FlowFieldAnalyzer.analyzeFlow()` to track element context:

```apex
// For each Flow element type, record WHERE the field is referenced:

// decisions → condition formulas (READ)
for each decision.rules.conditions:
    if condition.leftValueReference contains fieldName:
        add FlowFieldReference(field, decision.name, 'Decision', 'Read', 'Condition formula')

// assignments → variable assignments (READ source, WRITE target)
for each assignment.assignmentItems:
    if assignTo references field → WRITE
    if value references field → READ

// recordUpdates → field values being set (WRITE)
for each recordUpdate.inputAssignments:
    if field matches → WRITE, context = 'Record update field assignment'

// recordLookups → filter criteria (READ), output fields (READ)
for each recordLookup.filters:
    if value references field → READ, context = 'Record lookup filter'
for each recordLookup.outputAssignments:
    if field matches → READ, context = 'Record lookup output'

// screens → display fields (READ), input fields (WRITE)
// formulas → formula expressions (READ)
```

### 3.2 Apex Context Detection

Apex line-level analysis is the most complex and least precise. Two approaches:

#### Approach A: Regex-Based Source Scanning (Recommended for v1)

Query Apex source via Tooling API and scan with regex patterns:

```apex
public class ApexFieldReference {
    @AuraEnabled public String fieldName;
    @AuraEnabled public Integer lineNumber;
    @AuraEnabled public String accessType;     // 'Read', 'Write', 'Condition'
    @AuraEnabled public String context;         // 'SOQL WHERE clause', 'DML assignment', 'IF condition'
    @AuraEnabled public String lineSnippet;     // Truncated source line
}
```

**Detection heuristics**:

| Pattern | Access Type | Context |
|---------|------------|---------|
| `SELECT ... fieldName ... FROM` | Read | SOQL query |
| `WHERE fieldName =` or `WHERE fieldName !=` | Read | SOQL filter |
| `obj.fieldName = value` | Write | DML assignment |
| `value = obj.fieldName` | Read | Variable read |
| `if (obj.fieldName ...)` | Read | Conditional |
| `trigger.new[i].fieldName` | Read/Write | Trigger context |

**Limitations of regex approach**:
- Cannot track variables (`String ind = acc.Industry; if (ind == ...)` — misses the `if` line)
- Cannot detect dynamic field access (`acc.get('Industry')`)
- Approximate — not a proper AST parser
- Source code retrieval costs 1 API call per Apex class

#### Approach B: Symbol Table (Future Enhancement)

The Tooling API exposes `ApexClassMember` with `SymbolTable` — a parsed AST with variable types, method references, and locations. This is far more accurate but significantly more complex to implement.

**Recommendation**: Start with Approach A (regex) for v1, plan Approach B for a future iteration.

### 3.3 Validation Rule Formula Display

**Data source**: Tooling API `ValidationRule` object has `Metadata.errorConditionFormula` field.

```apex
public class ValidationRuleContext {
    @AuraEnabled public String ruleName;
    @AuraEnabled public String formula;             // Full formula text
    @AuraEnabled public Boolean isActive;
    @AuraEnabled public String errorMessage;
    @AuraEnabled public List<String> referencedFields;  // Fields found in formula
}
```

**Query**:
```sql
SELECT Id, ValidationName, Metadata
FROM ValidationRule
WHERE EntityDefinition.QualifiedApiName = 'Account'
  AND ValidationName = 'Require_Industry'
```

Parse `Metadata.errorConditionFormula` to extract field references using regex: `[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)?(__c)?`

### 3.4 Trigger Context Detection

For ApexTrigger references, parse the trigger source to detect contexts:

```apex
public class TriggerContext {
    @AuraEnabled public Boolean beforeInsert;
    @AuraEnabled public Boolean afterInsert;
    @AuraEnabled public Boolean beforeUpdate;
    @AuraEnabled public Boolean afterUpdate;
    @AuraEnabled public Boolean beforeDelete;
    @AuraEnabled public Boolean afterDelete;
    @AuraEnabled public Boolean afterUndelete;
}
```

Parse from trigger definition: `trigger AccountTrigger on Account (before insert, after update)` → extract contexts.

### 3.5 Data Model

New wrapper added to existing `DependencyRecord`:

```apex
// Extend existing DependencyRecord:
public class DependencyRecord {
    @AuraEnabled public String metadataComponentId;
    @AuraEnabled public String metadataComponentName;
    @AuraEnabled public String metadataComponentType;
    @AuraEnabled public String metadataComponentNamespace;
    @AuraEnabled public String accessType;
    @AuraEnabled public String setupUrl;
    // NEW:
    @AuraEnabled public List<ReferenceContext> referenceDetails;
}

public class ReferenceContext {
    @AuraEnabled public String elementName;    // Flow element, Apex line, VR formula
    @AuraEnabled public String elementType;    // 'Decision', 'SOQL', 'Formula', etc.
    @AuraEnabled public String accessType;     // 'Read', 'Write', 'Condition', 'Display'
    @AuraEnabled public String detail;          // Human-readable description
    @AuraEnabled public Integer lineNumber;     // For Apex only
    @AuraEnabled public String snippet;         // Code/formula snippet (truncated)
}
```

### 3.6 Service Layer Changes

#### New Class: `ReferenceContextService.cls`

```apex
public with sharing class ReferenceContextService {
    /**
     * Enrich dependency results with element-level context.
     * Called after initial dependency query.
     */
    public static List<DependencyRecord> enrichWithContext(
        List<DependencyRecord> dependencies,
        String searchedComponentName,
        String searchedMetadataType
    ) {
        for (DependencyRecord dep : dependencies) {
            if (dep.metadataComponentType == 'Flow') {
                dep.referenceDetails = getFlowContext(dep, searchedComponentName);
            } else if (dep.metadataComponentType == 'ApexClass') {
                dep.referenceDetails = getApexContext(dep, searchedComponentName);
            } else if (dep.metadataComponentType == 'ApexTrigger') {
                dep.referenceDetails = getTriggerContext(dep, searchedComponentName);
            } else if (dep.metadataComponentType == 'ValidationRule') {
                dep.referenceDetails = getValidationRuleContext(dep, searchedComponentName);
            }
        }
        return dependencies;
    }
}
```

**API budget**: Each enrichment requires 1 Tooling API call per component (to retrieve source/metadata). To stay within limits:
- Cap enrichment at 50 components per search
- Flow context reuses FlowFieldAnalyzer (already caches flow metadata)
- Apex/Trigger source retrieval is opt-in (user clicks "Show Details" to load)

### 3.7 Lazy Loading Strategy

Context enrichment is **expensive** (1 API call per component). Two strategies:

#### Strategy A: Eager Enrichment (Recommended for Flows + VRs)

For Flows and Validation Rules, fetch context automatically during the initial search:
- Flow metadata is already retrieved for subflow detection (FlowParsingService)
- VR metadata is a single Tooling API query per object (batch all VRs)
- Cost: 0-2 additional API calls (metadata already fetched or cheap to batch)

#### Strategy B: Lazy Enrichment (Recommended for Apex)

For Apex classes and triggers, don't fetch source automatically:
- Source retrieval costs 1 API call per class (expensive for 10+ Apex results)
- Instead, show a "Show Details" button on each Apex result
- Clicking it fetches the source, parses it, and displays reference context
- Cost: 1 API call per click (user-controlled)

## 4. UI Design

### Enhanced Dependency Result Item

```
┌─────────────────────────────────────────────────────────────────┐
│  ▼ Flow (4)                                                      │
│                                                                  │
│  ┌── Route_By_Industry ──────────────── [Read] ──── [↗] ────┐  │
│  │                                                            │  │
│  │  Referenced in:                                            │  │
│  │  ├─ Decision: "Check_Industry"                             │  │
│  │  │  Reads Account.Industry in condition formula             │  │
│  │  ├─ Get Records: "Get_Enterprise_Accounts"                 │  │
│  │  │  Filters WHERE Account.Industry = 'Technology'          │  │
│  │  └─ Assignment: "Set_Region_Var"                           │  │
│  │     Reads Account.Industry into {!varIndustry}             │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌── Territory_Assignment_Flow ──────── [Read] ──── [↗] ────┐  │
│  │                                                            │  │
│  │  Referenced in:                                            │  │
│  │  └─ Decision: "Route_By_Industry"                          │  │
│  │     Reads Account.Industry in condition formula             │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ▼ ApexClass (3)                                                 │
│                                                                  │
│  ┌── AccountService ────────────── [Read/Write] ── [↗] ─────┐  │
│  │                                                            │  │
│  │  [Show Details]  ← Click to load Apex source analysis      │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌── AccountService (after clicking Show Details) ───────────┐  │
│  │                                                            │  │
│  │  Referenced in:                                            │  │
│  │  ├─ Line 42: SOQL query                                   │  │
│  │  │  "SELECT Id, Industry FROM Account WHERE..."            │  │
│  │  ├─ Line 87: DML update                                   │  │
│  │  │  "acc.Industry = newValue;"                              │  │
│  │  └─ Line 103: Conditional                                  │  │
│  │     "if (acc.Industry == 'Technology') {"                   │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ▼ ValidationRule (2)                                            │
│                                                                  │
│  ┌── Require_Industry_For_Enterprise ─── [Read] ──── [↗] ───┐  │
│  │                                                            │  │
│  │  Formula:                                                  │  │
│  │  IF(Type = 'Enterprise' && ISBLANK(Industry), true, false)│  │
│  │  ─────────────────────────────────                         │  │
│  │  Fields referenced: Industry, Type                         │  │
│  │  Status: Active                                            │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Collapsed vs. Expanded

By default, reference details are **collapsed** — the result shows the component name, access badge, and setup link only (same as v1). A toggle expands to show element-level detail.

```
Collapsed (default):
  Route_By_Industry    [Read]    [↗]

Expanded:
  Route_By_Industry    [Read]    [↗]    [▼ Hide Details]
    ├─ Decision: "Check_Industry" → reads in condition
    ├─ Get Records: "Get_Enterprise_Accounts" → filters by
    └─ Assignment: "Set_Region_Var" → reads into variable
```

## 5. Files to Create / Modify

### New Files

| File | Purpose |
|------|---------|
| `classes/ReferenceContextService.cls` | Orchestrates context enrichment across component types |
| `classes/ReferenceContextServiceTest.cls` | Tests with mocked Tooling API responses |

### Modified Files

| File | Change |
|------|--------|
| `FlowFieldAnalyzer.cls` | Add `FlowFieldReference` inner class. Enhance `analyzeFlow()` to populate `fieldReferences` list with element-level detail. |
| `FlowFieldAnalyzerTest.cls` | Add tests for element-level reference tracking. |
| `DependencyService.cls` | Add `ReferenceContext` and `FlowFieldReference` inner classes to `DependencyRecord`. Optionally call `ReferenceContextService.enrichWithContext()` after initial query. |
| `DependencyServiceTest.cls` | Update tests for enriched results. |
| `DependencyController.cls` | Add `getApexContext(componentId, fieldName)` @AuraEnabled method for lazy Apex loading. |
| `DependencyControllerTest.cls` | Test lazy context loading. |
| `dependencyResults` LWC | Add expandable detail sections per result. Add "Show Details" button for Apex. Display Flow element context, VR formula, Apex line references. |

## 6. API Budget

| Operation | API Calls | When |
|-----------|-----------|------|
| Flow element context | 0 additional (already fetched for subflow detection) | Automatic |
| VR formula retrieval | 1 per object (batches all VRs) | Automatic |
| Apex source retrieval | 1 per class/trigger | On user click ("Show Details") |
| Total automatic overhead | 1-2 calls | Per search |
| Total on-demand overhead | 1 call per Apex click | User-controlled |

### Governor Limit Safety

| Constraint | Limit | Safeguard |
|-----------|-------|-----------|
| Max components enriched automatically | 50 | Skip enrichment beyond 50 |
| Max Apex sources retrieved per session | 20 | Disable "Show Details" after 20 |
| Tooling API calls per transaction | 100 | Count across all operations |
| Apex source body size | 1MB per class | Truncate scan at 1MB |

## 7. Known Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| Apex regex scanning is approximate | May miss variable-indirect references | "Show Details" disclaimer: "Approximate — based on source text scanning" |
| Dynamic Apex (`sObject.get('Field')`) not detectable | Inherently undetectable | Note in UI |
| Flow formula references may be in nested elements | Deep nesting may be missed | Scan top-level elements only for v1 |
| Apex source retrieval is expensive | 1 API call per class | Lazy loading — user opts in |
| VR formula may reference cross-object fields | `Account.Owner.Profile.Name` appears as single reference | Show full formula text so user can read it |
| Long Apex classes (1000+ lines) slow to scan | Regex over large strings | Cap scan at first 5000 lines |

## 8. AppExchange Considerations

- `ReferenceContextService.cls` uses `with sharing`
- Apex source code is retrieved but NOT stored or displayed in full — only line snippets (max 120 chars) are shown
- No external libraries for parsing
- All regex patterns are compiled once and reused
- 75%+ test coverage with mocked callouts
- Source code snippets are HTML-escaped before rendering (LWC handles this natively)

## 9. Phasing

### Phase A (MVP)
- Flow element-level context (leverages existing FlowFieldAnalyzer)
- VR formula display (single API call per object)
- Improved Read/Write badges based on Flow analysis (read in condition vs. write in assignment)

### Phase B
- Apex regex-based source scanning (lazy loading)
- Trigger context detection (before/after, insert/update/delete)

### Phase C (Future)
- Apex Symbol Table parsing for precise line-level references
- Cross-element flow tracing (field read in Decision → which path taken → what happens on each path)

## 10. Success Metrics

| Metric | Target |
|--------|--------|
| Flow element accuracy | 90%+ of field references correctly identified with element name |
| VR formula display | 100% of active VRs show formula text |
| Apex line detection | 70%+ accuracy (regex heuristic) |
| Detail expansion rate | 50%+ of users expand at least one result |
| Apex "Show Details" click rate | 30%+ of users with Apex results |
| Context enrichment time | < 2s additional on top of base search |
| No regressions | All existing tests pass |
| API budget adherence | 0 additional calls for Flow/VR context (reuse), max 1/click for Apex |
