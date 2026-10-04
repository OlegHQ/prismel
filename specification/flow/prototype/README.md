# Rays Flow prototype

A browser page that behaves like the target SOP network editor. It is the
behavioral reference for `specification/flow.md`; the implementation plan is
`specification/flow-migration.md`.

This is a design artifact, not product code:

- Dune does not build it, nothing links it, and it is never a browser or web
  fallback for Rays (the root `AGENTS.md` rule stands).
- Open `index.html` directly in a browser (`open specification/flow/prototype/index.html`).
  No server, no build step, no network access needed; without network the
  prose falls back from IBM Plex to system fonts. The kit face (Departure
  Mono) is embedded in `font.css`.
- When the prototype and `flow.md` disagree, `flow.md` wins. Fix the
  prototype only to remove such a divergence, in the same change as the spec.

## Files

| File | Contents |
|---|---|
| `index.html` | The page: mini editor shell (graph/list/text pane, view, inspector), demos, proposal text, `[%flow]` checker UI |
| `engine.js` | Everything with behavior: node kinds, evaluation, exposure rule, levels, keys, hints, fold/unfold, compounds, printer, reader and checker (`window.Flow`) |
| `font.css` | Departure Mono as a data URI (OFL; source `assets/fonts/`) |

## Where to look in `engine.js`

| Behavior | Function or table | Spec section |
|---|---|---|
| Node kinds, ports, folders, primaries | `K`, `F`/`I`/`V3` | §3, §5 |
| Exposure rule (which rows a card shows) | `shownOnCard`, `rowsOf` | §5 |
| Levels and zoom caps | `lodOf`, `RANK` | §6.4 |
| Port positions, stubs, polylines | `portXY`, `edgePts` | §6.2–6.3 |
| Keys and the leader | `KEYS`, `LEADER` | §7.2 |
| Guide strip and tooltips | `guideKeys`, `describe` | §10 |
| Letter hints | `hintTargets`, `hintKey` | §7.5 |
| Tab contexts and `.` repeat | `openSearch`, `addNode`, `repeatAdd` | §7.3–7.4 |
| Fold and unfold | `fold`, `unfold` | §7.7 |
| Group, enter, export | `group`, `enter`, `exportKey` | §7.8 |
| Evaluation (value lane stand-in) | `evalGraph` | §13 |
| Canonical printer | `toLispLines` | §11.7 |
| Reader and checker (`[%flow]` stand-in) | `readSexp`, `compileFlow` | §11, §12 |
| List view rows | `listRows` | §8.2 |

## Known divergences (the spec is authoritative)

- The catalog is a toy (Grid, Sphere, Noise Displace, Swirl, Transform,
  Merge, Output). Real SOPs come from `Sop_catalog.Editor.factories`.
- Vectors are stored as arrays; the implementation groups three float fields
  with `[@sop.vec3]` (§5.3).
- No strings, booleans or choices in the language; the spec has them (§11.2).
- Edges carry ids; the implementation keys every edge by its destination port
  (§3.6).
- JavaScript `Math.round` differs from OCaml `Float.round` on negative halves.
- Undo snapshots the whole page model as JSON; the implementation uses
  `Editor_core.History` with gesture keys (§4.3).
- Detail-level changes are not undo entries in the prototype; they are in the
  implementation (§4.3).
- Compound instances copy their definition; the implementation shares one
  definition per name (§3.8).
