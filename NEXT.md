# Phase 4 entry: a measured edit loop, open names, and the Flow IR with a CPU kernel tier

Date: 2026-10-07. Base: `dev` at `c011f225`. Roadmap: the owner's doc "Rays Lisp as a
compiled language" (Phases 0 to 2 and the canvas half of Phase 3 are done: 8ea576b2, 629178d1,
96bbc253). This file is the handoff for the next big item. It records what the code shows
today, the owner's decisions, the order to build in, the gates, and the no-regression contract.
Delete it when the item ships; the record goes into the commit message and `specification/`.

Implementation checkpoint (2026-10-07): Step 0 is implemented and passes
`_build/default/tools/check.exe --ship`, including native smoke. Baselines and
commands are recorded in `specification/performance-log.md`, "Phase 4 edit and
kernel baseline". Step 1's one-check/one-evaluation subtask is implemented:
`Lower.of_checked` takes the document's check, bypasses catalog reconstruction,
and retains recording data for `sync_scope`. Counts and value/plan/record parity
are tested on the 12 fixtures. Its measured 2,000-node scrub is still 76.226 ms
versus a 12.631 ms drag, so the literal fast path remains required. The rest of
Step 1 remains required, except the view-state subtask is now implemented: `v`
previews a lexical node at its loop selectors without changing source or history.
Static, nested geometry, piece and live/fold previews, framing and picking are
tested. It passes `--ship` and the native Shattered Cube VIEW regression. The
remeasured 2,000-node scrub is 68.178 ms versus a 12.415 ms drag; the target is
still unmet. A catalog-literal patch now avoids printing, parsing and checking;
static SOP parameters also reuse lowering and update pane rows without projection
or layout. It passes `--ship`, including source/plan/probe/cook comparisons,
static loops, comment preservation, rejection, undo and spelling-only changes.
The latest sequential run measures scrub versus drag at 1.963/2.163 ms (200),
7.396/7.156 ms (1,000), and 12.664/12.354 ms (2,000). The strict target is still
unmet at the larger sizes. Non-SOP values, geometry templates and frame folds
still use full lowering; generic value literal edits, the full checked-in-file
scrub sweep and the time budget remain required. Layout pruning now validates
remapped authored keys without projection, and a pane reuses an unchanged
graph's projection across structural edits elsewhere; dependency type changes
invalidate that reuse. This addition passes `--ship`. Its sequential benchmark
measures scrub versus drag at 1.977/2.060 ms (200), 7.183/7.190 ms (1,000), and
12.313/12.354 ms (2,000), meeting the latency target in this run with a thin
margin; the preceding run was slightly above it at the larger sizes.
Text-pane number scrubs now use the printer's token IDs to emit `Set_arg` in
all three tabs; active scrubs patch cached text/spans and release restores
canonical printing. Pointer tests verify zero pipeline calls, slow-path saved
bytes and one document undo entry for repeated static SOP scrubs. Unapplied
drafts retain whole-text checking/merge. Width changes, hard-bound rejection
without changing the document, and recovery from the retained draft are
tested. This addition passes `--ship`. Generic literal and non-static/non-SOP lowering
cases, file coverage and the budget are still required. Steps 2–4 and all
whole-item gates remain required. Keep this file until the full item ships.

Numeric vector component edits now preserve the fast path across Int/Float
spellings, and invalid Boolean vectors use the checker's refusal. Evaluation
retains an authored-form ID per plan node outside the semantic plan, allowing
static SOP parameter patches in anonymous nested cards, thread steps, defn
copies and graph overrides. Focused checks compare source bytes, plans and
one-/three-domain cooked bytes with the full path and verify zero check,
parse, evaluate and lower calls for these cases. Retained function records
keep full lowering until their captured checked bodies can be rebound.
This addition passes `--ship` with the evaluation metadata API promoted.
The sequential benchmark measures scrub versus drag at 1.954/2.062 ms (200),
7.078/7.191 ms (1,000), and 11.969/12.338 ms (2,000); the static SOP workload
meets the median target in this run. Whole-item gates remain pending.

Step 2's implementation and toy-domain gate are now in place. Domain types
are `Ty.Named` values; context descriptors supply result types, groups, colors
and catalog prefixes. An immutable workspace-owned `Op` list reaches checking,
evaluation, edits, projection, completion, menus and preset/source reloads.
`test/test_open_domain.ml` adds one type, one context and one operator list,
then checks its colored card, menu insertion through the editor host, help,
completion, reload and refused declarations. Constructor uses were migrated
with `tools/codemod open-domains`; its typed-AST locations are checked against
the current parsed constructors to refuse stale locations in strings/comments.
The intended API manifest is reviewed and promoted. `@all` and `@runtest`
pass window-free. The Step 2 `--ship` attempt fails native smoke because SDL
cannot find a display in this restricted session; that gate is unverified.
The sequential 2,000-node scrub/drag medians are 12.381/12.195 ms and the
1,000-node medians are 7.705/7.305 ms, so Step 1's strict median target is
again unmet. Measurements and remaining evidence gaps are recorded in
`specification/performance-log.md`, "Phase 4 open names checkpoint".
Steps 3–4, the remaining Step 1 work and whole-item gates remain required.

Step 3's declaration and component-cache implementation is now in place.
`Node.facts` subsumes the cook mode; the PPX derives parameter-sensitive
reads/writes, and the default declaration is exported through the factory,
Lisp manifest and `Flow.Check` metadata. Ten registered `Duplicate_input`
nodes declare preserved topology; scatter explicitly remains irregular and
topology-changing. Tests prove physical topology preservation and exact
authored bytes at one/eight domains, skipped transform/normal recooks after
color payload edits, fresh untouched attributes and diagnostics, proper
invalidation, bounded payload accounting and traced refusal of false facts.
Fallback normal reads and selected Mountain height reads are covered.
Expanded-zone body diagnostics survive hits while ordinary input diagnostics
refresh. The intended API, catalog and generated-ML digest changes are reviewed
and promoted. Window-free `@all` and `@runtest` pass, and all twelve workspace
cook hashes, node counts, retention and payload totals match Step 2.
Measurements are in `specification/performance-log.md`, "Phase 4 kernel facts
and component cache checkpoint". The strict scrub target is still unmet at
1,000 and 2,000 nodes; warm cache traversal is slower in this measurement.
Step 4, the remaining Step 1 cases and all whole-item gates remain required.
Native presentation remains unverified in this restricted session. Keep this
file until the complete item passes its gates.

Step 4 is now partially implemented. `flow_ir` has a typed dataflow graph,
specialized residual captures, cardinality origins, frame/event rates,
precision, authored provenance and tested sharing/hoisting/pruning/fusion-group
passes. Graph overrides have distinct instance identities; potentially failing
unused bindings remain evaluation roots. Placement refuses approximate
catalog/export/state/cache inputs unless explicitly read back. `(exact x)` is
an ordinary editable operator card. The value lane prepares IR programs once
per network, retains the existing scalar closures and runs supported packed
arithmetic maps in 1,024-element blocks through the shared domain pool. Probes
use the independent reference walker. Live packed maps/for/scan now defer
correctly; their reference evaluation budgets blocks separately, admitting a
million elements while still refusing expensive bodies. Tests compare all
twelve fixtures' arguments, instance inputs/results, values and records at
four times and one/eight domains, plus every element of a million-element
arithmetic map. Window-free `@all`/`@runtest` and the intended API promotion
pass. Measurements are in `specification/performance-log.md`, "Phase 4 IR and
packed arithmetic checkpoint". All twelve cook hashes still match Step 3.
`noise3` now has one canonical declaration, editor/CLI registration, an
editable card and packed execution over the same raw 0..1 sample3 semantics.
Native `noise_displace` now exposes an explicit `normal_3d` mode for the same
normal-displacement formula; its default height_2d output is unchanged. The
arithmetic body over supplied arrays matches native/reference/CPU at four
times and one/eight domains through 16,385 points; the million-point benchmark
also compares native and all execution modes byte for byte before timing.
Scratch is reused over stable chunks of sixteen 1,024-element blocks. The
noise measurements are in `specification/performance-log.md`, "Phase 4 noise
arithmetic and scratch reuse checkpoint". The full SOP kernel connection is
still required: `sop/attr`, `sop/with_attr`, SOP-fact-guided placement, CPU loops/reductions,
cross-map fusion execution, group timing/tier badges, packed fold execution,
the complete checked-in-file/pixel sweep and remaining Step 1 work are still
required. The benchmark currently supplies packed arrays directly; it does
not yet include attribute resolution and geometry writes, so the complete
first-kernel gate remains open. The affected window-free suites and `@all`
pass. The latest full `@runtest` attempt also reaches three existing offscreen
rendering tests that cannot start because this session has no Metal device.
The scrub target remains unmet at 1,000/2,000 nodes; native presentation is
still unavailable in this restricted session. Keep this file until all gates pass.

Step 1 is closed (2026-10-07) on a readjusted gate, at the owner's direction to rethink or
readjust it. A scrub changes a value and must recook what depends on it; a layout drag never
does, so the whole frames were never comparable and the old median target flipped with noise.
The gate is now the scrub frame without its cook phase (`bench_rays_editor`'s new
`rays_editor_scrub_edit_frame` row, computed per sample) against the drag frame, with the
seven pipeline phases at zero. Measured alone: 1.910/2.057 ms (200), 6.808/7.200 ms (1,000),
10.247/12.144 ms (2,000); every earlier run above meets it too. The file sweep the Tests
paragraph asked for exists (`test_workspace_doc`, `part_files`): 338 literals in 20 checked-in
`.rays` files take the literal path and the full path and must save the same bytes and refuse
with the same code; the literal path must repeat no print, parse, check or projection and its
patched lowering must have the full plan. It found and fixed two defects: a lowering-refused
literal reported `E_TYPE` instead of the full path's `E_LOWER`, and `(ref cage)` counted as
a read of the binding `cage`, so `Flow_edit.reorder` refused every full-path parameter edit in
the cube_cage scene graph with a false `E_GRAPH_CYCLE`. The sweep also measured the generic
(non-SOP) literal fallback: the edit itself is at most 0.8 ms in any file, and the rest is the
evaluation the changed value requires (particles: 29.9 of 31.4 ms in `Eval.static` for
10,000 points), which no literal fast path can avoid. The generic value-literal fast path and
the per-frame budget (old subtask 6) are therefore dropped (§5) with that evidence. `--ship`
passes from this console session, native smoke included. Numbers:
`specification/performance-log.md`, "Phase 4 Step 1 closure".

Owner decisions taken on 2026-10-07, in the owner's words: approximate geometry is allowed
because the GPU tier is wanted; measure first and compile incrementally so edit latency stays
fast; the closed variants must not stay closed. Everything below follows those three.

## 1. Where we are (measured against the tree)

Read-only audits of `lib/flow`, `lib/flow_sop`, `lib/procedural`, `lib/rdk`, `lib/rays_editor`,
`lib/editor_document`, `lib/sketch_support`, `ppx/ppx_rays` on 2026-10-07. Line numbers are
from `c011f225`.

### 1.1 The pipeline is whole-program and runs twice per edit

A committed graph gesture goes `Flow_edit.apply_checked` (flow_edit.ml:1556) → for each
candidate rewrite `Flow.Lisp.print` of the whole source, `Syntax.parse`, `Workspace.check`
(flow_edit.ml:1537-1547) → `Workspace_doc.prune` projects every graph and defn
(workspace_doc.ml:74-97; the comment at :160 says projection is 16 ms of a 44 ms edit at 2,001
nodes) → `Contexts.of_workspace` (contexts.ml:869) → `Lower.workspace` (lower.ml:84), which
rebuilds the catalog (`Catalog.of_factories`, lower.ml:89), runs `Workspace.check` a second
time (lower.ml:90) and `Eval.static` (lower.ml:97), then rebuilds every network. On the next
frame `sync_scope` (core_scope.ml:15-17) runs a second `Eval.static ~record:true` and
re-projects and re-lays the shown graph (core_scope.ml:27-54). A value scrub (`Set_arg`,
inspector drag, text-pane number drag) pays this whole path on every pointer-move frame
(core_text.ml:116-127; core_reduce.ml:396-433 only merges the history entries).

Reuse starts only after lowering: `same_network` keeps unchanged networks physically
(contexts.ml:845-856), `Edit_graph.compile_all ?previous` reuses compiled nodes
(cook.ml:194-199), compiled ids are stable through `Lower.t.sites`/`compiled_ids` keyed by
(instance, site index, iteration) (lower.ml:99-114), and the session LRU absorbs cooks.
`Workspace.path` is lexical identity, stable across edits (workspace.mli:20-25), and
`Flow_edit.remap` already says which layout keys an op moves (flow_edit.ml:1590+). Nothing
caches a per-graph or per-binding check or evaluation.

Only the time-dependent path is incremental: `Lower.pending` drives are forced per frame by
`Value_lane.resolve` → `Eval.force` (value_lane.ml:48-82) with no re-lowering.

### 1.2 Nothing times the edit loop

Timers that exist: per-node cook seconds in `Session` (session.ml:307-317, a `Hashtbl` capped
at 4,096 and reset wholesale), total seconds per async request (async_cook.ml:101-103), fps
once a second (core.ml:69-74), and GPU duration in `Runtime.stats`. The status strip shows
"cooked x s" and `Lower.status` (core_status.ml:36-58; lower.ml:412-415). No timer covers
print, parse, check, evaluate, lower, project, layout or `reduce`. No benchmark measures a
syntax-edit or scrub frame end to end; `tools/bench_rays_editor.ml` drags a node, which is a
layout edit and never re-checks (1.58 / 6.49 / 10.1 ms at 200 / 1,000 / 2,000 nodes,
`specification/performance-log.md`). `bench_workspace_lower` reports check / eval / lower /
cook medians (bloom 0.09 / 0.12 / 1.5 / 1.0 ms; wave eval 3.2, lower 7.7); `bench_workspace_live`
reports wave at 7.3 ms per frame, 5.7 ms of it `Eval.force`.

### 1.3 What the evaluator and checker already know, and who reads it

- The checker computes, per term, `{ty; live; live_len; vary; len; fn; ...}` (workspace.ml:91)
  and returns `Workspace.t.live` and `.invariant : Paths.t` (workspace.mli:93-101; set at
  :1444; `invariant` filled at :636 for `let*` inside a zone body). Readers are the projection
  (projection.ml:443), probes (probe.ml:235-264) and the inspector's hoist button
  (core_inspect.ml:341). The evaluator reads neither; it discovers liveness dynamically with
  `Needs_t` (eval.ml:352-359) and afterwards with `frame_dependent`/`state_dependent`
  (eval.ml:879-919).
- The plan is already a flat node array: `node = {id; inst; site; iter; kind; ty; args}`,
  `plan = {instances; nodes}` (eval.mli:75-96), ids sequential (eval.ml:154-162). `Deferred
  (ty, id)` is the only reference. Lowering consumes `plan.nodes` by id (lower.ml:99-100).
- Residuals: `{rid; rterm; renv; rc; previous; mutable fast}` (eval.ml:42-43). `Eval.fast_of`
  (eval.ml:224) compiles literals, `t`, scalar `Value`-context ops (binary ops through
  `Op.arith`, constant-folded), `let` of constants, `if`, and one-clause `sum`/`for` over a
  constant list unrolled to 4,096 (eval.ml:249-317) into closures over boxed `value`
  (`Dyn of Frame_input.t -> value`, eval.ml:210); budget 2,048 nodes per root (:213). Calls,
  `fn`, records, `state`, Hof, `cond`/`case`, `str`, packed loops, fold and scan fall back to
  the tree walker. Bit-exact test: test_workspace_eval.ml:360-413.
- Packed arrays are plain `float array` (`Float_array`, `Vec3_array` interleaved xyz,
  value.mli:2-11); `Value.array_init` (value.ml:173-186); packed `map`/`filter`/`sort_by`/
  `reduce` (eval.ml:614-662) and the packed `loop` writing a growable buffer (eval.ml:665-744).
  `array/sum` and `` `Sum `` add boxed values per element (op.ml:169-194; eval.ml:716).
- `Op.t` (op.mli:8-18): 83 records (test_op.ml:32). Facts an optimizer can read: `live` (the
  only impurity marker), `ctx`, `shape`, `signature`, `out : Ty.t list -> Ty.t`, `any_num`,
  `arithmetic` on the 8 binaries only. Missing: purity (node creation is visible only by a body
  calling `node`), algebraic facts, cost, any packed or unary float kernel.
- Budgets: `Eval.max_steps = 600_000` (eval.ml:5), checker `max_steps = 400_000`
  (workspace.ml:51), `Op.max_iterations = 4096` read at op.ml:95/319, workspace.ml:712/1080,
  eval.ml:151/307/699.
- State: environment-owned `{source; frame; before; next}` (eval.ml:45), keyed by
  `Marshal (inst, prefix @ zone, iter)` (eval.ml:104); `state_stamp` digests the state with
  `Marshal` (eval.ml:89). Reset on digest change or backward frame (eval.ml:97-99).

### 1.4 The cook side: facts declared nowhere, parallelism inside kernels only

- `Node.t` (node.ml:19-40): `cook : node_id:int -> Context.t -> Geometry.t array -> (cooked,
  error) result` is an opaque closure; parameters are a `name=value;...` string plus the typed
  record behind `parameterization`. `cook_mode` (`Generator | Duplicate_input of int | In_place
  | Instance_input | Passthrough | Generic`, node.mli:4-10) is hard-coded in each
  `Node.Private.make` call (129 `Duplicate_input`, 27 `Generic`, 19 `Generator`, 3
  `Passthrough`) and read by nothing in production; it is copied into `edit_graph.mli:31` and
  `graph.mli:9` and checked by tests only.
- The PPX (ppx/ppx_rays/ppx_rays.ml, 783 lines) has field attributes (`sop.default`, `sop.min`,
  `sop.vec3`, `sop.impact`, ...) and type attributes (`sop.node_key`, `sop.node_inputs`,
  `sop.node_slots`, ...; :34-42). There is no slot for element-wise behaviour, attributes read or
  written, topology preserved, or cost. `node_category_attribute` is missing from the
  registration list at :766-770.
- `Session` pulls depth-first and cooks inputs sequentially (session.ml:279-289); the LRU key
  is node id, version, operation, parameter key, input count and each input's whole-geometry
  `data_id` (session.ml:169-186). Component ids (`Geometry.payload_components`,
  geometry.ml:88-98) are used for byte accounting only. The zone loop is sequential with a
  `ponytail:` note at session.ml:243. Capacities: editor 512 entries / 256 MiB
  (core_setup.ml:65-66).
- `Parallel` (rays_math/parallel.mli): `run`, `map_array`, `init_array`, `for_ ?chunk_size`,
  `both`; `chunk_size` (default 64) is both grain and sequential cutoff. The constant is spelled
  `16_384`: 209 hits in lib/rdk, 173 of them `?(grain = 16_384)` defaults; `Context.grain`
  defaults to it too (context.ml:45).
- CPU kernel entry points exist and are nearly unused: `Kernel.map_points`,
  `generate_points`, `generate_point_ranges` have zero non-test callers; `edit_point_ranges`
  is used by `Deform.noise_displace` (deform.ml:588-605; `?cancel ?grain ~amplitude
  ~frequency ~seed`, SOP wrapper sop_shapes.ml:172-210) and `transform` by
  transform_ops.ml:895. Storage is structure-of-arrays `float array` (packed.ml:94-99), no
  Bigarray; attributes carry `data_id` and a rename-stable `storage_id` (attribute.mli:43-46).
- No per-element expression node exists (`sop/attr`, `sop/with_attr`, wrangle). The only
  per-element mechanism is a zone cooking a sub-graph per element (`sop/point_list`,
  `sop/piece_list`; eval.ml:757). `Iso_surface`, `Voronoi2` and `Kernel.map_points` are
  reachable only from OCaml.

### 1.5 The 2D domain is correct and not instanced

`Sketch_support.Drawing.render` (drawing.mli:3-5) emits one `Scene` node per shape; only
`draw/points` batches through `Ink` into one retained display list (drawing.ml:33-52).
`Scene.circle` is `ellipse` whose geometry cache key includes position (scene.ml:93), so a
moving circle misses. The canvas picture is reused only when the plan is physically the same,
nothing is live and the size is unchanged (environment.ml:795-805); any `state` or live arg
re-lowers every frame. `test/test_drawing.ml` pins the static case (4 vs 10,000 points,
198,263 bytes/frame); no test measures a dynamic 10,000-point frame. Ten OCaml examples remain
unported; the operators they would need: rotate, scale, hsl, noise, rounded-rect, quit, audio,
file dialog, PXUI widgets. 2D runs on the interpreter, which is where the roadmap put it.

### 1.6 The closed variants, with the measured cost of the last addition

- `Ty.t` (ty.mli:4-13): 19 constructors; the domain names `Geometry | Drawing | Scene | World
  | Settings | Panel | Editor | Material` have no rule in `fits`/`coerce`/`join` and behave
  only through `=`; `names`/`to_string`/`of_string`/`of_syntax` are table-driven (ty.ml:6-55).
  Exhaustive matches: `Ty.of_context`, `Node_menu.port_color` (node_menu.ml:98-104),
  `Navigator.type_color` (navigator.ml:341-345), `test_op.sample`. Plus about 100 pattern lines
  and 59 `= Ty.X` tests that are single-constructor or structural.
- `Context.t` (context.mli:1): 8 constructors, re-exported with constructors as
  `Workspace.context` (workspace.ml:6, workspace.mli), so four declaration sites. Exhaustive:
  `Context.name`, `supports_values`, `Ty.of_context`, `Navigator.group_of` (:110-112),
  `Navigator.context_color` (:330-338). Hand-kept and not compiler-forced: `Context.all`,
  `Context.of_string` (context.ml:6-13), `check.ml:174` and `catalog.ml:18` which hard-code
  `[Sop; Scene; World; Settings]`, and the help text at lisp_text.ml:199 which still lists six
  contexts and omits draw and material. That last one is drift already in the tree.
- Adding `Drawing`/`Draw` in 96bbc253 cost about 21 edits across 12 lib files; 7 were
  compiler-forced, 9 were by hand (`Context.all`, `of_string`, `Ty.names`,
  `Workspace.shape_ty`, `kind_out`, `Flow_edit.default_for`, `core_inspect.catalog`,
  `core_menu`:54, `rays_editor.ml`:141) plus `api_stable.json`. The hand edits are the risk.
- Constraints on the fix: `Ty.t` and `Context.t` are not Map/Hashtbl keys (ops are looked up
  by `Context.name ctx ^ "/" ^ name`, op.ml:404), but polymorphic `=` is used everywhere and
  `Marshal` reaches `Ty.t` through state values (eval.ml:89, :104). A record with closures
  cannot be `Ty.t`. The manifest stores only `Port_type` names (manifest.ml:52; check.ml:144)
  and infers context from the qualified prefix (check.ml:172-176).
- `Port_type.t` (5 constructors, 13 non-test files, 6 exhaustive sites) is the SOP parameter
  bridge and can stay closed. `Panels.panel` already has string-keyed `View`/`Canvas` (8
  exhaustive sites). `Scene_execution.pipeline_family` (11 constructors) is renderer-internal
  and stays closed. `Value.t` needs no new constructor for a new graph-node domain
  (`Deferred (ty, id)` takes any `Ty.t`); a new data kind (image, field buffer) would need one
  constructor in `Value.t` plus `Eval.payload` (eval.ml:17-31) and six exhaustive functions.

### 1.7 Dependency rules that shape the design

`flow` depends only on `param` and `frame_input` and may never reach `rays_math`
(test/dependency_gate.ml:145, :311), so `Parallel` is not available inside `lib/flow`.
`flow_graph` depends only on `flow` and `param` (:146). Anything that executes kernels in
parallel lives in a new library above `flow`.

## 2. The item

Three steps that are each shippable alone, then the IR. Order matters: timers before any
optimization, the fast scrub path before the IR (it is where edit latency is lost today), open
names before the IR (the IR adds `Ty`/`Context` consumers, and they should be the first ones
that need no edit in `lib/flow`).

### Step 0: timers and benchmarks (measure first)

- `Flow.Phase_timer` (or a record in `Editor3`): monotonic durations for print, parse, check,
  evaluate, lower, project, layout, reduce and cook per edit, sampled with the same clock the
  session uses (`Unix.gettimeofday`, session.ml:307). Hooks: doc.ml:23-26 (edit), lower.ml:90-97
  (check, eval, lower), core_scope.ml:17/29 (recording eval, projection), `Core.update`
  (core.ml:1053-1054, reduce). Surface the last edit's phases beside `Lower.status` in the
  status strip (core_status.ml:54-57) and in the crash report.
- Benchmarks, recorded in `specification/performance-log.md` with machine, OCaml version,
  profile and domains:
  1. `bench_rays_editor` gains an edit frame: a `Set_arg` scrub of one literal for 200 frames
     at 200 / 1,000 / 2,000 nodes, reporting the phase split. This is the number Steps 1 and 4
     are judged against.
  2. A dynamic 10,000-point frame in `test_drawing`/`bench_workspace_live`: particles with the
     state fold running, bytes and ms per frame.
  3. `tools/bench_kernel.ml`: `Rdk.Deform.noise_displace` on a 1M-point grid against the same
     body written as a Lisp kernel (Step 4), one and eight domains. Until Step 4 lands it
     records the rdk side alone; the roadmap names this as the first task of the kernel phase.
- Nothing else in Step 0. No optimization before the numbers exist.

### Step 1: the incremental edit loop

Target (readjusted 2026-10-07, see the closure paragraph above): a scrub frame without the
recook its value requires costs no more than a layout-drag frame at the same node count, and
its print, parse, check, evaluate, lower, project and layout phases are zero. Met. The
original wording compared whole frames and was unmeetable by more than noise. Changes,
smallest first:

1. **Scrub fast path.** `Workspace_doc.edit` already special-cases `Set_arg`,
   `Set_input_default`, `Set_note`, `Toggle_bypass` and `Set_layout_size` to skip pruning
   (workspace_doc.ml:159-163). Extend it: a `Set_arg` that replaces a literal with a literal of
   the same type at the same path patches the source text at that span, patches the checked
   term in place (same `Ty`, same `live`), and patches the network parameter the way
   `Lower.changes`/`Value_lane.resolve` already apply a changed port (value_lane.ml:48-82).
   No print, no reparse, no `check`, no `Lower.workspace`, no projection. The history gesture
   key (flow_edit.ml:1492) is unchanged. Text objects' `Set_parameter` and the inspector's
   `Scene_sync.set_fields` (scene_sync.ml:66) take the same path.
2. **One check, one evaluation.** `Lower.workspace` takes the checked `Workspace.t` from
   `Workspace_doc` instead of re-checking (lower.ml:90), and takes the cached catalog from
   `Contexts.catalog` (contexts.ml:123-130) instead of rebuilding it (lower.ml:89).
   `sync_scope` reuses `Lower.t`'s evaluation with recording on instead of a second
   `Eval.static ~record:true` (core_scope.ml:15-17); make `record` cheap enough to be always on,
   or record lazily per probed path.
3. **Project only what changed.** `Workspace_doc.prune` uses `Flow_edit.remap op` to drop
   layout keys instead of projecting every graph (workspace_doc.ml:74-97); `sync_scope`
   re-projects only the shown graph when its checked term changed (compare by path, not by
   physical identity of the whole `Workspace.t`).
4. **Per-graph check and static evaluation**, only if 1 to 3 leave a scrub or edit above the
   target. `Workspace.check` is a `driver` over top-level forms (workspace.ml:1378-1444); cache
   each defn and graph's result by its printed form and the environment it closes over
   (`defn` names and macros), and reuse `Eval.static` instances by the same key (instances are
   already cells cached by `name|sorted input keys`, eval.ml:796-824). Stop at the step where
   the target is met and record the numbers.
5. **View as view state.** Replace the `Display_set` → `Connect @result` text rewrite
   (core_reduce.ml:352-366) with a displayed-node request carried into `Cook.update`'s
   per-object `displayed` (cook.ml:204-218); the cook path already shows arbitrary nodes
   through `frame_request` and probes (cook.ml:261-268, :327-349). This also lifts the "cannot
   view a node inside a loop" refusal and leaves the document untouched, which the roadmap's
   "Keeping the graph" rules require before fusion.
6. **A budget and a fallback.** Dropped 2026-10-07 with the file sweep's evidence (§5): the
   only scrub over a frame's worth of pipeline in any checked-in file is evaluation the changed
   value requires, and skipping it would hide the scrub until release.

Tests: done in `test/test_workspace_doc.ml` (`part_literals` for the focused cases,
`part_files` for every checked-in `.rays` with a scrubbable literal: zero check, parse,
print and projection calls through `Phase_timer`, same saved bytes, same refusal codes,
same plan after the lowering patch).

### Step 2: open the names

Decision recorded (owner, 2026-10-07): the variants do not stay closed. Research result: open
the nominal part only; keep the structural core closed.

- `Ty.t` keeps `Float | Int | Bool | Vec3 | Text | Color | List | Array | Record | Fn | Any`
  and replaces the eight domain constructors with one `Named of string`, with
  `Ty.geometry = Named "geometry"` and so on as values. `=` and `Marshal` keep working;
  `names`/`of_string`/`to_string` read a registry. The four exhaustive sites become registry
  lookups (`of_context`, `port_color`, `type_color`, `test_op.sample`); the ~20
  `Deferred (Ty.Geometry, _)` patterns become `Deferred (ty, _) when Ty.is_geometry ty` or a
  helper; the 59 `= Ty.X` tests are a mechanical rename. Do it with the compiler-AST codemod
  in `tools/codemod`, as the operator registry migration did.
- `Context.t` becomes an abstract id over a registry of descriptors `{name; result : Ty.t;
  supports_values; label; color; group; catalog_prefix}`, registered in one list in `flow`
  (the way `Op.all` is a list). The five exhaustive sites read the descriptor; `Context.all`,
  `of_string`, `Workspace.context`'s re-export, check.ml:174, catalog.ml:18 and
  lisp_text.ml:199 disappear or read the list. Add a test that every registered context has a
  color, a group, a result type and a help entry, which is what the hand edits in 96bbc253 kept
  forgetting.
- `Port_type.t`, `Panels.panel`, `pipeline_family` stay closed; the note in `flow.md` says why.
- The gate for this step is the one the roadmap wrote for Phase 1: a toy domain (one `Op`
  list, one registered context, one named type) is added in a test without editing `ty.ml`,
  `context.ml` or any `match` in `lib/flow`, `lib/flow_graph`, `lib/pxui_graph` or
  `lib/rays_editor`, and the pane draws its card with a color and the menu lists it.
- Skipped on purpose: extensible variants (`type t += ...`) would keep pattern syntax but break
  the `Workspace.context` re-export and still need a registration API; a descriptor record as
  the type itself breaks `=` and `Marshal`; polymorphic variants spread a row type through
  `Value.t`, `Op.signature`, `term` and `payload`.

### Step 3: kernel facts in the declaration (Phase 0's open half)

- One PPX type attribute, `[@@sop.node_facts]`, or a `facts` field on `Node.t` filled by
  `Node.Private.make`, carrying: `elementwise : Points | Primitives | None`, `reads :
  string list` and `writes : string list` of attribute names (`"P"`, `"N"`, `"Cd"`, ...),
  `topology : Preserved | Changed`, `exact : bool` (the Boolean/Delaunay/remesh family is
  exact and irregular). `cook_mode` already encodes half of this and is read by nothing;
  derive `topology`/`elementwise` from it where it is truthful and declare the rest.
- First consumers, in this order: `Session`'s cache key uses component ids for the components a
  node reads (`Geometry.payload_components`, geometry.ml:88-98), so a colour-only upstream
  change does not recook a topology consumer; the IR placement (Step 4) reads `elementwise`
  and `exact`.
- Declare facts for the regular element-wise family first (transforms, `mountain`,
  `noise_displace`, peak, bend, normals, attribute noise, colour by height, scatter) and leave
  the rest `None`/`Changed`/`exact = true`, which is the safe default. A test asserts every
  `Duplicate_input` node that declares `topology = Preserved` keeps `Geometry.topology`
  physically on a cook of a fixture.

### Step 4: the Flow IR and the CPU kernel tier

New library `flow_ir` (deps: `flow`, `param`, `rays_math` for `Parallel`; gate rules: never
reaches `rays`, `pxui*`, `procedural`, `rdk`, `sketch_*`, `rays_editor`). `flow` stays the
reference interpreter and never depends on `flow_ir`.

- **IR.** A flat typed dataflow graph built from `Eval.plan` plus the residuals after
  specialization: node `{id : Workspace.path * int list (site, iter) ; ty : Ty.t; count :
  Count.t (Static n | Data | Unknown); rate : Static | Frame | Event; precision : Exact |
  Approx; kind : Source (frame field, input, state previous) | Kernel of body | Opaque of
  catalog call | Sink (draw, canvas, export, sop input)}`, edges by argument name. Rate comes
  from `Workspace.t.live` and the `frame/*` ops' `live` flag; invariance from
  `Workspace.t.invariant`; kernel bodies are the residual terms `fast_of` already walks
  (eval.ml:249-317) plus packed `map`/`for`/`fold`/`scan`/`sum` over `Array` (eval.ml:614-744).
- **Passes**, each a function `ir -> ir` with its own test: common-subterm sharing by
  structural hash of `(kind, args)`; hoisting of invariant nodes out of zones using the
  checker's set; fusion of adjacent element-wise kernels with equal `count` and no intervening
  sink; dead-node removal; placement, which assigns `Interp | Closure | Cpu_kernel | Cooked` by
  legality first (precision, exactness, `elementwise`), then by the Step 0 measurements.
- **CPU tier.** Block-at-a-time execution: each fused kernel is a loop over a block of about
  1,024 elements in unboxed `float array`s, blocks distributed by `Parallel.for_` in stable
  chunks; reductions use a fixed chunk-tree order. The roadmap rejects extending `fast_of`
  (one closure call and one boxed float per element) and rules out native code generation
  (register O4). Determinism contract: byte-identical to the interpreter and to itself at one
  and many domains, tested on every fixture.
- **Precision.** Decision recorded (owner, 2026-10-07): approximate geometry is allowed. The
  rule, from the roadmap: an `Approx` value may flow only to a display sink (`draw/*`,
  `ui/canvas`, the viewport, a texture); it may not flow into an `Opaque` catalog call, an
  export, a `state` seed or a cache key, except through an explicit readback form (`(exact x)`,
  one `Op` record, cost paid at placement). The IR carries `precision` from day one and the
  placement pass refuses the illegal flows with one diagnostic (`E_APPROX_SINK`), tested on an
  IR built directly in the test (there is no approximate producer until the GPU tier, so no
  Lisp program can produce one yet; do not add a fake one). The checker learns the class as a
  `Paths.t` beside `live` when the GPU tier lands.
- **Where it runs.** `Value_lane.resolve` (value_lane.ml:103) becomes the caller: the
  per-frame residual forcing goes through the IR's executor for nodes placed on `Closure` or
  `Cpu_kernel`, and through `Eval.force` for `Interp`. Materialization on demand: when a card
  is selected or probed, its cone runs on `Interp` (roadmap rule 2), so probes keep the
  reference semantics. The projection reports one time per fused group and a tier badge beside
  the live badge (roadmap rule 4); provenance tags pass through every kernel (rule 5).
- **First kernel.** `sop/attr g :P` reads a point attribute as a packed `Array Vec3`;
  `sop/with_attr g :P array` writes one back (count must equal the point count, `E_ATTR_COUNT`).
  Both are `Op` records in a `sop` list; `with_attr` lowers to `Kernel.edit_point_ranges` for
  `P` and to an attribute write for others. The roadmap's example is the gate:

  ```lisp
  (sop/with_attr g :P
    (map (fn [p n] (+ p (* n (* amp (noise3 (* p freq))))))
         (sop/attr g :P)
         (sop/attr g :N)))
  ```

  `noise3` is one more `Op` record over `Rays_math.Noise` semantics, so the Lisp body and
  `Deform.noise_displace` agree. Gate: the Lisp kernel is byte-identical to the interpreter at
  one and eight domains, `bench_kernel` records Lisp-kernel versus rdk time on 1M points, and
  the number is written down whatever it is. The roadmap predicts near-native; the prediction
  is not the gate, the measurement is.
- **Graph.** `sop/attr`, `sop/with_attr`, `noise3` and `(exact x)` are ordinary cards; the map
  inside `with_attr` is the existing zone with an element selector (roadmap: "a per-point
  kernel is that zone with an element selector"). No new syntax, so no new `Flow_edit` gesture
  beyond what the operator registry gives for free.

Gate for the whole item: Step 0's three benchmarks have before and after numbers; the scrub
edit frame meets the Step 1 target (met, 2026-10-07); the toy-domain test of Step 2 passes with no edit in `lib/flow`;
the regular element-wise SOP family declares facts and the component-keyed cache skips at
least one recook in a fixture; particles and every `.rays` file evaluate to the same values and
pixels on the IR as on the interpreter, at one and many domains.

## 3. No regression (the contract from the finished migrations)

- Every checked-in `.rays` and the 12 generated workspace fixtures evaluate to the same plan,
  instances, values and records at static evaluation and at `0`, `0.125`, `1.25`, `7`.
  `bench_workspace_lower _build/default/specification/workspace/cases 7` reports unchanged
  node counts, retention, payload and cook hash. Record medians before and after each step.
- `test_op` sweeps every `Op` record and grows with each new one (`noise3`, `sop/attr`,
  `sop/with_attr`, `exact`).
- Bit-exact `value/rand` hashes, the compiled-residual comparison and the particle export's
  byte identity (test_drawing native) stay as they are; the IR adds the same comparison for
  every fixture at one and eight domains.
- `flow_manifest.sexp` changes only when SOP metadata changes (Step 3 will change it; review
  the diff, `dune promote`). `api_stable.json`: promote once per step.
- Determinism rules from `AGENTS.md`: no domain per frame or item, immutable `Rand.t`, the
  shared `Parallel` pool with an explicit grain and a sequential cutoff, every cache with a
  capacity.
- Final check per step: `_build/default/tools/check.exe --ship` from a console session with
  Metal access; an SSH/tmux process cannot run `@smoke`.

## 4. Decisions needed (owner)

1. **Scrub target.** Taken 2026-10-07 (owner: readjust the gate): the scrub frame without its
   cook phase costs no more than a layout-drag frame at the same node count, with zero
   pipeline phases, measured by `bench_rays_editor`'s `rays_editor_scrub_edit_frame` row.
2. **Open names, shape.** Recommended: `Ty.Named of string` for the domain types and an
   abstract `Context.t` over a registry list; `Port_type`, `Panels.panel` and
   `pipeline_family` stay closed. Alternative: extensible variants, slightly larger diff, same
   loss of exhaustiveness.
3. **Kernel facts, home.** Recommended: a `facts` record on `Node.t` filled by the PPX from one
   `[@@sop.node_facts]` attribute; `cook_mode` is folded into it rather than kept beside it.
4. **Precision rule.** Recommended as written: approximate flows only to display sinks;
   `(exact x)` is the readback; the checker tracks the class when the GPU tier lands.
5. **`flow_ir` as a new library** above `flow`, depending on `rays_math` for `Parallel`, with
   gate rules. Alternative: put the IR in `flow` and the parallel executor in `flow_sop`; rejected
   because 2D kernels must not depend on the SOP library.

## 5. Skipped on purpose

- A machine-code JIT, LLVM, or generated OCaml source for hot zones (register O4: later, only
  with measurements, byte-identical).
- The GPU tier (Phase 5): shader emitter, pipeline cache, async compile, zero-copy buffers,
  float32 mirror. The IR's `precision` and the placement rule are the only Phase 5 work done
  here, because they shape the IR.
- Porting the ten remaining OCaml 2D examples and the missing draw kinds (rotate, scale, hsl,
  noise as a draw-side op, rounded-rect, quit, audio, dialog). Instanced 2D primitives and
  deferred tessellation (Phase 3's second half) wait until a dynamic 10,000-shape frame is
  measured in Step 0 and found slow.
- Opening `Port_type.t`, `Panels.panel`, `pipeline_family`, `Probe.summary`.
- A general `Op.register` mutable registry; a second list in `flow_ir` is enough.
- Parallel cooking of independent SOP branches (session.ml:243): after facts and component keys
  exist, as its own measured change.
- Reading `cook_mode` on its own: it is subsumed by Step 3's facts.
- A fast path for non-SOP value literals, geometry templates, frame folds and retained
  function records, and the per-frame edit budget (old Step 1 subtask 6). The file sweep
  measured the fallback on every checked-in `.rays`: the edit (print, parse, check) costs at
  most 0.8 ms; the rest is `Eval.static`/lowering that the changed value requires (particles
  29.9 ms for 10,000 points, sunflower 12.6, wave 12.2, tiles 8.0). The saving available is
  under a millisecond, and a budget that skips the evaluation hides the scrub. Making that
  evaluation cheap is Step 4's job (packed execution, incremental re-evaluation), not an edit
  fast path. Revisit only if a measured file shows the edit itself above a frame.
