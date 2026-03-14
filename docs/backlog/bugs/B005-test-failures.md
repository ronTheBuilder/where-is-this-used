# B005 — Test Failures (11 tests, pre-existing debt)

Status: 💡 idea
Priority: —
Added: 2026-03-13

## Probleem
11 van 97 tests falen (89% pass rate). Geen regressies van recente wijzigingen — allemaal pre-existing.

## Failing Tests

### ShadcnDashboardControllerTest (2)
- `saveDashboard_upsertsRecord` → `FinalException: Testing already started`
- `saveDashboardItems_replaces...` → `FinalException: Testing already started`
- **Oorzaak:** Test.startTest() wordt dubbel aangeroepen

### ShadcnReportControllerTest (3)
- `requiresFilterColumn`, `requiresRecordId`, `requiresReportId`
- **Oorzaak:** Controller validatie-logica gewijzigd, test assertions matchen niet

### BlastRadiusServiceTest (1)
- `getBlastRadius_rejectsInvalidInput` → callout error
- **Oorzaak:** Ontbrekende HttpCalloutMock

### SetupControllerTest (3)
- `assignPermissionSet_throwsOnEmpty`, `createNamedCredentialSetup_throwsOnBlankName`, `removePermissionSetAssignment_handlesNull`
- **Oorzaak:** Controller behavior gewijzigd, test expectations matchen niet

### OpportunityDashboardControllerTest (1)
- `getDashboardData_returnsExpectedShape` → Expected 2, got 1
- **Oorzaak:** Data-afhankelijk, org state mismatch

### MetadataPickerControllerTest (1)
- `getFlowsAndApexClasses_returnToolingData` → Expected 1, got 0
- **Oorzaak:** Tooling API mock moet bijgewerkt na flow changes

## Notities
- WITU core tests (DependencyService, ToolingApiClient, DataJourney) zijn clean
- Dit zijn test-only fixes, geen productie code wijzigingen nodig
