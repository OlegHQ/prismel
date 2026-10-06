# Workspace study: iteration, functions, data and macros

Implemented in Rays; this study remains the behavioural reference. Written 29 September 2026. Open **[index.html](index.html)** directly;
no server, build step or network is needed. It is a behavioral reference, not
product code and never a web fallback. The native editor stays PXUI on Metal.

The design is in [../iteration.md](../iteration.md), the reference programs in
[../case-studies.md](../case-studies.md), and the ambiguity register in
[../ambiguities.md](../ambiguities.md).

## Try it

1. **Probe a loop.** In *Bloom studio*, use the `ring` zone's iteration
   selector (‹, slider, ›). Every node inside shows its value at that
   iteration, and the 3D viewport highlights that petal. Click any petal to
   jump to the iteration that made it; drag to orbit, scroll to zoom.
2. **Scrub.** Drag any number: a literal, a number inside an `ƒ` chip, a vector
   component, or a dimmed default (which writes the keyword). Inside a loop,
   the change applies to every iteration.
3. **Unfold and fold.** In *Square wave*, `y` holds a `Σ` chip. Click its ƒ and
   it becomes a sum zone inside the `for` zone. The ƒ on the zone's title
   folds it back.
4. **Make a loop.** Select `heart` in Bloom and press **R** (Repeat). Then drag
   from the new zone's `i` onto `radius`, which writes `(* i 0.16)`. **⇧R**
   (Iterate) wraps a selection in `fold`.
5. **Hoist.** In *Sunflower*, `turn` carries **↥ same each time**. Click it to
   move the node out of the loop; the output is unchanged.
6. **Groups and scopes.** *Facade* draws `▦ attic` and `▦ lit` links from group
   writers to readers. `marked` is a named `let*` scope.
7. **Loops in the shell.** *Variations* builds four viewports with a `for` in
   the editor graph.
8. **Functions.** In *Garland*, `bead` is a λ zone: its selector steps through
   every call it received. Click a bead in the viewport to find its call. Select
   `total` and press **L** to turn it into a local function.
9. **Records and lists.** In *Kit of parts*, `window` returns `values`, so
   `big` and `small` show one output row per field; drag from a field row.
   Extend `widths` with + (it continues the step) and reorder with ↑.
10. **Macros.** In *Rosette*, press ⤵ on `outer` and step through the
   expansion. Select `soft` and press **M** to make a macro; click B to
   bypass a node, or type a note in the inspector.
11. **Live values.** In *Orrery*, nodes that depend on `t` show **◷ t**.
   Press Play in the viewport: the header counts the live and cached nodes
   and shows the cook time. Make a loop count depend on `t` to see
   `E_TIME_COUNT`.
12. **Sketch files.** Each gallery card's **.rays file** button shows the case
   as the file dune would compile, with its generated stanza.
13. **See the code.** Select anything: the Lisp panel shows that binding with
   everything it depends on, the selection marked, and a text editor for just
   that binding.

## Files

| File | Role |
|---|---|
| `index.html` | the self-contained study (generated) |
| `model.js` | reader, canonical printer, two-pass checker and evaluator, small 3D illustration kernel (faces, lines, points) |
| `cases.js` | the case-study workspaces (source of `../case-studies.md`) |
| `register.js` | the ambiguity register (source of `../ambiguities.md`) |
| `src/` | page markup, styles and editor code |
| `build.cjs` | assembles `index.html` from the above |
| `check.cjs` | model checks, Node standard library only |

```sh
node specification/workspace/prototype/check.cjs
node specification/workspace/prototype/build.cjs   # after editing src/ or the model
```

## Limits

The preview is a small 3D JavaScript renderer (painter's algorithm) illustrating
the catalog's semantics, not Rays geometry or Metal. The language core (loops, functions, records, hygienic macros, graph inputs, `ref`
and `t`) is implemented in `lib/flow` (`Syntax`, `Lisp`, `Macro`, `Workspace`,
`Eval`) and `check.cjs` is ported to `lib/flow/test_workspace*.ml`; `model.js`
remains the behavioral reference. Live values (`t`) and `.rays` sketches are
implemented too. Where the study and `lib/flow` differ, the code and `../ambiguities.md` are
current (the study reads no exponent in a number, for one; the register's status line names
the entries corrected after the study). Positions, frames and collapsed zones are layout and
never reach the workspace form. Comments attach to the next binding and survive graph edits. The
study limits (4,096 iterations per zone, 600,000 steps) are constants of `Flow.Workspace`
and `Flow.Eval`; 20,000 primitives exists only in the study.
