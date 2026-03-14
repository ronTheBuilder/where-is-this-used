# B009 — Flow Blast Radius Altijd Leeg in Dev Org

Status: 💡 idea
Priority: Low
Added: 2026-03-14

## Observatie
Flow Blast Radius toont alleen de root node met 0 edges. Dit is technisch correct — in een dev org refereert niets naar de flow. Maar het is verwarrend voor de gebruiker.

## Achtergrond
De Blast Radius zoekt "wie refereert naar MIJ?" (downstream). Voor flows in een dev org is dat antwoord bijna altijd: niemand. In productie-orgs met subflows, Apex die flows aanroept, of process builders die flows triggeren, zou dit wél resultaten geven.

## Mogelijke Verbeteringen
1. **UX: Melding tonen** als Blast Radius 0 edges heeft → "No other components reference this flow. In production orgs with subflows or Apex invocations, you would see connections here."
2. **Bi-directioneel**: Optioneel ook tonen wat de flow zelf referereert (upstream dependencies) — welke velden, objects, Apex classes de flow aanroept. Dit is eigenlijk het inverse van Dependency Finder.
3. **Combinatie view**: Root node + wat de flow gebruikt + wie de flow aanroept.

## Complexiteit
M — UX melding is simpel, bi-directioneel is significant

## Niet-blokkerend
Dit is geen bug maar een UX verbetering. Blast Radius werkt correct.
