# F007 — Apex Trigger Content Analysis

Status: 💡 idea
Priority: —
Added: 2026-03-14

## Probleem / Aanleiding
WITU toont Apex Triggers als dependencies, maar analyseert niet WELKE fields ze refereren. Voor Flow metadata doen we dit wel (via FlowFieldAnalyzer), maar voor triggers niet.

## Gewenst resultaat
Bij een field dependency search worden Apex Triggers die dat field lezen of schrijven getoond met access type (Read/Write/Read+Write), vergelijkbaar met hoe we dat voor Flows doen.

## Notities
- Tooling API `ApexTrigger` heeft een `Body` field met de volledige source code
- Regex/token parsing op Apex source is fragiel maar beter dan niets
- Alternatief: Symbol Table API (maar die is beperkt en niet altijd beschikbaar)
- Complexiteit: L — Apex parsing is significant complexer dan Flow JSON walking
- Risico: false positives bij string matching in comments/strings
