# F005 — Platform Cache voor Global Describe

Status: 💡 idea
Priority: —
Added: 2026-03-14

## Probleem / Aanleiding
Elke page load herhaalt `Schema.getGlobalDescribe()` en flow/label queries. Bij orgs met 1000+ objecten kost dit tijd en CPU.

## Gewenst resultaat
Veelgebruikte metadata (object lijst, flow lijst, label lijst) wordt gecachet in Salesforce Platform Cache met een configureerbare TTL.

## Notities
- SF Inspector cachet in-memory per sessie, DLRS cachet niet
- Platform Cache (Org partition) is de SF-native oplossing
- Let op: cache invalidation bij nieuwe deploys/objecten
- Complexiteit: M
- Vereist: Platform Cache partition setup in de org
