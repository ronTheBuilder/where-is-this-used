# F004 — Case-Insensitive Field Lookup

Status: 💡 idea
Priority: —
Added: 2026-03-14

## Probleem / Aanleiding
Managed package fields kunnen mixed-case API names hebben. WITU's field lookups zijn case-sensitive, wat kan leiden tot field-not-found issues.

SF Inspector en DLRS (via fflib) gebruiken beiden case-insensitive field maps.

## Gewenst resultaat
Alle field lookups in WITU zijn case-insensitive. Mixed-case managed package field names matchen correct.

## Notities
- Bron: DLRS `fflib_SObjectDescribe` (lowercase key Map)
- Aanpak: Wrap `Schema.describe().fields.getMap()` in een Map met lowercase keys
- Complexiteit: S
- Gerelateerd aan: F003
