# WITU Issues — QA Testing 12 maart 2026

## Found Issues

### ISSUE-1: Data Journey and Process Flow Map not accessible [HIGH]
**Description:** `dataJourneyView` and `processFlowMap` LWC components exist in the codebase but are not accessible to users. They are not referenced in:
- `dependencyFinder` (the main component in the FlexiPage)
- `Where_Is_This_Used_Page` FlexiPage (only contains `dependencyFinder`)

**Impact:** Two major features (Data Journey trace + Process Flow Map) are completely unreachable.

**Root cause:** The FlexiPage only includes `dependencyFinder`, which has 3 tabs (Dependency Finder, Setup, Blast Radius). Data Journey and Process Flow Map need to be added as additional tabs.

**Proposed fix:** Add "Data Journey" and "Process Flow" as tabs in `dependencyFinder.html` and `dependencyFinder.js`, embedding `c-data-journey-view` and `c-process-flow-map` components.

### ISSUE-2: FlexiPage deploy fails with server-side error [KNOWN]
**Description:** `Where_Is_This_Used_Page.flexipage-meta.xml` cannot be deployed due to Salesforce server-side bug (ErrorId: 275429527-14288).

**Impact:** Cannot add new components to the FlexiPage via metadata deployment. Workaround: add components within existing LWC structure.

**Status:** Known issue, requires Salesforce support.

### ISSUE-3: Dev org lacks test data for full validation [LOW]
**Description:** witu-dev org has no Flows, minimal Apex references, and few metadata dependencies. This makes it impossible to fully test Blast Radius graph rendering, Data Journey tracing, and Export functionality.

**Proposed fix:** Create test metadata in the org:
- A Flow that references Account.Active__c
- An Apex class that queries Account fields
- A validation rule on Account

## Previously Fixed (Code Review - 11 maart)
- CRITICAL: SetupController privilege escalation → allowlist + CRUD/FLS
- HIGH: CSV export broken (phase.automations → phase.steps)
- HIGH: window.open reverse tabnabbing → noopener,noreferrer
- HIGH: d3Loader permanent rejection cache → retry on failure
- HIGH: DRY violation → centralized wituConstants
- MEDIUM: Dead code removal, naming, API version, timer cleanup
