# F001 — EntityParticle Field Enrichment

Status: ✅ done
Priority: —
Added: 2026-03-13
Completed: 2026-03-13

## Probleem / Aanleiding
`Schema.describeSObjects()` retourneert niet alle fields voor managed package objecten. Protected fields in managed packages worden niet getoond in de field picker.

## Gewenst resultaat
Field picker toont ALLE fields inclusief managed package protected fields.

## Implementatie
- `DependencyService.getFieldsViaTooling()` — Tooling API `EntityParticle` query
- `MetadataPickerController.getFieldsEnriched()` — merged Schema + EntityParticle resultaten, dedupliceert op API name
- `metadataPicker.js` — switched naar `getFieldsEnriched` import

## Geraakt
- DependencyService.cls
- MetadataPickerController.cls
- metadataPicker.js
- DependencyServiceTest.cls

## Commit
`24fbebe` — feat: EntityParticle field enrichment and Composite API batching
