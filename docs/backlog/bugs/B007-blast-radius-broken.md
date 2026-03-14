# B007 — Blast Radius Toont Geen Dependencies

Status: 🟢 approved
Priority: Critical
Added: 2026-03-14

## Probleem
Blast Radius toont alleen de root node met 0 edges en 0 dependents, ongeacht welk component je zoekt. De graph is altijd leeg.

## Root Cause (2 bugs)

### Bug 1: `RefMetadataComponentName` bestaat niet
`BlastRadiusService.fetchDependents()` roept `ToolingApiClient.queryDependenciesWithNameFallback()` aan die `RefMetadataComponentName` als WHERE filter gebruikt. Dit veld bestaat NIET op `MetadataComponentDependency`. Fallback niveaus 1 en 3 falen hierdoor altijd.

### Bug 2: Onondersteunde RefMetadataComponentType waarden
`normalizeTypeForRoot()` mapt 'Standard Field' → 'StandardEntity', maar `StandardEntity` is geen geldig `RefMetadataComponentType` filter in de Tooling API. Hierdoor faalt ook fallback niveau 2.

### Gevolg
Alle 4 query-niveaus falen → `fetchDependents()` retourneert lege lijst → alleen root node in graph.

## Waarom Dependency Finder WÉL werkt
Dependency Finder gebruikt per metadata type een aparte strategie:
- **Layouts** → scant Layout metadata direct (parseert JSON body)
- **Flows** → scant Flow metadata via `FlowFieldAnalyzer` (recursieve JSON walker)
- **Fields** → 4 aparte scans (EntityParticle, Schema describe, Tooling, Layout scan)
- **Apex** → combineert `MetadataComponentDependency` + body parsing

Blast Radius probeert alles via 1 query op `MetadataComponentDependency`, maar die tabel trackt Layout→Field en Flow→Field relaties niet.

## Fix

### Aanpak: Hergebruik DependencyService resultaten
In plaats van een eigen query-strategie, moet Blast Radius de bestaande `DependencyService.searchDependencies()` hergebruiken voor depth=1, en dan recursief verder bouwen.

### Stappen
1. **`BlastRadiusService.fetchDependents()`** moet `DependencyService.searchDependencies()` aanroepen i.p.v. eigen `queryDependenciesWithNameFallback()`
2. **Map DependencyRecord → ComponentRef** — vertaal de DependencyService response naar het Blast Radius graph model
3. **Recursieve traversal behouden** — voor depth > 1, roep DependencyService opnieuw aan voor elke gevonden dependent
4. **Type mapping fixen** — `normalizeTypeForRoot()` moet mappen naar de types die DependencyService verwacht ('Standard Field', 'Custom Field', etc.), niet naar Tooling API types
5. **API call budget bewaken** — DependencyService doet meerdere callouts per search, dus `MAX_API_CALLS` (50) moet mogelijk omhoog of depth default omlaag

### Alternatief (simpeler, minder diep)
Blast Radius pakt de resultaten die de Dependency Finder al heeft gevonden (doorgegeven via LWC event) en toont die als depth=1 graph. Geen eigen Apex queries. Diepere traversal later toevoegen.

## Geraakt
- `BlastRadiusService.cls` — fetchDependents() + normalizeTypeForRoot()
- `BlastRadiusController.cls` — eventueel nieuwe parameter voor cached results
- `blastRadiusGraph.js` — eventueel LWC event handling
- `docs/METADATA-ROUTES.md` — documenteer Blast Radius strategie
- Tests: `BlastRadiusServiceTest.cls`, `BlastRadiusControllerTest.cls`

## Complexiteit
L — significante refactor van BlastRadiusService, maar DependencyService doet het zware werk al

## Verificatie
1. Zoek `Standard Field > Account > Account Name` → Blast Radius moet 4 Layout nodes tonen
2. Zoek een Flow → Blast Radius moet referenced fields/objects tonen
3. Depth > 1 moet recursief dependencies van dependencies tonen
4. Graph stats (nodes, edges, max depth) moeten kloppen
