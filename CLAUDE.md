# Where Is This Used? — Project Instructions

## What This Is

An open-source Salesforce app (free on AppExchange) that answers **"where is this used?"** for metadata types that Salesforce's native UI doesn't support — especially standard fields, flows/subflows, record types, and more.

This fills a major gap: Salesforce's built-in "Where is this used?" button only works for custom fields and misses most metadata types. There's strong IdeaExchange demand for this.

## Project Status

- **Phase**: Pre-development — architecture decided, design mockup complete, PRD not yet written
- **Next step**: Create PRD in `docs/`, then begin building

## Key Documents

- `docs/discussion.md` — Full landscape research, API analysis, competitive analysis, open questions (all resolved)
- `docs/design-mockup.html` — Interactive HTML mockup of the UI (open in browser to view)

## Decided Architecture

### Delivery Format
- **Native Salesforce app** (LWC + Apex) distributed as a **managed package** on AppExchange (free)
- Source code open on GitHub (MIT license)

### Technical Stack
- **Frontend**: Lightning Web Components (LWC)
- **Backend**: Apex controllers + service layer
- **Data source**: Tooling API `MetadataComponentDependency` (queried via Apex HTTP callout)
- **Auth**: Named Credential → Tooling API (requires one-time admin setup via a setup wizard)
- **API Version**: 65.0

### Core Architecture Pattern
```
LWC UI (thin) → Apex @AuraEnabled Controller → DependencyService → Tooling API callout
```

- `DependencyService` is the ONLY class that touches the Tooling API — everything else goes through it
- This makes the data source swappable if the API changes
- Real-time queries (no caching/indexing for v1)

### Package Structure
```
force-app/main/default/
├── classes/
│   ├── DependencyService.cls          ← core: queries MetadataComponentDependency via Tooling API
│   ├── DependencyController.cls       ← @AuraEnabled methods for LWC
│   ├── MetadataPickerController.cls   ← powers object/field/flow/class pickers
│   ├── FlowParsingService.cls         ← supplemental: parses Flow metadata for subflow refs
│   └── *Test.cls
├── lwc/
│   ├── dependencyFinder/              ← main container component
│   ├── metadataPicker/                ← type → object → field picker
│   ├── dependencyResults/             ← results display (accordion + badges)
│   └── setupWizard/                   ← Named Credential setup guide
├── tabs/
│   └── Where_Is_This_Used.tab
├── flexipages/
│   └── Where_Is_This_Used_Page.flexipage
├── permissionsets/
│   └── Where_Is_This_Used_User.permissionset
└── applications/
    └── Where_Is_This_Used.app
```

### v1 Scope (Metadata Types)
1. **Standard Fields** — the #1 gap, use MetadataComponentDependency
2. **Custom Fields** — same approach, with Read/Write badges for Apex
3. **Flows** — "where is this flow used as a subflow?" (requires Flow metadata parsing)
4. **Apex Classes** — which components reference this class

### Key API Details

**MetadataComponentDependency** (Tooling API, Beta but stable since Summer '18):
- 9 fields: MetadataComponentId/Name/Type/Namespace + RefMetadataComponentId/Name/Type/Namespace + Id
- Query: `SELECT ... FROM MetadataComponentDependency WHERE RefMetadataComponentName = 'Account.Industry'`
- Limits: 2,000 rows per Tooling API query, 100K via Bulk API 2.0
- Blind spots: Reports excluded, Flow→Flow (subflow) refs not tracked, inconsistent for some types
- Subflow workaround: Query FlowVersionView, retrieve Flow metadata, parse for `<subflow>` elements

**Auth constraint**: `UserInfo.getSessionId()` does NOT work from Lightning context. Must use Named Credential (Connected App + Auth Provider + Named Credential). The setup wizard LWC walks admins through this.

### API Fallback Strategy
If Salesforce ever kills MetadataComponentDependency, the fallback is brute-force metadata parsing (query all Apex bodies, Flow metadata, VF markup, etc. and search for references). This is 100x more API calls and would need async processing. The `DependencyService` abstraction is designed so only that one class would need to change.

## Design Decisions Made

| Decision | Choice | Rationale |
|---|---|---|
| Build new vs contribute to HappySoup | Build new | Native SF app (LWC) vs HappySoup's external web app |
| Auth approach | Named Credential + setup wizard | Safest for AppExchange security review |
| Data strategy | Real-time queries | Simpler for v1, no storage overhead |
| Metadata picker UX | Type-first picker | Extensible, clear what's supported per type |
| API blind spots | API + targeted Flow parsing | Best coverage without over-engineering |

## Existing Landscape (for context)

- **HappySoup.io** / sfdc-soup — MIT, free web app, last active ~2023, good but external-only
- **forcedotcom/dependencies-cli** — Archived May 2025, dead
- **Salto** — Commercial, paid, does this well but not open source
- **afawcett/dependencies-sample** — Reference for which API relationships actually work

## Development Guidelines

- Follow SLDS design patterns — the app should feel native to Salesforce
- AppExchange security review requirements: CRUD/FLS checks, no SOQL injection, no hardcoded credentials, proper sharing (`with sharing` keyword)
- All Apex must have test classes with 75%+ coverage (AppExchange requirement)
- Use `@AuraEnabled(cacheable=true)` where appropriate for read-only methods
- The Named Credential name used in callouts: `WITU_ToolingAPI`
