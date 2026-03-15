# WITU Backlog

Feature-driven backlog voor Where Is This Used.

## Workflow

```
💡 idea → 📋 spec ready → 🟢 approved → 🔨 in progress → 🧪 testing → ✅ done
                                                                        ❌ rejected
```

| Status | Wie | Betekenis |
|--------|-----|-----------|
| 💡 idea | Simon | Nieuw idee, nog geen spec |
| 📋 spec ready | Buurman | Spec geschreven, klaar voor review |
| 🟢 approved | Simon | Goedgekeurd, mag gebouwd worden |
| 🔨 in progress | Buurman | Wordt aan gewerkt |
| 🧪 testing | Buurman | Gebouwd, wordt getest |
| ✅ done | — | Afgerond en gedeployed |
| ❌ rejected | Simon | Niet doen |

## Structuur

```
docs/backlog/
├── BACKLOG.md            # Master overzicht (features + bugs tabel)
├── README.md             # Dit bestand
├── witu-backlog          # CLI tool (bash)
├── features/
│   ├── F001-entity-particle-enrichment.md
│   ├── F002-composite-api-batching.md
│   └── ...
└── bugs/
    ├── B001-layout-fullname-query.md
    ├── B002-flow-picker-managed.md
    └── ...
```

## CLI Tool

`witu-backlog` is een bash-script om snel door de backlog te navigeren.

### Installatie

Het script staat in `docs/backlog/witu-backlog`. Optioneel symlink naar je PATH:

```bash
ln -sf $(pwd)/docs/backlog/witu-backlog ~/bin/witu-backlog
```

### Gebruik

```bash
witu-backlog                      # alles tonen
witu-backlog open                 # alleen open items
witu-backlog features             # alleen features
witu-backlog bugs open            # open bugs
witu-backlog search "managed"     # zoek op keyword
witu-backlog show F003            # toon volledige spec
witu-backlog done                 # afgesloten items
witu-backlog help                 # help
```

### Output

Items zijn color-coded op status:
- 🟢 Groen = done
- 🟡 Geel = in progress / testing
- 🔵 Blauw = spec ready / approved
- ⬜ Grijs = idea
- 🔴 Rood = rejected

## Nieuw item toevoegen

1. Maak een bestand in `features/` of `bugs/` met het juiste ID-prefix (F-nummer of B-nummer)
2. Gebruik het template:

```markdown
# F008 — Titel van de feature

**Status:** 💡 idea
**Prioriteit:** —
**Aangemaakt:** YYYY-MM-DD

## Context

Waarom is dit nodig?

## Spec

Wat moet er precies gebeuren?

## Acceptatiecriteria

- [ ] Criterium 1
- [ ] Criterium 2

## Notities

Eventuele extra context.
```

3. Voeg een rij toe aan de tabel in `BACKLOG.md`
