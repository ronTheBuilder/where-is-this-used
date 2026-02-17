# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Where Is This Used? (WITU)** — A free, open-source Salesforce app (LWC + Apex) that provides dependency analysis for metadata types Salesforce's native "Where is this used?" doesn't support. Distributed as a managed package on AppExchange, source on GitHub (MIT).

## Common Commands

### Deploy to org (specific components only)
```bash
# Individual components
sf project deploy start -m "ApexClass:DependencyService" -m "ApexClass:DependencyController"

# Entire directory
sf project deploy start -d force-app/main/default/classes
```

### Run tests
```bash
# All tests
sf apex run test --code-coverage --result-format human

# Single test class
sf apex run test --class-names DependencyServiceTest --result-format human

# Single test method
sf apex run test --tests DependencyServiceTest.testSearchDependencies --result-format human
```

### Validate deployment (dry run)
```bash
sf project deploy start -d force-app --dry-run --test-level RunLocalTests
```

## Architecture

### Core Data Flow
```
LWC UI → Apex @AuraEnabled Controller → Service Layer → Tooling API (via Named Credential)
```

All Tooling API access goes through a single Named Credential: `callout:WITU_ToolingAPI`. The API endpoint base path is `/services/data/v65.0/tooling`.

### Feature Modules

The app has four distinct features, each following the same Controller → Service pattern:

| Feature | Controller | Service | LWC | Purpose |
|---|---|---|---|---|
| **Dependency Finder** | `DependencyController` | `DependencyService` | `dependencyFinder`, `metadataPicker`, `dependencyResults` | Core "where is this used?" query |
| **Blast Radius** | `BlastRadiusController` | `BlastRadiusService` | `blastRadiusGraph` | Recursive dependency graph traversal |
| **Data Journey** | `DataJourneyController` | `DataJourneyService` | `dataJourneyView` | Traces field read/write chains across automations |
| **Process Flow Map** | `ProcessFlowController` | `ProcessFlowService` | `processFlowMap` | Shows automation execution order for an object |

Supporting classes:
- `FlowFieldAnalyzer` — Parses Flow metadata JSON to extract field reads, writes, and subflow calls. Used by `DataJourneyService` and `DependencyService`.
- `MetadataPickerController` — Powers object/field/flow/class picker dropdowns. Uses `Schema.getGlobalDescribe()` for objects/fields, delegates to `DependencyService` for flows and Apex classes.

### Key Patterns

**Tooling API querying**: Each service class has its own `queryToolingRecords()`, `sendGet()`, and `resolveEndpoint()` methods (duplicated across services, not shared). All use the same `callout:WITU_ToolingAPI` Named Credential and the same HTTP callout pattern.

**Client-side filtering**: `RefMetadataComponentName` is not filterable in `WHERE` clauses on all orgs. The pattern is: query by `RefMetadataComponentType` only, then filter by name in Apex. This applies in `DependencyService`, `BlastRadiusService`, and `DataJourneyService`.

**Security gate**: Every service enforces `FeatureManagement.checkPermission('WITU_Access')` before any operation. The custom permission is included in the `Where_Is_This_Used_User` permission set.

**Input validation**: Component names are validated against `Pattern.compile('^[a-zA-Z][a-zA-Z0-9_.]*$')` with max length 255.

**Test pattern**: Tests use `HttpCalloutMock` implementations as inner classes. Example: `Test.setMock(HttpCalloutMock.class, new ControllerMock())`.

### LWC Structure

- `dependencyFinder` — Main container with tab navigation (Finder, Setup, Blast Radius)
- `metadataPicker` — Type-first metadata picker (Standard Field, Custom Field, Flow, Apex Class)
- `dependencyResults` — Accordion results display with badges
- `blastRadiusGraph` — SVG-rendered dependency graph (uses `lwc:dom="manual"` for SVG manipulation)
- `dataJourneyView` — SVG-rendered upstream/downstream field data flow
- `processFlowMap` — Automation execution order timeline
- `setupWizard` — Named Credential setup walkthrough

### API Details

**MetadataComponentDependency** (Tooling API): 2,000 row limit per query. Key fields: `MetadataComponentId/Name/Type/Namespace` + `RefMetadataComponentId/Name/Type/Namespace`.

**Subflow detection**: Tooling API doesn't track Flow→Flow (subflow) references. Workaround: query `FlowVersionView` for active flows, retrieve each flow's `/sobjects/Flow/{id}` metadata, parse for `flowName` keys.

**API version**: 65.0 (set in `sfdx-project.json` and hardcoded in service classes).

## Development Guidelines

- All Apex classes use `with sharing`
- AppExchange security review: CRUD/FLS checks required, no SOQL injection, 75%+ test coverage
- Use `@AuraEnabled(cacheable=true)` for read-only methods
- Follow SLDS design patterns
- SVG in LWC requires `lwc:dom="manual"` — cannot use template binding for SVG elements

## Key Documents

- `docs/prd.md` — Product Requirements Document
- `docs/delivered/setup-guide.md` — Named Credential setup (External Client App approach)
- `docs/delivered/discussion.md` — Architecture decisions and API research
- `docs/delivered/design-mockup.html` — Interactive UI mockup (open in browser)
