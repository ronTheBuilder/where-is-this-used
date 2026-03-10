# PRD: Scheduled Analysis & Change Detection — Historical Snapshots and Dependency Tracking

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU v1 is **point-in-time**: you run a query and get today's dependencies. But admins need historical perspective:

- **"What changed since last week?"** — A component's dependencies shifted. Which dependencies were added? Which were removed? Someone made a breaking change without tracking it.
- **"What did this component reference at the time it broke?"** — A Flow fails at runtime. Admin wants to see what dependencies it had when it was last modified (might differ from today).
- **Dependency timeline** — Over 6 months, how has the dependency complexity of Account.Industry evolved? Is it getting more or less interconnected?
- **Org governance** — "Alert me if a new Flow references a PII field" — proactive monitoring of sensitive field usage.
- **Change impact analysis** — "I'm about to delete this field. What was its dependency chain as of the last deployment?" Prepare for impact analysis before making the change.

### Real-World Scenarios

| Scenario | Current Pain |
|----------|-------------|
| Weekend emergency: a field calculation fails | Admin wants to understand what changed. Only has current snapshot. Can't compare to the state at last successful deployment. |
| Audit of field usage changes | Compliance team asks: "Which new Flows accessed Customer PII fields in Q4?" No historical record to answer this. |
| Field retirement planning | Admin checks field dependencies today, plans retirement. Schedules deprecation email. Meanwhile, a developer adds a new Flow that uses the field. Admin has no way to get alerts. |
| Org optimization | Architect wants to identify fields that used to have many dependencies but now have few (candidates for refactor or removal). No historical data. |

## 2. Solution

Two complementary features:

### 2.1 Scheduled Snapshots

Periodically capture a **snapshot** of all dependency metadata (all Flows, all fields, all Apex classes, etc.) with timestamps. Store snapshots to enable historical queries.

**Snapshot format**:
```
Timestamp: 2026-02-17 02:00 UTC (weekly at 2 AM)
Metadata catalog:
  - 150 Flows (with version info, active status)
  - 230 Apex classes
  - 180 Validation Rules
  - 500+ custom/standard fields

Dependency graph:
  - Account.Industry → Route_By_Industry (Flow) @ 2026-02-17 02:01
  - Account.Industry → Territory_Assignment (Flow) @ 2026-02-17 02:01
  - ... (all dependencies with capture timestamp)
```

**Storage**: Store snapshots as JSON in Salesforce (Salesforce File or custom record). Configurable retention (keep last 12 snapshots = 3 months of weekly history).

### 2.2 Dependency Diffing & Alerts

Compare snapshots to detect changes:
- **Added dependencies** — A new Flow now references Account.Industry (was added since last snapshot)
- **Removed dependencies** — AccountService no longer references Account.Industry (removed since last snapshot)
- **Component lifecycle** — A Flow was created, then deleted (visible in snapshots)

**Alert types** (opt-in):
- **Sensitive field monitoring** — "Alert me if any Flow references Account.SSN__c"
- **Component-specific monitoring** — "Alert me if Account.Industry dependencies change"
- **Org-wide change summary** — "Send me weekly digest: +5 new dependencies, -3 removed"

## 3. Technical Architecture

### 3.1 Snapshot Data Model

```apex
public class DependencySnapshot {
    @AuraEnabled public String snapshotId;           // UUID
    @AuraEnabled public DateTime capturedAt;         // When this snapshot was taken
    @AuraEnabled public String snapshotLabel;        // 'Weekly-2026-02-17', 'Manual-Deploy-Feb17'
    @AuraEnabled public SnapshotMetadata metadata;   // Catalog of all components
    @AuraEnabled public List<SnapshotDependency> dependencies;
    @AuraEnabled public SnapshotStats stats;
}

public class SnapshotMetadata {
    @AuraEnabled public Integer flowCount;
    @AuraEnabled public Integer apexClassCount;
    @AuraEnabled public Integer validationRuleCount;
    @AuraEnabled public Integer customFieldCount;
    @AuraEnabled public Integer standardFieldCount;
    @AuraEnabled public List<FlowMetadata> flows;
    @AuraEnabled public List<ApexMetadata> classes;
    @AuraEnabled public List<ValidationRuleMetadata> validationRules;
}

public class FlowMetadata {
    @AuraEnabled public String id;
    @AuraEnabled public String apiName;
    @AuraEnabled public String label;
    @AuraEnabled public String status;             // 'Active', 'Archived'
    @AuraEnabled public DateTime lastModifiedDate;
}

public class SnapshotDependency {
    @AuraEnabled public String id;                 // UUID
    @AuraEnabled public String metadataComponentType;
    @AuraEnabled public String metadataComponentName;
    @AuraEnabled public String refMetadataComponentType;
    @AuraEnabled public String refMetadataComponentName;
}

public class SnapshotStats {
    @AuraEnabled public Integer totalDependencies;
    @AuraEnabled public Integer uniqueComponents;
    @AuraEnabled public Map<String, Integer> dependenciesByType;
}

public class DependencyChange {
    @AuraEnabled public String changeType;          // 'Added', 'Removed', 'ComponentCreated', 'ComponentDeleted'
    @AuraEnabled public String metadataComponentType;
    @AuraEnabled public String metadataComponentName;
    @AuraEnabled public String refMetadataComponentType;
    @AuraEnabled public String refMetadataComponentName;
    @AuraEnabled public DateTime detectedAt;
    @AuraEnabled public DateTime snapshotATimestamp;
    @AuraEnabled public DateTime snapshotBTimestamp;
}
```

### 3.2 Snapshot Capture Process

**Scheduled Apex Job** (Queueable or Scheduled):

```apex
global class SnapshotSchedulerJob implements Schedulable {
    global void execute(SchedulableContext context) {
        System.enqueueJob(new SnapshotCaptureJob());
    }
}

public class SnapshotCaptureJob implements Queueable {
    public void execute(QueueableContext context) {
        enforceAccess();

        // Capture all metadata
        DependencySnapshot snapshot = new DependencySnapshot();
        snapshot.snapshotId = System.Uuid.randomUuid().toString();
        snapshot.capturedAt = DateTime.now();
        snapshot.snapshotLabel = 'Weekly-' + DateTime.now().format('YYYY-MM-dd');
        snapshot.metadata = captureAllMetadata();
        snapshot.dependencies = captureAllDependencies();
        snapshot.stats = computeStats(snapshot);

        // Store snapshot
        saveSnapshot(snapshot);

        // Compare to previous snapshot and generate alerts
        DependencySnapshot previousSnapshot = getPreviousSnapshot();
        if (previousSnapshot != null) {
            List<DependencyChange> changes = diffSnapshots(previousSnapshot, snapshot);
            processChanges(changes);
        }

        // Cleanup old snapshots (keep last 12)
        pruneOldSnapshots(12);
    }

    private SnapshotMetadata captureAllMetadata() {
        SnapshotMetadata meta = new SnapshotMetadata();

        // Query all Flows
        String flowQuery = 'SELECT Id, ApiName, Label, Status, LastModifiedDate FROM FlowDefinitionView ORDER BY ApiName';
        // ... parse results into meta.flows

        // Query all Apex classes
        // Query all Validation Rules
        // Query all custom fields

        return meta;
    }

    private List<SnapshotDependency> captureAllDependencies() {
        List<SnapshotDependency> deps = new List<SnapshotDependency>();

        String query = 'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, ' +
                      'RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType ' +
                      'FROM MetadataComponentDependency ORDER BY MetadataComponentType, MetadataComponentName';

        ToolingQueryResponse response = queryToolingRecords(query);
        for (Object rec : response.records) {
            Map<String, Object> row = (Map<String, Object>) rec;
            SnapshotDependency dep = new SnapshotDependency();
            dep.id = System.Uuid.randomUuid().toString();
            dep.metadataComponentType = (String) row.get('MetadataComponentType');
            dep.metadataComponentName = (String) row.get('MetadataComponentName');
            dep.refMetadataComponentType = (String) row.get('RefMetadataComponentType');
            dep.refMetadataComponentName = (String) row.get('RefMetadataComponentName');
            deps.add(dep);
        }

        return deps;
    }

    private void saveSnapshot(DependencySnapshot snapshot) {
        // Option A: Store in custom object `WITU_Snapshot__c`
        // Option B: Store as Salesforce File with metadata
        // Recommendation: Custom object (easier to query)

        WITU_Snapshot__c record = new WITU_Snapshot__c();
        record.SnapshotData__c = JSON.serialize(snapshot); // Compressed JSON
        record.SnapshotLabel__c = snapshot.snapshotLabel;
        record.CapturedAt__c = snapshot.capturedAt;
        record.TotalDependencies__c = snapshot.stats.totalDependencies;
        insert record;
    }

    private DependencySnapshot getPreviousSnapshot() {
        List<WITU_Snapshot__c> snapshots = [
            SELECT Id, SnapshotData__c
            FROM WITU_Snapshot__c
            ORDER BY CapturedAt__c DESC
            LIMIT 2
        ];

        if (snapshots.size() >= 2) {
            DependencySnapshot snap = (DependencySnapshot) JSON.deserialize(
                snapshots[1].SnapshotData__c, DependencySnapshot.class
            );
            return snap;
        }
        return null;
    }

    private List<DependencyChange> diffSnapshots(
        DependencySnapshot snapshotA, DependencySnapshot snapshotB
    ) {
        List<DependencyChange> changes = new List<DependencyChange>();

        // Build set of dependencies in each snapshot
        Set<String> depsA = buildDepSet(snapshotA.dependencies);
        Set<String> depsB = buildDepSet(snapshotB.dependencies);

        // Added dependencies (in B but not A)
        for (SnapshotDependency depB : snapshotB.dependencies) {
            String key = makeDepKey(depB);
            if (!depsA.contains(key)) {
                DependencyChange change = new DependencyChange();
                change.changeType = 'Added';
                change.metadataComponentType = depB.metadataComponentType;
                change.metadataComponentName = depB.metadataComponentName;
                change.refMetadataComponentType = depB.refMetadataComponentType;
                change.refMetadataComponentName = depB.refMetadataComponentName;
                change.detectedAt = DateTime.now();
                change.snapshotATimestamp = snapshotA.capturedAt;
                change.snapshotBTimestamp = snapshotB.capturedAt;
                changes.add(change);
            }
        }

        // Removed dependencies (in A but not B)
        for (SnapshotDependency depA : snapshotA.dependencies) {
            String key = makeDepKey(depA);
            if (!depsB.contains(key)) {
                DependencyChange change = new DependencyChange();
                change.changeType = 'Removed';
                // ... populate fields
                changes.add(change);
            }
        }

        return changes;
    }

    private void processChanges(List<DependencyChange> changes) {
        // Check if any changes match user-configured alert rules
        List<SnapshotAlert__c> alerts = [
            SELECT Id, AlertType__c, MonitoredComponentType__c, MonitoredComponentName__c
            FROM SnapshotAlert__c
            WHERE IsActive__c = true
        ];

        for (SnapshotAlert__c alert : alerts) {
            for (DependencyChange change : changes) {
                if (matchesAlert(change, alert)) {
                    // Trigger notification
                    sendAlert(alert, change);
                }
            }
        }
    }

    private void pruneOldSnapshots(Integer keepCount) {
        List<WITU_Snapshot__c> snapshots = [
            SELECT Id FROM WITU_Snapshot__c
            ORDER BY CapturedAt__c DESC
            LIMIT 100
        ];

        if (snapshots.size() > keepCount) {
            List<WITU_Snapshot__c> toDelete = snapshots.sublist(keepCount);
            delete toDelete;
        }
    }
}
```

**Scheduling**: Create scheduled Apex job via Setup UI or deploy with entry point:

```apex
// Deploy-time setup
System.schedule('WITU Snapshot Weekly', '0 0 2 ? * MON', new SnapshotSchedulerJob());
```

**Frequency options**:
- Daily (captures more history, uses more storage)
- Weekly (default, balanced history + storage)
- Monthly (minimal storage, less granular history)

### 3.3 Dependency Diffing

Compare two snapshots and highlight changes:

```apex
public class SnapshotDiffView {
    @AuraEnabled public DependencySnapshot snapshotA;
    @AuraEnabled public DependencySnapshot snapshotB;
    @AuraEnabled public List<DependencyChange> addedDependencies;
    @AuraEnabled public List<DependencyChange> removedDependencies;
    @AuraEnabled public Map<String, ComponentLifecycle> componentChanges;
}

public class ComponentLifecycle {
    @AuraEnabled public String componentType;
    @AuraEnabled public String componentName;
    @AuraEnabled public DateTime createdDate;
    @AuraEnabled public DateTime deletedDate;
    @AuraEnabled public Boolean createdBetweenSnapshots;
    @AuraEnabled public Boolean deletedBetweenSnapshots;
}

@AuraEnabled
public static SnapshotDiffView compareSnapshots(String snapshotIdA, String snapshotIdB) {
    enforceAccess();

    WITU_Snapshot__c recA = [SELECT SnapshotData__c FROM WITU_Snapshot__c WHERE Id = :snapshotIdA];
    WITU_Snapshot__c recB = [SELECT SnapshotData__c FROM WITU_Snapshot__c WHERE Id = :snapshotIdB];

    DependencySnapshot snapA = (DependencySnapshot) JSON.deserialize(
        recA.SnapshotData__c, DependencySnapshot.class
    );
    DependencySnapshot snapB = (DependencySnapshot) JSON.deserialize(
        recB.SnapshotData__c, DependencySnapshot.class
    );

    SnapshotDiffView diff = new SnapshotDiffView();
    diff.snapshotA = snapA;
    diff.snapshotB = snapB;
    diff.addedDependencies = new List<DependencyChange>();
    diff.removedDependencies = new List<DependencyChange>();
    diff.componentChanges = new Map<String, ComponentLifecycle>();

    // Compute diff (see diffSnapshots above)
    // ...

    return diff;
}
```

### 3.4 Alert System

Custom object `SnapshotAlert__c`:

```
SnapshotAlert__c
├── IsActive__c: Boolean
├── AlertType__c: Picklist ('SensitiveField', 'ComponentMonitor', 'OrgwideSummary')
├── MonitoredComponentType__c: String (e.g., 'CustomField')
├── MonitoredComponentName__c: String (e.g., 'Account.SSN__c')
├── AlertRecipients__c: Lookup(User) or Email
├── NotificationMethod__c: Picklist ('Email', 'InApp', 'Both')
└── LastTriggeredAt__c: DateTime
```

**Alert examples**:
- **Sensitive field monitoring**: MonitoredComponentType='CustomField', MonitoredComponentName='Account.SSN__c' → Alert when new Flow references this field
- **Component monitor**: MonitoredComponentType='Flow', MonitoredComponentName='Critical_Account_Creation_Flow' → Alert when new components reference this Flow (new dependents)
- **Org-wide digest**: AlertType='OrgwideSummary' → Send weekly email with +/- counts

## 4. UI Design

### Snapshot History Tab

```
┌─────────────────────────────────────────────────────────────────┐
│  Snapshot History & Timeline                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Capture Now]  [Configure Schedule]  [View Settings]           │
│                                                                 │
│  Captured Snapshots:                                            │
│  ────────────────────────────────────────────────────────────   │
│                                                                 │
│  ◉ Weekly-2026-02-17  02:00 UTC  (TODAY)                        │
│    • 150 Flows, 230 Apex classes, 500 fields, 2,847 dependencies│
│    [View] [Compare to previous] [Export]                        │
│                                                                 │
│  ○ Weekly-2026-02-10  02:00 UTC  (7d ago)                       │
│    • 148 Flows, 228 Apex classes, 500 fields, 2,823 dependencies│
│    [View] [Compare] [Export]                                    │
│                                                                 │
│  ○ Weekly-2026-02-03  02:00 UTC  (14d ago)                      │
│    • 148 Flows, 227 Apex classes, 495 fields, 2,801 dependencies│
│    [View] [Compare] [Export]                                    │
│                                                                 │
│  ○ Weekly-2026-01-27  02:00 UTC  (21d ago)                      │
│                                                                 │
│  Dependency Timeline (Account.Industry):                        │
│  ────────────────────────────────────────                       │
│                                                                 │
│  Feb 17:  8 references ┐                                        │
│  Feb 10:  8 references │                                        │
│  Feb 3:   7 references │ +1 new reference (new Flow created)   │
│  Jan 27:  7 references │                                        │
│           └──────────────────                                   │
│                                                                 │
│  Change detected between Feb 10 → Feb 17:                       │
│  ✓ Added: New_Account_Onboarding_Flow references Account.Industry
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Diff View

```
┌─────────────────────────────────────────────────────────────────┐
│  Compare Snapshots: Weekly-2026-02-17 vs Weekly-2026-02-10     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Time Range: Feb 10 02:00 → Feb 17 02:00 (7 days)              │
│                                                                 │
│  Summary:                                                       │
│  • Total dependencies: 2,823 → 2,847 (+24)                     │
│  • Components added: 2 (Flows), 3 (Apex classes)               │
│  • Components deleted: 1 (Flow)                                 │
│  • Dependencies added: 27                                       │
│  • Dependencies removed: 3                                      │
│                                                                 │
│  ▼ Added Dependencies (+27)                                     │
│    ├─ New_Account_Onboarding_Flow (Flow)                        │
│    │  → Account.Industry, Account.BillingCity                   │
│    ├─ EnhancedAccountValidation (ApexClass)                     │
│    │  → Account.Industry, Account.Type, Account.Revenue__c      │
│    └─ ...                                                        │
│                                                                 │
│  ▼ Removed Dependencies (-3)                                    │
│    ├─ Old_Lead_Assignment_v1 (Flow)    [Flow Deleted]           │
│    │  → Account.LeadSource                                      │
│    └─ ...                                                        │
│                                                                 │
│  ▼ Component Lifecycle                                          │
│    Created:  New_Account_Onboarding_Flow (Flow)                 │
│    Deleted:  Old_Lead_Assignment_v1 (Flow)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Alert Configuration

```
┌─────────────────────────────────────────────────────────────────┐
│  Snapshot Alerts Configuration                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Add Alert]                                                    │
│                                                                 │
│  Active Alerts:                                                 │
│                                                                 │
│  ✓ [Edit] [Delete]                                              │
│    Alert: "Monitor SSN field for new references"                │
│    Type: Sensitive Field                                        │
│    Component: Account.SSN__c                                    │
│    Watch For: Added dependencies (new components reading this)  │
│    Recipients: admin@company.com                                │
│    Notify: Email, In-App                                        │
│    Last triggered: 2026-02-10 @ 14:30 (New Flow detected)       │
│                                                                 │
│  ✓ [Edit] [Delete]                                              │
│    Alert: "Critical Flow changes"                               │
│    Type: Component Monitor                                      │
│    Component: Critical_Account_Creation_Flow                    │
│    Watch For: Added OR removed dependencies                     │
│    Recipients: dev-team@company.com                             │
│    Notify: Email                                                │
│    Last triggered: Never                                        │
│                                                                 │
│  ✓ [Edit] [Delete]                                              │
│    Alert: "Weekly org-wide digest"                              │
│    Type: Org-wide Summary                                       │
│    Watch For: Any dependency changes                            │
│    Recipients: architects@company.com                           │
│    Notify: Email (weekly)                                       │
│    Last triggered: 2026-02-17 @ 02:15                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 5. Files to Create

### New Apex Classes

| File | Purpose |
|------|---------|
| `SnapshotSchedulerJob.cls` | Scheduled Apex to capture snapshots |
| `SnapshotCaptureJob.cls` | Queueable job for capture logic |
| `SnapshotDiffService.cls` | Compare snapshots and generate changes |
| `SnapshotAlertService.cls` | Check and send alerts |
| `SnapshotControllerTest.cls` | Tests for snapshot functionality |

### New LWC Components

| File | Purpose |
|------|---------|
| `lwc/snapshotHistory/` | Display and manage snapshots |
| `lwc/snapshotDiffView/` | Compare and visualize diff |
| `lwc/snapshotAlerts/` | Configure and manage alerts |

### New Custom Objects

| Object | Purpose |
|--------|---------|
| `WITU_Snapshot__c` | Store captured snapshots |
| `SnapshotAlert__c` | Store alert rules |

## 6. Storage Implications

**Per snapshot size** (estimate):
- 150 Flows: ~15 KB
- 230 Apex classes: ~10 KB
- 2,847 dependencies: ~200 KB
- Metadata catalog: ~50 KB
- **Total**: ~275 KB per snapshot

**Storage for 12 weekly snapshots**: ~3.3 MB (minimal impact)

**Salesforce Files limit**: 2 GB per org. No concerns even with daily snapshots for 5+ years.

## 7. API Budget

| Operation | API Calls |
|-----------|-----------|
| Capture all metadata | 10-15 (Flows, Classes, VRs, etc.) |
| Capture all dependencies | 1-2 (single large query, may paginate) |
| Diff two snapshots | 0 (local comparison) |
| Send alerts | 0-N (depends on alert rules) |

**Execution window**: Run capture job at off-peak (2 AM UTC). Single job execution = 10-15 API calls.

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Snapshot capture success rate | 99%+ (on-schedule execution) |
| Diff accuracy | 100% match between snapshot comparison and manual review |
| Alert accuracy | 95%+ of triggered alerts are actionable |
| Storage efficiency | < 5 MB for 12 snapshots (3 months history) |
| Query performance | Snapshots load in < 2s, diffs compute in < 5s |
| Alert adoption | 40%+ of admins configure at least one alert |
| False positive rate | < 5% (changes detected that aren't real) |
