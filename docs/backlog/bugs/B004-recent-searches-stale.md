# B004 — Recent Searches Stale Data on Fast Clicks

Status: ✅ done
Priority: —
Added: 2026-03-12
Fixed: 2026-03-13

## Probleem
Bij snel klikken tussen recente searches kon stale data getoond worden — de response van een eerdere klik overschreef de nieuwere.

## Root Cause
Geen request-guard bij imperative Apex calls. Meerdere `searchDependencies()` calls konden parallel lopen.

## Fix
- Stale-request guard toegevoegd (request ID tracking)
- Betere localStorage key (type+object+component)
- Verbose pill labels

## Commit
`bb6e8cb` — fix: dropdown alignment, click handling, recent searches, managed package support
