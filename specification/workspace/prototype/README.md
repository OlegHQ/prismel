# Workspace study: iteration, scopes and groups

Pending proposal, 29 September 2026. Open **[index.html](index.html)** directly;
no server, build step or network is needed. It is a behavioral reference, not
product code and never a web fallback. The native editor stays PXUI on Metal.

The design is in [../iteration.md](../iteration.md), the reference programs in
[../case-studies.md](../case-studies.md), and the ambiguity register in
[../ambiguities.md](../ambiguities.md). The earlier
[report](../../../reports/Composable%20Lisp%20workspaces.md) covers contexts,
reuse and the composed shell.

## Try it

1. **Probe a loop.** In *Bloom studio*, drag across the strip of the `ring`
   zone. Every node inside shows its value at that iteration, and the viewport
   highlights that petal. Click any petal to jump to the iteration that made
   it. `[` and `]` step through iterations.
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
8. **See the code.** Select anything: the Lisp panel shows that binding with
   everything it depends on, the selection marked, and a text editor for just
   that binding.

## Files

| File | Role |
|---|---|
| `index.html` | the self-contained study (generated) |
| `model.js` | reader, canonical printer, two-pass checker and evaluator, 2D illustration kernel |
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

The preview is a 2D JavaScript illustration of the catalog's semantics, not
Prismel geometry. Loops, graph inputs and `[%workspace]` are proposals; today's
`[%flow]` accepts one graph plus `defgraph`s. Macros are binding-free value
templates only. Positions, frames and collapsed zones are session layout and
never reach the Lisp. Comments are not preserved through graph edits. The
study limits (4,096 iterations per zone, 600,000 steps, 20,000 primitives)
are demonstrative, not measured.
