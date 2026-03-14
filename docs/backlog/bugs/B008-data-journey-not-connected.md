# B008 — Data Journey Toont Altijd 0 Nodes

Status: 📋 ready
Priority: High
Added: 2026-03-14

## Probleem
Data Journey tab toont altijd "0 nodes, 0 links" ongeacht welke search je doet op de Dependency Finder tab.

## Root Cause
`dependencyFinder.html` rendert `<c-data-journey-view>` zonder `object-name` of `field-name` props:
```html
<c-data-journey-view></c-data-journey-view>
```

Het component verwacht die via `@api` setters die `tryLoadJourney()` triggeren. Zonder props is `hasValidInput` altijd `false` → nooit een API call → altijd leeg.

## Fix
Pass de geselecteerde object + field door vanuit de Dependency Finder state:
```html
<c-data-journey-view
    object-name={selectedObject}
    field-name={selectedComponent}>
</c-data-journey-view>
```

Voorwaarde: Data Journey is alleen relevant voor Standard Field en Custom Field types (niet voor Flow, Apex, etc.). Conditie toevoegen of een melding tonen voor niet-ondersteunde types.

## Geraakt
- `force-app/main/default/lwc/dependencyFinder/dependencyFinder.html`
- `force-app/main/default/lwc/dependencyFinder/dependencyFinder.js` (state tracking)
- Mogelijk `dataJourneyView.js` (error handling voor ongeldige input)

## Complexiteit
S — simpele prop-doorgave

## Verificatie
1. Zoek Standard Field > Account > BillingStreet
2. Klik Data Journey tab
3. Moet nodes + links tonen voor het BillingStreet field journey
