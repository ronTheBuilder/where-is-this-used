# PRD: Extended Metadata Types — Phase 2 Type Expansion

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU v1 supports 4 metadata types: Standard Fields, Custom Fields, Flows, and Apex Classes. While these cover the most common "where is this used?" scenarios, admins and developers frequently ask the same question about other metadata types that Salesforce's native UI doesn't support:

- **Record Types** — "Which Flows, page layouts, assignment rules, and Apex classes reference this record type?" Record types are heavily used in Flow decision elements and assignment rules, but there's no way to see all references at once.
- **Custom Labels** — "Where is this label referenced?" Custom labels are used across Apex, Visualforce, LWC, and Aura components. Renaming or deleting one without checking dependencies breaks translations and UI text.
- **Platform Events** — "What publishes and subscribes to this event?" Platform Events are invisible wiring — a trigger publishes, a Flow subscribes, but there's no single view showing both sides.
- **Validation Rules (reverse lookup)** — "What fields and components does THIS validation rule depend on?" The inverse of the standard query — instead of "where is field X used?", it's "what does VR Y reference?"
- **Custom Metadata Types** — "Where are records of this CMDT used?" Custom Metadata Types drive configuration across Flows, Apex, and custom settings replacements. Changing a CMDT schema can silently break consumers.

### Real-World Scenarios

| Scenario | Current Pain |
|----------|-------------|
| Admin renames a Record Type developer name | Has to manually search every Flow, layout, and Apex class to find references. Misses one → broken automation. |
| Developer deletes an unused Custom Label | No way to verify it's truly unused. Deletes it → broken Visualforce page in another language. |
| Architect reviews Platform Event usage | Must manually trace publishers (Apex triggers, Flows) and subscribers (Platform Event-triggered Flows, Apex triggers) across the org. |
| Admin modifies a Validation Rule | Doesn't know which fields the VR checks — the formula is complex and spans related objects. |
| Team deprecates a Custom Metadata Type | CMDT records are referenced in Apex constants, Flow decision elements, and custom LWC. No way to find all consumers. |

## 2. Solution

Extend WITU's metadata picker with 5 new types, each with an appropriate sub-picker and query pattern. The core architecture (DependencyService → MetadataComponentDependency → client-side filtering) remains identical — only the type registry, picker options, and query patterns expand.

### User Flow

1. User opens WITU → selects type from expanded dropdown (now 9 types)
2. Type-specific sub-picker appears:
   - **Record Type**: Object → Record Type picker
   - **Custom Label**: Searchable combobox of all Custom Labels
   - **Platform Event**: Searchable combobox filtered to `__e` objects
   - **Validation Rule**: Object → Validation Rule picker
   - **Custom Metadata Type**: Searchable combobox filtered to `__mdt` objects
3. User clicks **"Find Usages"**
4. Results appear in the same accordion format with type badges

## 3. Metadata Types to Add

### 3.1 Record Types

**Problem**: Record Types are referenced in Flow decision elements, page layout assignments, assignment rules, Apex `RecordTypeInfo` calls, and Quick Actions. Renaming or removing a Record Type without checking all references breaks automation silently.

**Tooling API type**: `RecordType`

**Component name format**: `Object.RecordTypeDeveloperName` (e.g., `Account.Enterprise`)

**Picker implementation**:
```
MetadataPickerController.getRecordTypes(String objectName)
  → Schema.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName()
  → Filter out Master record type
  → Return as List<MetadataOption> with label = RecordType.Name, value = Object.DeveloperName
```

**Query pattern**:
```sql
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       MetadataComponentNamespace, RefMetadataComponentName
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = 'RecordType'
ORDER BY MetadataComponentType, MetadataComponentName
-- Client-side filter: RefMetadataComponentName = 'Account.Enterprise'
```

**Expected dependent types**: Flow, ApexClass, ApexTrigger, Layout, QuickAction, ValidationRule

**Limitations**:
- Record Type references in report filters are not tracked (reports excluded from API)
- Record Type references via `Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()` in Apex may not always appear in dependencies (dynamic string construction)

### 3.2 Custom Labels

**Problem**: Custom Labels (`System.Label.My_Label`) are referenced across Apex classes, Visualforce pages, LWC, and Aura components. They're critical for translations. Deleting or renaming a label without checking all references breaks i18n.

**Tooling API type**: `CustomLabel`

**Component name format**: Label API name (e.g., `Error_Message_Required_Field`)

**Picker implementation**:
```
MetadataPickerController.getCustomLabels()
  → Tooling API: SELECT Id, Name, Value, Language FROM ExternalString ORDER BY Name
  → Return as List<MetadataOption> with label = Name + ' (' + truncate(Value, 50) + ')', value = Name
```

**Query pattern**:
```sql
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       MetadataComponentNamespace, RefMetadataComponentName
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = 'CustomLabel'
ORDER BY MetadataComponentType, MetadataComponentName
-- Client-side filter: RefMetadataComponentName = 'Error_Message_Required_Field'
```

**Expected dependent types**: ApexClass, ApexTrigger, AuraDefinitionBundle, LightningComponentBundle, Page (Visualforce)

**Limitations**:
- Labels referenced via `System.Label.get(namespace, name)` dynamic calls are not detectable
- Namespaced labels (from managed packages) require namespace prefix in the search

### 3.3 Platform Events

**Problem**: Platform Events (`My_Event__e`) are the pub/sub backbone of modern Salesforce orgs. A trigger publishes an event, a Platform Event-triggered Flow subscribes to it. But there's no single view showing both publishers and subscribers. Admins modifying an event schema have no way to assess impact.

**Tooling API type**: `CustomObject` (Platform Events are stored as custom objects with `__e` suffix)

**Component name format**: Event API name (e.g., `Order_Update__e`)

**Picker implementation**:
```
MetadataPickerController.getPlatformEvents()
  → Reuse getObjects() but filter where objectApiName.endsWith('__e')
  → Return as List<MetadataOption>
```

**Query pattern**:
```sql
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       MetadataComponentNamespace, RefMetadataComponentName
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = 'CustomObject'
ORDER BY MetadataComponentType, MetadataComponentName
-- Client-side filter: RefMetadataComponentName = 'Order_Update__e'
```

**Results interpretation**: Differentiate publishers vs. subscribers in the UI:
- **Publishers**: ApexClass/ApexTrigger that reference the event (likely `EventBus.publish()`)
- **Subscribers**: Flow (Platform Event-triggered), ApexTrigger on the event object
- Badge: `[Publisher]` or `[Subscriber]` based on heuristic (triggers on the event object = subscriber, other Apex = publisher)

**Limitations**:
- Cannot distinguish publisher vs. subscriber with 100% accuracy from MetadataComponentDependency alone — the relationship type is "reference" not "publish" or "subscribe"
- CDC (Change Data Capture) events are not queryable this way

### 3.4 Validation Rules (Reverse Lookup)

**Problem**: Standard WITU query answers "where is Field X used?" — but admins also need the inverse for Validation Rules: "What does this VR depend on?" This is critical when a VR is causing save errors and the admin needs to understand all the fields and components the VR references.

**Tooling API type**: `ValidationRule`

**Component name format**: `Object.ValidationRuleDeveloperName` (e.g., `Account.Require_Industry`)

**Picker implementation**:
```
MetadataPickerController.getValidationRules(String objectName)
  → Tooling API: SELECT Id, ValidationName, Active, EntityDefinition.QualifiedApiName
    FROM ValidationRule
    WHERE EntityDefinition.QualifiedApiName = :objectName
    ORDER BY ValidationName
  → Return as List<MetadataOption> with label = ValidationName + (Active ? ' [Active]' : ' [Inactive]'),
    value = Object.ValidationName
```

**Query pattern** (REVERSE — VR is the MetadataComponent, not the Ref):
```sql
SELECT RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType,
       RefMetadataComponentNamespace
FROM MetadataComponentDependency
WHERE MetadataComponentType = 'ValidationRule'
ORDER BY RefMetadataComponentType, RefMetadataComponentName
-- Client-side filter: MetadataComponentName = 'Account.Require_Industry'
```

**Note**: This is a fundamentally different query direction. Instead of "who references X?", it's "what does X reference?" This requires a new method in DependencyService: `searchReverseDependencies()`.

**Expected referenced types**: CustomField, StandardEntity (fields the VR formula checks)

**Limitations**:
- The reverse query may return a large number of field references for complex VR formulas
- Cross-object formula references (e.g., `Account.Owner.Profile.Name`) may appear as a single reference to the related object rather than the specific field path

### 3.5 Custom Metadata Types

**Problem**: Custom Metadata Types (`My_Config__mdt`) are used to drive configuration in Apex, Flows, and LWC. They replace custom settings for deployable config. Changing a CMDT's schema (adding/removing fields) can break all consumers silently.

**Tooling API type**: `CustomObject` (CMDTs are stored as custom objects with `__mdt` suffix)

**Component name format**: CMDT API name (e.g., `Routing_Config__mdt`)

**Picker implementation**:
```
MetadataPickerController.getCustomMetadataTypes()
  → Reuse getObjects() but filter where objectApiName.endsWith('__mdt')
  → Return as List<MetadataOption>
```

**Query pattern**:
```sql
SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType,
       MetadataComponentNamespace, RefMetadataComponentName
FROM MetadataComponentDependency
WHERE RefMetadataComponentType = 'CustomObject'
ORDER BY MetadataComponentType, MetadataComponentName
-- Client-side filter: RefMetadataComponentName = 'Routing_Config__mdt'
```

**Expected dependent types**: ApexClass, Flow, LightningComponentBundle, AuraDefinitionBundle

**Limitations**:
- References to individual CMDT records (e.g., `Routing_Config__mdt.Default_Route`) are harder to track — the dependency is on the object type, not specific records
- SOQL queries like `SELECT ... FROM Routing_Config__mdt` in Apex appear as references to the CMDT object, but don't indicate which fields are read

## 4. Technical Architecture

### 4.1 Type Registry Extension

Extend the type map in `DependencyService.cls`:

```apex
// Current (v1):
private static final Map<String, String> TYPE_MAP = new Map<String, String>{
    'Standard Field' => 'StandardEntity',
    'Custom Field'   => 'CustomField',
    'Flow'           => 'Flow',
    'Apex Class'     => 'ApexClass'
};

// Extended (v1.1):
private static final Map<String, String> TYPE_MAP = new Map<String, String>{
    'Standard Field'       => 'StandardEntity',
    'Custom Field'         => 'CustomField',
    'Flow'                 => 'Flow',
    'Apex Class'           => 'ApexClass',
    'Record Type'          => 'RecordType',
    'Custom Label'         => 'CustomLabel',
    'Platform Event'       => 'CustomObject',
    'Validation Rule'      => 'ValidationRule',
    'Custom Metadata Type' => 'CustomObject'
};
```

Update `getSupportedMetadataTypes()` to return all 9 types.

### 4.2 Picker Extensions

New methods in `MetadataPickerController.cls`:

```apex
@AuraEnabled(cacheable=true)
public static List<MetadataOption> getRecordTypes(String objectName) {
    // Schema.SObjectType describe → getRecordTypeInfosByDeveloperName()
    // Filter out Master, return Object.DeveloperName format
}

@AuraEnabled(cacheable=true)
public static List<MetadataOption> getCustomLabels() {
    // Tooling API: SELECT Name, Value FROM ExternalString ORDER BY Name
    // Requires callout → delegates to DependencyService.getCustomLabels()
}

@AuraEnabled(cacheable=true)
public static List<MetadataOption> getValidationRules(String objectName) {
    // Tooling API: SELECT ValidationName, Active FROM ValidationRule
    //   WHERE EntityDefinition.QualifiedApiName = :objectName
    // Requires callout → delegates to DependencyService.getValidationRules()
}

@AuraEnabled(cacheable=true)
public static List<MetadataOption> getPlatformEvents() {
    // Reuse getObjects() filtered to __e suffix
}

@AuraEnabled(cacheable=true)
public static List<MetadataOption> getCustomMetadataTypes() {
    // Reuse getObjects() filtered to __mdt suffix
}
```

### 4.3 Query Patterns per Type

| Type | RefMetadataComponentType | Query Direction | Client-Side Filter Field |
|------|--------------------------|----------------|--------------------------|
| Standard Field | `StandardEntity` | Standard (who refs me?) | `RefMetadataComponentName` |
| Custom Field | `CustomField` | Standard | `RefMetadataComponentName` |
| Flow | `Flow` | Standard | `RefMetadataComponentName` |
| Apex Class | `ApexClass` | Standard | `RefMetadataComponentName` |
| Record Type | `RecordType` | Standard | `RefMetadataComponentName` |
| Custom Label | `CustomLabel` | Standard | `RefMetadataComponentName` |
| Platform Event | `CustomObject` | Standard | `RefMetadataComponentName` |
| Validation Rule | `ValidationRule` | **Reverse** (what do I ref?) | `MetadataComponentName` |
| Custom Metadata Type | `CustomObject` | Standard | `RefMetadataComponentName` |

### 4.4 Reverse Query Mode

New method in `DependencyService.cls` for Validation Rule reverse lookup:

```apex
public static DependencySearchResponse searchReverseDependencies(
    String metadataType, String componentName
) {
    enforceAccess();
    validateInputs(metadataType, componentName);

    String toolingType = TYPE_MAP.get(metadataType);
    String soql =
        'SELECT RefMetadataComponentId, RefMetadataComponentName, ' +
        'RefMetadataComponentType, RefMetadataComponentNamespace, MetadataComponentName ' +
        'FROM MetadataComponentDependency ' +
        'WHERE MetadataComponentType = \'' + String.escapeSingleQuotes(toolingType) + '\' ' +
        'ORDER BY RefMetadataComponentType, RefMetadataComponentName';

    // Client-side filter on MetadataComponentName = componentName
    // Parse results into DependencyRecord list (swap Ref ↔ Component fields)
}
```

### 4.5 Shared Type Disambiguation

Platform Events and Custom Metadata Types both map to `CustomObject` in the Tooling API. The client-side filter on component name (ending in `__e` or `__mdt`) handles disambiguation. No special logic needed in DependencyService — the name suffix is the differentiator.

### 4.6 LWC Picker Changes

The `metadataPicker` LWC needs new conditional sub-pickers:

```javascript
// Existing sub-pickers:
// 'Standard Field' / 'Custom Field' → Object dropdown → Field dropdown
// 'Flow'        → Flow combobox (searchable)
// 'Apex Class'  → Apex class combobox (searchable)

// New sub-pickers:
// 'Record Type'          → Object dropdown → Record Type dropdown
// 'Custom Label'         → Custom Label combobox (searchable)
// 'Platform Event'       → Platform Event combobox (searchable)
// 'Validation Rule'      → Object dropdown → Validation Rule dropdown
// 'Custom Metadata Type' → CMDT combobox (searchable)
```

## 5. UI Design

### Extended Type Dropdown

```
┌──────────────────────────────────────────────────────────┐
│  1. Select Type                    2. Select Item        │
│  ┌────────────────────────┐       ┌───────────────────┐  │
│  │ ▼ Standard Field       │       │ (type-specific    │  │
│  │   Custom Field         │       │  sub-picker here) │  │
│  │   Flow                 │       │                   │  │
│  │   Apex Class           │       │                   │  │
│  │ ─────────────────────  │       │   [Find Usages]   │  │
│  │   Record Type      NEW │       │                   │  │
│  │   Custom Label     NEW │       └───────────────────┘  │
│  │   Platform Event   NEW │                              │
│  │   Validation Rule  NEW │                              │
│  │   Custom Metadata  NEW │                              │
│  └────────────────────────┘                              │
└──────────────────────────────────────────────────────────┘
```

### Record Type Sub-Picker

```
┌──────────────────────────────────────────────────────────┐
│  Type: Record Type                                       │
│                                                          │
│  Object: [ Account              ▼]                       │
│  Record Type: [ Enterprise      ▼]                       │
│                                                          │
│  Searching for: Account.Enterprise                       │
│                                           [Find Usages]  │
└──────────────────────────────────────────────────────────┘
```

### Validation Rule Sub-Picker (Reverse)

```
┌──────────────────────────────────────────────────────────┐
│  Type: Validation Rule                                   │
│                                                          │
│  Object: [ Account              ▼]                       │
│  Rule:   [ Require_Industry [Active]  ▼]                 │
│                                                          │
│  ℹ Shows what this validation rule references            │
│  (fields, objects, and components it depends on)         │
│                                           [Find Usages]  │
└──────────────────────────────────────────────────────────┘
```

### Results Example — Record Type

```
┌─────────────────────────────────────────────────────────┐
│  Where is Account.Enterprise used?     [Record Type]     │
│                                                          │
│  8 references found                                      │
│  [Flow: 3] [Layout: 2] [ApexClass: 2] [QuickAction: 1] │
│                                                          │
│  ▼ Flow (3)                                              │
│    ⚡ Account_Onboarding_Flow              [Decision] ↗  │
│    ⚡ Lead_Conversion_Flow                 [Decision] ↗  │
│    ⚡ Account_Assignment_Flow              [Decision] ↗  │
│                                                          │
│  ▶ Layout (2)                                            │
│  ▶ ApexClass (2)                                         │
│  ▶ QuickAction (1)                                       │
└─────────────────────────────────────────────────────────┘
```

### Results Example — Validation Rule (Reverse)

```
┌─────────────────────────────────────────────────────────┐
│  What does Account.Require_Industry reference?           │
│  [Validation Rule — Reverse Lookup]                      │
│                                                          │
│  5 components referenced                                 │
│  [StandardEntity: 3] [CustomField: 2]                    │
│                                                          │
│  ▼ StandardEntity (3)                                    │
│    📍 Account.Industry                              ↗    │
│    📍 Account.Type                                  ↗    │
│    📍 Account.RecordTypeId                          ↗    │
│                                                          │
│  ▼ CustomField (2)                                       │
│    📍 Account.Region__c                             ↗    │
│    📍 Account.Tier__c                               ↗    │
└─────────────────────────────────────────────────────────┘
```

## 6. Files to Modify / Create

### Modified Files

| File | Changes |
|------|---------|
| `DependencyService.cls` | Add 5 entries to `TYPE_MAP`. Add `searchReverseDependencies()` method. Add `getCustomLabels()` and `getValidationRules()` methods. |
| `DependencyServiceTest.cls` | Add test methods for new types and reverse query. |
| `DependencyController.cls` | Add `searchReverseDependencies()` @AuraEnabled method. |
| `DependencyControllerTest.cls` | Add test for reverse search. |
| `MetadataPickerController.cls` | Add `getRecordTypes()`, `getCustomLabels()`, `getValidationRules()`, `getPlatformEvents()`, `getCustomMetadataTypes()` methods. |
| `MetadataPickerControllerTest.cls` | Add tests for all 5 new picker methods. |
| `metadataPicker` LWC (html/js) | Add 5 new conditional sub-picker sections. Add imports for new Apex methods. |
| `dependencyResults` LWC (html/js) | Add "Reverse Lookup" badge for VR results. Adjust heading text for reverse mode. |
| `dependencyFinder` LWC (js) | Pass `isReverse` flag when type is Validation Rule. |

### No New Files Required

All changes extend existing files. No new Apex classes or LWC components needed.

## 7. Integration with Existing Features

| Feature | Integration |
|---------|-------------|
| **Blast Radius** | All 5 new types work with Blast Radius. User can click "Show Blast Radius" on any result. For VR reverse results, blast radius shows the VR's downstream dependents (standard direction). |
| **Data Journey** | Record Type and Custom Label types don't apply (not field-level). Platform Event, VR, and CMDT types are excluded from Data Journey (field-level only). |
| **Process Flow Map** | No integration needed. Process Flow Map is object-scoped, not component-scoped. |
| **BlastRadiusService** | Needs `normalizeTypeForRoot()` updated to include new type mappings. |

## 8. AppExchange Considerations

- All new picker methods use `with sharing` and respect FLS (Schema.describe checks)
- Custom Label and Validation Rule pickers require Tooling API callout → must go through DependencyService (not direct callout from MetadataPickerController)
- No new external libraries
- `getRecordTypes()` uses Schema.describe → no callout, can be `cacheable=true`
- `getPlatformEvents()` and `getCustomMetadataTypes()` reuse `getObjects()` → no callout, `cacheable=true`
- New test methods must achieve 75%+ coverage for modified classes

## 9. API Coverage per Type

| New Type | MetadataComponentDependency Coverage | Notes |
|----------|-------------------------------------|-------|
| Record Type | Good — tracked as `RecordType` references | May miss dynamic `getRecordTypeInfos()` calls |
| Custom Label | Good — tracked as `CustomLabel` references | May miss `System.Label.get()` dynamic calls |
| Platform Event | Good — tracked as `CustomObject` references | Cannot distinguish publish vs. subscribe |
| Validation Rule | Good for reverse — VR tracked as `MetadataComponentType = 'ValidationRule'` | Formula field references well-tracked |
| Custom Metadata Type | Partial — tracked as `CustomObject` references | References to individual CMDT records not tracked |

## 10. Known Limitations

| Type | Limitation |
|------|-----------|
| Record Type | Dynamic `RecordTypeInfo` lookups via developer name strings in Apex not always detected |
| Custom Label | `$Label.namespace__LabelName` in Visualforce may need namespace handling |
| Platform Event | Pub/sub direction is heuristic, not definitive |
| Platform Event | Shares `CustomObject` type with Custom Objects, Custom Metadata Types — relies on `__e` suffix for disambiguation |
| Validation Rule | Reverse query scans ALL VR dependencies then filters client-side — may be slow for orgs with thousands of VRs |
| Custom Metadata Type | Shares `CustomObject` type — relies on `__mdt` suffix for disambiguation |
| Custom Metadata Type | Individual record references (e.g., `Routing_Config__mdt.Default`) not tracked |
| All new types | Report references remain excluded (API blind spot) |

## 11. Phasing Recommendation

### Wave 1 (build first — high value, low complexity)

| Type | Rationale |
|------|-----------|
| **Record Type** | High demand. Simple picker (Schema.describe). Standard query pattern. |
| **Custom Label** | High demand. Simple query. Only needs a Tooling API picker for ExternalString. |

### Wave 2 (build second — medium complexity)

| Type | Rationale |
|------|-----------|
| **Platform Event** | Medium demand. Simple query but needs pub/sub badge heuristic. |
| **Custom Metadata Type** | Medium demand. Simple query (reuse getObjects filter). |

### Wave 3 (build third — different query pattern)

| Type | Rationale |
|------|-----------|
| **Validation Rule** | Reverse query direction requires new `searchReverseDependencies()` method. Different UX (shows references, not dependents). |

## 12. Success Metrics

| Metric | Target |
|--------|--------|
| Type coverage | 9 types supported (up from 4) |
| Picker load time | < 2s for all new sub-pickers |
| Query accuracy | 95%+ match with manual Setup review |
| User adoption | 25%+ of WITU users try at least one new type within 30 days |
| AppExchange review | Pass on first submission |
| Test coverage | 75%+ on all modified/new methods |
| Record Type usage | Most-used new type (based on admin demand) |
