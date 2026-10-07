# One operator registry: migration strategy

Date: 2026-10-07. Base: `dev` at `8ea576b2` (one declaration per SOP, done; `MIGRATION.md`).
Roadmap: this is Phase 1, item 1 of "Rays Lisp as a compiled language" (the owner's doc), the
first step after Phase 0. Status: done. Implemented, verified with the native shipping gate
on 2026-10-07 and committed to `dev` as one commit.

## Implementation record (2026-10-07)

| Roadmap item | Implementation | Verification |
|---|---|---|
| Phase 1, item 1: one operator registry | Done: `Flow.Op.all` owns all 58 declarations; checker, evaluator, compiled arithmetic and editor read them | Registry sweep, existing value/workspace/editor tests and baseline comparisons pass; `check.exe --ship` (`@all`, `@runtest`, `@smoke`, `git diff --check`) passed natively on 2026-10-07 |

The roadmap doc ("Rays Lisp as a compiled language") was actualized on 2026-10-07: this row is
done, prefix dispatch is gone, and opening the variants stays open under Phase 1.

Steps 1–6 are implemented, including step 6's deletion, documentation and API promotion.
Mechanical moves used OCaml compiler-AST codemods for
operator signatures/bodies and all affected `Struct` sites, followed by `codemod drop-unused`
and `codemod prune --target @all lib/flow lib/rays_editor` to a fixpoint. There is no parallel
legacy implementation or compatibility layer.

Three details refine the original sketch below:

- `Struct` stores its resolved `Ty.t` alongside the head and arguments. This lets pure
  `Value.ty_of` and formatting distinguish panels, editors, materials and deferred element
  lists without a catalog or prefix lookup. Checked catalog calls and catalog function values
  retain their `Context.t`; the evaluator derives the stored type with `Ty.of_context`.
  Deferred SOP lists retain their former dynamic `List Any` type. Existing tests changed only
  mechanically to accommodate the additional field; their assertions remain intact.
- OCaml requires equal type arities for a variant re-export. `Eval` therefore re-exports
  `('f, 'r) payload = ('f, 'r) Value.t`, then specializes `value = (fn, residual) payload`.
  Constructor names remain available through `Eval`; no separate value implementation remains.
- A body receives the evaluator's plan-node callback, so `sop/curve` owns its behavior in its
  declaration. The eight arithmetic records also carry their binary closures, read through
  `Op.arith`, preserving specialized binary dispatch in the compiled arithmetic path.

Unused exports removed during cleanup are `workspace_window`, `Editor3.default_layout`,
`Editor3.graph` and `Workspace.run`; internal entry-point behavior remains implemented.
`Workspace.op_signature`, `value_ops`, `op_choices`, `name_taken` and `special_forms` remain
registry readers with their original argument and result types. `flow_manifest.sexp` is unchanged.

Baseline evidence uses `8ea576b2`, not an earlier migration checkout: 30 workspace inputs
(all 12 fixtures and 18 stock-catalog sketches), static plans and live evaluation/records at
`0`, `0.125`, `1.25` and `7`, plus all seven contexts' 336 completion entries. Cook hashes,
retained-entry counts, evictions and exact payload bytes were compared for every lowered
fixture graph with session capacities 32 and 512, cold then seven warm cooks (272 records).
The complete 759-line canonical snapshots match byte for byte; both SHA-256 values are
`5dc4e50fc1103b5f49c05b9d18f7c792d876a059b6daab14f7c98274696b898d`.
An additional 15-line comparison covers `specification/pxui-kit/kit.rays` and both host-owned
catalogs, `sop_gallery` and `voxel_wall`, using their actual factory declarations extracted by
an OCaml AST codemod. Their static plans and evaluation/records at the same four times also
match byte for byte (SHA-256
`e220a70c483ce7e4f43f2b0a89c2b88f9d773f923742e002e654538a3dfbdc9f`).
Together these cover every checked-in `.rays` file and all twelve generated fixtures.
Both hosts' own runtests pass; `voxel_wall`'s stock-catalog rejection is identical before and
after. Temporary snapshot tooling was kept outside the product tree after comparison.

The 58-record sweep also checks optional/rest/keyword inputs, arithmetic closures against
bodies, concrete validation and residual skipping, Material heads inside macros, and catalog
aliases/function values whose names do not encode their context. Existing bit-exact random
hash and compiled-residual/interpreter tests remain green.

`bench_workspace_lower _build/default/specification/workspace/cases 7` was measured sequentially
against the base and migrated trees, dev profile, OCaml 5.3.0, arm64 macOS, eight available
domains. Evaluation runs on the initial domain; cooking uses the default context domain count.
The benchmark now reports median evaluation allocation as well as timings. Representative
results (evaluation ms / allocated bytes; node counts unchanged):

| Fixture | Nodes | Before | After |
|---|---:|---:|---:|
| bloom | 84 | 0.118 / 501,088 | 0.108 / 470,760 |
| sunflower | 241 | 1.006 / 4,114,096 | 0.896 / 3,887,248 |
| tiles | 193 | 0.323 / 1,178,448 | 0.349 / 1,105,008 |
| wave | 13 | 3.909 / 16,778,168 | 3.976 / 15,035,576 |

Allocation fell on all twelve fixtures; timings are mixed, so this is not a speedup claim.
The larger immutable operator declarations add 12,640 live bytes before catalog creation.
The native Metal and display failures also reproduce on the unmodified base checkout.

Passing gates are `@check`, `@all`, `@lib/flow/runtest`, `@lib/sop_catalog/runtest`,
`@tools/api_manifest/runtest`, `@lib/editor_core/runtest`, `@lib/pxui_shell/runtest`,
`@test_text_pane`, `@test_rays_editor_logic`, `@test_scene_sync`, `@test_editor_consistency`,
`@test_workspace_doc`, `@test_workspace_shell`, `@test_workspace_source`, `@test_workspace_live`,
`@examples/sop_gallery/runtest`, `@sketches/voxel_wall/runtest` and `git diff --check`.
`@doc` passes with existing unresolved odoc references. `codemod dead-exports lib/flow
lib/rays_editor` reports no unused exports.

The implementing agent's SSH/tmux processes could not reach Metal or SDL displays, so the
native gate ran afterwards from the owner's console session (Apple M1, Metal):
`_build/default/tools/check.exe --ship` passed on 2026-10-07. Tests were not weakened or
moved to another alias. The per-step commits proposed below were collapsed into one commit
on `dev`.

## Why this area, why now

Phase 0 cured one disease: a SOP was declared three to six times and the copies drifted. The
built-in operators of the workspace language (`+`, `range`, `value/rand`, `scene/merge`,
`ui/split`, ...) have the same disease, in smaller print: an operator is spelled in up to six
places, and two of them, the checker's signature table and the evaluator's `match`, are tied
together only by a string. Everything the roadmap wants next needs to add operators: live
inputs (`frame/dt`, `pointer/x`), state (`state/prev`), packed arrays, and the whole 2D domain
(`draw/*`). Today each of those edits `lib/flow/workspace.ml`, `lib/flow/eval.ml` and two
editor files by hand, in step. The registry makes an operator one record, so a domain is a
list of records and nothing else.

Rungs tried, in order: it does need to exist (the next four roadmap items each add operators);
nothing in the codebase does it (the SOP PPX derives from a record, but an operator has a typed
output function and an OCaml body, not a parameter record); the standard library has nothing to
offer; it is not one line. So: the minimum record that both the checker and the evaluator read.

## Where we are (measured, `dev` 8ea576b2)

58 built-in operators, declared in `Workspace.ops` (`lib/flow/workspace.ml:90-139`):
40 value operators, 3 `sop/` (`curve`, `point_list`, `piece_list`), `scene/merge`,
`material/standard`, `world/none`, 13 `ui/`.

One operator is spelled in these places today:

| Where | What it says | Sites |
|---|---|---|
| `Workspace.ops` and `find_op` (`workspace.ml:70-148`) | name, context, positional/optional/rest/keyword inputs with types, output type function, `any_num` | 58 records, 37 quoted names |
| `Eval.value_op` (`eval.ml:289-387`) and `arith_fns` | the body, dispatched by name; `\| _ -> arity ()` swallows a missing arm as `E_ARITY` | 8 + 37 arms |
| `Eval.apply_op` (`eval.ml:746-761`) | which names make a `Struct`, which splice lists (`scene/merge`, `ui/tile`), which make a plan node (`sop/curve`) | 5 `if`s by name |
| `Eval.check_struct` (`eval.ml:395-430`) | range checks of `ui/split`, `ui/split-at`, `ui/tile`, `ui/graph`, `ui/lisp`; reads `Workspace.op_choices` back | 5 arms |
| `Eval.struct_ty` and `is_struct_op` (`eval.ml:134-139`, `:253`) | the `Ty` of a `Struct`, by name prefix (`scene/`, `world/`, `settings/`, `ui/`, `material/`) | 2 prefix lists |
| `Eval.compile` (`eval.ml:517-528`) | the residual compiler redoes the arithmetic dispatch through `arith_fns` | 1 |
| `Eval.ev` (`eval.ml:663`) | a catalog `Call` is a `Struct` when its kind starts with `scene/`, `world/`, `settings/`; the checker already knew the kind's `Context.t` and dropped it | 1 prefix list |
| `Lisp_text.ops_of` (`lib/rays_editor/lisp_text.ml:214-226`) | the operators of each context, spelled again by hand (its own `ponytail:` comment says so) | 20 quoted names |
| `Lisp_text.contexts`, `ws_context` (`lisp_text.ml:205-211`) | the context names and the string → `Context.t` map, again | 7 + 7 |
| `Core_add.categorize` (`lib/rays_editor/core_add.ml:31-36`) | the node menu's category of each value operator | 5 arms |
| `Workspace.known` (`workspace.ml:323`) | the contexts an operator may live in: `[Value; Sop; Scene; World; Settings; Editor]`, `Material` forgotten | 1 |
| `Workspace.type_names` (`workspace.ml:67`), `Check.known_prefix` (`check.ml:211`) | type names and namespace names, beside `Ty.names` and `Context.of_string` | 2 |

Counted: 26 quoted operator names in `eval.ml`, 37 in `workspace.ml`, 20 in `lisp_text.ml`.
`Workspace.op_signature`, `value_ops`, `op_choices`, `special_forms`, `name_taken` are the
public surface; callers are `Flow_sop.Projection` (1), `Flow_sop.Flow_edit` (6, `name_taken`),
`Lisp_text` (8), `Core_add` (2), `Eval` (3).

No test sweeps the operators: a signature with no body, or a body the signature never admits,
is found by a workspace that happens to call it. The 27 `scene/`, `world/`, `settings/` and
`ui/` names in `lib/editor_document/contexts.ml` are the host's own factory kinds and panel
layout, not operators; they stay.

## Target

An operator is one record, in one module, read by everyone:

```ocaml
(* lib/flow/op.ml *)
type signature = { pos : (string * Ty.t) list; opt : (string * Ty.t) list;
  rest : (string * Ty.t) option; kw : (string * Ty.t) list }
type shape = Scalar | Struct of { splice : bool }  (* a value, or a scene/world/settings/ui/material value *)
type t = {
  name : string;                         (* "value/lerp", "ui/split" *)
  ctx : Context.t;                       (* Value runs everywhere *)
  signature : signature;
  out : Ty.t list -> Ty.t;               (* the checker's output type from the input types *)
  any_num : bool;                        (* int, float or vec3 at every input *)
  choices : (string * string list) list; (* ui/graph :view, ui/lisp :tab *)
  shape : shape;
  check : (string * 'v) list -> unit;     (* E_RANGE on concrete arguments; Struct only *)
  body : (string * 'v) list -> 'v;        (* the evaluator *)
  category : string;                     (* the node menu: Math, Compare, Convert, List, Text *)
}
```

`'v` is `Value.t`, moved out of `eval.ml` unchanged except that `Fn` and `Residual` carry type
parameters (`('f, 'r) Value.t`), because `fn` and `residual` close over the evaluator's own
state and must stay there. `Eval` re-exports `type value = (fn, residual) Value.t = Int of int
| ...`, so every `Eval.Int`, `E.Struct ("scene/root", _)` pattern in `editor_document`,
`flow_sop` and `rays_editor` compiles as it is. Operator bodies never look inside a residual
(the evaluator forces before calling, and `check` skips them), so they are polymorphic in
`'f` and `'r` and the module order is `Ty → Context → Value → Op → Workspace → Eval`.

Four rules:

1. **One record.** The checker reads `signature`, `out`, `any_num`, `ctx`, `choices`; the
   evaluator reads `shape`, `check`, `body`; the editor reads `name`, `ctx`, `category`,
   `signature`. No module keeps a list of operator names.
2. **Context decides, not the prefix.** A `Struct` is what an operator of shape `Struct`
   returns, and a catalog `Call` is a `Struct` when the kind's context is not `Sop`
   (`Context.supports_values` is already that predicate, with `Material` as the one special
   case that both holds values and builds a `Struct`). `W.Call` carries the kind's context from
   the checker; `struct_ty`, `is_struct_op` and the prefix list at `eval.ml:663` go.
3. **The editor derives.** `Lisp_text.ops_of ctx` is `Op.of_context ctx`; `Core_add.categorize`
   is the record's `category`; `Lisp_text.contexts` and `ws_context` are `Context.all` and
   `Context.of_string`; `Workspace.type_names` is `Ty.names`.
4. **Nothing moves semantically.** Every body is the existing arm, cut and pasted; the
   test is byte-identical evaluation of every checked-in workspace before and after.

Not a mutable registry. The list is a value in `lib/flow/op.ml`; a second domain adds a second
list and `Op.all = value @ sop @ scene @ ... @ draw`. Registration by side effect at module
initialisation was considered and rejected: `rays-lisp check` links `Workspace` without `Eval`
(the audit's step 0.2), so a table filled when `Eval` initialises would be empty there.

## Steps

Each step leaves the tree green, is one commit, and is worth having without the next.

| | Step | How | Test |
|---|---|---|---|
| 1 | **`Value` out of `Eval`.** New `lib/flow/value.ml`: the `value` constructors as `('f, 'r) t`; `Eval` re-exports `type value = (fn, residual) Value.t = ...`. `hash`, `fmt4`, `num`, `truthy`, `to_int`, `round`, `arith`, `comps`, `is_vec`, `coerce_to`, `key_of`, `show_with` move with it (they read only constructors). | Pure move; `codemod` cannot do a type re-export, so by hand, compiler-driven. | `@lib/flow/runtest` unchanged; `api_stable.json` shows the additive `Value` module and no change to `Eval`'s constructors. |
| 2 | **`Op` record and the 58 records.** New `lib/flow/op.ml` with the type above and `Op.all`. Each record's `signature`/`out`/`any_num`/`ctx` is the existing `Workspace.ops` entry; its `body` is the existing `Eval.value_op` arm (value operators get `body = positional f` which drops names and calls `f : 'v list -> 'v`); `shape`/`check` are the `apply_op`/`check_struct` arms; `choices` is `Workspace.op_choices`'s data; `category` is `Core_add.categorize`'s answer. `arith_fns` becomes the eight `+ - * / mod pow min max` records sharing one `arith` helper. | Cut and paste, one operator at a time within the commit; the compiler's exhaustiveness on the old `match` is gone, so step 2's sweep test is written first. | `test_op.ml`: for every record in `Op.all`, build arguments from the signature (`Float → 1.5`, `Int → 2`, `Bool → true`, `Vec3 → [1 2 3]`, `Text → "a"`, `List e → two of e`, `Panel → ui/outline`, `Scene`/`World` → the empty struct), call `body`, assert no `E_ARITY`, and assert `Ty.fits (Value.ty_of result) (out (input types))`. Rest and optional inputs are tried absent and present. |
| 3 | **Checker reads `Op`.** `Workspace.ops`, `mk`, `num2`, `unary`, `compare_op`, `bool_op`, `panel`, `leaf`, `op_table`, `find_op`, `op_choices`, `value_ops`, `op_signature` become readers of `Op.all` (`find_op` is `Op.find name ctx`, the bare-name `value/` fallback kept). `W.Call` gains `ctx : Context.t` from `k.context` at `apply_kind`. `known` at `:323` iterates `Context.all`. `type_names` is `Ty.names`. | The `op` record type in `workspace.ml` is deleted; `op_signature` stays as the public type (it is `Op.signature`). | `test_workspace.ml`, `test_check.ml` unchanged. A new case: `material/standard` is a known head in a Material graph (the forgotten context). |
| 4 | **Evaluator reads `Op`.** `apply_op` is: look up the record, splice if `shape = Struct {splice = true}`, `check`, `body`. `value_op`, `arith_fns`, `check_struct`, `struct_ty`, `is_struct_op`, `value_op_name`, `is_element_list` are deleted; `Eval.compile`'s arithmetic fast path reads the eight records' bodies through `Op.arith` (the `Const`/`Dyn` folding stays as it is). `ev`'s `W.Call` arm reads `ctx` instead of the prefix list; `ty_of (Struct (n, _))` is `(Op.find n).out []` for operators and `Ty.of_context ctx` for catalog structs (the `W.Call` ctx is stored in the `Struct`: `Struct of string * Context.t * ...` is one more field, or the record is looked up by name through a `Check.catalog` the evaluator already has in `st`; pick the lookup, fewer type changes). | The `Eval.Private.compile_residuals` bit-for-bit test already compares closure against interpreter; it covers the compile path. | `test_workspace_eval.ml` unchanged; `test/lisp_build.t` and every `sketches/*/sketch.rays` through `rays-lisp check`; `bench_workspace_lower ... 7`: byte-identical plan, cook hash and node counts for all 12 fixtures. |
| 5 | **Editor derives.** `Lisp_text.ops_of` is `Op.of_context`; `contexts`/`ws_context` are `Context.all`/`Context.of_string`; `Core_add.categorize` is `(Op.find op Value).category`. `Check.known_prefix` is `Context.all` plus `user`. | Deletions; `codemod drop-unused` for what they leave behind. | `test_lisp_text` completions for each context list the same names as before (snapshot taken in step 2, compared here); `test_editor_logic` node-menu entries unchanged. |
| 6 | **Delete what is dead and document.** `codemod prune`/`drop-unused` on `lib/flow`, `lib/rays_editor`; `dune promote` the API manifest; `specification/flow.md` §11.4 names `Flow.Op` as the resolution table; this migration's Phase 1 implementation row is marked done (the separate roadmap is the owner's handoff). | | `--ship`. |

Steps 1 and 2 are additive (the old tables still exist). Steps 3 and 4 are the switch-over and
can be one commit if the sweep test from step 2 and the byte-identical fixture run both pass;
keep them separate if either fails, so the bisect is one module.

Expected size: `workspace.ml` loses about 80 lines, `eval.ml` about 150, `lisp_text.ml` and
`core_add.ml` about 25; `op.ml` is about 200 and `value.ml` about 120, mostly moved. Net is
roughly zero lines; the gain is one declaration, not fewer lines. Not measured until step 6.

## No regression

- Every checked-in `.rays` (`sketches/*`, `specification/workspace/cases/*`, the two
  host-owned catalogs through their own checks) passes `rays-lisp check` and evaluates to the
  same plan: `bench_workspace_lower ... 7` reports unchanged node counts, retention, payload
  and cook hash; `test_workspace_eval`'s determinism cases (`wave`, `orrery`, `sunflower`,
  `bloom`, `tiles` at several times) are unchanged.
- The `value/rand` hash cases (`test_workspace_eval.ml:413-424`) are bit-exact, as they are.
- The compiled-residual comparison (`Eval.Private.compile_residuals`) still runs against the
  interpreter bit for bit.
- `flow_manifest.sexp` does not change: operators are not catalog kinds.
- No existing test is edited except to read `Op` where it read `Workspace.ops` directly; none
  does today.
- `api_stable.json`: additive (`Value`, `Op`), and `Workspace.op_signature`, `value_ops`,
  `op_choices`, `name_taken`, `special_forms` keep their types. Promote once, at step 6.
- Edit latency: `Op.find` is a `Hashtbl` built once at module initialisation, as `op_table` is
  today; no per-call list scan over 58 records (the editor calls `op_signature` per keystroke
  in `Lisp_text.complete`).

## Decisions (taken 2026-10-07)

1. **`Struct` carries its context or looks it up.** Rule 2 needs the evaluator to know a
   catalog struct's `Ty` without the prefix. Decided: neither of the two options sketched;
   `Struct` stores its resolved `Ty.t` beside the head and arguments (see the implementation
   record), so `Value.ty_of` is pure and needs no catalog. The pattern sites in
   `editor_document/contexts.ml` changed mechanically by codemod.
2. **`material/standard`'s shape.** Decided as recommended: a `Struct` record with
   `splice = false`; "shape is a field", not "shape follows the context".
3. **Does `Flow_sop.Lower` keep its three kind-name tests** (`sop/merge`, `sop/curve`,
   `sop/material`)? Decided: yes. Lowering a specific SOP kind to its `rdk` node is that
   kind's business, not an operator-table concern.

## Skipped on purpose

- **A mutable, open registry** (`Op.register`): the roadmap row says "open registry"; a list
  value in one module is open to a second list and has no link-order failure mode. Add
  `register` when a domain lives in a library that `flow` cannot see, which is not the case for
  anything on the roadmap (`draw/*` belongs in `flow` or a sibling it can list).
- **Opening `Ty.t` and `Context.t`** (roadmap Phase 1, item 2): 33 match sites on the six
  struct constructors of `Ty.t` (21 in `workspace.ml`), 15 on `Context.t` across 7 files, and
  `Port_type.t` in 12 files. The registry removes the name-prefix dispatch, which is the half
  of that row that bites today; opening the variants is only needed when a domain needs a type
  the checker cannot name, and 2D's `drawing` is one constructor added to `Ty.t`, not a reason
  to open it. Revisit when the second such type appears.
- **A typed deferred node for `Geo of int`** (Phase 1, item 4): independent of this; 10 sites in
  `lower.ml`, 6 in `probe.ml`, 25 in `eval.ml`. Plan it with the 2D drawing value, which is its
  first second case.
- **A neutral graph layer** (Phase 1, item 3): `pxui_graph` references `Procedural` in one
  signature (`node_menu.mli`, `Edit_graph.factory`); `Projection`, `Flow_edit` and `Probe`
  reference no `Procedural` module at all, only `Check`, `Workspace`, `Eval`, `Param`,
  `Exposure`. The move is a `dune` change and a gate rule, not a refactor; do it when 2D needs
  the pane without the geometry stack, with the gate test extended first.
- **Deriving operator records with the PPX**: the SOP PPX derives from a parameter record; an
  operator's `out` is a function of input types and its body is OCaml. A record literal is
  shorter than an attribute grammar for 58 entries.
- **Generating `specification/flow.md`'s operator list from `Op.all`**: one `grep` in review
  until the list changes more than once a quarter.
