# Iteration, scopes and groups in workspaces

**Proposal, 29 September 2026.** This extends the
[composable workspaces report](../../reports/Composable%20Lisp%20workspaces.md).
It is not the normative Flow specification: [`flow.md`](../flow.md) §11
remains the language that `[%flow]` accepts today. Nothing here changes
native code, Dune or the catalog.

The interactive study is [`prototype/index.html`](prototype/index.html). It
checks and runs every construct below and draws it in the Pxui kit. The
[case studies](case-studies.md) are the reference programs, and the
[ambiguity register](ambiguities.md) lists every decision a reader could
otherwise make two ways.

## 1. Goals

1. **Every Lisp form has exactly one drawing, and every drawing prints to
   one form.** Loops, scopes and branches are structure on the canvas, never
   hidden inside a text field unless the author put them in an argument.
2. **Iterations are visible.** A loop shows each of its iterations. Any node
   inside a loop shows its value at a chosen iteration and across all of
   them. A shape in the viewport leads back to the iteration that made it.
3. **Bounded, pure and deterministic.** There is no `while`, no recursion and
   no stateful randomness. Parallel and sequential evaluation give identical
   bytes, as `AGENTS.md` requires.
4. **Sketches stay OCaml.** A sketch embeds its workspace as a compile-time
   string. The PPX checks it, reports errors at lines inside the string, and
   exposes typed inputs to OCaml.

## 2. Language additions

### 2.1 Grammar delta

These rules are added to the workspace grammar of the report. They use the
Flow §11 conventions: keywords for parameters, positional geometry slots,
and `let*` for sharing.

```text
graph    = "(" "graph" name ":context" context [ inputs ] body ")" ;
defn     = "(" "defn"  name ":context" context inputs body ")" ;
inputs   = "[" { "(" name ":" type [ literal ] ")" } "]" ;   (* graph inputs need a default *)
expr    += for | fold | scan | sum | if | ref | "t" ;
for      = "(" "for"  "[" clause { clause } "]" body ")" ;
fold     = "(" "fold" "[" name expr "]" "[" clause { clause } "]" body ")" ;
scan     = "(" "scan" "[" name expr "]" "[" clause { clause } "]" body ")" ;
sum      = "(" "sum"  "[" clause { clause } "]" body ")" ;
clause   = name expr ;                              (* expr is a list *)
if       = "(" "if" expr expr expr ")" ;
ref      = "(" "ref" name { ":" name expr } ")" ;   (* input overrides *)
body     = "(" "let*" "[" { name expr } "]" expr ")" | expr ;
```

The new list producers are `(range n)`, `(range a b)`, `(linspace a b n)`,
`(sop/point_list g)` and `(sop/piece_list g)`. `(count xs)` reads a length.
`value/rand` is a pure hash; `value/hsv`, `value/lerp` and `value/polar` are
the value helpers the case studies use. The comparisons `< > <= >= =` and
`and`, `or` and `not` produce Bool.

### 2.2 Semantics

| Form | Meaning | Result type |
|---|---|---|
| `(for [x xs] b)` | evaluate `b` once per element of `xs`, collect in order | `list T` where `b : T` |
| `(for [x xs y ys] b)` | product, row-major, last clause fastest; `ys` may read `x` | `list T` |
| `(fold [a init] [i xs] b)` | `a := init`; per element `a := b`; return `a` | type of `init` |
| `(scan [a init] [i xs] b)` | as fold, but collect each new `a` | `list A` |
| `(sum [i xs] b)` | add `b` over the elements; empty is `0` | Int, Float or Vec3 |
| `(if c a b)` | only the taken branch runs | the type both branches share |
| `(let* [...] r)` inside an expression | a scope: names are private, only `r` leaves | type of `r` |
| `(ref g :k v)` | evaluate graph `g` with input `k` overridden; cached by input values | `g`'s context type |

**Lists and splicing.** A list is a value like any other. Variadic slots
(`sop/merge`, `scene/merge`, `ui/tile`) splice a list argument one level. No
other slot flattens. That keeps `(sop/merge ring)` a single wire while
`(for …)` stays a list, which scalar consumers reject with a type error.

**Captures.** A zone body may read any name bound outside it. Those values
are evaluated once, before the zone runs, and are the same in every
iteration. Because evaluation is pure, the compiler may hoist a loop-invariant
body node. The result is identical, so the editor can offer the same move.

**Shadowing is an error** (`E_SHADOW`), including for loop and accumulator
names. On a canvas, two nodes called `x` on either side of a zone border
would make every wire ambiguous to read.

**Randomness** comes only from `(value/rand key …)`, a pure integer hash of
its keys in `[0, 1)`. Per-iteration variation passes the index explicitly,
as in `(value/rand seed i)`, so hoisting, reordering and parallel evaluation
cannot change a result.

### 2.3 Checking

The checker has two passes, both implemented in the study's `model.js`:

1. **Static pass.** It types every definition, graph and zone body once,
   whatever the iteration count, and types both branches of every `if`.
   Arity, keywords, contexts, shadowing, recursion, fold accumulator
   agreement (`E_ACC_TYPE`), group names (`W_UNKNOWN_GROUP`, §3.7) and
   literal loop bounds are all reported here. This is what the PPX runs.
2. **Run pass.** It evaluates with records. Driven counts over the bound,
   the step budget, nonfinite math and allocation limits are reported here,
   with the zone's path in the message.

### 2.4 Bounds

The study's limits are 4,096 iterations per zone, 600,000 evaluation steps
and 20,000 primitives. Native limits must be measured, published and named
in their diagnostics (see register L3), not hidden constants. A literal
count is checked at compile time; a count that depends on an input, `t` or
geometry is checked when the program runs.

## 3. Graph representation

### 3.1 Form → drawing

| Lisp | Canvas |
|---|---|
| `name (op …)` in a `let*` | node card: title, one row per slot and keyword, footer |
| a keyword left at its default | a dimmed row; scrubbing it writes the keyword |
| a nested call in an argument | a chip, `ƒ (op …)`, whose numbers stay scrubbable |
| `name (for …)` / `fold` / `scan` / `sum` | a **zone**: a tinted region with rail, strip, body and yield |
| `name (let* …)` | a **scope**: a dashed region with a rail and a result |
| an inline loop or scope in an argument | a chip whose glyph names it: `for`, `⟲`, `Σ`, `let` |
| a symbol argument | a wire, solid for a whole argument, dashed when inside an expression |
| a loop variable, accumulator or captured name | a **rail row** on the zone's left edge |
| the zone body's result | the **yield** row on the right edge: collect, next, add, result |
| `(if c a b)` | a node with `if`, `then` and `else` rows, plus branch counts inside loops |
| group writer `:name "x"` → reader `:group "x"` | a dotted named link, `▦ x` |
| graph inputs `[(n : int 12)]` | input nodes at the left, and sliders in the navigator |

Frames (visual grouping), positions, bends and collapsed zones are layout.
They are stored with the document and never printed (Flow ambiguity rule
10).

### 3.2 Zones

The anatomy follows Blender's zones and vvvv's regions, which both use a
visible border as the scope of repetition. It adds what neither shows: the
iterations themselves.

- **Title**: the kind glyph, the binding name, the total count and the result
  type, with a collapse toggle. A list output has a *stacked* socket.
- **Strip**: one cell per iteration. Geometry cells are thumbnails, number
  cells are bars, and a `fold` shows the state after each step. Dragging
  across the strip sets the zone's **probe**. The readout names the loop
  variable's value, for example `i = 5 · 6 of 12`.
- **Rail** (left): one row per iteration clause (`i ∈ (range petals)`, with
  the count scrubbable in place), the accumulator (`shape ⟲ from frame`) and
  every captured outer name (`seed · same for all`). Outer wires end at the
  rail and inner wires start from it. Captures are derived from the body's
  free names and are never authored, so the rail cannot disagree with the
  Lisp.
- **Yield** (right): the only exit. Wiring from inside a zone to anything
  outside is refused with a reason, as in Blender.
- **Feedback**: `fold` and `scan` draw a dashed line from *next* back to the
  accumulator row, labelled `⟲ next becomes shape`.
- **Collapsed**: a stacked card that keeps the rail rows, so its wiring stays
  readable. Collapse is layout.

Nested zones probe independently. An inner zone's strip and values are those
of the inner loop *at the outer probe*.

### 3.3 Scopes and frames

A nested `let*` bound to a name is a scope. It has private names, a dashed
border, a rail of captures and a result row. From outside it is one node, and
Fold (ƒ) inlines it. A frame is only a label around nodes and prints
nothing. Register L12 lists the five box-like things and how they differ.

### 3.4 Per-iteration display

A node inside a zone shows, in its footer:

- its value at the probe, or *not run here* for an untaken branch;
- a sparkline across the innermost loop's iterations (numbers and Bool);
- `×n`, its evaluation count;
- for `if`, `then a · else b`;
- or a green **↥ same each time** when it does not depend on any loop name.
  Clicking the badge hoists the node: it moves out and runs once, with the
  identical result.

The inspector lists every iteration's value, and clicking one sets the
probe. `[` and `]` step the probe.

### 3.5 Provenance

Primitives produced by a `for` carry `(zone path, index)` tags. The tags are
provenance metadata and are never readable by the program. The viewport:

- highlights the probed iteration and dims the rest when a zone, or a node
  inside one, is selected;
- draws a `fold`'s state at the probe as a dashed overlay;
- on a click, selects the zone that made the shape and sets the probe there.
  The status line says which iteration it was.

### 3.6 Direct manipulation → Lisp

| Gesture | Rewrite |
|---|---|
| drag a number, including in a chip, a vector or a default | replace that literal; one undo step per drag |
| drag an output onto an input | set the argument to the symbol, then stable topological reorder |
| drag a loop variable onto a number `v` | `(* i v)`: the number becomes the per-iteration step |
| drag from inside a zone to outside | refused: values leave only through the yield |
| click ƒ on a chip | the argument becomes a new binding in the same scope; a loop becomes a zone |
| click ƒ on a title (single use) | inline the binding into its only use |
| **Repeat** (R) on a selection | `x_each (for [i (range 6)] body)` plus `x (sop/merge x_each)`, or `(sum …)` for numbers |
| **Iterate** (⇧R) on a selection | `x (fold [prev input] [i (range 4)] body[input := prev])` |
| click ↥ same each time | move the binding to the enclosing scope |
| Only iteration k differs | argument becomes `(if (= i k) v v)` |
| double-click inside a zone | the add palette inserts into that zone's body |
| rename in the inspector | rename the binding and every use in its scope |

A scrub inside a loop changes every iteration. The status line says so while
dragging, and the explicit per-iteration special case is the `if` above. That
is register V4.

### 3.7 Groups

Geometry groups are named selections carried on geometry. The catalog marks
a parameter as a *group writer* (`group_bounds :name`, `group_random :name`)
or a *group reader* (`blast :group`, `set_color :group`). The checker tracks
literal names written upstream on the same wire. It warns
(`W_UNKNOWN_GROUP`) when a reader names a group that nothing upstream writes,
and the graph draws a dotted named link from writer to reader. Computed group
names are open question G2.

## 4. Loops in the editor graph

The editor graph is ordinary Lisp, so it can loop too:

```lisp
sheet (ui/tile (for [s (range 4)]
                 (ui/viewport (ref scene :seed (+ s 1)))))
```

A panel made by a loop has no binding. Its header says *from a loop* and
links to the loop node. Structural panel edits (split, close, retype) happen
on the loop, and panel focus is keyed by iteration index (register E1). The
host's Restore layout stays outside the described tree.

## 5. Sketches as compile-time Lisp

```ocaml
module Bloom = [%workspace {|
(workspace bloom
  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)] …)]
      (sop/merge ring))))
|}]
(* Bloom.Flower.inputs = { petals : int; seed : int }
   Bloom.Flower.default_inputs
   Bloom.program : Prismel_workspace.Program.t *)

let () =
  Bloom.program
  |> Prismel_workspace.Program.with_inputs Bloom.Flower.{ default_inputs with petals = 16 }
  |> Prismel_editor.Workspace.run
```

- **The string is the source of truth.** There is no antiquotation (register
  O2). OCaml values enter through graph inputs, for which the PPX generates a
  typed record with defaults. The editor shows an input overridden from OCaml
  as driven.
- **Errors map to lines inside the string**, using the existing `[%flow]`
  mechanism (flow.md §12.3). Compile-time and run-time checks split as in
  §2.3.
- **One plan.** The PPX emits checked plan data, as `[%flow]` does today
  through `Flow_sop.Build.program`, and the live editor runs the same plan
  (register O4).
- **Write-back is explicit.** Edits in a running sketch change a live copy.
  Write back to main.ml rewrites only the string literal, keeps comments and
  shows a diff first; otherwise the edits persist as a document preset that
  records the manifest digest (register O1).

## 6. Mapping onto Flow

This is a plan for review, not a milestone commitment.

1. **Language.** Extend `Flow.Check` with lists, zones, `if`, graph inputs and
   `E_SHADOW`, typing zone bodies once. Keep `defgraph` compatibility. Add
   expect tests for every new code and every register rule marked as a
   proposed rule.
2. **Document.** A zone is a new instance kind in `Flow_sop.Network`: like a
   compound (§3.8), it owns a body network. It adds iteration clauses,
   accumulators and captures computed from the body. Compiled ids extend
   `Instance_path` with an iteration index (register I1).
3. **Evaluation.** Unroll zones into `Edit_graph` when the count is small and
   static; otherwise run them through a zone cook step that caches per
   `(path, index)`. Measure both approaches on the case studies before
   choosing (flow.md §15). Keep the value lane's determinism regression, and
   add a one-domain versus multi-domain check for zones.
4. **Canvas.** `pxui_graph` draws zones, rails, strips and chips as widgets
   over `Ui.box`, with no second hit-test or capture path. It emits typed
   requests (`Wrap_in_loop`, `Hoist`, `Set_probe`), and the reducer applies
   them outside `Ui.frame`.
5. **PPX.** `[%workspace]` reuses the `[%flow]` reader, manifest and
   diagnostic mapping, and generates the input records.

## 7. References

- Blender manual: [Repeat Zone](https://docs.blender.org/manual/en/latest/modeling/geometry_nodes/utilities/repeat_zone.html),
  [For Each Geometry Element Zone](https://docs.blender.org/manual/en/4.3/modeling/geometry_nodes/utilities/for_each_geometry_zone.html).
- vvvv gamma, The Gray Book: [Loops](https://thegraybook.vvvv.org/reference/language/loops.html)
  (splicers, accumulators).
- SideFX: [Looping in SOPs](https://www.sidefx.com/docs/houdini/model/looping.html).
- Grasshopper data matching: [forum discussion](https://www.grasshopper3d.com/xn/detail/2985220:Comment:666154).
- Bret Victor, [Learnable Programming](https://worrydream.com/LearnableProgramming/) (2012).
- Enso: [dual visual and textual representation](https://github.com/enso-org/enso).
