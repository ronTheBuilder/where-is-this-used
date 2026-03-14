# B001 — Layout FullName Query Causes Silent Failure

Status: ✅ done
Priority: —
Added: 2026-03-12
Fixed: 2026-03-13

## Probleem
`findLayoutsUsingField()` in DependencyService.cls queried `SELECT Id, Name, FullName FROM Layout`. Het `FullName` field veroorzaakt een `FIELD_INTEGRITY_EXCEPTION` in de Tooling API, die silently gecatcht werd → 0 layout resultaten.

## Root Cause
`FullName` is een compound field op het Layout Tooling object dat niet altijd queryable is. De supplementary scan wrappte alles in een single try-catch die alle errors swallowde.

## Fix
- `FullName` verwijderd uit de Layout query
- Betere error logging toegevoegd

## Commit
`c279056` — fix: layout detection and flow picker for managed packages
