# F006 — Workflow Rules in Dependency Search

Status: 💡 idea
Priority: —
Added: 2026-03-14

## Probleem / Aanleiding
Process Flow Map toont Workflow Rules in de execution order, maar de Dependency Finder scant niet op Workflow Rule references bij field searches. Een field kan gebruikt worden in een Workflow Rule field update zonder dat dit in de dependency results verschijnt.

## Gewenst resultaat
Workflow Rules die een field refereren (in criteria of field updates) verschijnen in de dependency results voor dat field.

## Notities
- WorkflowRule is een Tooling API object
- Workflow Field Updates zijn apart (`WorkflowFieldUpdate`)
- Complexiteit: M — vergelijkbaar met de Layout/FlexiPage supplementary scan
