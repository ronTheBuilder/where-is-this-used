# B002 — Flow Picker Excludes Managed/Installed Flows

Status: ✅ done
Priority: —
Added: 2026-03-12
Fixed: 2026-03-13

## Probleem
Flow picker was leeg in orgs waar alle flows managed/installed zijn. `FlowVersionView WHERE Status = 'Active'` excluded managed flows. `@AuraEnabled(cacheable=true)` cachete het lege resultaat.

## Root Cause
- `FlowVersionView` query miste managed flows
- Caching van lege resultaten
- Alle 40 flows in de test org waren Managed-Installed

## Fix
- Flow query aangepast om managed flows te includeren
- `@AuraEnabled(cacheable=true)` verwijderd van flow methods (callout-incompatibel)
- 5-level fallback chain in ToolingApiClient verbeterd

## Commit
`c279056` — fix: layout detection and flow picker for managed packages
