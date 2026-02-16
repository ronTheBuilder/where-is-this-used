# PRD: Process Flow Mapper — Automation Chain Visualization

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU) v2
**Status**: Draft

---

## 1. Problem Statement

Salesforce orgs accumulate layers of automation over time: Record-Triggered Flows, Before/After Triggers, Validation Rules, Workflow Rules (legacy), Assignment Rules, Auto-Response Rules, and Escalation Rules. When a record is saved, all of these fire in a specific order — but there is no single view that shows the complete automation chain for an object.

Admins and developers frequently ask:
- **"What happens when an Account is created/updated?"**
- **"In what order do all these automations fire?"**
- **"Could this trigger be conflicting with that flow?"**
- **"What's the full data journey from Lead creation to Opportunity close?"**

There is no native Salesforce tool and no free AppExchange tool that answers this.

## 2. Solution

Add a **"Process Flow Map"** tab to WITU that lets users select an object and see all automations that fire on record DML, rendered as an ordered flowchart following Salesforce's actual execution order.

### User Flow
1. User selects **"Process Flow Map"** tab in WITU
2. Selects an object (e.g., Account, Opportunity)
3. Selects trigger context: **Insert**, **Update**, **Delete**, or **All**
4. WITU queries all automations for that object
5. Renders an ordered flowchart following Salesforce execution order:

```
Record DML
  ↓
① System Validation Rules (required fields, field formats)
  ↓
② Before Triggers (Apex)
  ↓
③ Custom Validation Rules
  ↓
④ After Triggers (Apex)
  ↓
⑤ Assignment Rules
  ↓
⑥ Auto-Response Rules
  ↓
⑦ Record-Triggered Flows (before-save)
  ↓
⑧ Workflow Rules (legacy)
  ↓
⑨ Workflow Field Updates → re-evaluation loop
  ↓
⑩ Record-Triggered Flows (after-save)
  ↓
⑪ Entitlement Rules
  ↓
⑫ Record-Triggered Flows (async)
  ↓
Commit
```

## 3. Technical Architecture

### 3.1 Data Collection

New Apex service: `ProcessFlowService.cls`

Must query multiple metadata sources per object:

| Automation Type | Data Source | Method |
|----------------|------------|--------|
| Apex Triggers | `ApexTrigger` (Tooling API) | Query `TableEnumOrId`, parse `UsageBeforeInsert`, `UsageAfterInsert`, etc. |
| Validation Rules | `ValidationRule` (Tooling API) | Query by `EntityDefinitionId`, get `Active`, `ErrorConditionFormula` |
| Record-Triggered Flows | `FlowVersionView` + Flow metadata | Query where `ProcessType = 'AutoLaunchedFlow'` AND `TriggerType != null`, parse `TriggerObjectOrEvent`, `TriggerOrder` |
| Workflow Rules | `WorkflowRule` (Metadata API) | Query by object, get criteria + actions |
| Workflow Field Updates | `WorkflowFieldUpdate` (Metadata API) | Linked to WorkflowRules |
| Assignment Rules | `AssignmentRule` (Metadata API) | Object-specific |
| Auto-Response Rules | `AutoResponseRule` (Metadata API) | Object-specific |

### 3.2 Data Model

```apex
public class AutomationStep {
    @AuraEnabled public String id;
    @AuraEnabled public String name;
    @AuraEnabled public String automationType;    // 'ValidationRule', 'BeforeTrigger', 'AfterTrigger', 'Flow_BeforeSave', 'Flow_AfterSave', 'Flow_Async', 'WorkflowRule', 'WorkflowFieldUpdate', 'AssignmentRule'
    @AuraEnabled public Integer executionPhase;    // 1-12 per Salesforce order of execution
    @AuraEnabled public String phaseName;          // 'Before Triggers', 'Validation Rules', etc.
    @AuraEnabled public Boolean isActive;
    @AuraEnabled public String triggerContext;      // 'Insert', 'Update', 'Delete', 'Undelete'
    @AuraEnabled public String description;        // Short summary (formula for VR, entry criteria for WFR)
    @AuraEnabled public String setupUrl;
    @AuraEnabled public List<String> fieldsReferenced;  // Fields this automation reads
    @AuraEnabled public List<String> fieldsModified;    // Fields this automation writes (if detectable)
}

public class ProcessFlowResponse {
    @AuraEnabled public String objectName;
    @AuraEnabled public String triggerContext;
    @AuraEnabled public List<AutomationPhase> phases;
    @AuraEnabled public Integer totalAutomations;
    @AuraEnabled public List<String> warnings;
}

public class AutomationPhase {
    @AuraEnabled public Integer phaseNumber;
    @AuraEnabled public String phaseName;
    @AuraEnabled public String phaseDescription;
    @AuraEnabled public List<AutomationStep> steps;
}
```

### 3.3 Execution Order Knowledge

The service must encode Salesforce's documented order of execution:

```apex
private static final List<PhaseDefinition> EXECUTION_ORDER = new List<PhaseDefinition>{
    new PhaseDefinition(1, 'System Validations', 'Required fields, field formats, max length'),
    new PhaseDefinition(2, 'Before Triggers', 'Apex before insert/update/delete triggers'),
    new PhaseDefinition(3, 'Custom Validation Rules', 'Active validation rules on the object'),
    new PhaseDefinition(4, 'After Triggers', 'Apex after insert/update/delete triggers'),
    new PhaseDefinition(5, 'Assignment Rules', 'Lead and Case assignment rules'),
    new PhaseDefinition(6, 'Auto-Response Rules', 'Lead and Case auto-response rules'),
    new PhaseDefinition(7, 'Before-Save Flows', 'Record-triggered flows (before save)'),
    new PhaseDefinition(8, 'Workflow Rules', 'Legacy workflow rules and immediate actions'),
    new PhaseDefinition(9, 'Workflow Field Updates', 'Field updates from workflow rules (may re-trigger)'),
    new PhaseDefinition(10, 'After-Save Flows', 'Record-triggered flows (after save)'),
    new PhaseDefinition(11, 'Entitlement Rules', 'Entitlement and milestone processing'),
    new PhaseDefinition(12, 'Async Flows', 'Record-triggered flows (run asynchronously)')
};
```

### 3.4 Flow Detail Parsing

For Record-Triggered Flows, parse Flow metadata to extract:
- **Entry criteria** (filter conditions)
- **What it does** (summary of DML operations, email sends, subflow calls)
- **Trigger order** (Fast Field Updates = before-save, Actions and Related Records = after-save)

```apex
// From FlowVersionView:
// - ProcessType = 'AutoLaunchedFlow'
// - TriggerType = 'RecordBeforeSave' | 'RecordAfterSave'
// - TriggerObjectOrEvent.QualifiedApiName = 'Account'
```

### 3.5 Conflict Detection (Stretch Goal)

Analyze the automation chain for potential conflicts:
- **Field collision**: Two automations both write to the same field → last write wins, user may not realize
- **Recursion risk**: After-save flow updates record → triggers re-fire → potential infinite loop
- **Order-dependent logic**: Validation rule checks field that a before-trigger modifies → validation sees the modified value

Flag these as warnings in the UI.

## 4. UI Design

### Tab Layout
```
┌─────────────────────────────────────────────────────────┐
│  [Finder] [Process Flow Map] [Setup]                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Object: [ Account          ▼]                           │
│  Context: (●) Insert  (○) Update  (○) Delete  (○) All   │
│                                            [Analyze →]   │
│                                                          │
│  ┌── Execution Order ──────────────────────────────────┐ │
│  │                                                     │ │
│  │  ① System Validations                    [built-in] │ │
│  │  ───────────────────────────────────────────────    │ │
│  │                                                     │ │
│  │  ② Before Triggers                                  │ │
│  │     ├─ AccountTrigger.trigger          [Active] ↗   │ │
│  │     │  Before Insert, Before Update                 │ │
│  │     │  Fields: Name, Industry, BillingCity          │ │
│  │     └─ AccountValidationTrigger        [Active] ↗   │ │
│  │                                                     │ │
│  │  ③ Custom Validation Rules                          │ │
│  │     ├─ Require_Industry_For_Enterprise [Active] ↗   │ │
│  │     │  IF(Type='Enterprise' && ISBLANK(Industry))   │ │
│  │     └─ Billing_Address_Required        [Active] ↗   │ │
│  │                                                     │ │
│  │  ④ After Triggers                                   │ │
│  │     └─ AccountTrigger.trigger          [Active] ↗   │ │
│  │        After Insert, After Update                   │ │
│  │                                                     │ │
│  │  ⑤ Assignment Rules                    [none]       │ │
│  │  ───────────────────────────────────────────────    │ │
│  │                                                     │ │
│  │  ⑦ Before-Save Flows                               │ │
│  │     └─ Set_Account_Region              [Active] ↗   │ │
│  │        Trigger: Before Save (Create, Update)        │ │
│  │        Sets: Region__c based on BillingCountry      │ │
│  │                                                     │ │
│  │  ⑩ After-Save Flows                                │ │
│  │     ├─ Create_Welcome_Task             [Active] ↗   │ │
│  │     │  Trigger: After Save (Create only)            │ │
│  │     │  Creates: Task on Account Owner               │ │
│  │     └─ Sync_To_External_System         [Active] ↗   │ │
│  │        Trigger: After Save (Create, Update)         │ │
│  │        Calls: External_Sync subflow                 │ │
│  │                                                     │ │
│  │  ⚠️ Warnings                                        │ │
│  │  • Field collision: Region__c written by both       │ │
│  │    BeforeTrigger and Before-Save Flow               │ │
│  │                                                     │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  Summary: 2 triggers · 2 VRs · 3 flows · 0 workflows    │
│  [Export as PDF]  [Copy as Text]                         │ │
└─────────────────────────────────────────────────────────┘
```

## 5. Files to Create

```
force-app/main/default/
├── classes/
│   ├── ProcessFlowService.cls
│   ├── ProcessFlowServiceTest.cls
│   ├── ProcessFlowController.cls
│   └── ProcessFlowControllerTest.cls
└── lwc/
    └── processFlowMap/
        ├── processFlowMap.html
        ├── processFlowMap.js
        ├── processFlowMap.css
        └── processFlowMap.js-meta.xml
```

## 6. Integration with WITU

- New tab in `dependencyFinder`: **"Process Flow Map"**
- Reuses `metadataPicker` for object selection (object dropdown)
- Adds radio buttons for trigger context
- Shares permission gate (`WITU_Access` custom permission)
- Shares Named Credential (`WITU_ToolingAPI`)

## 7. API Limits & Safety

| Constraint | Limit |
|-----------|-------|
| Tooling API calls per analysis | ≤ 20 |
| Max flows parsed per object | 100 |
| Max validation rules | 200 |
| Max triggers | 50 |
| Apex transaction timeout | 120s |
| SOQL queries (standard) | ≤ 10 |

## 8. AppExchange Compliance

- All classes `with sharing`
- Custom permission gate on all entry points
- No external JS libraries
- Input validation on object names
- No hardcoded org-specific values
- 75%+ test coverage with callout mocks

## 9. Limitations (v1 of this feature)

- **Workflow Rules**: Requires Metadata API (REST), more complex than Tooling API. May defer to v2 of this feature.
- **Process Builder**: Deprecated — intentionally excluded.
- **Assignment/Auto-Response Rules**: Only relevant for Lead + Case. Include if Metadata API access is feasible.
- **Field-level detail for triggers**: Requires Apex source parsing, which is imprecise. Show trigger name but not field-level detail initially.
- **Conflict detection**: Stretch goal — implement basic field-collision detection first.

## 10. Success Metrics

| Metric | Target |
|--------|--------|
| Analysis render time | < 5s per object |
| Object coverage | All standard + custom objects |
| User engagement | 30%+ of WITU users try Process Flow Map |
| Accuracy | 100% match with Setup > Object Manager automation list |
