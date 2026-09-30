# Workspace migration plan

**Status: implemented (W0-W12, gaps closed in W13), 30 September 2026. Deviations are summarised in
`specification/flow-migration.md` "Workspace" and `progress.md`, which also lists what is
not fully done.** Original text: plan of record for review, 30 September 2026. This turns the workspace
proposal ([iteration.md](iteration.md), [ambiguities.md](ambiguities.md),
[case-studies.md](case-studies.md), the [study](prototype/index.html)) into
native Prismel code. It is written for an implementer, human or Codex, to
execute milestone by milestone. Every milestone lists what to **reuse**,
the **minimum to build**, what is **skipped** and when to add it, the
**files and signatures**, the **tests**, and a **done when** gate.

The plan follows the *ponytail* discipline. Every design choice climbs the
same ladder:

1. Do we need it?
2. Does the codebase already have it?
3. Does the standard library have it?
4. Does the platform have it?
5. Does an installed dependency have it?
6. Can it be one line?
7. Only then, the minimum code.

Deliberate corners are marked `ponytail:` with their ceiling and upgrade
path.

Normative rules still apply: `AGENTS.md`, the nested `AGENTS.md` files,
`specification/flow.md` and the dependency gate. Where this plan changes a
contract, the milestone names the spec section to update.

---

## 0. Where we start (surveyed 30 September 2026)

### 0.1 What exists and is reused

| Area | Existing piece | Reuse for |
|---|---|---|
| Reader | `Flow.Sexp.parse : string -> (t list, Diagnostic.t) result`, with `node = Atom \| List \| Vector \| Meta`, spans and positions (`lib/flow/sexp.mli`) | base of the workspace reader |
| Checker | `Flow.Check.check : catalog -> string -> program option * Diagnostic.t list`, plus the catalog from the manifest (`catalog_of_manifest`), kind resolution, keyword and slot checking, range checks and edit-distance hints (`lib/flow/check.ml`, 825 lines) | calls to catalog kinds inside the new checker, unchanged |
| Diagnostics | `Flow.Diagnostic.t = {code; severity; position; message; span}` | every new error, as string codes like today |
| Field expressions | `Flow.Expr.t = Num \| Time \| Op` and the infix/s-expression parser | drives that depend on `t` (unchanged) |
| Network | `Flow_sop.Network.t` (geometry `Edit_graph`, value graph, drives, instances) | the cooked form of each graph after lowering |
| Compounds | `Flow_sop.Compile.flatten`, `Instance_path.t = int list`, persisted `compiled_ids` (`flow.md` §13.3) | per-(path, iteration) ids when loops are unrolled |
| Build | `Flow_sop.Build.program`, which turns a checked term into a `Network` | the lowering back end |
| Printer | `Flow_sop.Print.network` with `binding_lines` | the text view only; deleted with it in W12 |
| Bypass | `^:bypass` → `Check.call.bypass` → `Edit.set_bypass` → print, plus `Edit_graph.set_bypass` | as is |
| Value lane | `Flow_sop.Value_lane.resolve ~time` (scalar drives, per-frame) | `t`-driven parameters |
| Cooking | `Procedural.Session`, `Async_cook` (latest-request rule, bounded cache, `Parallel.run`) | unchanged, except the cache capacity (W2) |
| Editor loop | `Core.update` → `Shell.frame` → `Doc.apply` reducer → `History.record ~label`, intents only (`lib/prismel_editor`) | every new gesture is an intent reduced once per frame |
| Graph pane | `Pxui_graph` tiles, rows, wires, BVH hit tests, `automatic_layout`, the ƒ fold/unfold rows, `with_applied` | nodes and rows; zones are added on top |
| Shell | `Pxui_shell.Layout` (fixed three columns), `Tree`, `Inspector.flow_fields`, `Prompt` | W10 replaces only the layout |
| Presets | `Editor_document.Preset` (JSON), `Editor_core.Store` | s-expression `.plisp` files (W3); no JSON, no older format |
| PPX | `ppx_prismel` `[%flow]`: reads the manifest, maps spans to OCaml locations, emits `Build.program` | kept for OCaml sketches; `.plisp` files replace it for pure sketches (W11) |
| Generated-file flow | `flow_manifest.sexp` and `api_stable.json`: a rule regenerates, `runtest` diffs, `dune promote` accepts | `sketches/dune.plisp.inc` (W11) |
| Groups | `Pdk.Group`, `Group_ops.valid_group_name`, `find_group` | computed group names are plain text |
| Provenance ids | scatter/point_generate write point `id` | stable point iteration (W8) |

### 0.2 Gaps the surveys found (must be fixed or designed around)

1. **Structure.** One `graph` per file (`E_ONE_GRAPH`), and `Program.t` holds
   one network. There is no workspace root.
2. **Types.** `Flow.Port_type.t = Geometry | Float | Int | Bool | Vec3` is
   the only type. There are no list, record, function or text value types.
3. **Reader.**
   - Comments are dropped (`sexp.ml` l.49–51).
   - There are no `{}` maps and no quote, backquote or unquote.
   - Vectors must have 3 elements.
4. **Rendering and cooking.**
   - `Pdk.Mesh_merge.merge` fails unless all inputs have identical attributes
     and groups (`mesh_merge.ml` l.81–120). Loops that group per iteration,
     like the Facade case, cannot merge today.
   - The catalog's `sop/merge` has fixed slots `a b c`, although
     `Sop.merge : Node.t list -> Node.t` is variadic.
   - There is no per-primitive provenance, no triangle-to-primitive map in
     `Pdk_prismel.to_mesh`, and no ids on `Scene3` nodes. Viewport picking
     only handles camera markers.
5. **Catalog mismatches with the proposal.**
   - `sop/set_color` has integer `red green blue alpha` fields and no `group`
     field.
   - `sop/transform` uses `rotate`, while generators use `rotation`.
6. **Editor.**
   - The text view is read-only (`core.ml` `text_pane`).
   - The text view builds its catalog with version 1 instead of
     `Manifest.version`, which is a small bug.
7. **Shell.** `Pxui_shell.Layout` is a hard-coded three-column record keyed
   by `column` all through Core.
8. **Cooking and ids.**
   - The session cache holds 32 entries, so unrolled loops would evict
     themselves.
   - Cache keys include `Node.id`, so every iteration needs its own compiled
     id.
9. **Build does not re-check.** `Build.program` only compares digests,
   although the spec says it re-checks.

### 0.3 The one architectural decision

**The authored syntax becomes the document; networks are derived.**
- Today the `Network` is the truth and the text is printed from it.
- Loops, functions, macros, records and comments cannot be represented as a
  flat network plus overlay without inventing a second language inside the
  network.
- Therefore: `Document` stores a `Flow.Syntax.t` (the reader's tree plus
  notes, metadata and stable form ids).
- Every gesture is a syntax rewrite.
- `Check` plus lowering produce the `Network.t` values that cook.
- Layout is keyed by *path ids* (`graph/binding/inner`), not node ints.

This matches the report's "store authored syntax … derive typed IR and
execution plans" and the study's architecture, which is proven there with
52 register rules.

`ponytail:` we do not build an id-preserving diff from free text to the
old network (the survey's "id-preserving reconciliation"). The syntax *is*
the document, so the ids are path ids and survive text edits by
construction, except renames, which rewrite layout keys in the same
transaction (register I1).

---

## 1. Milestone map

```text
W0  fixes & catalog prerequisites ─┐
W1  language core (flow)           ├─► W2 lowering & cooking ─► W2b live t ─┬─► W3 document v4 + history ─┬─► W4 graph pane zones ─┬─► W5 probes & footers ─► W6 viewport provenance
                                   │                                        │                             ├─► W7 text editing       └─► W8 geometry-driven loops
                                   │                                        │                             └─► W9 macros UI, notes
                                   └────────────────────────────────────────┴─► W11 .plisp sketches + dune (needs W1, W2, W2b)
W10 contexts & composable shell (needs W3, W4)                    W12 migration & removal (last)
```

| Milestone | Size | Libraries touched | User-visible result |
|---|---|---|---|
| W0 | S | pdk, sop_catalog, prismel_editor | loops can merge grouped pieces; set_color takes a colour and a group |
| W1 | L | flow | the full language checks and prints, tested on the 12 case studies |
| W2 | L | flow, flow_sop, procedural | workspaces cook; loops are unrolled deterministically |
| W2b | M | flow, flow_sop, procedural, prismel_editor | `t` animates in real time: live nodes recook each frame, static nodes stay cached; `E_TIME_COUNT`, `E_TIME_BRANCH` |
| W3 | M | editor_document, prismel_editor, editor_core | the editor opens and saves workspaces (s-expression preset) |
| W4 | L | pxui_graph, prismel_editor | zones, rails, iteration selectors, λ zones, chips and output rows in the graph |
| W5 | M | flow, prismel_editor, pxui_graph | values per iteration, sparklines, branch counts, invariant badges |
| W6 | M | pdk, pdk_prismel, prismel_editor | clicking a shape selects the node and iteration that made it |
| W7 | M | pxui, pxui_shell, prismel_editor | editable, selection-scoped Lisp with atomic apply |
| W8 | M | procedural, flow_sop | `for` over points and pieces, cached per (path, index) |
| W9 | S | prismel_editor, pxui_graph | macro lens and make-macro, notes, bypass flag |
| W10 | L | flow, editor_document, pxui_shell, prismel_editor | scene/world/settings graphs; the editor shell is an editor graph |
| W11 | M | tools/plisp, flow_sop, prismel_editor | `sketches/<name>/sketch.plisp` compiled by dune, errors at `.plisp` lines, Save and live reload on the file |
| W12 | S | sketches, examples, specs | everything migrated; the old single-graph path removed |

One milestone is one PR, or several if it has sub-steps. Merge only on the
green pre-commit loop:

```sh
dune build @all && dune runtest && dune build @smoke && git diff --check
```

---

## 2. Milestones

### W0 — Prerequisite fixes (small, independent)

**Reuse.** The existing pdk merge, the catalog PPX attributes and
`Manifest` promotion.

**Build.**
1. **`Pdk.Mesh_merge.merge` accepts inputs whose group sets differ.**
   - A group missing from one input becomes an empty group of that owner in
     its section. The rule is a union of group names, with order as first
     seen.
   - Attributes still must match, except a new `~pad_groups:true` default.
   - Detail attributes keep their explicit policy.
   - File: `lib/pdk/mesh/mesh_merge.ml` (+ `.mli` doc).
   - Test: merge three boxes carrying groups `floor_0`, `floor_1`,
     `floor_2`. Every result group has the right membership bitset.
   - Bench: `tools/bench_*` merge, before and after, recorded in the PR
     (`lib/pdk/AGENTS.md` requires numbers).
2. **`sop/merge` accepts any number of inputs.** W2 lowers every merge to
   one internal `flow.merge_n` node (`Sop.merge` already takes a list). The
   rest slot (`Rest of string` in `Edit_graph.input_requirement`, manifest
   `(slot "input" rest)`, and the `+ input` row of `Pxui_graph`) moves to W4.
3. **`sop/set_color` gets a `group` text field and a `color` vec3 group.**
   - `color_r color_g color_b` are floats 0–1 with `[@sop.vec3 "color"]`;
     `alpha` becomes a float.
   - Files: `lib/sop_catalog/attributes.ml` (the Set_color record) and
     `Sop.set_color ?group`.
   - `ponytail:` a hex text parameter is not added. `value/hsv` and vec3
     literals cover colour, and a hex literal can be a later reader feature.
4. **Text view uses `Manifest.version`** (`core.ml` `printed_level`),
   replacing `version:1`. This is a one-line fix.
5. **`sop/transform :rotate` and generators' `:rotation`.** Do nothing. It
   is a catalog naming difference, not a bug. Record it in
   `case-studies.md` and add aliases only if users complain.

**Tests.**
- `lib/pdk/mesh/test_mesh_merge*`
- `test/test_sop_catalog.ml`: manifest round trip and set_color defaults
- the 1-domain vs N-domain merge byte test

**Done when** the checks pass, the manifest is promoted, and `api_stable.json`
is promoted if `.mli` files changed.

---

### W1 — Language core in `lib/flow`

The goal is that every construct in the study is read, expanded, checked
and printed in OCaml. There is no cooking yet. This is the largest
milestone. It ports `prototype/model.js` (about 1,000 lines of JS) into
OCaml modules one-to-one.

**Reuse.**
- `Flow.Sexp` as the tokenizer base.
- `Check.catalog`, `kind_call`, `resolve` and `validate_parameter` for
  catalog calls.
- `Diagnostic`, `Symbol.valid_name` and `Expr`.

**New modules** (all in `flow`, no new dependencies; the gate forbids UI
and geometry imports):

| Module | Port of (model.js) | Role |
|---|---|---|
| `Flow.Syntax` | `read`, notes/meta, `clone` | authored tree: `type t = {id : int; node : node; span; notes : string list; meta : string list}` where `node = Sym \| Kw \| Num of string \| Str \| List \| Vec \| Map \| Quote of quote_kind * t`. The id is stable per form. |
| `Flow.Ty` | `parseType`, `formatType`, `fits`, `joinT`, `hasFn`, `coerce` | `type t = Geometry \| Float \| Int \| Bool \| Vec3 \| Text \| List of t \| Record of (string * t) list \| Fn \| Any` plus the context types `Scene \| World \| Settings \| Panel \| Editor` |
| `Flow.Macro` | `checkMacro`, `expandOnce`, `expand`, `macroParams` | hygienic quasiquote expansion with limits |
| `Flow.Workspace` | `compile` (static pass) | checker: resolves, types and validates a workspace, producing the typed IR |
| `Flow.Lisp` | `pp`, `print`, `printMarked` | canonical printer with notes, `^:bypass` and marked spans for selection |
| `Flow.Eval` | `ev` (run pass) for value-only terms | pure evaluator for numbers, vec3, text, lists, records and fn: the partial evaluator used by W2 lowering |

**`Flow.Syntax` details.**
- `parse : string -> (t list, Diagnostic.t) result`.
- Keep `Sexp`'s span and position code; add:
  - comments collected as notes on the next form;
  - `{` `}` read as `Map`;
  - `` ` ``, `~`, `~@` and `'` read as `Quote`;
  - vectors of any length, so a 3-element vector is still vec3 by type,
    not by syntax;
  - `2.0` kept as a float spelling.
- `Sexp` stays for `[%flow]` until W12, then becomes an alias.
- `ponytail:` notes attach to the next form only (register N1). A trailing
  comment on the same line is also treated as a leading comment of the
  next form. Add same-line attachment only if round-trip complaints appear.

**`Flow.Workspace` IR** (what W2 lowers):
```ocaml
type path = string list                        (* graph/binding/inner, stable *)
type term = { path : path option; ty : Ty.t; node : node; form : Syntax.t }
and node =
  | Lit of Param.value | Vec of term list | Text of string
  | Ref_binding of string * string list         (* name.field.field *)
  | Call of { kind : string; args : (string * term) list; bypass : bool } (* catalog *)
  | Call_fn of { fn : string; args : term list }                           (* defn or local fn *)
  | Graph_ref of { graph : string; inputs : (string * term) list }
  | Let of (pattern * term) list * term
  | Loop of { kind : [`For | `Fold | `Scan | `Sum]; accs : (pattern * term) list;
              clauses : (pattern * term) list; body : term; zone : path }
  | If of term * term * term | Cond of (term * term) list * term | Case of term * (Syntax.t * term) list * term
  | Fn of { params : (pattern * Ty.t option) list; body : term; zone : path }
  | Hof of [`Map | `Filter | `Reduce | `Sort_by] * term list
  | List of term list | Record of (string * term) list | Get of term * string | Assoc of term * (string * term) list
  | Str of term list | List_op of string * term list | Time
and pattern = Name of string | Seq of pattern list | Keys of string list
type graph = { name : string; context : Context.t; inputs : (string * Ty.t * term) list; body : term }
type t = { graphs : graph list; defs : graph list; macros : Syntax.t list; source : Syntax.t list }
val check : Check.catalog -> Syntax.t list -> t option * Diagnostic.t list
```
- `Context.t` gains `Settings | Editor` in W10. Until then those contexts
  are `E_CONTEXT_PLANNED`, as `scene`/`world` are today.

**Rules** (each already decided in the register; codes are new strings):
- `E_SHADOW` (L11)
- `E_FN_ESCAPES` (F1)
- `E_ACC_TYPE` (L6)
- `E_ITER_BOUND` for literal counts over the limit (L3)
- `E_MACRO_CAPTURE` / `E_MACRO_UNQUOTE` / `E_MACRO_DEPTH` / `E_MACRO_SIZE`
  (M1)
- `E_NO_ELSE` (C1)
- `E_PATTERN` (D3)
- `E_INPUT_DEFAULT` for graph inputs without a default (L14)
- `E_TIME_COUNT`: a loop count or collection that depends on `t`. This is
  new: see W2's unrolling constraint.
- `W_UNKNOWN_GROUP` (G1)

**Limits** (constants in `Workspace`, named in their messages):
- iterations per zone: 4,096
- expansion depth: 32
- expanded forms: 5,000

`ponytail:` these are the study's values. W2 measures and adjusts them.

**Static typing.** Type every body once, both `if` branches, and fn bodies
per call site, as in `model.js` static mode. Unannotated fn parameters
start as `Any` (register F2).

**Printer.**
- `Flow.Lisp.print : ?mark:Syntax.id -> Syntax.t list -> string` returns
  text plus a map from form id to byte spans. It has the same layout rules
  as the study: 84 columns, aligned `let*`, keyword pairs one per line when
  a form breaks.
- Law: `print (parse (print x)) = print x` for every fixture.

**Fixtures (single source).**
- `specification/workspace/cases/*.lisp`: 11 files, one per case study.
- `prototype/build.cjs` and `cases.js` read them; this changes the study to
  load text files at build time.
- OCaml tests read the same files with `(deps (glob_files …))`.

**Tests** (`lib/flow/test_workspace.ml`, plain asserts like `test_check.ml`):
- **The check.cjs suite, 120 cases.**
  - Port each `t('…', …)` into an OCaml assertion.
  - The value expectations need W2's evaluator; put those in
    `test_workspace_eval.ml` once `Flow.Eval` exists (end of W1).
- **Every register rule marked as a proposed rule** gets at least one
  positive and one negative test.
- **Round-trip law** on the 12 fixtures and a construct-coverage file.
- **Macro hygiene and limits.**
  - `(radial k …)` works.
  - A template naming a caller variable is `E_MACRO_CAPTURE`.
  - Gensym numbering is deterministic.

**Docs.**
- `flow.md` §11 gets a pointer: "the workspace language is in
  `specification/workspace/`; §11 applies to `[%flow]`".
- `specification/workspace/iteration.md` §2 and §7 become normative when W1
  lands. Change their status line.

**Done when**
- all 12 fixtures check, print canonically and round-trip;
- the ported model tests pass;
- `dune build @lib/flow/runtest` is green;
- the gate still shows `flow` depending only on `param`.

---

### W2 — Lowering and cooking (`flow`, `flow_sop`, `procedural`)

The goal is that a checked workspace cooks. **Strategy: evaluate values,
unroll geometry.**

1. **`Flow.Eval.run : time:float -> inputs:… -> Workspace.t -> …`**
   evaluates everything that is not geometry: numbers, vec3, text, lists,
   records, function applications and loops over them. It runs
   sequentially on the initial domain with IEEE doubles, the way the
   value lane does.
   - The result is a *geometry plan*: for every geometry-typed term, a call
     with fully evaluated literal arguments plus geometry inputs, keyed by
     `(path, iteration tuple)`.
2. **`Flow_sop.Lower.workspace`** turns the geometry plan into one
   `Network.t` per sop graph, reusing `Build`'s node-construction helpers.
   - **Ids.** Each (path, iteration tuple) gets a compiled id from
     `compiled_ids : int Instance_path.Map.t`. Extend the key: an
     iteration segment is encoded as `-(index + 1)` in the int list, so no
     new type is needed.
     - `ponytail:` negative-int encoding; switch to a variant if paths ever
       need other segment kinds.
   - **Merging lists.** A list of geometry spliced into `sop/merge` becomes
     one internal `flow.merge_n` node.
   - **Parameters that depend on `t`** are not evaluated here. They become
     live drives (W2b), so animation never re-lowers.
3. **Structure never depends on `t`** (`E_TIME_COUNT` and `E_TIME_BRANCH`,
   specified in W2b), so one lowering serves every frame.
4. **Graph inputs and `ref`.** `(ref g :k v)` evaluates `g` with overrides.
   - Geometry refs lower to a shared sub-network per distinct input tuple,
     cached by value like the study's `graph()` cache.
   - The number of distinct tuples is bounded by the evaluation-step
     budget.
5. **Session capacity.** Raise the editor default `max_entries` from 32 to
   512 and keep `max_payload_bytes`.
   - Measure first on Sunflower (240 iterations) and Wave (540), recording
     cook time and memory before and after in the PR (`AGENTS.md`:
     performance is correctness).
6. **Provenance ids for W6.**
   - Every collecting merge passes `~source_attribute:"__flow_src"`. This is
     a new optional pdk argument that writes the input index per primitive
     as a prim int attribute; the Mesh_merge change is ~20 lines.
     (W6 refined this: the value is a workspace-wide tag and an input that
     already has it keeps it, so nested merges resolve exactly; see
     progress.md.)
   - `Lower` records a table `(merge node id, input index) → (zone path,
     iteration tuple)`.
   - `ponytail:` no per-iteration tag nodes. The merge is the only place
     iterations meet, so it is the only place to tag.
7. **Bypass** lowers exactly as today (`Edit.set_bypass`).
8. **`Build.program` re-check (gap 9).**
   - `Lower` runs `Workspace.check` before building, so construction cannot
     fail on unchecked input.
   - `Build.program` itself keeps its signature for `[%flow]` until W12.

**Determinism.**
- Evaluation is sequential.
- Cooking uses `Parallel` as today.
- New test `test/test_workspace_cook.ml` cooks every sop fixture at 1 and 3
  domains and compares geometry bytes (`Pdk.Geometry.data_id` equality is
  not enough; compare packed arrays).
- `value/rand` is `Flow.Eval`'s pure hash. Specify its bit-exact algorithm
  in `iteration.md` §2.2, porting `hash` from `model.js`.

**Performance gates** (recorded, not guessed):
- lowering time for each fixture, and total cook time for Sunflower, Wave
  and Tree;
- the target is that lowering + cook for Bloom takes less than one frame
  at 60 fps on the reference machine. If not, profile before optimising.
- Add `tools/bench_workspace_lower.ml` with a before/after command in the
  PR.

**Tests.**
- Value results for all register examples (sum, fold, scan, product order,
  dependent clauses, ref overrides, records, destructuring, HOFs, str
  formatting per C2).
- Lowered node counts per fixture, for example Bloom: 12 petal subgraphs
  + heart + merges.
- `E_TIME_COUNT`.
- Provenance table correctness.

**Done when** all fixtures with sop graphs cook deterministically and
their benches are recorded.

---

### W2b — Live evaluation: `t`, per-frame recooks and realtime edits (`flow`, `flow_sop`, `procedural`, `prismel_editor`)

The goal is that time-driven workspaces animate in real time: only what
depends on `t` recooks, and everything else stays cached. The
[Orrery](case-studies.md#orrery) case is the acceptance fixture. The study
implements the rules: it has the ◷ t marks, the live and cached readout,
and the two errors (`prototype/check.cjs`, "t …" tests).

**What exists and is reused.** The editor already has the whole per-frame
path for scalar drives (`lib/prismel_editor/cook.ml`):

1. `Sketch_support.Timeline` (play, pause, seek; `Play_pause` in the
   keymap) supplies `time`.
2. `Flow_sop.Value_lane.resolve ~time` re-evaluates drives. Its plan
   already knows `time_dependent`, and it applies **only changed SOP
   ports**. A static network reuses its previous result.
3. `Edit_graph.compile_all ?previous` recompiles incrementally, and an
   unchanged graph is physically equal, so an idle frame never
   resubmits.
4. `Async_cook` is latest-request: a slow cook never blocks the frame, and
   intermediate times are skipped.
5. `Procedural.Session` caches by node key, and `stats` reports
   hits, misses and evictions.

W2b changes what drives look like. It adds no new per-frame machinery.

**Build.**

1. **Liveness analysis** in `Flow.Workspace.check`. This is the same
   dependency pass that computes loop-invariance (`↥`), with a different
   source.
   - A term is **live** when it mentions `t`, or depends on a live binding,
     rail capture, fold accumulator (its init or body), `ref` override,
     graph, or function whose body is live.
   - The result is `live : Path.Set.t` on the checked workspace. It is
     exposed to the canvas (W4) and the inspector (W5).
   - `ponytail:` the only live source is `t`. Add `mouse`, `frame` or an
     audio level when a case needs one: each is a reserved name plus a field
     of the `~live` environment below. The analysis does not care which
     source it is.
2. **Structural rules**, checked statically on the liveness set:
   - `E_TIME_COUNT`: a loop collection or count, a `range` argument, a fold
     step count, or any list whose length depends on `t` and reaches
     geometry is an error. A `filter` over a live predicate is one example.
     Value-only lists, such as `(sum (filter …))`, are fine.
   - `E_TIME_BRANCH`: an `if`, `cond` or `case` with a live test whose
     result type is geometry (or a list of it) is an error. A live choice
     between values, such as a size, a colour or a group name, is fine
     because it is a parameter.
   - Both messages name the binding and suggest the value form: "scale the
     piece to 0", "pick the colour, not the shape".
   - The study checks these rules by evaluating at t, t+0.7 and t+2.3 and
     comparing zone counts, geometry bindings and branch arms. Native code
     checks them statically on `live`, so the study's sampling is not
     ported.
   - `ponytail:` rejecting the case is the whole cost. When a case needs a
     time-switched shape, lower both arms and use `sop/switch` with a
     driven selector field. The manifest's switch has slots `a` and `b`
     and no field today, so this needs a W0-sized catalog change.
3. **Split evaluation.**
   - `Flow.Eval.run ~time` becomes:
     ```ocaml
     val static : inputs:… -> Workspace.t -> (Static.t, Diagnostic.t list) result
     (* every non-live term evaluated once per document change *)

     type residual            (* a live term with its static free variables folded in *)
     val residual_eval : residual -> live:{ t : float } -> (Flow.Value.t, Diagnostic.t) result
     ```
   - `Lower` emits one **live drive** per live parameter slot:
     `(compiled id, field) → residual`.
     - The loop index and every static capture are folded in as
       constants.
     - A Vec3 parameter is one residual whose result writes the three
       manifest component fields (`center_x`, `center_y`, `center_z`),
       which the manifest already splits.
     - An iteration of an unrolled loop gets its own residual, so the
       count of live drives is at most the count of unrolled nodes, which
       is already bounded.
   - **One drive kind.** Add `Drive.Live of Flow.Eval.residual` and
     evaluate it inside `Value_lane.resolve` beside `Drive.Expr`.
     `time_dependent` becomes true when any `Live` drive exists.
     - `ponytail:` residuals cover everything `Flow.Expr` can express and
       more (`value/hsv`, `value/rand` of t, `if` on values, records,
       `str`), so there is one live path.
     - `Drive.Expr` remains only for `[%flow]` and the legacy graph pane,
       and is removed in W12.
     - Cost: Orrery evaluates about 100 residuals per frame, which should
       be microseconds. W2b's bench confirms it.
4. **Per-frame path (unchanged).**
   1. Timeline time.
   2. `Value_lane.resolve`, which applies changed ports only.
   3. Incremental `compile_all`.
   4. `Async_cook.submit`, latest request.
   5. The Session recooks the nodes whose parameters changed and their
      downstream cone. Static upstream nodes hit the cache.
   - In Orrery, `base` and `plinth` cook once; `sun`, `glow`, every moon
     and the merges cook each frame.
5. **Cache policy for volatile nodes.**
   - The problem: a live node makes a new cache key every frame, so it
     would churn the Session's LRU (512 entries after W2) and evict static
     entries, the very ones that make playback cheap.
   - The fix: `Session.set_volatile`, a predicate replaced after each
     lowering (an optional argument of `create` would not reach its many
     callers).
   - A volatile node keeps exactly **one** entry, its latest. It is
     replaced in place and never counted in, or evicted from, the LRU.
   - `Lower` marks a node volatile when it is live, or downstream of a
     live node in the same graph.
   - `ponytail:` one slot per volatile node, so scrubbing back and forth
     recooks. Add a small per-node ring when scrub-back latency is
     measured to matter.
6. **Frame pacing and determinism.**
   - Interactive play never blocks. When a cook exceeds the frame, the
     viewport shows the last completed result, which is the existing
     latest-request rule.
   - The status bar shows `cook 23 ms · skipping frames` while that
     happens (the `Status` text already exists).
   - `Sketch.Fixed dt`, `Sketch.export`, and runs under
     `PRISMEL_MAX_FRAMES` must produce the geometry for exactly frame *n*'s
     time.
   - Before building, read how `Editor3` export cooks today (`cook.ml`,
     `take_export`). If it goes through `Async_cook`, add
     `Async_cook.await : 'a t -> 'a completion` and use it only on
     fixed-step runs.
   - Artifacts must be byte-identical at 1 and 3 domains.
7. **Realtime edits, not only time.**
   - Scrubbing a parameter or a graph input is a live edit without a
     history entry, committed once on release, as today.
   - Each drag event re-runs `Eval.static` and `Lower`.
   - `compile_all ?previous` keeps the unchanged nodes, so only the edited
     node's downstream cone recooks.
   - A scrub that changes a loop count re-lowers; W2's gate "Bloom lower +
     cook < one frame" covers that.
   - Live reload of a `.plisp` file (W11) is the same path, triggered by
     the file instead of the pointer.

**UI (built in W4/W5, specified here).**
- A **◷ t** chip on every live node and zone. It sits beside `↥ same each
  time` and uses the accent colour.
- The inspector shows `cook: live, recooks every frame` or `cook: cached`.
- The viewport header shows `◷ N live · M cached · cook X ms`.
- Transport is the existing timeline bar and `Play_pause`. W2b adds no
  second transport.

**Tests.**
- Liveness:
  - direct `t`;
  - through a binding, a capture, a fold accumulator, a function and a
    graph `ref`;
  - `t` is reserved and cannot be bound;
  - a macro gensym named `t#` is not `t`.
- `E_TIME_COUNT`: `range` over a live count, a live `filter` spliced into
  merge, and a value-only live `filter` summed (accepted).
- `E_TIME_BRANCH`: geometry arms rejected; value arms accepted.
- `Value_lane`: a static network is resolved once; a live network applies
  only the changed ports (existing test style in `test_network.ml`).
- **Orrery playback**, 600 frames at `Fixed (1/60)`, with Session `stats`
  asserted:
  - `base` and `plinth` miss exactly once, then always hit;
  - live nodes miss every frame;
  - the eviction count of static entries is 0.
- Determinism: an Orrery fixed-step export is byte-identical at 1 and 3
  domains.

**Bench.**
- `tools/bench_workspace_live.ml`: Orrery, Wave and Sunflower (the last
  made live by animating `spread`).
- It reports the p50 and p99 frame cost split into resolve, compile,
  submit and cook, plus Session hits and misses.
- Record the command and the numbers in the PR.

**Done when**
- Orrery plays at 60 fps on the reference machine with its static nodes
  cached, or the PR records the measured bottleneck.
- Both errors report at their binding.
- The fixed-step export is deterministic.

---

### W3 — Document v4 and history (`editor_document`, `prismel_editor`)

**Reuse.**
- `Editor_core.History.record ~label ~merge`, which already holds whole
  immutable documents.
- `Network_layout`'s fields for per-node view data.

**Build.**
1. **`Flow_sop.Flow_edit`**, UI-free, holding every gesture as a pure syntax
   rewrite (port of e1.js/e2.js): `set_arg`, `connect`, `disconnect`,
   `unfold`, `fold`, `wrap_in_loop (For|Fold)`, `hoist`, `rename`,
   `make_local_fn`, `make_macro ~holes`, `inline_macro`, `toggle_bypass`,
   `set_note`, `add_item`, `move_item`, `add_field`, `add_node`,
   `delete_nodes`, `set_input_default` (`set_layout_ratio` is W10).
   - One `op` variant and one `apply`; no command objects. Each op keeps
     notes (a comment travels with its binding name), prints canonically,
     re-parses and re-checks atomically.
   - `ponytail:` the checker is the type oracle: `Wrap` tries the geometry
     and number shapes (or each candidate feedback input) and keeps the first
     that checks.
2. **`Editor_document.Workspace_doc`** and `Layout_by_path`:
   ```ocaml
   type t = { source : Flow.Syntax.t list; checked : Flow.Workspace.t;
              layout : Layout_by_path.t; settings : Settings.t }
   val of_text : ?settings -> catalog -> string -> (t, Flow.Diagnostic.t list) result
   val edit : catalog -> t -> Flow_edit.op -> (t, Flow.Diagnostic.t) result
   ```
   - `Layout_by_path` is `Network_layout`'s fields keyed by
     `Workspace.path` (at, pinned, rows, bends, wireless) plus `collapsed` and
     `frames`. Keys survive text edits by construction; `Flow_edit.remap`
     rewrites them in the same transaction as a rename or a hoist.
3. **Presets are s-expressions.** One `.plisp` file: the `(workspace ...)`
   form with its comments, then optional `(layout ...)`, `(settings ...)` and
   `(view ...)` forms. `.plisp` sketches (W11) are the same text without the
   trailing forms.
   - No JSON, no version number, no older format: the v3 reader and writer
     and W0's set_color migration are deleted. Only a workspace document
     saves; `Editor_core.Store` gains atomic text writes and keeps JSON only
     for user preferences and viewport encoders.
4. **Core.**
   - `Document.workspace` pairs the `Workspace_doc` with its `Lower.t`;
     `Document.of_workspace` lowers it into one geometry object per `sop`
     graph, so undo restores both and the old graph pane shows the lowered
     top-level networks until W4.
   - `Pxui_graph.Syntax_edit of Flow_edit.op` and `Doc.syntax_edit` reduce a
     gesture: one history entry named by `Flow_edit.label`, `Gesture` merge
     for a scrub. `Editor3/2` accept `?workspace` and offer `edit`.
   - After each lowering `Cook.set_volatile` gets `Lower.is_volatile`.

**Tests.**
- `test/test_workspace_edit.ml`: every study gesture as a pure text test.
- `test/test_workspace_doc.ml`: text, layout and settings round trip; atomic
  edits and layout key rewrites; the editor opens a workspace; labels and
  merged scrubs through undo and redo; `t` recooks and static nodes stay
  cached; save and load through `Space s` / `Space b`.
- Existing editor tests pass.

**Done when**
- the editor opens and saves a workspace, and time-driven ones animate;
- existing editor tests pass with the graph pane still showing the top-level
  graph through the old path, which W4 replaces.

---

### W4 — Graph pane projection (`pxui_graph`, `prismel_editor`)

The graph pane draws the syntax projection: nodes, zones, rails,
iteration selectors, chips, output rows and λ zones.

**Reuse.**
- Tiles, rows, sockets and wires; `Ui.line` polylines; BVH hit testing;
  `automatic_layout`.
- The ƒ row button, the `M` bypass tag, `with_applied` and `Tree`.
- The study's `e2.js` layout algorithm and `argRows` rules, as the
  reference implementation.

**Build.**
1. **`Flow_sop.Projection`** (new, UI-free, so it is testable). It is a
   port of `buildView` / `buildScope` / `mkNode` / `argRows`:
   ```ocaml
   type row = { label : string; key : Flow_edit.arg_key; ty : Flow.Ty.t option; expr : Flow.Syntax.t option;
                default : Param.value option; socket : bool; kind : [`Arg | `Rest | `Add | `Hole | `Binder | `Group_writer | `Group_reader] }
   type node = { path : Flow.Workspace.path; name : string; head : string; rows : row list;
                 outputs : (string * Flow.Ty.t) list;   (* record fields or destructured names *)
                 note : string option; bypass : bool; macro : string option;
                 zone : zone option }
   and zone = { kind : [`For | `Fold | `Scan | `Sum | `Let | `Fn]; rail : rail_row list; scope : scope; yield_label : string }
   and scope = { nodes : node list; result : [`Link of string | `Node of node | `Literal] }
   val of_graph : Flow.Workspace.t -> string -> scope
   ```
2. **Pxui_graph.**
   - Accept a `Projection.scope` in place of the flat network for workspace
     documents.
     - `ponytail:` keep one code path by converting the flat network case
       into a projection too, once every document is a workspace.
   - Zones are painted in `paint_background` under tiles, using new theme
     tokens in `Pxui.Theme`: `zone_for`, `zone_fold`, `zone_sum` and
     `zone_fn`, with the hollow dashed style for λ zones.
     - The kit parity test gains a fixture for these tokens.
   - The rail and yield are rows drawn with the existing row code.
   - The **iteration selector** is a `Ui.box` holding two buttons, a
     slider track and a readout.
     - Reuse `Ui.slider` if it exists; otherwise add a minimal
       `Ui.stepper_slider` to `lib/pxui/ui.ml`, one widget with no second
       hit path.
     - It emits `Probe_set {zone; index}`.
   - **Layout.** Recursive layout per scope; a zone's size comes from its
     inner layout. Port `layoutScope` / `nodeSize` / `place`.
     - `ponytail:` no crossing minimisation, the same as today's
       `automatic_layout` note.
   - **Chips** for inline calls, loops, fn, records and macros render in
     the value field with the glyphs `ƒ for Σ ⟲ λ {} ◆`. Numbers inside
     chips are scrubbable, and hovering expands the chip.
   - **Output rows** for records and patterns sit under the card. Wiring
     from one writes `r.field`.
   - **Stacked sockets** for lists and the diamond socket for fn use new
     `Theme.ports` entries.
   - **New `change` cases:**
     - `Syntax_edit of Flow_edit.op` (already in `change` since W3)
     - `Probe_set of {zone : path; index : int}`
     - `Zone_collapsed of {zone : path; collapsed : bool}`

     `ponytail:` one edit request, not twenty.
3. **Prismel_editor.** `Doc.syntax_edit` already handles the pane's `Syntax_edit` (W3).
   The probe is view state (`Core.probes : int Path_map.t`), not document
   data, and not recorded in history.

**Tests.**
- `test/test_pxui_graph.ml`:
  - projection snapshots for every fixture (node, zone and row counts);
  - hit tests on the selector buttons and track;
  - gesture → request mapping.
- The 2,001-node smoke stays within baseline. Add a 1,000-iteration zone
  smoke: only visible zones draw, and hidden iterations are never
  materialised as tiles.
- Kit parity fixture.

**Done when** every fixture renders in the native graph pane with zones and
selectors, and all gestures from W3 are reachable by mouse and keys.

---

### W5 — Probes, footers and sparklines

**Reuse.** `with_applied` (a setter from Core to the pane) and
`Session.stats`.

**Build.**
1. `Flow.Eval` records values per `(path, iteration tuple)` when asked
   (`?record:bool`), bounded to 4,096 records per path, the same as the
   study. Geometry records store only `prim count`, `groups` and
   `data_id`, never geometry.
   - `ponytail:` no geometry thumbnails. The viewport shows geometry; the
     footer shows counts.
2. `Cook` exposes `records : path -> (int list * value_summary) array`.
   `Pxui_graph.with_records` mirrors `with_applied`.
3. Footer content:
   - the value at the probe;
   - a sparkline across the innermost zone (floats, ints, bools);
   - `×n`;
   - `then a · else b` for `if`;
   - `kept a of b` for `filter`;
   - `↥ same each time` (loop-invariant, from `Flow.Workspace`'s dependency
     analysis), which emits `Syntax_edit (Hoist ...)`.
   - `◷ t` on live nodes and zones, from W2b's liveness set, plus the
     inspector's `cook: live` or `cook: cached` row and the viewport
     header's `◷ N live · M cached · cook X ms`.
4. The inspector lists per-iteration values; clicking one emits
   `Probe_set`.

**Tests.**
- Record bounds.
- The invariant analysis on the Sunflower and Tree fixtures.
- Footer text for known probes.

---

### W6 — Viewport provenance (`pdk_prismel`, `prismel_editor`)

**Reuse.**
- `__flow_src` from W2.
- The lowering table.
- `Pdk.Ray` (the kernel exists).
- Viewport3's pick hook (`handles`).

**Build.**
1. `Pdk_prismel.to_mesh ?prim_of_triangle:bool` optionally returns `int
   array` mapping each triangle to its primitive.
2. Click in Viewport3 without a drag:
   - cast a ray against the displayed mesh (`Pdk.Ray` on the prepared
     geometry) to get the primitive;
   - read `__flow_src` from that primitive;
   - look it up in the table to get `(zone path, iteration tuple)`;
   - emit an action that selects the zone and sets the probe.
   - `ponytail:` a CPU ray cast, not an ID buffer. The ID-buffer upgrade
     path is an OGPU feature (`add-ogpu-feature`) when meshes exceed about
     1M triangles.
3. Highlight: the displayed mesh draws the probed iteration's primitives
   with the selection tint through a per-triangle colour attribute, and
   dims the rest. This is a prepare-side change, not a renderer change.

**Tests.**
- Ray pick on a fixture with known geometry.
- The provenance table round trip.

---

### W7 — Editable text (`pxui`, `pxui_shell`, `prismel_editor`)

**Reuse.**
- `Ui.text_field`'s focus, IME and caret code.
- `Flow.Lisp.print`'s id→span map.
- `Workspace_doc.of_text`.

**Build.**
1. `Pxui.Ui.text_area`: a multiline variant of `text_field` sharing its
   focus and IME path, with no second text-entry path (`AGENTS.md`). It
   supports scrolling, a caret, selection, and copy and paste through SDL's
   clipboard.
2. The text pane has three tabs: **Selection**, **Graph** and **Document**.
   - **Selection** prints the selected binding's top-level ancestor plus
     its upstream closure, with the selection marked; it can be edited per
     binding.
   - **Document** is the whole workspace with an atomic Check & apply. An
     invalid draft stays in the pane while every other pane shows the last
     applied document.
   - Apply is one history entry, "Edit text".
3. Errors show at their line via `Diagnostic.position`.

**Tests.**
- `text_area` unit tests.
- Apply and discard.
- An invalid draft keeps the document unchanged.
- Undo labels.

---

### W8 — Loops over geometry (`procedural`, `flow_sop`)

`for [p (sop/point_list g)]` needs a cook to know its count.

**Reuse.**
- `Session` recursion.
- The `id` point attribute from scatter and point_generate.
- The per-(path, index) compiled ids.

**Build.** A **zone cook step**: a `Procedural` node kind `Zone` whose
cook function:
1. cooks the collection input;
2. derives the element list: points or pieces, ordered by `:key` attribute
   if present, else by index (register I2);
3. for each element, instantiates the body sub-network with the element
   bound, through `Session.cook` with ids from `(path, element key)`;
4. merges with `__flow_src`.

The body is lowered once (as a template network). Cache keys include the
element key, so an unchanged element is a cache hit.
- `ponytail:` sequential over elements inside one cook. Parallelise with
  `Parallel.map_array` only after a byte-identical test and a bench show a
  win.

**Tests.**
- A Garden-like fixture with scatter → for over points.
- Cache hits after moving one point.
- 1 vs N domains.

---

### W9 — Macros UI, notes, bypass

**Reuse.** `Flow.Macro.expand_once`, `Flow_edit.make_macro` /
`inline_macro` / `set_note` / `toggle_bypass`, and the `M` bypass tag.

**Build.**
- **Macro lens.** A collapsible panel under a macro call node shows the
  expansion steps as a selector and prints the step with `Flow.Lisp`.
  "Replace call with expansion" emits `Inline_macro`.
- **Make macro.** A `Pxui_shell.Prompt` lists literals with checkboxes and
  hole names (the study's dialog).
- **Notes.** A note row on the card; editing it in the inspector emits
  `Set_note`.
- **Bypass.** A title flag replaces the `M` tag, using the same request.

**Tests.** Pure edit tests exist from W3; add pane request tests only.

---

### W10 — Scene, world, settings and a composable shell

**Reuse.**
- Scene objects (`objects.ml`) and world layers (`layers.ml`), including
  `Layers.of_world` and `network_of_world`.
- `Settings`.
- `Pxui_shell.Tree`, `Chrome` and `Shell.frame`.

**Build.**
1. **Contexts.** `scene`, `world`, `settings` and `editor` become checkable
   contexts.
   - Scene calls (`scene/object`, `scene/merge`) lower into the existing
     scene `Edit_graph` object nodes.
   - World calls lower into layer nodes.
   - Settings lower into `Settings.t`.
   - `ponytail:` only the object, layer and settings kinds that exist today
     get Lisp spellings, each generated from its existing schema. No new
     scene features.
2. **Layout tree.** Replace `Pxui_shell.Layout`'s record with:
   ```ocaml
   type panel = View of string | Graph | List | Lisp | Inspector | Outline | Timeline
   type t = Leaf of panel | Split of { axis : [`H | `V]; ratio : float; a : t; b : t } | Tile of t list | Float of t
   val geometry : t -> Frame.t -> (panel * bounds) list
   ```
   - `Core` keys focus and commands by `panel`, not `column`.
   - The editor graph evaluates to this tree. Split, close, retype and
     resize become `Flow_edit` ops on the editor graph.
   - **Recovery.** The host keeps "Restore layout" outside the tree, and a
     failed layout keeps the previous one (register E1).
   - `ponytail:` no OS windows. `Float` is an in-window overlay.
   - Update `prismel_editor/AGENTS.md`'s "keep the three-column workspace"
     rule in the same PR: the default editor graph *is* the three-column
     layout.

**Tests.**
- The Variations fixture renders four viewports.
- Restore after an invalid editor graph.
- Every existing keyboard focus test.

---

### W11 — `.plisp` sketches compiled by dune (`tools/plisp`, `flow_sop`, `prismel_editor`)

A sketch is one file, `sketches/<name>/sketch.plisp`, holding one
`(workspace …)` form. It has no `main.ml` and no per-sketch `dune`.
`dune build` checks it against the catalog, reports errors at lines inside
the `.plisp` file, and links a native executable. The running editor writes
edits back to the same file.

```text
sketches/bloom/sketch.plisp        ← the only file an author writes
sketches/dune.plisp.inc            ← generated, checked in, kept current by `dune promote`
_build/default/sketches/bloom/main.ml   ← generated per build, never checked in
```

**The ponytail ladder, applied.**
1. *Do we need a new build stanza?* No. Dune has no plugins. Its existing
   `include`, `subdir`, `rule` and promotion features are enough.
2. *Does the codebase have the pieces?*
   - W1 gives the reader, checker and printer.
   - W2 gives evaluation.
   - `Editor3.run` gives the host.
   - The `api_manifest` and `flow_manifest.sexp` flows already use the
     "generated file checked by `diff` in `runtest`, accepted with
     `dune promote`" pattern.
3. *Can the generated OCaml be one line?* Nearly. `main.ml` embeds the source
   text and calls one function (below).
4. *Then the minimum:* one small tool with three subcommands.

**Build.**

1. **`tools/plisp/plisp.ml`**, an executable with `(public_name prismel-plisp)`
   in package `prismel`. It links `flow`, `flow_sop` and `sop_catalog`, so it
   uses the in-process catalog and never reads the manifest file. Three
   subcommands, with no dependency beyond `Stdlib` and `Arg`:
   - **`prismel-plisp check FILE…`** parses, expands macros and checks each
     file. It prints diagnostics in the OCaml compiler's format, so dune,
     editors and compilation modes jump to the line:
     ```text
     File "sketches/bloom/sketch.plisp", line 6, characters 17-24:
     Error [E_UNKNOWN_NODE]: sop/circel is not in the catalog; did you mean sop/circle?
     ```
     It exits 1 on any error. Warnings are errors, as for OCaml (`AGENTS.md`),
     unless the file has `^:allow-warnings` on its `workspace` form.
   - **`prismel-plisp ml FILE`** runs `check`, then prints `main.ml` to
     stdout:
     ```ocaml
     (* generated by prismel-plisp from sketches/bloom/sketch.plisp; do not edit *)
     let () =
       Prismel_editor.Workspace.main
         ~path:"sketches/bloom/sketch.plisp"
         ~digest:"<sha256 of the source text>"
         ~catalog:"<Sop_catalog manifest digest>"
         {plisp_7f3a|…source text, verbatim…|plisp_7f3a}
     ```
     - The quoted-string delimiter is `plisp_` plus the first 4 hex digits
       of the digest. If that delimiter occurs in the source, the tool
       appends a digit until it does not.
     - The text is embedded verbatim, not re-printed, so comments and
       layout survive. `Workspace.main` re-parses it at startup in low
       milliseconds (register O4, and see the risk row in §5).
   - **`prismel-plisp dune DIR`** scans `DIR/*/sketch.plisp` in sorted order
     and prints the include file:
     ```dune
     ; generated by prismel-plisp dune sketches; accept changes with dune promote
     (subdir bloom
      (rule
       (target main.ml)
       (deps sketch.plisp (glob_files *.png) (glob_files *.ttf))
       (action (with-stdout-to %{target} (run %{bin:prismel-plisp} ml sketch.plisp))))
      (executable (name main) (modules main) (libraries prismel_editor))
      (rule (alias smoke-all)
       (action (setenv PRISMEL_MAX_FRAMES 120 (run ./main.exe)))))
     ```
     - The `glob_files` deps cover assets next to the sketch, so assets
       rebuild with it. The asset extensions are whatever
       `Runtime_resources` loads.
     - `ponytail:` the smoke frame count is fixed at 120. Add a per-sketch
       count when a sketch needs one: read it from `settings` (W10).

2. **The dune wiring**, once per directory that holds sketches (`sketches/`,
   and `examples/` if examples adopt it):
   ```dune
   ; sketches/dune
   (include dune.plisp.inc)
   (rule
    (target dune.plisp.inc.gen)
    (deps (glob_files_rec sketch.plisp))
    (action (with-stdout-to %{target} (run %{bin:prismel-plisp} dune .))))
   (rule (alias runtest) (action (diff dune.plisp.inc dune.plisp.inc.gen)))
   ```
   - Adding a sketch means creating `sketches/foo/sketch.plisp` and then
     running `dune build @runtest; dune promote`. The same flow is already
     documented for `flow_manifest.sexp`.
   - A bootstrap `dune.plisp.inc` is checked in empty. Dune requires an
     included file to exist.
   - Check early: `subdir` targets a source directory that has no `dune`
     file of its own, and `glob_files_rec` needs lang 3.0 or later (the
     repo is on 3.17). Both are supported, but W11's first commit must
     prove them on one sketch before generating the rest.
   - Existing OCaml sketches keep their own `dune` files. The generator only
     lists directories that contain `sketch.plisp` and no `dune`. A
     directory with both is an error that names the file to delete.

3. **`Prismel_editor.Workspace`**, a new module with an `.mli`:
   ```ocaml
   val main :
     path:string -> digest:string -> catalog:string -> string -> unit
   (** Entry point for generated [main.ml]. Parses and checks the embedded
       source, runs [Editor3] on it, and exits non-zero with diagnostics on
       failure. [path] is relative to the project root. *)

   val run :
     ?config:Editor3.config -> ?source:source -> Flow_sop.Workspace_program.t -> unit
   (** For OCaml hosts. [main] is [run] after [load]. *)

   type source = { path : string; digest : string }

   val load : string -> (Flow_sop.Workspace_program.t, Flow.Diagnostic.t list) result
   ```
   - `Flow_sop.Workspace_program.t` is the checked workspace (W1–W2) plus
     its input overrides.
   - `with_inputs : t -> graph:string -> (string * Flow.Value.t) list ->
     (t, Flow.Diagnostic.t) result` checks names and types at run time.
   - The window title, size and seed come from the workspace's `settings`
     graph (W10). Before W10 they come from `Editor3.default_config`, with
     the title set to the workspace name.
   - `catalog` mismatch: when the running catalog digest differs from the
     one at build time, `main` re-checks and reports rather than trusting
     stale plan data. That cannot happen in one dune build, but it can for a
     copied binary.

4. **Save writes the `.plisp` file** (register O1). No OCaml literal splicing
   is needed.
   - At startup, `main` looks for the source file: it walks up from the
     executable's directory, and then the working directory, to the first
     `dune-project` not under `_build`, then joins `path`.
   - It enables **Save** (⌘S) only when that file exists and its SHA-256
     equals `digest`, meaning it is the text the binary was built from.
   - Save prints the document with `Flow.Lisp` (comment-preserving, W1),
     writes it atomically (temp file plus `Sys.rename`) and updates the
     remembered digest.
   - Otherwise Save falls back to a preset (the v4 document) under the
     editor's store, and the status bar says why. For example: "source
     changed since build; saved as preset".
   - `ponytail:` there is no three-way merge. Add one when two writers of
     one sketch are common.

5. **Live reload from disk.** While the sketch runs, the editor polls the
   source file's mtime at most twice a second, on the initial domain, from
   the frame loop.
   - When the mtime and digest change, it re-parses and re-checks.
   - On success it replaces the document as one history entry,
     "Reload sketch.plisp", keeping probes and layout by path id.
   - On failure it keeps the last good document and shows the diagnostics
     in the text tab and the status bar.
   - Save from the editor updates the remembered digest first, so its own
     writes do not reload.
   - This is the loop the format exists for: edit the `.plisp` in any text
     editor, and the graph and viewport follow without rebuilding.
   - `ponytail:` it polls rather than using `inotify` or `FSEvents` (no new
     dependency). The ceiling is one `stat` per 500 ms. Add native file
     events when watching many files.

6. **`prismel-plisp fmt FILE`** prints the canonical text with the W1
   printer. That is the same text Save writes, so a hand-formatted file and
   an editor-saved file converge. `ponytail:` it is not wired into
   `dune fmt`. Add that when `.plisp` files are reviewed in PRs often
   enough that format diffs hurt.

7. **Scaffolding.** `tools/new_example.exe -- --plisp <name>` writes
   `sketches/<name>/sketch.plisp` from the Bloom fixture, then prints the
   `dune build @runtest; dune promote` step.

**Skipped, and when to add it.**

| Skipped | Add when |
|---|---|
| `[%workspace]` PPX and generated typed input records | an OCaml host needs Lisp and OCaml in one file, or overrides inputs often enough that run-time name errors hurt. `Workspace.run` with `with_inputs` covers the rest. |
| Several sketches or OCaml callbacks per `.plisp` | a case needs host code. It then becomes an OCaml sketch that calls `Workspace.load` on its `.plisp` (with a `(rule (alias runtest) (action (run %{bin:prismel-plisp} check x.plisp)))`). |
| Compiling Lisp to OCaml | measurement shows the plan interpreter too slow (O4, §4). |
| An LSP or syntax highlighting | `.plisp` is s-expressions, so any Lisp mode highlights it. `check` output already drives compilation-mode jumps. |
| Hot reload of changed catalog code | never at run time. Rebuilding is the answer. |

**Tests.**
- `tools/plisp/test/` covers:
  - expect tests for `check` on one fixture per diagnostic class, asserting
    the exact `File …, line …, characters …` lines;
  - `ml` output, including the delimiter-collision case;
  - `dune` output for a directory with two sketches, a sketch with a `dune`
    file (an error) and an empty directory.
- A dune test (`test/plisp_build/`, a `cram` test with `(using directory-targets)`
  already enabled) builds a temp project containing:
  - one valid sketch, which must build;
  - one with a typo, which must fail with the `.plisp` line.
- `Workspace.main` tests:
  - digest match enables Save;
  - digest mismatch falls back to a preset;
  - an atomic write followed by an identical re-read;
  - reload keeps probes by path id;
  - a failed reload keeps the last good document.
- All twelve `specification/workspace/cases/*.lisp` fixtures (W1) are copied
  to `sketches/ws_<case>/sketch.plisp` and run under `@smoke-all`.

**Done when.**
- `sketches/ws_bloom/sketch.plisp` is the only authored file for that
  sketch.
- A typo in it fails `dune build` at the right line.
- `dune build @smoke-all` runs it.
- Editing it in a text editor updates the running window, and ⌘S in the
  window rewrites it with comments intact.

---

### W12 — Migration and removal

1. Port sketches that are only a `[%flow]` graph plus an `Editor3.run` call
   (for example `sketches/flow_terrain`) to `sketches/<name>/sketch.plisp`,
   deleting their `main.ml` and `dune`. Keep `[%flow]` for OCaml sketches
   that mix host code, as sugar: a single `graph` payload becomes
   `(workspace <name> <graph>)`.
2. Delete:
   - the read-only `text_pane` and `Flow_sop.Print.network`'s editor use;
   - `Check.program`'s single-graph path, once `[%flow]` is sugar.
3. Update the docs:
   - `flow.md`: status, §8.3, §11 pointer, §17.
   - `api.md`: `.plisp` sketches, `prismel-plisp`, `Workspace.main`, `Workspace.load`, `Workspace.run`.
   - `AGENTS.md`: the sketch layout (`sketches/<name>/sketch.plisp`), and the `dune promote` step for `dune.plisp.inc`.
   - `tools/new_example`: document `--plisp`.
   - `backend.md`: the gate, if boundaries changed.
   - `pxui.md`: `text_area` and the layout tree.
   - `performance.md`: the new benches.
4. Run `prune-dead-code` to a fixpoint.

---

## 3. Study → OCaml porting map

| Study (JS) | OCaml destination | Notes |
|---|---|---|
| `model.js` `read`, notes, meta | `Flow.Syntax` | keep spans |
| `pp`, `printMarked` | `Flow.Lisp` | identical layout rules; golden tests from the study's output |
| `parseType` … `coerce` | `Flow.Ty` | |
| static pass of `compile` | `Flow.Workspace.check` | error texts copied from the study |
| run pass (`ev`, `evZone`, `evCall`, HOFs) | `Flow.Eval` | value-only in W2; geometry calls become the plan |
| `checkMacro`, `expand*` | `Flow.Macro` | |
| 3D kernel and `sop/*` ops | **not ported** | Prismel has pdk; the study kernel is an illustration only |
| `e1.js` edit primitives | `Flow_sop.Flow_edit` | pure; port the tests |
| `e1.js` `buildView` / `argRows` | `Flow_sop.Projection` | |
| `e2.js` layout and paint | `Pxui_graph` | Pxui boxes and lines; no DOM |
| `e3.js` shell | `Pxui_shell.Layout` tree (W10) | |
| `e3.js` renderer | **not ported** | Metal renders; only picking ideas carry over (W6) |
| `e4.js` inspector, Lisp panel, navigator | `prismel_editor` panes | |
| `register.js` | tests | each rule is one test |

---

## 4. Explicitly not building

| Skipped | Add when |
|---|---|
| procedural (code-running) macros | a case needs computation at expansion that templates can't express |
| recursion, `while`, escaping closures | never, in this language; use fold (F1, L3) |
| implicit broadcasting | never (D1) |
| `for-zip` form | a case needs zipped iteration that `map` over lists can't express (L2, F4) |
| several fold accumulators | never; records cover it (L6) |
| native OCaml code generation from zones | measurements show the plan interpreter too slow (O4) |
| live sources other than `t` (mouse, frame, audio) | a case needs one; it is a reserved name plus a field of the `~live` environment (W2b) |
| time-switched shapes (`sop/switch` with a driven selector) | a case needs `t` to pick between shapes (T3) |
| per-node cache ring for scrubbing back in time | scrub-back latency is measured to matter (W2b) |
| a `[%workspace]` PPX | an OCaml host needs Lisp and OCaml in one file (W11) |
| OS windows for floating panels | the in-window `Float` is insufficient in practice |
| geometry thumbnails in the selector | never in the selector; a viewport overlay if needed |
| record field rename across accessors | first user request (D2 notes the study lacks it too) |
| hex colour literals | colour picking by text is requested |
| comment attachment to the same line | round-trip complaints |

---

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Unrolling blows the session cache or frame budget (Sunflower 240, Wave 540 iterations) | W2 benches are gating. Raise capacity with measurement; W8's zone step caches per element, so move heavy loops there. |
| Pixel parity breaks with new theme tokens | Add tokens only; the parity fixtures gain a zone panel; review PNG diffs |
| The dependency gate: `Flow_edit` / `Projection` needing UI | Both live in `flow_sop` and are UI-free by construction; the gate test enforces it |
| Merge padding changes existing geometry | Padding only adds empty groups when inputs differ; existing merges with identical schemas produce identical bytes (tested) |
| Startup cost of re-parsing the embedded `.plisp` text | Measure; parse + check of the Bloom fixture is expected in the low milliseconds. Switch to data emission only if measured |
| dune `subdir` or `glob_files_rec` behaving differently than expected for generated sketch stanzas | W11's first commit proves the wiring on one sketch before generating the rest; fallback is a two-line checked-in `dune` per sketch, still with no OCaml |
| Live nodes churn the Session cache during playback | W2b's volatile single-slot policy, asserted by Session `stats` in the Orrery playback test |
| Playback slower than the frame | Latest-request cooking already skips frames without blocking; W2b's bench records p50/p99 per phase so the slow phase is known, not guessed |

---

## 6. How to work this plan (for Codex)

1. Read in order:
   - `AGENTS.md` and the nested `AGENTS.md` for each library the milestone
     touches;
   - this plan's milestone;
   - `iteration.md` §2 and §7;
   - `ambiguities.md` (the rules are tests);
   - the study's source for the ported piece (`prototype/model.js`,
     `src/e*.js`).
2. One milestone per PR. Keep each commit green.
3. Use the repo skills:
   - `implement-flow-milestone` for flow and pxui_graph work;
   - `add-pdk-op` and `add-sop` for W0;
   - `extend-prismel-editor` for editor changes;
   - `focused-test` while iterating;
   - `promote-manifests` after `.mli` changes;
   - `smoke` for native checks;
   - `prune-dead-code` in W12.
4. **Tests come from the study.**
   - The twelve fixtures, the 120 model checks and the 52 register rules are
     the acceptance tests.
   - When the study and this plan disagree, the register wins. Update the
     study so they agree.
5. **Record measurements in every PR** that touches cooking, lowering or
   drawing: command, machine, domains, before/after numbers.
6. **Record each milestone** in `specification/flow-migration.md` under a
   new "Workspace" section, with its date, what landed and any deviation
   from this plan.
