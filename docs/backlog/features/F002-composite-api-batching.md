# F002 — Composite API Batching

Status: ✅ done
Priority: —
Added: 2026-03-13
Completed: 2026-03-13

## Probleem / Aanleiding
WITU maakt 3+ losse Tooling API callouts per dependency search. Composite API kan tot 25 subrequests bundelen in 1 callout, wat governor limits spaart.

## Gewenst resultaat
Batch meerdere Tooling queries in één HTTP callout via `/tooling/composite`.

## Implementatie
- `ToolingApiClient.compositeToolingQueries(Map<String,String> labeledQueries)` — POST naar Composite endpoint
- Per-label response parsing met fout-tolerantie (failed subrequests → empty response, niet exception)

## Geraakt
- ToolingApiClient.cls
- ToolingApiClientTest.cls

## Commit
`24fbebe` — feat: EntityParticle field enrichment and Composite API batching
