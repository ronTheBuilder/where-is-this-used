# F003 — Field Name Canonicalization

Status: 💡 idea
Priority: —
Added: 2026-03-14

## Probleem / Aanleiding
WITU normaliseert component names niet voordat ze naar `MetadataComponentDependency` worden gestuurd. Als een gebruiker "accountname" intypt in plaats van "AccountName", kan de dependency query missen.

DLRS lost dit op door `getDescribe().getName()` te gebruiken om field names te canonicaliseren op het moment van opslaan.

## Gewenst resultaat
Input component names worden genormaliseerd naar de canonieke API name voordat de dependency search wordt uitgevoerd. Case-mismatches veroorzaken geen stille misses meer.

## Notities
- Bron: DLRS pattern (`updateDescribableFieldNames()` in `RollupSummaries.cls`)
- Impactanalyse: `DependencyService.searchDependencies()` entry point
- Complexiteit: S
