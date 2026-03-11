# Full Code Quality Review (Salesforce LWC + Apex)

Scope reviewed:
- All Apex classes and test classes under `force-app/main/default/classes`
- All LWC components under `force-app/main/default/lwc`
- Architecture context from `CLAUDE.md`

---

## CRITICAL

1. Privilege escalation in `SetupController.assignPermissionSet`
- File: `force-app/main/default/classes/SetupController.cls:52-83`
- Issue: Method accepts any `permSetName` from client input and performs `insert PermissionSetAssignment` in system context without object/field permission checks and without server-side allowlist.
- Impact: Any user with `WITU_Access` can assign arbitrary permission sets (including highly privileged sets) to arbitrary users.
- Fix:
  - Hard-allowlist permitted set names server-side (`Where_Is_This_Used_User`, `Where_Is_This_Used_Admin`).
  - Enforce admin-only gate for assignment operations (custom permission dedicated for setup admin, not general app user).
  - Add CRUD check before DML (`PermissionSetAssignment` createability).

---

## HIGH

1. Process Flow CSV export is broken
- File: `force-app/main/default/lwc/exportUtils/exportUtils.js:112`
- Issue: `buildProcessFlowCsv()` iterates `phase.automations`, but response model uses `phase.steps` (`ProcessFlowService` uses `steps`).
- Impact: Process Flow CSV exports are empty/incorrect.
- Fix: iterate `phase.steps` consistently.

2. Incomplete CRUD/FLS enforcement in setup/admin Apex paths
- Files:
  - `force-app/main/default/classes/SetupController.cls:32-49` (`User` query)
  - `force-app/main/default/classes/SetupController.cls:52-83` (`PermissionSetAssignment` insert)
  - `force-app/main/default/classes/SetupController.cls:231-244` (`PermissionSetAssignment` delete)
  - `force-app/main/default/classes/SetupController.cls:14-19` (`WITU_Settings__c` upsert)
- Issue: No explicit object/field-level checks before SOQL/DML in methods exposed to LWC.
- Impact: Security-review risk and potential overexposure/mutation outside intended permissions.
- Fix: add `Schema.sObjectType.*.isAccessible/isCreateable/isUpdateable/isDeletable` checks and fail with controlled errors.

3. `wituConstants` introduced but not adopted; type/color constants duplicated across multiple components
- Files:
  - `force-app/main/default/lwc/wituConstants/wituConstants.js`
  - `force-app/main/default/lwc/blastRadiusGraph/blastRadiusGraph.js:15-45`
  - `force-app/main/default/lwc/dependencyResults/dependencyResults.js:6-49`
  - `force-app/main/default/lwc/dataJourneyView/dataJourneyView.js:13-36`
  - `force-app/main/default/lwc/processFlowMap/processFlowMap.js:13-50`
- Issue: New shared constants module is not used where it matters.
- Impact: Drift risk and inconsistent UX semantics over time.
- Fix: centralize imports from `c/wituConstants` and remove local duplicates.

4. Reverse-tabnabbing risk from unprotected `window.open`
- Files:
  - `force-app/main/default/lwc/dependencyResults/dependencyResults.js:202,394,563`
  - `force-app/main/default/lwc/processFlowMap/processFlowMap.js:265`
  - `force-app/main/default/lwc/dataJourneyView/dataJourneyView.js:267`
- Issue: Uses `window.open(url, '_blank')` without `noopener,noreferrer`.
- Impact: Opened page can access `window.opener` and manipulate origin tab.
- Fix: use `window.open(url, '_blank', 'noopener,noreferrer')` consistently.

5. `d3Loader` caches rejected promises permanently
- File: `force-app/main/default/lwc/d3Loader/d3Loader.js:13-18,25-33`
- Issue: If initial load fails, cached promise stays rejected, and later retries on same page cannot recover.
- Impact: transient load failure becomes sticky until full page reload.
- Fix: reset `d3Promise`/`d3SankeyPromise` on rejection.

---

## MEDIUM

1. Apex services are too large and violate separation-of-concerns
- Files:
  - `force-app/main/default/classes/DependencyService.cls` (~1000 lines)
  - `force-app/main/default/classes/DataJourneyService.cls` (~760 lines)
  - `force-app/main/default/classes/ProcessFlowService.cls` (~560 lines)
  - `force-app/main/default/classes/ToolingApiClient.cls` (~580 lines)
- Issue: multiple responsibilities (validation, orchestration, parsing, formatting, fallback logic) in single classes.
- Impact: harder testing, increased regression surface, low change velocity.
- Fix: extract query builders, parsers, DTO mappers, and feature-specific helpers into smaller units.

2. `String.valueOf(null)` pitfalls can introduce "null" as synthetic business data
- Files:
  - `force-app/main/default/classes/BlastRadiusService.cls:192-195`
  - `force-app/main/default/classes/DependencyService.cls:919-922` (and similar patterns)
- Issue: `String.valueOf(null)` returns literal `'null'`, which passes some non-blank checks.
- Impact: invalid nodes/records can be included instead of skipped.
- Fix: use null-safe helper (`value == null ? null : String.valueOf(value)`) before blank checks.

3. `DependencyFinder` contains unused cleanup state/imports and dead tab logic
- File: `force-app/main/default/lwc/dependencyFinder/dependencyFinder.js:2-4,13-20,33-35`
- Issue: `getObjects`, `findUnusedCustomFields`, and cleanup tab state are present but not wired in template.
- Impact: dead code and misleading maintenance surface.
- Fix: either complete cleanup feature UI wiring or remove dormant state/imports.

4. `DataJourneyView` has unused/unfinished connector path model
- Files:
  - `force-app/main/default/lwc/dataJourneyView/dataJourneyView.js:236-254`
  - `force-app/main/default/lwc/dataJourneyView/dataJourneyView.html:64`
- Issue: `connectorPaths` is computed but never rendered into manual SVG layer.
- Impact: dead logic and potential feature incompleteness.
- Fix: either render connectors via manual SVG code or delete unused model.

5. `SetupController.UserInfo` name collides semantically with platform `UserInfo`
- File: `force-app/main/default/classes/SetupController.cls:247-259`
- Issue: nested DTO named `UserInfo` is easy to confuse with `System.UserInfo`.
- Impact: readability and maintenance risk.
- Fix: rename DTO to `UserSummary` or `UserViewModel`.

6. API version mismatch in export utility
- File: `force-app/main/default/lwc/exportUtils/exportUtils.js:187`
- Issue: generated `package.xml` uses `65.0`, while project/tooling code targets `66.0`.
- Impact: consistency/confusion risk.
- Fix: align to single API version constant.

---

## LOW

1. Repetitive controller exception wrapping pattern
- Files:
  - `DependencyController.cls`, `BlastRadiusController.cls`, `DataJourneyController.cls`, `ProcessFlowController.cls`, `MetadataPickerController.cls`
- Issue: repeated `AuraHandledException` boilerplate and duplicate `setMessage` calls.
- Impact: noise and duplication.
- Fix: centralize wrapper helper.

2. Timer cleanup missing in some LWCs
- Files:
  - `force-app/main/default/lwc/metadataPicker/metadataPicker.js:262-268`
  - `force-app/main/default/lwc/setupWizard/setupWizard.js:293-305`
- Issue: no `disconnectedCallback` clearing pending timers.
- Impact: small memory/leak/lifecycle risk.
- Fix: clear timeouts in component teardown.

3. Naming/style consistency
- File: `force-app/main/default/classes/ToolingApiClient.cls:381`
- Issue: `shaped_record` uses snake_case among camelCase codebase.
- Impact: convention inconsistency.
- Fix: rename to `shapedRecord`.

---

## POSITIVE

1. Broad access gate is consistently applied across services
- Pattern: `ToolingApiClient.enforceAccess()` present in feature services/controllers.
- Good: clear custom-permission gate for product feature access.

2. Input validation for injection defense is generally strong
- Examples:
  - `ToolingApiClient.validateComponentName()`
  - regex/object validation in `DataJourneyService` and `ProcessFlowService`
  - extensive `String.escapeSingleQuotes` usage in dynamic SOQL
- Good: SOQL injection posture is much better than typical Tooling API wrappers.

3. Tooling API fallback strategy is thoughtfully designed
- File: `ToolingApiClient.cls` fallback chains for `FlowVersionView` and `MetadataComponentDependency`.
- Good: robust cross-org compatibility approach.

4. Test suite has good scenario coverage for main happy paths and several failure modes
- Especially for Tooling fallback behavior and major service flows.
- Good: meaningful mocks and explicit assertions for retry/fallback logic.

5. LWC accessibility effort is visible in many areas
- Examples: assistive labels, keyboard handlers for collapsible headers (`dependencyResults`, `processFlowMap`), explicit `aria-label` on interactive controls.

---

## Test Coverage Assessment (Targeted)

Current strengths:
- Most Apex production classes have corresponding test classes.
- Tooling API fallback/retry logic is well represented (`ToolingApiClientTest`).

Coverage gaps:
- No LWC Jest tests found for any component (`force-app/main/default/lwc`).
- Limited negative/security tests around setup/admin operations:
  - no tests asserting server-side restriction of assignable permission sets
  - no tests for CRUD/FLS-denied paths
- Major `DependencyService` branches under-tested:
  - formula field path
  - validation-rule formula parsing path
  - layout/flexipage supplementary scans
- No tests for newly added `wituConstants` usage integration (currently unused).

---

## New Code Assessment

### `SetupController`
- Verdict: **Not solid yet** for security-hardening.
- Main blocker: privilege escalation + missing CRUD/FLS checks on setup/admin operations.

### `d3Loader`
- Verdict: **Mostly solid**, but should handle failed-load retry by clearing cached rejected promises.

### `wituConstants`
- Verdict: **Concept is good**, implementation incomplete because consumers still duplicate constants.

### `blastRadiusGraph`
- Verdict: **Feature-rich and ambitious**, but very large/complex and should be split; maintainability risk is high. Also ensure all mode-specific update paths are covered by tests (especially tree mode interactions).

