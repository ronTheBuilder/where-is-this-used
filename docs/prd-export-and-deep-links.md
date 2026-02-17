# PRD: Export & Deep Links — Results Export and Setup Navigation

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU displays dependency results, blast radius graphs, data journeys, and process flow maps — but all of that information is trapped in the UI. Users cannot:

- **Export results** to share with team members, include in documentation, or attach to change requests
- **Navigate directly** to a referenced component in Salesforce Setup — the "Open in Setup" links currently point to generic list pages (e.g., `/lightning/setup/ApexClasses/home`) rather than the specific component
- **Generate deployment artifacts** — after identifying all components that reference a field, developers want a `package.xml` to retrieve or deploy those components
- **Copy results** in structured formats (Markdown, Mermaid diagrams) for documentation wikis, Confluence pages, or Slack messages

### User Stories

| As a... | I want to... | So that... |
|---------|-------------|-----------|
| Admin | Export dependency results as CSV | I can attach them to a change request in Jira/ServiceNow |
| Developer | Click a component name to jump directly to it in Setup | I don't waste time navigating manually through Setup menus |
| Developer | Generate a `package.xml` from dependency results | I can retrieve all affected components for a deployment |
| Architect | Copy results as a Markdown table | I can paste them into our wiki documentation |
| Admin | Copy a blast radius graph as a Mermaid diagram | I can embed the visualization in Confluence or GitHub |
| Team Lead | Export a process flow map as text | I can include automation documentation in our runbook |

## 2. Solution

Two capabilities delivered together:

### 2.1 Setup Deep Links (ID-Specific Navigation)

Replace generic Setup list page URLs with direct links to the specific component. When a user clicks the ↗ icon next to a dependency result, it opens the exact component in Setup — not the list page.

**Current**: `AccountService` → `/lightning/setup/ApexClasses/home` (list of ALL Apex classes)
**After**: `AccountService` → `/lightning/setup/ApexClasses/page?address=/01p4x000001234AAA` (direct to this class)

### 2.2 Export Menu

Add an "Export" dropdown button to every WITU view (dependency results, blast radius, data journey, process flow map) with these options:

| Action | Format | Output |
|--------|--------|--------|
| Export as CSV | `.csv` file download | Tabular dependency data |
| Download package.xml | `.xml` file download | Salesforce deployment descriptor |
| Copy package.xml | Clipboard | Same XML, for pasting into IDE |
| Copy as Text | Clipboard | Plain text summary |
| Copy as Markdown | Clipboard | Markdown table |
| Copy as Mermaid | Clipboard | Mermaid diagram syntax |

## 3. Technical Architecture

### 3.1 Setup Deep Links — URL Resolution

#### New Utility Class: `SetupUrlResolver.cls`

Currently, `buildSetupUrl()` is duplicated in 3 service classes (`DependencyService`, `BlastRadiusService`, `DataJourneyService`) with identical logic mapping MetadataComponentType to generic list page URLs. This refactoring:

1. Extracts URL resolution into a single shared class
2. Adds ID-specific URL patterns for 25+ component types
3. Falls back to list pages when no ID is available

```apex
public with sharing class SetupUrlResolver {
    /**
     * Resolve the Setup URL for a specific metadata component.
     *
     * @param metadataComponentType  The MetadataComponentType from Tooling API
     * @param metadataComponentId    The 15/18-char Salesforce ID (nullable)
     * @param metadataComponentName  The component name (for object extraction)
     * @return Relative Setup URL path
     */
    public static String resolve(
        String metadataComponentType,
        String metadataComponentId,
        String metadataComponentName
    ) { ... }
}
```

#### URL Patterns by Type

| MetadataComponentType | ID-Specific URL Pattern | Fallback (No ID) |
|----------------------|------------------------|-------------------|
| `ApexClass` | `/lightning/setup/ApexClasses/page?address=/{id}` | `/lightning/setup/ApexClasses/home` |
| `ApexTrigger` | `/lightning/setup/ApexTriggers/page?address=/{id}` | `/lightning/setup/ApexTriggers/home` |
| `Flow` | `/builder_platform_interaction/flowBuilder.app?flowId={id}` | `/lightning/setup/Flows/home` |
| `ValidationRule` | `/lightning/setup/ObjectManager/{object}/ValidationRules/{id}/view` | `/lightning/setup/ObjectManager/home` |
| `Layout` | `/lightning/setup/ObjectManager/{object}/PageLayouts/{id}/view` | `/lightning/setup/ObjectManager/home` |
| `LightningComponentBundle` | `/lightning/setup/LightningComponentBundles/page?address=/{id}` | `/lightning/setup/LightningComponentBundles/home` |
| `AuraDefinitionBundle` | `/lightning/setup/AuraDefinitionBundles/home` | Same (no ID pattern) |
| `CustomField` | `/lightning/setup/ObjectManager/{object}/FieldsAndRelationships/{id}/view` | `/lightning/setup/ObjectManager/home` |
| `CustomObject` | `/lightning/setup/ObjectManager/{object}/Details/view` | `/lightning/setup/ObjectManager/home` |
| `StandardEntity` | `/lightning/setup/ObjectManager/{object}/Details/view` | `/lightning/setup/ObjectManager/home` |
| `QuickAction` | `/lightning/setup/ObjectManager/{object}/ButtonsLinksActions/view` | `/lightning/setup/ObjectManager/home` |
| `FlexiPage` | `/lightning/setup/FlexiPageList/home` | Same |
| `CustomLabel` | `/lightning/setup/ExternalStrings/home` | Same |
| `RecordType` | `/lightning/setup/ObjectManager/{object}/RecordTypes/{id}/view` | `/lightning/setup/ObjectManager/home` |
| `PermissionSet` | `/lightning/setup/PermSets/page?address=/{id}` | `/lightning/setup/PermSets/home` |
| `Profile` | `/lightning/setup/Profiles/page?address=/{id}` | `/lightning/setup/Profiles/home` |
| `EmailTemplate` | `/lightning/setup/CommunicationTemplatesEmail/home` | Same |
| `Report` | `/lightning/o/Report/{id}/view` | `/lightning/o/Report/home` |
| `Dashboard` | `/lightning/o/Dashboard/{id}/view` | `/lightning/o/Dashboard/home` |
| `Page` (VF) | `/lightning/setup/ApexPages/page?address=/{id}` | `/lightning/setup/ApexPages/home` |
| `WorkflowRule` | `/lightning/setup/ObjectManager/{object}/WorkflowRules/view` | `/lightning/setup/ObjectManager/home` |
| `CustomTab` | `/lightning/setup/CustomTabs/home` | Same |
| `StaticResource` | `/lightning/setup/StaticResources/home` | Same |

**Object name extraction**: For types that need an object name in the URL (ValidationRule, Layout, CustomField, etc.), extract it from the component name (e.g., `Account.My_Rule` → object = `Account`).

```apex
@TestVisible
private static String extractObjectName(String componentName) {
    if (String.isBlank(componentName) || !componentName.contains('.')) {
        return null;
    }
    return componentName.substringBefore('.');
}
```

### 3.2 Refactoring Duplicated `buildSetupUrl`

Remove the private `buildSetupUrl()` methods from:
- `DependencyService.cls` (replace with `SetupUrlResolver.resolve()`)
- `BlastRadiusService.cls` (replace with `SetupUrlResolver.resolve()`)
- `DataJourneyService.cls` (replace with `SetupUrlResolver.resolve()`)

All three services now delegate to `SetupUrlResolver` — single source of truth.

### 3.3 Export — Client-Side Architecture

All export logic runs in the browser. No Apex server calls needed — the data is already loaded client-side from the initial query. This avoids governor limits, CRUD/FLS concerns for file creation, and storage limits.

#### New LWC Module: `exportUtils`

A service module (no HTML template) with pure utility functions:

```
force-app/main/default/lwc/exportUtils/
├── exportUtils.js          ← Main module: downloadFile, copyToClipboard
├── csvFormatter.js         ← CSV generation: escapeCsvCell, buildCsvString
├── packageXmlGenerator.js  ← package.xml: Tooling→Metadata type map, XML generation
├── clipboardFormats.js     ← Plain text, Markdown, Mermaid formatters
└── exportUtils.js-meta.xml
```

#### New LWC Component: `exportMenu`

A reusable dropdown button embedded in each view:

```
force-app/main/default/lwc/exportMenu/
├── exportMenu.html
├── exportMenu.js
├── exportMenu.css
└── exportMenu.js-meta.xml
```

**Public API**:
```javascript
export default class ExportMenu extends LightningElement {
    @api viewType;       // 'dependencies' | 'blastRadius' | 'dataJourney' | 'processFlow'
    @api data;           // The view-specific response object
    @api searchContext;  // { metadataType, componentName, objectName, fieldName }
}
```

### 3.4 CSV Format

#### Dependency Results CSV

```csv
Component Name,Component Type,Namespace,Access Type,Setup URL
Route_By_Industry,Flow,,Read,/builder_platform_interaction/flowBuilder.app?flowId=3014x...
AccountService,ApexClass,,Read,/lightning/setup/ApexClasses/page?address=/01p4x...
Require_Industry,ValidationRule,,,/lightning/setup/ObjectManager/Account/ValidationRules/03d4x.../view
Account Layout,Layout,,,/lightning/setup/ObjectManager/Account/PageLayouts/00h4x.../view
```

#### Blast Radius CSV

```csv
Component Name,Component Type,Depth,Is Root,Is Cycle Node,Setup URL
Account.Industry,StandardEntity,0,true,false,/lightning/setup/ObjectManager/Account/Details/view
Route_By_Industry,Flow,1,false,false,/builder_platform_interaction/flowBuilder.app?flowId=...
AccountService,ApexClass,1,false,false,/lightning/setup/ApexClasses/page?address=/01p...
Territory_Assignment,Flow,2,false,false,/builder_platform_interaction/flowBuilder.app?flowId=...
```

#### Data Journey CSV

```csv
Node Name,Node Type,Direction,Access Type,Depth,Detail,Setup URL
Account.Region__c,field,root,,0,,/lightning/setup/ObjectManager/Account/Details/view
Set_Account_Region,flow,upstream,write,1,Flow writes to this field,/builder_platform_interaction/...
Territory_Assignment,flow,downstream,read,1,Flow reads this field,/builder_platform_interaction/...
```

#### Process Flow Map CSV

```csv
Phase,Phase Name,Automation Name,Automation Type,Is Active,Trigger Context,Setup URL
2,Before Triggers,AccountTrigger,ApexTrigger,true,"Before Insert, Before Update",/lightning/setup/...
3,Custom Validation Rules,Require_Industry,ValidationRule,true,Insert/Update,/lightning/setup/...
7,Before-Save Flows,Set_Account_Region,Flow,true,"Create, Update",/builder_platform_interaction/...
```

### 3.5 Package.xml Generation

Map Tooling API `MetadataComponentType` values to Metadata API type names:

```javascript
const TOOLING_TO_METADATA_TYPE = {
    'ApexClass':                'ApexClass',
    'ApexTrigger':              'ApexTrigger',
    'Flow':                     'Flow',
    'ValidationRule':           'ValidationRule',
    'Layout':                   'Layout',
    'LightningComponentBundle': 'LightningComponentBundle',
    'AuraDefinitionBundle':     'AuraDefinitionBundle',
    'CustomField':              'CustomField',
    'CustomObject':             'CustomObject',
    'FlexiPage':                'FlexiPage',
    'QuickAction':              'QuickAction',
    'CustomLabel':              'CustomLabel',
    'RecordType':               'RecordType',
    'PermissionSet':            'PermissionSet',
    'Profile':                  'Profile',
    'Page':                     'ApexPage',
    'StaticResource':           'StaticResource',
    'EmailTemplate':            'EmailTemplate',
    'CustomTab':                'CustomTab',
    'WorkflowRule':             'WorkflowRule'
};
```

**Generated output**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- Generated by Where Is This Used? (WITU) -->
    <!-- Dependencies of: Account.Industry (Standard Field) -->
    <!-- Generated: 2026-02-17T15:30:00Z -->
    <types>
        <members>Route_By_Industry</members>
        <members>Territory_Assignment_Flow</members>
        <name>Flow</name>
    </types>
    <types>
        <members>AccountService</members>
        <members>AccountHelper</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Account.Require_Industry</members>
        <name>ValidationRule</name>
    </types>
    <version>65.0</version>
</Package>
```

**Exclusions**: Types that are not deployable via Metadata API are excluded from package.xml:
- `StandardEntity` (standard fields — not deployable)
- `Report` (not standard metadata deployment)
- `Dashboard` (not standard metadata deployment)

### 3.6 Clipboard Formats

#### Plain Text

```
Where is Account.Industry used?
================================

Flow (4):
  - Route_By_Industry [Read]
  - Territory_Assignment_Flow [Read]
  - Industry_Subflow [Read] [Subflow]
  - Set_Default_Values [Read]

ApexClass (3):
  - AccountService [Read]
  - AccountHelper [Read]
  - IndustryUtils [Read]

ValidationRule (2):
  - Require_Industry_For_Enterprise
  - Industry_Must_Match_Record_Type

Layout (1):
  - Account Layout
```

#### Markdown Table

```markdown
## Dependencies: Account.Industry (Standard Field)

| Component | Type | Access | Setup Link |
|-----------|------|--------|------------|
| Route_By_Industry | Flow | Read | [Open](url) |
| AccountService | ApexClass | Read | [Open](url) |
| Require_Industry_For_Enterprise | ValidationRule | | [Open](url) |
| Account Layout | Layout | | [Open](url) |
```

#### Mermaid Diagram

For dependency results (flat graph):
```
graph LR
    root["Account.Industry"]
    root --> n1["Route_By_Industry (Flow)"]
    root --> n2["AccountService (ApexClass)"]
    root --> n3["Require_Industry (VR)"]
    root --> n4["Account Layout (Layout)"]
```

For blast radius (depth graph):
```
graph TD
    n0["Account.Industry"]:::root
    n0 --> n1["Route_By_Industry"]:::flow
    n0 --> n2["AccountService"]:::apex
    n1 --> n3["Territory_Assignment"]:::flow
    n2 --> n4["AccountServiceTest"]:::apex

    classDef root fill:#FF538A,color:#fff
    classDef flow fill:#1B96FF,color:#fff
    classDef apex fill:#9050E9,color:#fff
```

For data journey (bidirectional):
```
graph LR
    u1["Set_Account_Region (Flow)"]:::upstream -->|writes| root["Account.Region__c"]:::root
    root -->|read by| d1["Territory_Assignment (Flow)"]:::downstream
    root -->|read by| d2["VR: Region_Required"]:::downstream

    classDef root fill:#1B96FF,color:#fff
    classDef upstream fill:#04844B,color:#fff
    classDef downstream fill:#9050E9,color:#fff
```

### 3.7 File Download Implementation

Standard LWC pattern using `Blob` + anchor element (AppExchange safe):

```javascript
function downloadFile(filename, content, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url); // Prevent memory leaks
}
```

### 3.8 Clipboard Implementation

```javascript
async function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
        return true;
    }
    // Fallback for Lightning Experience iframe restrictions
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    const success = document.execCommand('copy');
    document.body.removeChild(textarea);
    return success;
}
```

**Important**: In Lightning Experience, `navigator.clipboard` may be restricted due to cross-origin iframe constraints. The `execCommand('copy')` fallback is essential. Both paths must be tested.

### 3.9 Data Flow

```
User clicks export menu item
         │
         ▼
exportMenu.js handles selection
         │
         ▼
Calls exportUtils function:
  ├── 'csv'           → downloadFile(filename, csvContent, 'text/csv')
  ├── 'packageXml'    → downloadFile(filename, xmlContent, 'text/xml')
  ├── 'packageXmlCopy'→ copyToClipboard(xmlContent)
  ├── 'text'          → copyToClipboard(textContent)
  ├── 'markdown'      → copyToClipboard(markdownContent)
  └── 'mermaid'       → copyToClipboard(mermaidContent)
         │
         ▼
Show toast: success or error
```

No server round-trip. All data is already in the LWC component from the initial Apex query.

## 4. UI Design

### Export Button Placement — Dependency Results

```
┌─────────────────────────────────────────────────────────────────┐
│  Showing results for Account.Industry  [Standard Field]         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  23 references found               [Show Blast Radius] [Export ▾]│
│  across 5 metadata types                                         │
│                                                                  │
│  [All: 23] [Flow: 4] [ApexClass: 3] [VR: 2] [Layout: 1]       │
│                                                                  │
│  ▼ Flow (4)                                                      │
│    Route_By_Industry               [Read]              [↗]       │
│    Territory_Assignment_Flow       [Read]              [↗]       │
│    Industry_Subflow                [Read] [Subflow]    [↗]       │
│    Set_Default_Values              [Read]              [↗]       │
│                                                                  │
│  ▶ ApexClass (3)                                                 │
│  ▶ Validation Rule (2)                                           │
│  ▶ Layout (1)                                                    │
└─────────────────────────────────────────────────────────────────┘
```

### Export Dropdown Menu

```
┌──────────────────────────┐
│  Export ▾                 │
├──────────────────────────┤
│  ↓  Export as CSV         │
│  ↓  Download package.xml  │
│  📋 Copy package.xml      │
│  ────────────────────     │
│  📋 Copy as Text          │
│  📋 Copy as Markdown      │
│  📋 Copy as Mermaid       │
└──────────────────────────┘
```

Uses `lightning-button-menu` with `lightning-menu-item` — standard SLDS, no custom styling.

### Export Menu Availability by View

| Action | Dependencies | Blast Radius | Data Journey | Process Flow |
|--------|-------------|-------------|-------------|-------------|
| CSV | Yes | Yes | Yes | Yes |
| Package.xml | Yes | Yes | No* | No* |
| Copy Text | Yes | Yes | Yes | Yes |
| Copy Markdown | Yes | Yes | Yes | Yes |
| Copy Mermaid | Yes | Yes | Yes | Yes |

*Package.xml is excluded for Data Journey and Process Flow because those views show analytical relationships, not deployable metadata components.

## 5. Files to Create / Modify

### New Files

| File | Purpose |
|------|---------|
| `lwc/exportUtils/exportUtils.js` | Main module: downloadFile, copyToClipboard |
| `lwc/exportUtils/csvFormatter.js` | CSV escaping and formatting |
| `lwc/exportUtils/packageXmlGenerator.js` | Tooling→Metadata type map, XML generation |
| `lwc/exportUtils/clipboardFormats.js` | Plain text, Markdown, Mermaid formatters |
| `lwc/exportUtils/exportUtils.js-meta.xml` | LWC metadata |
| `lwc/exportMenu/exportMenu.html` | Dropdown button with export options |
| `lwc/exportMenu/exportMenu.js` | Menu event handling |
| `lwc/exportMenu/exportMenu.css` | Minimal styling |
| `lwc/exportMenu/exportMenu.js-meta.xml` | LWC metadata |
| `classes/SetupUrlResolver.cls` | Centralized URL resolution for 25+ types |
| `classes/SetupUrlResolverTest.cls` | Test coverage |

### Modified Files

| File | Change |
|------|--------|
| `DependencyService.cls` | Replace `buildSetupUrl()` with `SetupUrlResolver.resolve()`. Remove private method. |
| `BlastRadiusService.cls` | Replace `buildSetupUrl()` with `SetupUrlResolver.resolve()`. Remove private method. |
| `DataJourneyService.cls` | Replace `buildSetupUrl()` with `SetupUrlResolver.resolve()`. Remove private method. |
| `dependencyResults` LWC | Add `<c-export-menu>` component. Make component names clickable links. |
| `blastRadiusGraph` LWC | Add `<c-export-menu>` in toolbar area. |
| `dataJourneyView` LWC | Add `<c-export-menu>` component. |
| `processFlowMap` LWC | Add `<c-export-menu>` component. |
| `DependencyServiceTest.cls` | Update for refactored `buildSetupUrl` removal. |
| `BlastRadiusServiceTest.cls` | Update for refactored `buildSetupUrl` removal. |
| `DataJourneyServiceTest.cls` | Update for refactored `buildSetupUrl` removal. |

## 6. AppExchange Considerations

### No External Libraries

All export functionality is pure JavaScript:
- CSV: String concatenation + `Blob`
- XML: Template literal string building
- Clipboard: `navigator.clipboard.writeText()` + `execCommand('copy')` fallback
- File download: `Blob` + `URL.createObjectURL()` + anchor element

### Lightning Locker/LWS Compatibility

- `Blob`, `URL.createObjectURL()`, `document.createElement('a')` are all allowed
- `navigator.clipboard` may be restricted in cross-origin iframe — fallback essential
- File sizes will be well under 1MB (max ~2000 dependency rows) — no chunking needed

### Security

- No server-side file generation — no `ContentVersion` or `Attachment` records created
- All data was already loaded client-side by the initial Apex query — export just reformats in-memory data
- No data leaves the org through the export process
- `SetupUrlResolver.cls` uses `with sharing`, 75%+ test coverage

## 7. Success Metrics

| Metric | Target |
|--------|--------|
| Setup URL coverage | 25+ MetadataComponentType values mapped |
| ID-specific URLs | 18+ types link directly to the component |
| CSV export adoption | 30%+ of users who view results |
| Package.xml usage | 20%+ of developer users |
| Clipboard copy usage | 40%+ of users who view results |
| Export file accuracy | 100% match between displayed and exported data |
| Package.xml validity | Generated XML passes `sf project deploy validate` |
| Deep link accuracy | 90%+ of ID-specific URLs resolve correctly |
| Export render time | < 500ms for 500-row results |
| No regressions | All existing tests pass after `buildSetupUrl` refactor |
