# PRD: Data Journey — Field-Level Data Flow Tracing

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU) v2
**Status**: Draft

---

## 1. Problem Statement

WITU v1 answers "where is this field used?" — but it treats each reference as isolated. It doesn't show the **chain effect**: Field A is read by Flow X, which then writes to Field B, which triggers Validation Rule Y, which blocks the save if Field C is blank.

Admins troubleshooting complex orgs need to trace **how data flows through a field** — not just who references it, but what happens to the data downstream.

Common questions:
- **"Where does the value of Account.Industry end up?"** → It's read by a Flow that sets Opportunity.Type, which is checked by a Validation Rule
- **"What populates Contact.Region__c?"** → A before-save Flow reads Account.BillingCountry and writes it here
- **"If I change this field's picklist values, what breaks?"** → Decision elements in 3 Flows, 1 Validation Rule formula, and 2 reports depend on specific values

## 2. Solution

Add a **"Data Journey"** view that traces a specific field's data flow both **upstream** (what writes to it) and **downstream** (what reads it and where that data goes next).

### User Flow
1. User selects a field (same picker as v1)
2. Clicks **"Trace Data Journey"**
3. WITU shows two-directional flow:

```
UPSTREAM (who writes to this field?)          DOWNSTREAM (who reads it and what happens?)
                                              
Account_Region_Flow ──writes──→ [Region__c] ──read by──→ Territory_Assignment_Flow
Admin (manual edit) ──writes──→ [Region__c] ──read by──→ VR: Region_Required_For_Enterprise
Data Loader        ──writes──→ [Region__c] ──read by──→ Report: Revenue by Region
                                              ──read by──→ Formula: Account.Region_Category__c
                                                              ↓
                                                          ──read by──→ Flow: Route_to_Queue
```

## 3. Technical Architecture

### 3.1 Upstream Analysis (Who Writes)

Sources that can write to a field:

| Write Source | Detection Method |
|-------------|-----------------|
| Record-Triggered Flow (before-save) | Parse Flow metadata → find `recordUpdates` or `assignments` targeting this field |
| Record-Triggered Flow (after-save) | Same, but updates via DML |
| Apex Trigger / Class | MetadataComponentDependency (type = Apex, infer write from trigger context) |
| Workflow Field Update | Query `WorkflowFieldUpdate` WHERE `FieldDefinitionId` matches |
| Formula Field | This field IS a formula → show the formula source fields |
| Process Builder (legacy) | Metadata API query (low priority) |
| Manual / API | Always possible — note as implicit source |

### 3.2 Downstream Analysis (Who Reads)

This is what v1 already does, PLUS chaining:

1. **Level 1**: v1 dependency results (MetadataComponentDependency)
2. **Level 2**: For each Flow that reads this field, parse what that Flow writes → those are downstream fields
3. **Level 2**: For each Formula that reads this field, that formula field itself becomes a downstream node → recurse

### 3.3 Flow Metadata Deep Parsing

Critical capability: parse Flow XML to determine field-level reads and writes.

```apex
public class FlowFieldAnalysis {
    @AuraEnabled public String flowApiName;
    @AuraEnabled public String flowLabel;
    @AuraEnabled public List<String> fieldsRead;    // Fields used in conditions, formulas, get records
    @AuraEnabled public List<String> fieldsWritten;  // Fields set in assignments, record updates
    @AuraEnabled public List<String> subflowsCalled;
}
```

**Flow elements to scan:**
- `decisions` → condition formulas reference fields (READ)
- `assignments` → variable assignments from fields (READ) and to fields (WRITE)
- `recordUpdates` → field values being set (WRITE)
- `recordCreates` → field values on new records (WRITE, cross-object)
- `recordLookups` → filter criteria fields (READ), stored output fields (READ)
- `screens` → displayed fields (READ), input fields (WRITE)
- `formulas` → formula expressions reference fields (READ)

### 3.4 Data Model

```apex
public class DataJourneyNode {
    @AuraEnabled public String id;
    @AuraEnabled public String name;              // 'Account.Region__c' or 'Territory_Assignment_Flow'
    @AuraEnabled public String nodeType;           // 'field' | 'flow' | 'apex' | 'validationRule' | 'formula' | 'workflowUpdate'
    @AuraEnabled public String direction;          // 'upstream' | 'downstream' | 'root'
    @AuraEnabled public String accessType;         // 'read' | 'write' | 'readwrite'
    @AuraEnabled public Integer depth;
    @AuraEnabled public String setupUrl;
    @AuraEnabled public String detail;             // e.g., "Reads in Decision element 'Check_Region'"
}

public class DataJourneyEdge {
    @AuraEnabled public String sourceId;
    @AuraEnabled public String targetId;
    @AuraEnabled public String relationship;       // 'writes_to' | 'reads_from' | 'triggers' | 'feeds_into'
    @AuraEnabled public String detail;             // e.g., "Assignment element 'Set_Region'"
}

public class DataJourneyResponse {
    @AuraEnabled public String fieldName;
    @AuraEnabled public String objectName;
    @AuraEnabled public List<DataJourneyNode> nodes;
    @AuraEnabled public List<DataJourneyEdge> edges;
    @AuraEnabled public List<String> warnings;
    @AuraEnabled public Boolean limitReached;
}
```

### 3.5 Service Architecture

New: `DataJourneyService.cls`

```
traceDataJourney(objectName, fieldName, maxDepth=3)
  ├── traceUpstream(field)
  │   ├── findFlowWrites(field) → parse Flow XML for write operations
  │   ├── findApexWrites(field) → MetadataComponentDependency + heuristic
  │   ├── findWorkflowUpdates(field) → Metadata API
  │   └── findFormulaSource(field) → if formula, return source fields
  │
  └── traceDownstream(field)
      ├── findDirectDependents(field) → MetadataComponentDependency (v1 logic)
      ├── findFlowReads(field) → parse Flow XML for read operations
      │   └── for each Flow that reads: what does it write? → chain
      ├── findFormulaDependents(field) → which formulas use this field
      │   └── those formula fields become new downstream nodes → chain
      └── findValidationRules(field) → which VRs reference this field
```

## 4. UI Design

### Two-panel horizontal flow
```
┌────────────────────────────────────────────────────────────┐
│  Data Journey: Account.Region__c                    [Close]│
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ◀ UPSTREAM (writes)          ▶ DOWNSTREAM (reads)         │
│                                                            │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │ 🔵 Flow     │    │              │    │ 🔵 Flow       │  │
│  │ Set_Account │───→│  📍 Field    │───→│ Territory_    │  │
│  │ _Region     │    │  Account.    │    │ Assignment    │  │
│  └─────────────┘    │  Region__c   │    └──────┬────────┘  │
│                     │              │           │           │
│  ┌─────────────┐    │   (Custom    │    ┌──────▼────────┐  │
│  │ ✏️ Manual   │───→│    Picklist) │    │ 📍 Field      │  │
│  │ Entry / API │    │              │    │ Opportunity.  │  │
│  └─────────────┘    └──────────────┘    │ Territory__c  │  │
│                                         └──────┬────────┘  │
│                           ┌─────────────┐      │           │
│                           │ 🟠 VR       │◀─────┘           │
│                           │ Region_     │                  │
│                           │ Required    │                  │
│                           └─────────────┘                  │
│                                                            │
│  ┌── Detail ──────────────────────────────────────────┐    │
│  │ Set_Account_Region (Record-Triggered Flow)         │    │
│  │ Writes to: Account.Region__c                       │    │
│  │ Via: Assignment element "Assign_Region"             │    │
│  │ Source: Account.BillingCountry                      │    │
│  │ [Open in Flow Builder ↗]                           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                            │
│  [Export Journey]  [Copy as Text]                          │
└────────────────────────────────────────────────────────────┘
```

## 5. Files to Create

```
force-app/main/default/
├── classes/
│   ├── DataJourneyService.cls
│   ├── DataJourneyServiceTest.cls
│   ├── DataJourneyController.cls
│   ├── DataJourneyControllerTest.cls
│   ├── FlowFieldAnalyzer.cls          ← parses Flow XML for field-level read/write
│   └── FlowFieldAnalyzerTest.cls
└── lwc/
    └── dataJourneyView/
        ├── dataJourneyView.html
        ├── dataJourneyView.js
        ├── dataJourneyView.css
        └── dataJourneyView.js-meta.xml
```

## 6. Integration with WITU

- Accessible from `dependencyResults`: **"Trace Data Journey"** button (only for field types)
- Also accessible from `metadataPicker` directly via a toggle: "Show dependencies" vs "Trace data journey"
- Shares all auth infrastructure (Named Credential, custom permission)
- Reuses `DependencyService` for level-1 downstream (MetadataComponentDependency query)

## 7. Complexity & Phasing

This is the most complex feature. Recommended phasing within v2:

**Phase A (MVP):**
- Downstream only (reads) — essentially v1 results as a visual graph with formula chaining
- Flow field-level detection (which fields a Flow reads/writes)

**Phase B:**
- Upstream analysis (who writes to this field)
- Cross-object tracing (Flow writes to Opportunity.Field → follow that field)

**Phase C:**
- Conflict detection (same field written by multiple automations)
- Specific Flow element identification ("Decision element 'Check_Region' on line 42")

## 8. API Limits

| Constraint | Limit |
|-----------|-------|
| Flow metadata retrievals per trace | ≤ 50 |
| Chain depth | ≤ 3 levels |
| Max downstream nodes | 200 |
| Max upstream nodes | 50 |
| Apex timeout | 120s |

## 9. Known Limitations

- **Apex field detection is imprecise**: MetadataComponentDependency says "ApexClass references Account" but not which specific field. Full accuracy requires parsing Apex source code, which is brittle.
- **Dynamic references undetectable**: `sObject.get('FieldName')` in Apex, dynamic Flow formulas with `{!variable}` substitution.
- **Cross-object depth explosion**: Tracing across objects grows exponentially. Hard cap at depth 3.
- **Reports excluded**: Salesforce's API doesn't expose report field references.

## 10. Success Metrics

| Metric | Target |
|--------|--------|
| Trace render time | < 5s for depth 2 |
| Flow field accuracy | 90%+ of read/write fields correctly identified |
| User engagement | 20%+ of WITU users try Data Journey |
| Unique value | No competing free tool offers this |
