# B003 — Combobox Dropdown Misalignment + Click Handling

Status: ✅ done
Priority: —
Added: 2026-03-12
Fixed: 2026-03-13

## Probleem
- Dropdown picker stond niet direct onder de combobox input
- Klikken op een dropdown optie registreerde niet (dropdown sloot voordat selectie werd verwerkt)

## Root Cause
- `onclick` handler op opties werd overschreven door de document `click` handler die de dropdown sloot
- Shadow DOM `composedPath()` werd niet gebruikt voor buiten-klik detectie

## Fix
- `onclick` → `onmousedown` op opties + `event.stopPropagation()`
- `composedPath()` voor Shadow DOM buiten-klik detectie
- `MAX_VISIBLE` verhoogd van 200 → 500

## Commits
`b12faab` — fix: combobox click handling, dropdown alignment, and picker limits
`bb6e8cb` — fix: dropdown alignment, click handling, recent searches, managed package support
