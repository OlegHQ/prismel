# Iteration, functions, data and macros in workspaces

**§2 and §7 are normative for the workspace language as of W1, 30 September
2026** (`Flow.Syntax`, `Flow.Lisp`, `Flow.Macro`, `Flow.Workspace` and
`Flow.Eval` implement them; the study's `prototype/check.cjs` is ported to
`lib/flow/test_workspace*.ml`). §1 and §3–§6 remain proposals. This extends the
[composable workspaces report](../../reports/Composable%20Lisp%20workspaces.md).
[`flow.md`](../flow.md) §11 remains the language that `[%flow]` accepts today.
The language core adds no native code, Dune rule or catalog change.

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
4. **A sketch is a `.rays` file.** `sketches/<name>/sketch.rays` holds one
   workspace with no OCaml wrapper. `dune build` checks it, reports errors at
   lines in the file, and links a native program. The running editor saves
   back to the file and reloads it when it changes on disk.
5. **Time is live, structure is not.** `t` drives parameters and recooks only
   the nodes that depend on it. Loop counts and shape choices never depend
   on `t`.

## 2. Language additions

### 2.1 Grammar delta

These rules are added to the workspace grammar of the report. They use the
Flow §11 conventions: keywords for parameters, positional geometry slots,
and `let*` for sharing. The `material` context returns a typed material value
from `material/standard`; a SOP assigns it through `sop/material` and a
material graph reference. Group assignment and renderer behavior are specified
in [materials.md](materials.md).

```text
graph    = "(" "graph" name ":context" context [ inputs ] body ")" ;
defn     = "(" "defn"  name ":context" context inputs body ")" ;
inputs   = "[" { "(" name ":" type [ literal ] ")" } "]" ;   (* graph inputs need a default *)
expr    += for | fold | scan | sum | if | ref | "t" ;
for      = "(" "for"  "[" clause { clause } "]" [ skip ] body ")" ;
fold     = "(" "fold" "[" name expr "]" "[" clause { clause } "]" body ")" ;
scan     = "(" "scan" "[" name expr "]" "[" clause { clause } "]" body ")" ;
sum      = "(" "sum"  "[" clause { clause } "]" body ")" ;
clause   = name expr ;                              (* expr is a list *)
skip     = ":skip" "[" { int | "[" int { int } "]" } "]" ;   (* for, scene/merge: iteration tuples left out *)
if       = "(" "if" expr expr expr ")" ;
ref      = "(" "ref" name { ":" name expr } ")" ;   (* input overrides *)
body     = "(" "let*" "[" { name expr } "]" expr ")" | expr ;
```

The new list producers are `(range n)`, `(range a b)`, `(linspace a b n)`,
`(sop/point_list g)` and `(sop/piece_list g)`. `(count xs)` reads a length.
`value/rand` is a pure hash; `value/hsv`, `value/lerp` and `value/polar` are
the value helpers the case studies use. The comparisons `< > <= >= =` and
`and`, `or` and `not` produce Bool. Numbers convert on their own: an Int
reaching a Float input is widened, and a Float reaching an Int input (a
SOP keyword, `range`, `nth`, a typed parameter) rounds half away from
zero. `floor`, `ceil`, `round` and `int` (truncation toward zero) make the
conversion explicit and give an Int; `float` gives a Float.

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

**Skipping** (`:skip`, register L16). `(for [x xs …] :skip tuples body)` leaves out the iterations whose
*iteration tuple* is listed, and `(scene/merge a b … :skip tuples)` leaves out the arguments at the listed
tuples. A tuple is the running index of each enclosing loop, outermost first (the same tuple records,
probes and compiled ids use), then the index inside this form: for a `for` the row-major running index of its
clause product, for a `scene/merge` the position of the argument as written. A tuple of one may be written as
a bare integer, so `:skip [0 3]` is `:skip [[0] [3]]` for a top-level loop. The list is a static literal of
non-negative integers (`E_SKIP` otherwise), so it never depends on `t` and cannot raise `E_TIME_COUNT`; only
`for` and `scene/merge` have it (`sum`, `fold` and `scan` are `E_ZONE`), and a `for` over the elements of
geometry has none. A skipped iteration is not evaluated, makes no plan node and is absent from the result list;
the others keep their index, so their compiled ids, per-tuple cache keys and provenance do not move. The loop
variables are still recorded at a skipped iteration, so a selector counts it and a node inside shows
`not run here`. A scene sync writes it: deleting a loop-made object adds to a `:skip`, never rewrites the
collection (register V4).

**Shadowing is an error** (`E_SHADOW`), including for loop and accumulator
names. On a canvas, two nodes called `x` on either side of a zone border
would make every wire ambiguous to read.

**Randomness** comes only from `(value/rand key …)`, a pure integer hash of
its keys in `[0, 1)`. Per-iteration variation passes the index explicitly,
as in `(value/rand seed i)`, so hoisting, reordering and parallel evaluation
cannot change a result.

**The hash, bit for bit** (`Flow.Eval.hash`; the study's `hash`). All
arithmetic is on 32-bit integers, kept unsigned:

```text
h := 0x9e3779b9
for each key x (Int, Float or Bool, read as a double; Bool is 0 or 1):
  k := ToInt32(floor(x * 1000003.0))   (* JS ToInt32: NaN and infinities give 0,
                                          otherwise truncate and reduce mod 2^32 *)
  h := imul(h xor k, 0x85ebca6b)        (* low 32 bits of the product *)
  h := h xor (h >>> 13)                 (* logical shift *)
  h := imul(h, 0xc2b2ae35)
  h := h xor (h >>> 16)
result := float(h mod 1000000) / 1000000.0
```

No keys give `0.435769`; other vectors: `(value/rand 0)` is `0.009611`,
`(value/rand 3 4 5)` is `0.706664`, `(value/rand 1.5 -2)` is `0.622571`,
`(value/rand 1 2 3 4 5 6)` is `0.659002`. A key beyond 2^53 loses its low
bits before the floor, on every platform alike, because the product is a
double.

**Formatting** (`str`, register C2). An int prints as its digits. A float
prints as `toFixed(4)` with trailing zeros and a trailing point removed, and
`-0` prints as `0`; an exact tie at the fifth decimal rounds away from zero
(`0.03125` is `0.0313`). A vec3 prints `[x y z]` with the same rule per
component, a list `[a b]`, a record `{:a 1 :b 2}` in written order.

### 2.3 Checking

The checker has two passes, both implemented in the study's `model.js`:

1. **Static pass.** It types every definition, graph and zone body once,
   whatever the iteration count, and types both branches of every `if`.
   Arity, keywords, contexts, shadowing, recursion, fold accumulator
   agreement (`E_ACC_TYPE`), group names (`W_UNKNOWN_GROUP`, §3.7) and
   literal loop bounds are all reported here. This is what `rays-plisp check` runs at build time.
2. **Run pass.** `Flow.Eval` evaluates everything that is not geometry, in
   order, on IEEE doubles. Geometry calls become a plan (see `eval.mli`), so
   nothing here cooks. These are reported here, each with its code and the
   path of the zone or term in the message:

   | Code | When |
   |---|---|
   | `E_ITER_BOUND` | a `range`, `linspace` or `concat` past 4,096, or a zone running more than 4,096 iterations, with a count that was not a literal |
   | `E_EVAL_BUDGET` | more than 600,000 evaluation steps |
   | `E_LIST_RANGE` | `first`, `last` or `nth` outside the list |
   | `E_PATTERN` | a pattern longer than a driven list |
   | `E_NONFINITE` | a scalar result that is NaN or infinite (`pow`, `*`) |
   | `E_RANGE` | `ui/tile` holds 1–16 panels; a computed split axis, ratio or settings value out of range |
   | `E_DEPTH` | more than 64 nested calls |

   Division and `mod` by zero give 0 and `sqrt` takes the absolute value, as
   in the study.

   `t` is not known to the static run: a term that depends on it is kept as
   a *residual* (the term with its environment) and evaluated by
   `Flow.Eval.residual_eval` for a given time (register T1; W2b).

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
| `name (for …)` / `fold` / `scan` / `sum` | a **zone**: a tinted region with rail, iteration selector, body and yield |
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
- **Iteration selector**: `‹`, a slider and `›`, with ticks when there are
  48 iterations or fewer. It sets the zone's **probe**; arrow keys, Home and
  End work when it has focus. The readout names the loop variable's value,
  for example `i = 5 · 6 of 12`. For `fold` it selects the state after each
  step, for a λ zone the call. It deliberately shows no thumbnails: the
  viewport is where results are seen, and it highlights the probed
  iteration.
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

Nested zones probe independently. An inner zone's selector and values are those
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

**Loop-made objects (normative).** The copies of a loop that makes scene objects are instances of one
template. Editing a copy in the viewport, list or inspector edits the template: a literal argument (or a
literal component of a vector) is written once and every copy changes, and the status says so; an argument
the loop computes from its variable is refused with its expression, and `=(expression)` typed in the row
replaces it. Renaming writes the template's `:name`. Deleting a copy is exact at any nesting depth, for any
number of clauses, and when a copy makes several objects (register L16): the iteration that made it is added
to the `:skip` list of its loop (the outermost iteration all of whose objects go, when there is one), or, when
the iteration makes other objects that stay, the object's place is added to the `:skip` of the `scene/merge`
that holds it. Nothing else is rewritten: every other copy keeps its iteration tuple, so its id, cache key and
provenance are unchanged. Repeated deletes accumulate in one list, and a loop whose copies are all deleted stays
a loop that makes nothing.

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
links to the loop node. Retyping edits its template. Splitting, closing or docking
one copy into another split is refused; its disclosure and floating bounds can
change independently. Panel focus is keyed by iteration index (register E1). The
host's Restore layout stays outside the described tree.

### Named layouts

A workspace's layouts are one editor graph with a switch:

```lisp
(graph editor :context editor
  (let* [preview (ui/viewport (ref scene))
         network (ui/graph)
         inspector (ui/inspector)
         code (ui/lisp)
         build (ui/split-at "horizontal" 0.4 preview
                 (ui/split-at "horizontal" 0.62 network inspector))
         write (ui/split-at "horizontal" 0.46 preview
                 (ui/split-at "vertical" 0.5 network code))
         look preview]
    (ui/workspace (ui/switch build write look :active 0))))
```

`(ui/switch panel... :active n)` evaluates to its `n`th panel (0-based, in text); it can sit at the
root of the workspace or inside a split, where it swaps one column. The panels are shared bindings,
so a viewport keeps its orbit and the text pane its draft across layouts. A layout has no stored
name: `Editor_core.Panels.label` reads it from its tree. A leaf is its panel word (`View`, `Graph`,
`List`, `Lisp`, `Inspector`, `Outline`, `Timeline`); side by side joins with `|`, stacked with `/`
(which binds tighter, so only a row inside a stack is bracketed); same-axis nesting flattens;
neighbours of one name collapse to `×n` (a tile of four viewports is `View ×4`); floating windows
come last after `+`. Layouts that read the same add their largest panel and its share
(`View | Graph · Graph 70%`), and any that still match get a number.

- Inspector: `:active` is a choice whose labels are the computed names.
- Graph pane: one input row per layout, labelled with its name. The active wire is solid and
  accented, the others dashed grey; a click on a row switches.
- Keys (`Space [`): the first switch's layouts as `0`..`9` (name, `(active)` mark), `Space [ 0..9`
  switches, `Space [ n` adds a copy of the current layout and activates it (a document without a
  switch gets one around its tree; ten layouts at most), `Space [ x` removes the current one (the
  last stays). A switch is `Flow_edit.Set_layout`, history label "Layout"; repeats within 1.5
  seconds merge into one entry. These edits address the first switch of the layout: one at the root
of the workspace, or nested in its splits, tiles and floats (bound to a name or written in place),
so a switch that swaps one column is edited where it is.
- Windows: `Space n` plus a kind letter of `Space l` (`g l t i u m w`) wraps the active layout in a
  split whose second side is `(ui/floating ...)` (`Layout_window`); `Space o f` floats the focused
  docked panel or docks the focused window beside the rest (`Layout_float`). Both rewrite only the
  active layout; the splits it names are copied into one expression, its panels stay shared.
  Window bounds are `(layout (panel ... :window [x y w h]))`. There are no OS windows.

An older file with several `:context editor` graphs and `(layout (editor "studio"))` still
loads: the selected graph is the shell and `Space [` lists the graphs by name (`Select_layout`,
one undo entry). It is not rewritten on load (that would mark an untouched file changed). The first
`Space [ n` there migrates it in one undo entry, "Merge layouts" (`Flow_edit.Merge_layouts`): the
other editor graphs join the selected graph's switch (made around its tree when it has none) as
layouts, in file order, each graph's bindings renamed `graph_name` so they cannot clash, the graphs
are removed and the selected-layout key of `(layout ...)` is cleared; then the new copy is made as
usual. Ten layouts at most. There is no top bar any more, so the layouts menu is `Space [`, the
palette and the switch node itself, which all read the same switch.

### Panel arrangement

The dotted header handle undocks and moves a panel. Drop at a docked panel's
edge to create a split; the header menu's Dock returns a floating panel to its
original place. Window mode floats inside the editor. The lower-right handle
resizes it, and the disclosure chevron collapses or expands its body. One drag
is one undo entry. Splitter ratios, docking syntax, disclosure and window bounds
save with the selected layout, including leader-key visibility changes.

```lisp
(layout
  (editor "studio")
  (panel ["studio" "network"] :collapsed false :window [500 80 620 450]))
```

A workspace without an editor graph writes its current shell on the first panel
edit. Floating viewports share the shell's UI paint order and hit tree.

Layout has one codec, `Layout_by_path`. Its active readers are:

| Saved field | Reader / behavior |
|---|---|
| `editor` | `Workspace_doc.editor_graph` selects the authored shell. |
| `panels` | `Core.panel_state` supplies disclosure and floating bounds to shell geometry. |
| `at`, `collapsed`, `frames` | `Core.sync_scope` supplies Scope positions, zone disclosure and canvas frames. |
| `display` | `Core.sync_scope` marks the displayed binding; `Core.display_node` selects its geometry. |
| `pinned`, `rows`, `bends`, `wireless` | Preserved and remapped by the codec; the current Scope pane has no reader for these legacy fields. |

Scope movement/frame sizing, shell splitters and floating-window movement keep
their held-drag offsets in pane/chrome state. Release emits one document edit;
one undo restores the previous placement. Parameter scrubs instead apply while
held and coalesce into one history gesture.

Each viewport has its own free orbit and scene membership, including lights
and camera objects drawn as guides. The render controller remains shared:
ACTIVE resolves only among primary scene cameras, so look-through and PNG
export use that camera and its lens/settings even while a comparison panel is
focused. Comparison camera declarations retain their authored values and do
not select or replace the primary render camera. The primary World, its day
cycle and map gestures are also shared across views; `ui/viewport` does not
declare an independent World. Editing a comparison ref leaves that World's
baked output and the primary render camera unchanged. Independent authored
per-view render-camera/World controllers would require an explicit API extension.

## 5. Sketches as `.rays` files

```lisp
; sketches/bloom/sketch.rays: the only authored file
(workspace bloom
  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)] …)]
      (sop/merge ring))))
```

- **The build.**
  - `sketches/dune` includes a generated `dune.rays.inc`, which
    `rays-plisp dune sketches` writes.
  - `runtest` diffs the include, and `dune promote` accepts a new sketch.
  - For each sketch the include has a `subdir` stanza: a rule running
    `rays-plisp ml sketch.rays` to produce `main.ml`, an executable, and
    a `smoke-all` run.
  - There is no custom dune stanza and no per-sketch `dune` file. Plan W11
    has the full text.
- **Errors at their line.** `rays-plisp check` prints `File "…/sketch.rays",
  line L, characters A-B:` diagnostics, the OCaml compiler's format, so dune
  and editors jump to them (register O3). Warnings are errors.
- **One plan.** The generated `main.ml` embeds the verbatim source and its
  digest, and calls `Rays_editor.Workspace.main`. That re-parses the
  source at startup and runs the same plan the live editor edits (register
  O4).
- **The file is the source** (register O1).
  - Save rewrites `sketch.rays` atomically with the comment-preserving
    printer, if its digest still matches the build.
  - Otherwise edits are saved as a document preset (an s-expression: the
    same text plus layout and settings).
  - Changes to the file on disk reload the running sketch as one history
    entry. Probes and layout are kept by path id.
- **OCaml hosts.**
  - There is no antiquotation (register O2).
  - A host program calls `Workspace.load` on a `.rays` and overrides graph
    inputs with `Workspace_program.with_inputs`.
  - The editor shows an overridden input as driven from OCaml.
  - A `[%workspace]` PPX with generated input records is deferred until a
    host needs it.

## 5a. Live values and realtime recooking

- **Liveness** (register T1). A term is live when it mentions `t` or depends
  on a live binding, capture, accumulator, `ref` override, graph or
  function. Live nodes show **◷ t**. While playing, they and their
  downstream nodes recook every frame, and every other node stays cached.
  `t` is reserved.
- **Fixed structure** (T2, T3).
  - `E_TIME_COUNT`: a loop count, collection or geometry list length
    depends on `t`.
  - `E_TIME_BRANCH`: a live test chooses between geometry arms.
  - Live choices between values are parameters and are allowed. One
    lowering serves every frame.
- **Realtime** (T4). Each frame, live parameters are re-evaluated and only
  changed ones are applied. Then comes an incremental compile and a
  latest-request background cook.
  - A slow cook shows the last finished result and never blocks.
  - Fixed-step runs and exports wait for each frame and are deterministic.
  - Live nodes keep one cache slot, so they never evict static entries.
- **Drags are live edits.** Scrubbing a value recooks the affected cone and
  commits one history entry on release.
- **Case study.** The [Orrery](case-studies.md#orrery). Plan W2b has the
  implementation.

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
4. **Canvas.** `pxui_graph` draws zones, rails, iteration selectors and chips as widgets
   over `Ui.box`, with no second hit-test or capture path. It emits typed
   requests (`Wrap_in_loop`, `Hoist`, `Set_probe`), and the reducer applies
   them outside `Ui.frame`.
5. **Build.** `.rays` files compile through a small `rays-plisp` tool
   and generated dune rules (§5). `[%flow]` remains for OCaml sketches.

## 7. Functions, data, branches and macros

This section extends §2–§3 with the rest of the language a sketch needs.
The rules are in the [register](ambiguities.md) (F, D, C, M and N items). All
of them are implemented in the study, and `prototype/check.cjs` covers each.

### 7.1 Grammar delta

```text
expr    += fn | list | record | cond | case | str | hof | access | quasi ;
fn       = "(" "fn" "[" { pattern | "(" name ":" type ")" } "]" body ")" ;
pattern  = name | "[" { pattern } "]" | "{" ":keys" "[" { name } "]" "}" ;
list     = "(" "list" { expr } ")" ;                   (* homogeneous *)
record   = "{" { ":" name expr } "}" | "(" "values" { ":" name expr } ")" ;
access   = name "." name { "." name } | "(" "get" expr ":" name ")" ;
cond     = "(" "cond" { expr expr } ":else" expr ")" ;
case     = "(" "case" expr { literal expr } ":else" expr ")" ;
hof      = "(" ( "map" | "filter" | "reduce" | "sort-by" ) expr { expr } ")" ;
type    += "fn" | "(" "list" type ")" | "{" { ":" name type } "}" ;
macro    = "(" "defmacro" name "[" { name } [ "&" name ] "]" template ")" ;
template = "`" form ;       (* ~p fills a hole, ~@rest splices, x# is fresh *)
meta     = "^:bypass" form ;
```

List operations are `first last rest nth reverse take drop concat count`.
Destructuring works wherever a name is bound: `let*`, loop clauses and `fn`
parameters.

### 7.2 Semantics that shape the editor

- **Functions are non-escaping values** (F1). A `fn` may be bound, passed to a
  higher-order form or a defn parameter of type `fn`, and called. It can't be
  returned, stored or carried through `ref` or `fold`. Every program keeps one
  finite graph, and recursion stays impossible.
- **A function is a loop over its calls** (F3). Each call pushes an
  iteration frame `(function, call index)`. Records, probes, sparklines and
  viewport provenance therefore work for functions exactly as for loops.
- **map zips** (F4) and **for multiplies** (L2), so the two forms never
  overlap. Nothing broadcasts implicitly (D1).
- **Records are structural** (D2). `values` is a record, so several results
  and several outputs are the same thing.
- **Branches are exhaustive** (C1), and `str` formats deterministically (C2),
  which makes computed group names reproducible (G2).
- **Macros are hygienic declarative templates** (M1). A hole may be a name
  chosen by the caller (M2), which is what makes `radial` usable. The
  expansion is a read-only view (M3).
- **Comments attach to the next binding by name** (N1), and `^:bypass` is
  the only metadata (N2).

### 7.3 Drawing and gestures

| Construct | Canvas | Direct manipulation → Lisp |
|---|---|---|
| `name (fn [a b] …)` | hollow λ zone; the rail lists parameters and captures; the selector steps through every call; the output socket is a diamond | **L** on a selection: outside inputs become parameters, and the selection becomes the first call |
| `(map f xs)` and other higher-order forms | a card with a diamond `f` row; filter shows `kept a of b` | wire a λ output, a defn or an operator into `f`; an inline `fn` is a chip that ƒ lifts into a zone |
| `(list …)` | one row per item with its index; a stacked socket | scrub; ↑ moves an item up; + appends, continuing a numeric step; a wire dropped on + appends a symbol |
| records and `values` | one output row per field under the card | + field takes `name value`; dragging from a field row writes `r.field` |
| destructuring | a *split* card with one output row per name | every name is wireable |
| `cond` / `case` | when/then rows with a required else | scrub and wire each arm |
| `str` | a row per part; the result in the footer | + adds a text part; a wire makes a part |
| macro call | ◆ card; rows are holes; a binder hole is a pill; ⤵ opens a lens with steps from call to full expansion | **M** on a selection turns chosen literals into holes and inner names into `x#`; *Replace call with expansion* inlines it |
| `; note` | a note row on the node | type in the inspector (**N**) |
| `^:bypass` | a B flag and a striped title | click B, or press **B** |

### 7.4 Why these designs

A research pass and three competing mockups per problem converged on one
principle: add nothing that doesn't extend the existing zone, chip, row and
socket vocabulary. The precedents we adopted, and what each costs elsewhere:

- **λ zones** follow Blender 5 closure zones and Snap! rings. We avoid Snap!'s
  implicit parameters and Blender's name-matched sockets.
- **Calls as iterations** turn Excel's per-element spill of `MAP` into the
  loop's iteration selector that already exists.
- **Field rows** borrow Unreal's split struct pins, without the lock-out on
  recombining.
- **The expansion lens** is DrRacket's macro stepper, driven by the same probe
  gesture as loops.
- **Hole punching** follows Figma component properties: a hole is a
  per-instance override.
- **The list fill** is the spreadsheet fill handle.

Deferred ideas, recorded so they aren't lost:
- *spill a list wire* into a floating strip;
- *override for this call*, which evolves a template from a ghost edit;
- *livelit rows*, macro-declared widgets for holes;
- *bypass preview*, ghost sparklines before committing.

## 8. Editor consistency contract (2 October 2026)

These are implementation requirements for the current editor. The detailed
audit and remaining gaps are in [consistency-audit.md](consistency-audit.md).

- Authored source, layout and sketch settings install as one checked document.
  A derived scene/World/settings edit reconciles through its source home before
  entering history. A refusal preserves the installed document.
- Document Lisp and whole-document copy serialize saved metadata as well as
  graphs. An absent metadata form keeps its supplied fallback; explicit settings
  start from schema defaults, and an explicit empty layout clears layout. A full
  preset starts with default settings, independently of the running session.
- Text applies before cook submission. Asynchronous rendering may retain a
  successful previous cook; an awaited update renders the applied document.
- Geometry, lights and camera bookkeeping resolve the same viewport instance.
  An empty override is distinct from a missing override. Focused previews remain
  focused when the UI is hidden; renderer caches key by viewport identity.
- Inspector ownership is independent of the navigation level. Composition
  invalidation includes the actual scene, level and viewport membership.
  Named SOP handle selection, transforms and argument edits also resolve the
  compiled node's owner. Viewport framing works without a graph pane and uses
  only the focused scene instance's bounds; an empty instance has no frame target.
- Unique named viewport bindings key their orbit/render slots by editor graph
  and binding name. Reordering and docking keep those keys; docking introduces
  a split wrapper without renaming either panel. Renaming changes the authored
  key. Inline, looped, or repeated uses of the same binding use placement keys;
  their transient state may reset when rearranged. No additional persistence
  format is introduced.
- Each lowered viewport retains its panel origin, authored scene ref where
  available, and evaluated instance in `Document.shell.preview_sources`.
  Derived auxiliary objects remain read-only: their inspector explains the
  source-edit route, and shared reconciliation refuses write-back with the
  viewport identity. Editing ref overrides remains the authored route.

Light `:intensity` and `:color` retain residual expressions and resolve at the
editor timeline's `t` during composition, including independent preview
overrides. The saved document stays at its checked source-derived state;
object/panel identities, SOP networks and prepared geometry stay unchanged.
Only recorded live fields are evaluated, using their checked port descriptors;
one resolved scene is cached by authored scene/drives/time. Non-finite or other
evaluation failures retain that light's last successful values while healthy
siblings advance, and report `E_CONTEXT_LIVE` with object/view/field attribution;
recovery clears the error.
Intensity/color keep the schema's ordinary hard-bound normalization.

Other time-dependent fields in scene, World, settings, editor and material structs are refused
when installing the document or reading startup configuration, with
`E_CONTEXT_TIME` naming the graph and field. They are not silently evaluated at
zero. Live SOP/value drives remain supported, including a scene's reference to
time-driven geometry. Startup window settings and the cook seed are captured
when the host starts; their built-in inspector labels say “on restart.” The
selected live fields do not change the window or its captured cook seed.

## 9. References

- Blender manual: [Repeat Zone](https://docs.blender.org/manual/en/latest/modeling/geometry_nodes/utilities/repeat_zone.html),
  [For Each Geometry Element Zone](https://docs.blender.org/manual/en/4.3/modeling/geometry_nodes/utilities/for_each_geometry_zone.html).
- vvvv gamma, The Gray Book: [Loops](https://thegraybook.vvvv.org/reference/language/loops.html)
  (splicers, accumulators).
- SideFX: [Looping in SOPs](https://www.sidefx.com/docs/houdini/model/looping.html).
- Grasshopper data matching: [forum discussion](https://www.grasshopper3d.com/xn/detail/2985220:Comment:666154).
- Bret Victor, [Learnable Programming](https://worrydream.com/LearnableProgramming/) (2012).
- Enso: [dual visual and textual representation](https://github.com/enso-org/enso).
