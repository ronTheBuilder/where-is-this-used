# PRD: Bulk Analysis & Org Hygiene — Batch Dependency Analysis and Unused Metadata Detection

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU v1 is designed for **one-off queries**: "Where is this field used?" But admins and architects often need **org-wide analysis**:

- **Bulk field analysis** — "Show me dependencies for ALL fields on the Account object" (20+ fields, 200+ dependencies total). Running 20 separate searches is tedious.
- **Unused metadata detection** — "Which Flows, Apex classes, and Validation Rules are never referenced? They're cluttering Setup." No way to identify candidates for deletion.
- **Object health report** — "Give me a summary for every object: # of fields, # of direct dependencies, # of automation pieces (Flows, VRs, triggers)."
- **Dependency coverage** — "What percentage of our org's components have zero dependencies? Those might be test/abandoned code."

### Real-World Scenarios

| Scenario | Current Pain |
|----------|-------------|
| Org cleanup before release | Admin manually searches ~50 Flows to find unused ones. Finds 3 candidates but isn't confident — no way to prove they're not used. |
| Data model refactor | Architect needs to understand all fields on Account + their dependencies to plan schema changes. Searches 30 fields individually over 2 hours. |
| Security audit | Team needs to list all Apex classes that have zero external references → candidates for review (internal-only). Must manually build this list. |
| Performance investigation | "Which are the most-used fields?" Admin needs to rank fields by # of references to focus optimization efforts. |

## 2. Solution

Two complementary tools:

### 2.1 Bulk Dependency Analysis

Run dependency query for multiple components at once. Input: list of field names or objects. Output: Unified dependency report showing all dependencies across all input components.

**Modes**:
- **By object** — Analyze all fields on an object (Account, Opportunity, etc.)
- **By component list** — User provides 5 Flow names, get dependencies for all 5
- **By type** — Analyze all Apex classes, or all active Flows

### 2.2 Unused Metadata Detector

Inverse query: "What components have zero dependencies?" Identifies Flows, Apex classes, Validation Rules, Custom Labels, etc., that are never referenced.

**Output**:
- Unused Flows list with last modified date (admin must manually verify active/inactive status)
- Unused Apex classes (same caveats)
- Unused Custom Labels
- Unused Validation Rules

## 3. Technical Architecture

### 3.1 Bulk Dependency Analysis

**New Controller Method**:

```apex
@AuraEnabled
public static BulkDependencyResponse analyzeBulkDependencies(
    String analysisMode,       // 'object', 'componentList', 'byType'
    String objectName,          // 'Account' (for object mode)
    List<String> componentNames, // List of flow names, apex classes, etc.
    String componentType        // 'Flow', 'ApexClass' (for byType mode)
) {
    enforceAccess();

    List<String> targetComponents = new List<String>();

    if (analysisMode == 'object') {
        // Get all fields on the object
        targetComponents = MetadataPickerController.getFields(objectName);
    } else if (analysisMode == 'componentList') {
        targetComponents = componentNames;
    } else if (analysisMode == 'byType') {
        targetComponents = getComponentsByType(componentType);
    }

    // Run parallel queries where possible, cap at 25 components (governor limit)
    List<String> toAnalyze = targetComponents.sublist(0, Math.min(25, targetComponents.size()));

    BulkDependencyResponse response = new BulkDependencyResponse();
    response.totalComponentsRequested = targetComponents.size();
    response.totalComponentsAnalyzed = toAnalyze.size();
    response.allDependencies = new List<DependencyRecord>();
    response.dependencySummary = new Map<String, Integer>();

    for (String component : toAnalyze) {
        DependencyService.DependencySearchResponse singleResult =
            DependencyService.searchDependencies(componentType, component);

        if (singleResult != null && singleResult.dependencies != null) {
            response.allDependencies.addAll(singleResult.dependencies);

            for (DependencyRecord dep : singleResult.dependencies) {
                String key = dep.metadataComponentType;
                response.dependencySummary.put(
                    key,
                    response.dependencySummary.containsKey(key) ?
                    response.dependencySummary.get(key) + 1 : 1
                );
            }
        }
    }

    // Aggregate and deduplicate
    Map<String, DependencyRecord> uniqueDeps = new Map<String, DependencyRecord>();
    for (DependencyRecord dep : response.allDependencies) {
        String key = dep.metadataComponentType + ':' + dep.metadataComponentName;
        if (!uniqueDeps.containsKey(key)) {
            uniqueDeps.put(key, dep);
        }
    }

    response.uniqueDependencies = new List<DependencyRecord>(uniqueDeps.values());
    response.totalUniqueDependencies = uniqueDeps.size();

    return response;
}

public class BulkDependencyResponse {
    @AuraEnabled public Integer totalComponentsRequested;
    @AuraEnabled public Integer totalComponentsAnalyzed;
    @AuraEnabled public Integer totalUniqueDependencies;
    @AuraEnabled public List<DependencyRecord> allDependencies;
    @AuraEnabled public List<DependencyRecord> uniqueDependencies;
    @AuraEnabled public Map<String, Integer> dependencySummary;
    @AuraEnabled public List<String> warnings;
}
```

**UI Flow**:
1. Admin selects "Bulk Analysis" tab
2. Chooses mode: "All fields on object", "Custom list", or "By type"
3. For "All fields on object": selects object (Account, Opportunity)
4. System runs analysis (may take 30-60 seconds for 20+ components)
5. Results show:
   - Total dependencies found: 127
   - Breakdown by type: [Flows: 45] [Apex: 32] [VRs: 28] [Layouts: 22]
   - Unique components: 98 (some appear multiple times)
   - Full dependency list with export options (CSV, Markdown, etc.)

### 3.2 Unused Metadata Detector

**Approach 1: Inverse Query**

Query `MetadataComponentDependency` to find all components that appear as `MetadataComponentId/Name` but NOT as `RefMetadataComponentId/Name`. Those are unused.

**Data model**:
```apex
public class UnusedMetadataAnalysis {
    @AuraEnabled public String componentName;
    @AuraEnabled public String componentType;      // 'Flow', 'ApexClass', etc.
    @AuraEnabled public String componentId;
    @AuraEnabled public Boolean isActive;           // For Flows, VRs
    @AuraEnabled public DateTime lastModifiedDate;
    @AuraEnabled public String lastModifiedBy;
    @AuraEnabled public Integer referenceCount;     // Should be 0
    @AuraEnabled public String setupUrl;
}

public class UnusedMetadataResponse {
    @AuraEnabled public List<UnusedMetadataAnalysis> unusedFlows;
    @AuraEnabled public List<UnusedMetadataAnalysis> unusedApexClasses;
    @AuraEnabled public List<UnusedMetadataAnalysis> unusedValidationRules;
    @AuraEnabled public List<UnusedMetadataAnalysis> unusedCustomLabels;
    @AuraEnabled public List<UnusedMetadataAnalysis> unusedCustomObjects;
    @AuraEnabled public String analysisDate;
    @AuraEnabled public String warningMessage;
}
```

**Algorithm**:

```apex
public static UnusedMetadataResponse findUnusedMetadata() {
    enforceAccess();

    UnusedMetadataResponse response = new UnusedMetadataResponse();
    response.unusedFlows = new List<UnusedMetadataAnalysis>();
    response.unusedApexClasses = new List<UnusedMetadataAnalysis>();
    response.unusedValidationRules = new List<UnusedMetadataAnalysis>();
    response.unusedCustomLabels = new List<UnusedMetadataAnalysis>();
    response.unusedCustomObjects = new List<UnusedMetadataAnalysis>();

    // Query all referenced components (components that ARE used)
    Set<String> usedComponents = new Set<String>();
    String referencedQuery =
        'SELECT DISTINCT MetadataComponentName, MetadataComponentType ' +
        'FROM MetadataComponentDependency';
    ToolingQueryResponse referencedResults = queryToolingRecords(referencedQuery);
    for (Object rec : referencedResults.records) {
        Map<String, Object> row = (Map<String, Object>) rec;
        String key = row.get('MetadataComponentType') + ':' + row.get('MetadataComponentName');
        usedComponents.add(key);
    }

    // Query all Flows
    String flowQuery = 'SELECT Id, ApiName, Label, Status, LastModifiedDate, LastModifiedById ' +
                       'FROM FlowDefinitionView ORDER BY ApiName';
    ToolingQueryResponse flowResults = queryToolingRecords(flowQuery);
    for (Object rec : flowResults.records) {
        Map<String, Object> row = (Map<String, Object>) rec;
        String flowName = (String) row.get('ApiName');
        String key = 'Flow:' + flowName;
        if (!usedComponents.contains(key)) {
            UnusedMetadataAnalysis unused = new UnusedMetadataAnalysis();
            unused.componentName = flowName;
            unused.componentType = 'Flow';
            unused.componentId = (String) row.get('Id');
            unused.isActive = (String) row.get('Status') == 'Active';
            unused.lastModifiedDate = (DateTime) row.get('LastModifiedDate');
            unused.setupUrl = SetupUrlResolver.resolve('Flow', unused.componentId, flowName);
            response.unusedFlows.add(unused);
        }
    }

    // Query all Apex classes
    String apexQuery = 'SELECT Id, Name, LastModifiedDate, LastModifiedById ' +
                       'FROM ApexClass ORDER BY Name';
    ToolingQueryResponse apexResults = queryToolingRecords(apexQuery);
    for (Object rec : apexResults.records) {
        Map<String, Object> row = (Map<String, Object>) rec;
        String className = (String) row.get('Name');
        String key = 'ApexClass:' + className;
        if (!usedComponents.contains(key)) {
            UnusedMetadataAnalysis unused = new UnusedMetadataAnalysis();
            unused.componentName = className;
            unused.componentType = 'ApexClass';
            unused.componentId = (String) row.get('Id');
            unused.lastModifiedDate = (DateTime) row.get('LastModifiedDate');
            unused.setupUrl = SetupUrlResolver.resolve('ApexClass', unused.componentId, className);
            response.unusedApexClasses.add(unused);
        }
    }

    // Repeat for Validation Rules, Custom Labels, etc.

    response.analysisDate = DateTime.now().format();
    response.warningMessage = 'Note: Unused metadata detection is approximate. ' +
        'Components may be used via dynamic references (Apex strings, etc.) that are not tracked in MetadataComponentDependency.';

    return response;
}
```

**Limitations**:
- Reports (excluded from MetadataComponentDependency) won't be found as "unused" even if unused
- Dynamic Apex references not tracked (e.g., `Type.forName('MyClass')`)
- Components used by managed package dependencies may not appear as used in the host org

### 3.3 Object Health Report

Combines all data into a summary for admins:

```apex
public class ObjectHealthReport {
    @AuraEnabled public String objectName;
    @AuraEnabled public Integer totalFields;           // standard + custom
    @AuraEnabled public Integer standardFields;
    @AuraEnabled public Integer customFields;
    @AuraEnabled public Integer fieldsWithDependencies;
    @AuraEnabled public Decimal dependencyCoverage;    // % of fields with at least 1 dependency
    @AuraEnabled public Integer totalDependencies;
    @AuraEnabled public Map<String, Integer> dependenciesByType;
    @AuraEnabled public Integer automationCount;       // Flows + Triggers + VRs on this object
    @AuraEnabled public Integer flowCount;
    @AuraEnabled public Integer triggerCount;
    @AuraEnabled public Integer validationRuleCount;
    @AuraEnabled public String riskAssessment;         // 'Low', 'Medium', 'High'
}

@AuraEnabled
public static List<ObjectHealthReport> getOrgHealthReport() {
    enforceAccess();

    List<ObjectHealthReport> reports = new List<ObjectHealthReport>();

    // Iterate all objects in org
    for (String objectName : Schema.getGlobalDescribe().keySet()) {
        Schema.DescribeSObjectResult objDesc = Schema.getGlobalDescribe().get(objectName).getDescribe();
        if (!objDesc.isAccessible() || objDesc.isCustomSetting()) {
            continue;
        }

        ObjectHealthReport report = new ObjectHealthReport();
        report.objectName = objDesc.getLabel();

        // Field counts
        Map<String, Schema.SObjectField> fields = objDesc.fields.getMap();
        report.totalFields = fields.size();
        report.customFields = countCustomFields(fields);
        report.standardFields = report.totalFields - report.customFields;

        // Dependencies
        report.dependenciesByType = new Map<String, Integer>();
        Integer fieldsWithDeps = 0;
        for (Schema.SObjectField field : fields.values()) {
            String fieldName = field.getDescribe().getName();
            String fullName = objectName + '.' + fieldName;

            // Check if this field has dependencies
            if (hasDependencies(fullName)) {
                fieldsWithDeps++;
                // Count by type
            }
        }
        report.fieldsWithDependencies = fieldsWithDeps;
        report.dependencyCoverage = (fieldsWithDeps / report.totalFields) * 100;

        // Automation
        report.flowCount = countFlowsOnObject(objectName);
        report.triggerCount = countTriggersOnObject(objectName);
        report.validationRuleCount = countValidationRulesOnObject(objectName);
        report.automationCount = report.flowCount + report.triggerCount + report.validationRuleCount;

        // Risk assessment
        if (report.automationCount > 10 || report.dependencyCoverage > 80) {
            report.riskAssessment = 'High';
        } else if (report.automationCount > 5 || report.dependencyCoverage > 50) {
            report.riskAssessment = 'Medium';
        } else {
            report.riskAssessment = 'Low';
        }

        reports.add(report);
    }

    return reports;
}
```

**UI Display**:
```
Object Health Report — All Objects

[Search] [Export to CSV]

┌─────────────────────────────────────────────────────────────────────┐
│ Object | Fields | W/ Deps | Coverage | Automation | Risk            │
├─────────────────────────────────────────────────────────────────────┤
│ Account | 45 | 38 | 84% | 12 (5 flows, 2 triggers, 5 VRs) | High │
│ Contact | 28 | 15 | 54% | 4 (1 flow, 2 VRs, 1 trigger) | Medium │
│ Opportunity | 52 | 42 | 81% | 9 (3 flows, 2 triggers, 4 VRs) | High │
│ Lead | 18 | 8 | 44% | 2 (1 flow, 1 VR) | Low │
│ Custom_Object__c | 15 | 3 | 20% | 0 | Low │
└─────────────────────────────────────────────────────────────────────┘

High-Risk Objects (>10 automation or >80% field coverage):
• Account — consider refactoring
• Opportunity — audit field changes carefully
```

## 4. API Budget

| Operation | API Calls |
|-----------|-----------|
| Bulk analysis (20 fields) | 20 calls (1 per field) |
| Unused metadata detection | 5 calls (1 per metadata type) |
| Object health report (org-wide) | 10 calls (1 per 30 objects, with batching) |

**Governor limits**: All bulk operations are O(n) where n = # of components. Max 100 API calls per transaction; bulk analysis capped at 25 components per invocation. If org has 100+ flows to analyze, user must run 4 separate queries.

## 5. UI Design

### Bulk Analysis Tab

```
┌─────────────────────────────────────────────────────────────────┐
│  Bulk Analysis                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Analysis Mode:                                                 │
│  ⦿ All fields on an object                                      │
│  ○ Custom component list                                        │
│  ○ By type (all Flows, all Apex classes, etc.)                  │
│                                                                 │
│  [For "All fields on object" mode:]                             │
│  Object: [ Account                        ▼]                    │
│                                           [Analyze]             │
│                                                                 │
│  Results (Account — 20 fields analyzed):                        │
│  ────────────────────────────────────────                       │
│                                                                 │
│  Total dependencies found: 127                                  │
│  Unique components referenced: 98                               │
│  Average dependencies per field: 6.4                            │
│                                                                 │
│  Breakdown by component type:                                   │
│  [Flows: 45] [ApexClass: 32] [VR: 28] [Layout: 22]            │
│                                                                 │
│  [Export as CSV] [Copy as Markdown] [Copy as Mermaid]          │
│                                                                 │
│  ▼ Detailed Results (127 dependencies)                          │
│    (accordion showing all dependencies with standard UI)        │
└─────────────────────────────────────────────────────────────────┘
```

### Unused Metadata Tab

```
┌─────────────────────────────────────────────────────────────────┐
│  Org Hygiene — Unused Metadata                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Analysis Date: 2026-02-17 @ 15:30 UTC                          │
│  [Re-run Analysis]                                              │
│                                                                 │
│  ⚠ WARNING: Detection is approximate. Unused metadata may have   │
│  dynamic/runtime references not tracked in MetadataComponentDep.│
│                                                                 │
│  Candidates for Deletion:                                       │
│  ────────────────────────                                       │
│                                                                 │
│  ▼ Unused Flows (12)       [Export] [Export for review]         │
│                                                                 │
│    Old_Account_Import_Flow [Inactive]  Last Modified: 6mo ago   │
│    ├─ Status: [Inactive]                                        │
│    ├─ Last Modified: 2025-08-17                                 │
│    └─ Setup: [Open in Setup]                                    │
│                                                                 │
│    Test_Lead_Assignment_v3 [Active]  Last Modified: 1mo ago     │
│    └─ ⚠ Note: This is Active — verify before deleting           │
│                                                                 │
│  ▼ Unused Apex Classes (8)                                      │
│                                                                 │
│  ▼ Unused Validation Rules (3)                                  │
│                                                                 │
│  ▼ Unused Custom Labels (5)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Object Health Report Tab

```
┌─────────────────────────────────────────────────────────────────┐
│  Object Health Report                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Risk Level Filter: [All] [Low] [Medium] [High]                 │
│  [Export Report]                                                │
│                                                                 │
│  ▼ High-Risk Objects (3):                                       │
│                                                                 │
│  Account                                                        │
│  ├─ 45 Fields (38 std, 7 custom)                                │
│  ├─ 38 fields have dependencies (84% coverage)                  │
│  ├─ 12 automation pieces (5 flows, 2 triggers, 5 VRs)           │
│  ├─ Risk: HIGH                                                  │
│  └─ [View Field Dependencies] [View Automation]                 │
│                                                                 │
│  Opportunity                                                    │
│  ├─ 52 Fields (40 std, 12 custom)                               │
│  ├─ 42 fields have dependencies (81% coverage)                  │
│  ├─ 9 automation pieces (3 flows, 2 triggers, 4 VRs)            │
│  ├─ Risk: HIGH                                                  │
│  └─ [View Field Dependencies] [View Automation]                 │
│                                                                 │
│  ▼ Medium-Risk Objects (8):                                     │
│                                                                 │
│  ▼ Low-Risk Objects (18):                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 6. Files to Create / Modify

### New Files

| File | Purpose |
|------|---------|
| `classes/BulkAnalysisController.cls` | Handle bulk dependency queries and object health reports |
| `classes/BulkAnalysisControllerTest.cls` | Tests for bulk analysis |
| `classes/UnusedMetadataDetector.cls` | Find unused components via inverse query |
| `classes/UnusedMetadataDetectorTest.cls` | Tests for unused metadata detection |
| `lwc/bulkAnalysisView/` | LWC component for bulk analysis UI |
| `lwc/unusedMetadataView/` | LWC component for unused metadata UI |
| `lwc/objectHealthReport/` | LWC component for object health report |

### Modified Files

| File | Change |
|------|--------|
| `dependencyFinder` LWC | Add "Bulk Analysis" and "Org Hygiene" tabs alongside existing finder/setup/blastRadius tabs |

## 7. Performance Considerations

- **Bulk analysis** capped at 25 components per request (API governor limit)
- **Unused metadata detection** queries all orgs' Flows/Classes/VRs — may be slow for 1000+ Flows
- **Object health report** batches queries to stay within limits
- Results cached with session cache (reuse bulk analysis results if re-run same day)

## 8. Known Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| Reports excluded from MetadataComponentDependency | "Unused" detection can't find unused reports | Warn user in UI |
| Dynamic references not tracked | Some used components may appear unused | Disclaimer in UI about approximate detection |
| 25-component bulk analysis cap | Large orgs (100+ Flows) need multiple queries | UI allows incremental queries |
| Health report may include archived objects | Not all objects are active | Filter archived in UI |

## 9. Success Metrics

| Metric | Target |
|--------|--------|
| Bulk analysis speedup vs. individual searches | 5-10x faster for 10+ components |
| Unused component detection accuracy | 85%+ precision (few false positives) |
| Time to identify candidates for deletion | < 5 minutes vs. hours of manual review |
| Org hygiene adoption | 30%+ of admins use unused metadata detector quarterly |
| Health report usage | 50%+ of admins review health report after major changes |
