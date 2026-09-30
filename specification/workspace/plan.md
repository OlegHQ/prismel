# Workspace migration plan

**Plan of record for review, 30 September 2026.** This turns the workspace
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
| Printer | `Flow_sop.Print.network` with `binding_lines` | v3 → v4 conversion only |
| Bypass | `^:bypass` → `Check.call.bypass` → `Edit.set_bypass` → print, plus `Edit_graph.set_bypass` and the preset field | as is |
| Value lane | `Flow_sop.Value_lane.resolve ~time` (scalar drives, per-frame) | `t`-driven parameters |
| Cooking | `Procedural.Session`, `Async_cook` (latest-request rule, bounded cache, `Parallel.run`) | unchanged, except the cache capacity (W3) |
| Editor loop | `Core.update` → `Shell.frame` → `Doc.apply` reducer → `History.record ~label`, intents only (`lib/prismel_editor`) | every new gesture is an intent reduced once per frame |
| Graph pane | `Pxui_graph` tiles, rows, wires, BVH hit tests, `automatic_layout`, the ƒ fold/unfold rows, `with_applied` | nodes and rows; zones are added on top |
| Shell | `Pxui_shell.Layout` (fixed three columns), `Tree`, `Inspector.flow_fields`, `Prompt` | W10 replaces only the layout |
| Presets | `Editor_document.Preset` v3, `Editor_core.Store` | the v4 loader wraps v3 |
| PPX | `ppx_prismel` `[%flow]`: reads the manifest, maps spans to OCaml locations, emits `Build.program` | `[%workspace]` extends it |
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
48 register rules.

`ponytail:` we do not build an id-preserving diff from free text to the
old network (the survey's "id-preserving reconciliation"). The syntax *is*
the document, so the ids are path ids and survive text edits by
construction, except renames, which rewrite layout keys in the same
transaction (register I1).

---

## 1. Milestone map

```text
W0  fixes & catalog prerequisites ─┐
W1  language core (flow)           ├─► W2 lowering & cooking ─► W3 document v4 + history ─► W4 graph pane zones
                                   │                                   │                        │
                                   │                                   ├─► W7 text editing      ├─► W5 probes & footers ─► W6 viewport provenance
                                   │                                   │                        │
W11 [%workspace] PPX ◄─────────────┘ (needs W1, W2)                    └─► W9 macros UI, notes  └─► W8 geometry-driven loops
W10 contexts & composable shell (needs W3, W4)          W12 migration & removal (last)
```

| Milestone | Size | Libraries touched | User-visible result |
|---|---|---|---|
| W0 | S | pdk, sop_catalog, prismel_editor | loops can merge grouped pieces; set_color takes a colour and a group |
| W1 | L | flow | the full language checks and prints, tested on the 11 case studies |
| W2 | L | flow, flow_sop, procedural | workspaces cook; loops are unrolled deterministically |
| W3 | M | editor_document, prismel_editor, editor_core | the editor opens and saves workspaces (preset v4); v3 converts |
| W4 | L | pxui_graph, prismel_editor | zones, rails, iteration selectors, λ zones, chips and output rows in the graph |
| W5 | M | flow, prismel_editor, pxui_graph | values per iteration, sparklines, branch counts, invariant badges |
| W6 | M | pdk, pdk_prismel, prismel_editor | clicking a shape selects the node and iteration that made it |
| W7 | M | pxui, pxui_shell, prismel_editor | editable, selection-scoped Lisp with atomic apply |
| W8 | M | procedural, flow_sop | `for` over points and pieces, cached per (path, index) |
| W9 | S | prismel_editor, pxui_graph | macro lens and make-macro, notes, bypass flag |
| W10 | L | flow, editor_document, pxui_shell, prismel_editor | scene/world/settings graphs; the editor shell is an editor graph |
| W11 | M | ppx_prismel, flow_sop | `[%workspace]` in sketches, typed inputs, write-back |
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
2. **`sop/merge` accepts any number of inputs** by turning the three fixed
   slots into a rest slot.
   - `Edit_graph.factory_slots` takes `?slots`. Add a `Rest of string` slot
     kind in `Edit_graph.input_requirement`: an array of any length ≥ 1.
   - The `sop/merge` factory declares `[Rest "input"]` and calls `Sop.merge`
     directly.
   - Manifest: `(slots (slot "input" rest))`. Accept with `dune promote`.
   - `ponytail:` if a rest slot turns out to touch too much of `Edit_graph`,
     W2 can instead build one internal `flow.merge_n` node per collected
     list (`Sop.merge` already takes a list). Try the rest slot first,
     because Pxui_graph's `+ input` row needs it anyway.
3. **`sop/set_color` gets a `group` text field and a `color` vec3 group.**
   - `color_r color_g color_b` are floats 0–1 with `[@sop.vec3 "color"]`;
     `alpha` becomes a float.
   - The preset v3 loader maps old `red/green/blue/alpha` ints by dividing by
     255.
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
- editor preset v3 load test for set_color migration
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
- **The check.cjs suite, 114 cases.**
  - Port each `t('…', …)` into an OCaml assertion.
  - The value expectations need W2's evaluator; put those in
    `test_workspace_eval.ml` once `Flow.Eval` exists (end of W1).
- **Every register rule marked as a proposed rule** gets at least one
  positive and one negative test.
- **Round-trip law** on the 11 fixtures and a construct-coverage file.
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
- all 11 fixtures check, print canonically and round-trip;
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
     one merge node with a rest slot (W0.2).
   - **Parameters driven by `t`.** They stay `Expr` drives through the
     existing value lane, so animation does not re-lower.
3. **Rule `E_TIME_COUNT`.** Loop *counts* and *collections* may not depend
   on `t`, because that would re-lower every frame. Parameters may.
   - `ponytail:` this keeps unrolling valid. Lift the rule only if a case
     needs time-varying counts, and then prefer the W8 zone step.
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

### W3 — Document v4 and history (`editor_document`, `prismel_editor`)

**Reuse.**
- `Editor_core.History.record ~label ~merge`, which already holds whole
  immutable documents.
- `Store` and the `Preset` v3 loader.
- `Network_layout` for per-network view data.

**Build.**
1. `Editor_document.Workspace_doc` (new, UI-free):
   ```ocaml
   type t = { source : Flow.Syntax.t list;          (* authored truth *)
              checked : Flow.Workspace.t;           (* cached, derived *)
              layout : Layout_by_path.t;            (* positions, collapsed zones, frames; keyed by path *)
              settings : Settings.t }
   val of_text : catalog -> string -> (t, Flow.Diagnostic.t list) result
   val edit : catalog -> t -> Flow_edit.op -> (t, Flow.Diagnostic.t) result   (* re-checks atomically *)
   ```
   - `Layout_by_path` is `Network_layout.t`'s fields keyed by
     `Workspace.path`: at, pinned, rows, bends and wireless, plus
     `collapsed : bool` and `frames`.
2. **`Flow_edit`**, a new module in `flow_sop` so that it stays UI-free,
   holding every gesture as a pure syntax rewrite. Port e1.js/e2.js:
   - `set_arg`, `connect`, `disconnect`, `unfold`, `fold`
   - `wrap_in_loop (For|Fold)`, `hoist`, `rename`
   - `make_local_fn`, `make_macro ~holes`, `inline_macro`
   - `toggle_bypass`, `set_note`
   - `add_item`, `move_item`, `add_field`, `add_node`, `delete_nodes`
   - `set_input_default`, `set_layout_ratio` (W10)

   Each returns `(Syntax.t list, Diagnostic.t) result` and keeps notes (the
   `revec` rule).
   - `ponytail:` one `op` variant type, one `apply`. There is no command
     object hierarchy.
3. **Preset v4:** `{"version":4,"source":"<canonical text>","layout":{…by
   path…},"settings":…}`.
   - The loader accepts v3 by printing the v3 document to text with the
     existing `Flow_sop.Print.network` / `definition`, wrapped in
     `(workspace <name> …)`, and mapping layout ids to paths through
     `binding_lines`.
   - The round-trip laws in `test/test_editor_document.ml` already prove
     this text is faithful.
   - The v3 writer is deleted.
4. **Core.** `Doc.apply` gets one new case, `Syntax_edit of Flow_edit.op`.
   Its label comes from the op (for example "Repeat", "Unfold",
   "Make macro"). One gesture is one history entry, and scrubs use
   `Gesture` merge as today.

**Tests.**
- Every Playwright gesture from the study becomes a pure test in
  `test/test_workspace_edit.ml`: apply the op to a fixture and compare the
  printed text with the expected text. This covers:
  - scrub, connect, the unfold/fold round trip, Repeat, Iterate, hoist,
    rename, make λ, make macro, inline, bypass, notes, list add/move and
    record field add.
- v3 → v4 conversion of every preset in the repo and in the test
  fixtures.
- Undo/redo labels.

**Done when**
- the editor opens a v4 workspace;
- all existing v3 presets load and resave as v4 with an identical cook
  (byte compare);
- existing editor tests pass with the graph pane still showing the
  top-level graph through the old path, which is replaced in W4.

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
       into a projection too, once W3 converts documents.
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
     - `Syntax_edit_requested of Flow_edit.op`
     - `Probe_set of {zone : path; index : int}`
     - `Zone_collapsed of {zone : path; collapsed : bool}`

     `ponytail:` one edit request, not twenty.
3. **Prismel_editor.** `Doc.apply` handles `Syntax_edit_requested` (W3).
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
     analysis), which emits `Syntax_edit_requested (Hoist path)`.
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

### W11 — `[%workspace]` (`ppx_prismel`, `flow_sop`)

**Reuse.** The whole `[%flow]` rewriter: payload read, manifest,
diagnostic location mapping and local node discovery.

**Build.**
1. `[%workspace {| … |}]` uses `Flow.Syntax.parse`, `Flow.Macro` and
   `Flow.Workspace.check` against the manifest, with diagnostics at their
   lines inside the string (as `[%flow]` does). It emits a module:
   ```ocaml
   module Bloom = [%workspace {| (workspace bloom …) |}]
   (* expands to *)
   module Bloom : sig
     val program : Flow_sop.Workspace_program.t          (* source text + manifest digest *)
     module Flower : sig type inputs = { petals : int; seed : int } val default_inputs : inputs end
   end
   ```
   - **Emitting source text.** The PPX embeds the canonical source text,
     not AST data. At run time `Workspace_program.load` re-parses and checks
     it (milliseconds) and verifies the manifest digest.
   - `ponytail:` this keeps the emitter tiny and makes write-back trivial.
     Emitting data is an optimisation for later, if startup measurement
     says so (register O4).
2. `Workspace_program.with_inputs : t -> graph:string -> (string * value)
   list -> t` sets overrides. The typed record converts to that list.
3. `Prismel_editor.Workspace.run : ?config … -> Workspace_program.t -> unit`
   is a thin wrapper over `Editor3.run` with `?program` replaced.
4. **Write back to main.ml** (register O1):
   - The editor knows the source file and span from `Workspace_program.t`,
     recorded by the PPX (`__FILE__` and the string's offsets).
   - The command writes only that string literal after showing a diff in a
     `Prompt`.
   - It is disabled when the file changed since build (compare an mtime
     and hash recorded at startup).

**Tests.**
- ppx expansion tests for every diagnostic class.
- Input record generation.
- A write-back test on a temp file.

---

### W12 — Migration and removal

1. Port sketches that use `[%flow]` (for example `sketches/flow_terrain`)
   to `[%workspace]`. Keep `[%flow]` as sugar: a single `graph` payload
   becomes `(workspace <name> <graph>)`.
2. Delete:
   - `Flow_sop.Print.network`'s editor use (keep it only for the v3
     loader, then delete the loader after one release; record that in
     `flow-migration.md`);
   - the read-only `text_pane`;
   - `Check.program`'s single-graph path, once `[%flow]` is sugar.
3. Update the docs:
   - `flow.md`: status, §8.3, §11 pointer, §17.
   - `api.md`: `[%workspace]`, `Workspace.run`.
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
| The v3 → v4 conversion loses layout | Layout maps ids to paths via `binding_lines`; test every repo preset; keep the v3 loader for one release |
| Pixel parity breaks with new theme tokens | Add tokens only; the parity fixtures gain a zone panel; review PNG diffs |
| The dependency gate: `Flow_edit` / `Projection` needing UI | Both live in `flow_sop` and are UI-free by construction; the gate test enforces it |
| Merge padding changes existing geometry | Padding only adds empty groups when inputs differ; existing merges with identical schemas produce identical bytes (tested) |
| PPX startup cost of re-parsing text | Measure; parse + check of the Bloom fixture is expected in the low milliseconds. Switch to data emission only if measured |

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
   - The eleven fixtures, the 114 model checks and the 48 register rules are
     the acceptance tests.
   - When the study and this plan disagree, the register wins. Update the
     study so they agree.
5. **Record measurements in every PR** that touches cooking, lowering or
   drawing: command, machine, domains, before/after numbers.
6. **Record each milestone** in `specification/flow-migration.md` under a
   new "Workspace" section, with its date, what landed and any deviation
   from this plan.
