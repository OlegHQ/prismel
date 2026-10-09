# F: the loose ends after Phase 5

Handoff for the next agent. Read all of it before touching the tree. Written
2026-10-08 against `dev` at ce133675, the day the P3, P4, P5 and PL branches
were consolidated. The roadmap that got us here is the Claude Doc "Rays Lisp
as a compiled language: where we are"; its continuation is "Rays Lisp: one
language, two targets". This file is the repository's copy of what is left,
with enough detail that you do not have to reconstruct any of it.

There is no other plan file. `P3.md`, `P4.md`, `P5.md`, `PL.md`, `NEXT.md` and
`MIGRATION*.md` are gone; their evidence is in `specification/performance-log.md`
from the section "Phase 4 whole-item verification (2026-10-08)" to the end of
the file, and in the commit messages between a7022bc6 and ce133675. If you
find a file with one of those names, it is stale: delete it.

---

## 0. How to work on this file

### 0.1 Who does what

You are GPT 6.1 Sol. You are good at plumbing, tests, benchmark runs, reading
code and recording results. You are not good at inventing fast algorithms or
at judging whether a measured number is noise. So the rule is:

**Every non-trivial optimization is designed and reviewed by a GPT 6 Astra
sub-agent. You do not design it yourself.** This is not optional.

"Non-trivial optimization" means any change that satisfies at least one of:

- It has a measured gate (a number in this file or in `performance-log.md`
  that must move).
- It touches a hot loop in `lib/rdk/**`, `lib/flow_ir/packed.ml`,
  `lib/flow_ir/flow_ir.ml` (the passes `share`, `hoist`, `fuse`, `prune`,
  `place`), `lib/flow_gpu/emit.ml`, `lib/flow_gpu/run.ml`,
  `lib/rays/scene3_native_lowering.ml`, `lib/scene_command/**`,
  `lib/pxui/ui.ml` (arrangement, paint, hit), or `lib/procedural/session.ml`
  (placement, cache keys).
- It changes a data layout (a packed plane, a vertex stream, a cache key).
- It changes what `Parallel` splits or how.
- It adds or removes a tier, a pass, or a precision rule.

For every such item below there is an "Astra brief" paragraph. Spawn Astra
with that brief verbatim plus the file paths and the numbers in the item. Ask
Astra for (a) the design, (b) the one check that fails if the design is wrong,
(c) the before/after measurement protocol. Then **you** implement the plumbing,
run the measurements exactly as Astra specified, and send the raw numbers back
to Astra for the verdict. Astra decides whether the gate is met. You never
write "gate met" on your own judgment.

What you do alone: adding tests, wiring a new kind through `Flow.Op`, catalog
and projection, documentation, running the shipping loop, writing the
`performance-log.md` section, promoting manifests, deleting dead code with
`tools/codemod` (the `prune-dead-code` skill).

### 0.2 The loop

```sh
dune build @check                                  # after every edit
dune build tools/check.exe                         # once per session
_build/default/tools/check.exe @lib/flow/runtest   # focused aliases, see each item
_build/default/tools/check.exe --ship              # before every commit
dune build @runtest-native                         # on a machine with a Metal device
```

`tools/check.exe` queues behind other agents' validations; never run
`dune build` with `--force` or clean between validations (Dune's cache is the
reason a `--ship` takes minutes, not hours).

Every public `.mli` change shows up as a diff of
`tools/api_manifest/api_stable.json`; accept an intended one with
`dune promote` (the `promote-manifests` skill). A SOP metadata change shows as
a diff of `lib/sop_catalog/flow_manifest.sexp`; same thing.

Warnings are errors. Python is not allowed anywhere in build, generation or
validation glue. No new dependencies.

### 0.3 Measuring

Every number you write down has a command, a machine, a domain count and a
repetition count next to it. The reference machine is the Apple M1 in
`performance-log.md` (eight domains, OCaml 5.3.0, Dune dev profile). Run each
benchmark alone: no builds, no other agents, no tests running. Take medians of
at least seven repetitions. Keep the raw CSV under
`specification/performance/` with a `f-` prefix (`f-merge-before.csv`,
`f-merge-after.csv`). If the number did not move, write that it did not move.
Never call a change an improvement because it "should" be one.

A `performance-log.md` section looks like the existing ones: a heading with
the date, the machine, the commands in a code block, a table, one paragraph
saying what the table establishes and what it does not, the raw file paths.

### 0.4 What you must never do

- Add a CPU raster, browser, SDL2 or OpenGL fallback. Metal unavailability is
  a typed startup error (`No_adapter`).
- Reach `Metal.` or `Ogpu_metal_native.` from anything above the Metal
  backend. `test/dependency_gate.ml` lists no exception.
- Create a domain or thread per frame or per item. Use the shared `Parallel`
  pool.
- Use `Stdlib.Random`. Use immutable `Rand.t`.
- Break byte-identity between one and eight domains on any CPU path.
- Let an approximate (GPU float32) value reach an export, a catalog input, a
  state seed or a cache key. `E_APPROX_SINK` exists for this.
- Add an OCaml-only parameter or behaviour. Lisp is first; the OCaml function
  is derived from the Lisp declaration (`specification/procedural.md`, "one
  declaration").
- Add a new Lisp form without its graph projection, its `Flow_edit` gestures
  and a test (`specification/flow.md` is normative).
- Add a second UI engine, hit-test path or text-entry path. `Pxui.Ui` only.
- Relax a golden, a tolerance or a gate to make a check pass.
- Claim a native result from a sandbox without a Metal device.

---

## 1. Where the tree is

**Current open work (2026-10-09).** The paragraphs below preserve checkpoint
history; their earlier “open” statements are not the current task list. Known
remaining work is F3 fan-out (latest retained
production learned-eight median63.197136 ms against≤50.600 ms). The chunked
vertex trial is rejected and restored; its evidence and boundary regression
remain. The unchanged, uninstrumented capture remeasurement below passes the
changing-source GPU median gate at4.755571 ms (range4.344505–5.610975 ms;
three of seven trials exceed5 ms). A final requirement-by-requirement audit and final F5 qualification
are still required. F2.4/F4 retain their conditional/optional scope; F8 is a
handoff. Overall completion is not claimed.

**Committed milestone (2026-10-08, `e36a0ac4`).** F1.1, F1.2, F1.4 and the F6 canvas-image
coercion are implemented and verified. The field SOP, selected-tuple probes,
sampled extractor, empty-cell guard and cube-count lookup are implemented;
F2.1 remains open because its eight-domain whole-cook median is 20.167 ms
against the unchanged <10 ms gate. F1.3 and F2.2–F2.3 remain open. F2.4 and F4
are conditional, and F3 requires the owner's request to move its numbers.
**Current continuation (2026-10-09).** Packed Vec2/Vec4 groundwork is committed
in `46984986`; CPU `image/map` is committed in `4ba82525`, and immutable GPU
uploads in `767dea7d`. The GPU producer/converter checkpoint is recorded in
F2.2 below. Authored image qualification and private borrowed runtime image
backing are implemented by the checkpoints below. Resident consumers are
committed in `6636e12b`; connected workspace GPU publication and independent
CPU snapshots are committed in `3db45c8b`. Completed-Canvas borrowing is committed
in `5f0e50b2`; the retained workspace Canvas checkpoint below passes F2.3's
measured allocation gate. Connected image/map timing/allocation gates now pass
the checkpoint below; captured geometry and frozen exact GPU snapshots remain
open. The paragraphs that follow
record the earlier field and qualification implementation history.
Deterministic sampled slab chunks (`8f1f4789`) now preserve complete geometry and seam
normals, improving the eight-domain whole cook from 20.954 to 12.937 ms in
their paired trial. The subsequent explicit-rounding checkpoint measures
13.569 ms: the unchanged <10 ms gate remains open. Scalar `length` now matches
primitive/packed multiply-add rounding on every off-centre asymmetric sample;
SOP/RDK sampling coordinates explicitly use fused multiply-add. Corrected
asymmetric benchmark samples match the dense hash. Astra says keep these
changes. Same-cook time-only attribution now measures about 1.55/2.58/2.23/5.68 ms
for grid/preparation/kernel/extraction at eight domains, with an uninstrumented
whole-cook median of 11.755 ms. GC snapshots inside the first diagnostic caused
large pauses; that intrusive evidence is kept separately. Both temporary patches
are archived and production source restored byte-for-byte. Astra next approves
an indexed finite-value check at the shared packed-array validation boundary;
the indexed validation trial is now implemented and measured: eight-domain
whole cook 12.350→11.300 ms, one-domain time flat, allocation reduced by
13.18 MB. The strict <10 ms gate remains open. Astra next approves only
deterministic row chunks for SOP grid filling through the shared pool.
That trial regressed whole cooking at both domain counts and is reverted (`2c7cd365`);
its exactness/cancellation tests and raw measurements are retained. Astra
next approved time-only attribution of preparation into map construction
and IR compilation (`31a4cb1e`). That attribution identified the finite
scan; moving its error call outside the successful loop reduces preparation
to about 0.59 ms and improves whole cooking to 10.417 ms in the first paired
eight-domain batch (11.280 ms in the reverse-order batch). Astra says keep
the scan and next approves only sequential y/z FMA hoisting in the SOP grid.
The strict <10 ms whole-cook gate remains open. That hoist is now rejected
after the balanced repeat; Astra next approves joined extractor count/
emission time attribution inside the same complete cook. That diagnostic is
complete: emission is the largest interval (6.155 ms at eight domains), and
Astra next approves direct packed edge writes with a captured all-mask golden.
F1.3's shared compiler/emitter/dispatch form checks are implemented; focused,
shipping and native GPU checks pass. Its two-stage qualification wiring remains pending.
Explicit declaration capabilities (`e7c36ea7`) and diagnostic compilation are
implemented; the diagnostic checkpoint passes focused, shipping and native
GPU checks with Astra approval. Static kernel observation also passes focused,
shipping and native GPU checks with Astra approval. Actual-capture qualification
remains pending.
Direct packed edge writes (`97e5f7bf`) now pass F2.1's measured gate: eight-domain whole
cook medians are 9.131908 and 9.860992 ms in opposite execution orders,
with exact geometry and about 15.7 MB less allocation. Astra's verdict is
“met”; shipping and full F5 native/pixel qualification pass (exit 0).
Actual-capture qualification and the connected checker/lowering/document/
inspector/tool migration now complete F1.3. The 39-file actual-catalog audit
checks 23 qualified authored/body paths through fused/unfused compilation
and emission. Capture changes rebuild accepted/refused/pending conclusions;
ambiguous or missing observations never qualify. Focused and shipping checks,
the full workspace sweep and native GPU numerics pass (exit 0). Astra's F1.3
gate verdict is “met”; the final materialized-source/shared-function regressions
also pass. F2.2 now has a connected CPU image/map checkpoint: typed Lisp and
graph gestures, packed pixel functions, owned RGBA8 conversion, live captures,
workspace drawing/sampling/textures, stable identity across edits/resize, and
nested render invalidation are implemented. Astra accepts its prepared CPU
whole-cook gate: 1024² medians are 11.874914 ms (gradient) and 12.237072 ms
(live capture) at eight domains, with matching full-byte hashes across domains
1/8 at all three measured sizes. F2.2 remains open for GPU qualification,
conversion/copy, resident/exact consumers, geometry capture resolution and
native GPU timing/allocation/parity. F2.3 remains open. These checkpoints do
not complete F.md.
Full F5 native/pixel validation passed at `8f1f4789` (exit 0) on the confirmed
M1, including the 37-file pixel sweep. The current shared-form-check checkpoint
passes focused checks, `--ship` and native GPU numerics. The direct-edge
checkpoint also passes the full F5 native/pixel aliases, including every
workspace at four times/domains 1/8. Final full native/pixel qualification
remains part of shipping the completed F scope.

Earlier status paragraphs below are the implementation history; this
checkpoint supersedes their temporary native-access and commit restrictions.
The current Apple M1 host passed `@all @runtest`, the native aliases listed
under F5, all three workspace pixel aliases, and `--ship` (exit 0). Native
workspace parity includes 37 standard files, two custom-catalog executables
and 13 fixtures at four times and domains 1/8, including `flow_field` and
`flow_vectors`. GPU arithmetic/select are exact at 1,024 and 65,536 elements;
noise maximum errors are 8.82050105e-7 and 9.88528899e-5 within the existing
tolerance. No golden, tolerance or performance gate was relaxed.

Everything in the six phases of the first roadmap has landed. Read this table
once so you know what exists before you add anything.

| Area | Where | What it does today |
|---|---|---|
| Language | `lib/flow` (`syntax`, `lisp`, `macro`, `check`, `workspace`, `eval`, `op`, `packed_ops`, `ty`, `context`, `port_type`) | Reader, printer, hygienic macros, checker with liveness/invariance/approx sets, reference tree walker, one operator registry (`Flow.Op`), one packed operator declaration (`Flow.Packed_ops`, 22 names: 15 binary, 5 unary, noise, derived vec3 length). Depends only on `param` and `frame_input`. |
| IR | `lib/flow_ir` (`flow_ir.ml`, `packed.ml`, `operators.ml`) | Typed dataflow with `rate`, `precision`, `Count`, tiers `Interp | Closure | Cpu_kernel | Gpu | Gpu_compile | Gpu_readback | Cooked`; passes `share`, `hoist`, `fuse`, `prune`, `place`; `Cost` with measured affine rows; `Gpu.backend` callback; `Executor.try_display`. Packed register programs in 1,024-element blocks. |
| GPU tier | `lib/flow_gpu` (`emit`, `pipelines`, `run`, `host`) | Metal source from a packed program (`Emit.kernel`), pipeline cache of 64 (`Pipelines`), owned runners and buffers (`Run`), the host that owns at most 64 runners and 64 pipelines and installs the backend (`Host`). Depends on `flow`, `flow_ir`, `ogpu`, `rays_execution`, `lru`, `rays_math`, `param`. |
| SOP overlay | `lib/flow_sop` (`lower`, `attribute_kernel`, `value_lane`, `operators`) | Lowers a checked workspace to a `Procedural` network; `sop/attr` and `sop/with_attr` are the kernel boundary (`Attribute_kernel` over `Rdk.Kernel.edit_point_ranges`); image resolver callback (`Lower.with_images`). |
| Graph layer | `lib/flow_graph` (`projection`, `flow_edit`, `exposure`, `probe`) | Domain-neutral projection and gestures; zones for map/filter/reduce/sort-by and if/cond/case arms; probes force one tuple. |
| 2D | `lib/sketch_support/drawing.ml`, `lib/flow/op.ml` (`draw_op` lines ~200-240) | 18 `draw/*` kinds; plural kinds (`circles`, `rects`, `lines`, `points`, ...) lower to one instanced `Scene_command.Shape_batch`; GPU display sinks take a `gpu_token`. |
| Images | `lib/flow/op.ml`, `lib/flow_sop/image_kernel.ml`, `lib/rays_editor/workspace_images.ml`, `lib/procedural` (`attr_from_image`) | `image/load`, retained display `image/render`, `image/noise`, CPU/GPU display `image/map` (packed Vec2→Vec4, owned RGBA8); resident `draw/image`/`scene/geometry :texture image`; exact CPU `sop/attr_from_image`. The editor pins at most 64 images. Connected timing/allocation gates pass; captured geometry and deferred frozen exact GPU snapshots remain open. |
| Catalog | `lib/sop_catalog`, `ppx/ppx_rays`, `lib/procedural/node.ml` | 162 `sop/*` kinds, one declaration each, including the field SOP, `Node.facts` (elementwise, reads, writes, topology, exact). |
| Cook | `lib/procedural/session.ml` | Component-keyed LRU; learned placement fans branches and zone elements across domains above a 2 ms measured subtree. |
| Geometry | `lib/rdk/**` | Float64 structure-of-arrays planes; `Mesh_merge.merge_plain` is the serial merge (see F3). Scene3 packs planes into float32 24+12-byte streams (`lib/rays/scene3_native_lowering.ml`). |
| Editor | `lib/rays_editor` (`workspace_gpu.ml`, `workspace_images.ml`, `spreadsheet.ml`, `viewport3.ml`) | GPU owner with `Measured | Qualification` policy; spreadsheet pane; `ui/viewport` is 3D only. |
| Benchmarks | `tools/bench_kernel.ml` (`--gpu`, `--gpu-check`, `--cost`, `--loops`, `--fusion`, `--attribute-fusion`, `--attributes`), `tools/bench_gpu.ml` (`--msl`), `tools/bench_workspace_lower.ml` (`--branches N off|learned`, `--loops N ...`, `--images`, `--approx`, `--nodes`, `--residuals`, `--eval`), `tools/bench_drawing.ml` (`[count] [--static] [--profile]`), `tools/bench_rays_editor.ml` (`200 1000 2000`, `--panels 200`), `tools/bench_scene3_packing.ml` | The numbers in `performance-log.md` come from these. |
| Reference sketches | `sketches/flow_kernel/sketch.rays` (CPU attribute kernel), `sketches/flow_particles_gpu/sketch.rays` (1,000,000 circles on the GPU and the `(exact ...)` SOP variant), `sketches/flow_image/sketch.rays`, `sketches/ws_spreadsheet`, `sketches/ws_shared` + `ws_shared_other` (imports) | Copy these when you need a workspace that exercises a tier. |
| Tests you will extend | `lib/flow/test_workspace.ml`, `test_check.ml`, `test_ty.ml`; `lib/flow_ir/test_ir.ml`, `test_packed.ml`, `test_noise.ml`, `test_frame_kernel.ml`; `lib/flow_gpu/test_emit.ml` (+ `goldens/*.metal`), `test_pipelines.ml`, `test_run_lifetime.ml`, `test_run.ml` (native); `lib/flow_sop/test_attribute_kernel.ml`; `test/test_workspace_ir.ml` (every `.rays` file at four times, one and eight domains), `test/test_open_domain.ml`, `test/test_2d_ports.ml`, `test/test_workspace_images*.ml` | Every item below names which of these it adds to. |

Numbers you should know (Apple M1, from `performance-log.md`):

| What | Number |
|---|---|
| Million-point noise kernel, CPU tier, 1 / 8 domains | 85.7 / 25.5 ms (native 29.8 / 8.1, interpreter 1,442) |
| CPU tier cost row | 23.16 µs fixed + 16.50 ns per element; interpreter 710 ns per element; crossover 34 elements |
| GPU cost rows | compile 8.2 ms cold; display 0.438 ms + 19.8 ns per element; readback 10 µs + 7.9 ns per element |
| Editor frame, 1,000,000 noise-driven circles | CPU 903 ms, GPU 28.6 ms; 10,000: 10.1 ms vs 1.48 ms |
| GPU readback error vs CPU tier | 1.9e-6 maximum absolute at 1M; 8.82e-7 at 1,024; 9.89e-5 at 65,536 (native suite) |
| 2D plural shapes, moving, 100,000 | circles 43.3 ms, rects 43.3, lines 20.7, points 16.6; 10,000 circles 4.7 ms |
| Two-chain fixture (2M points, two noise chains, one merge), 8 domains | 58-64 ms; its `merge` alone is 40 ms; Step 0 was 75.9 ms; the gate was 50.6 ms |
| 64-piece zone (3.2M points), 8 domains | 259-286 ms learned vs 1,226 ms off |
| Full static editor update, 100,000 circles | 155,620 bytes/frame; retained Drawing lowering alone 1,393 bytes/frame |
| Spreadsheet pane, 1,000,000 points | 0.49 ms per frame |

---

## 2. The items

Order of attack: F0, then F1 and F2 (they share the port-type work; do F1.1
before anything in F2), then F5 as a continuous habit, then F3 and F4 only
with Astra and only if the owner wants the numbers moved. F6 and F7 are
small. F8 is the hand-off into the continuation.

### F0. Documentation drift (do first, one hour)

**Done (2026-10-08, `89d11c97`).** The commit `Document flow_gpu ownership and
dependency rules (F0)` adds the library row and dependency rule below.
`dune build @check tools/check.exe`, `_build/default/tools/check.exe --ship`
and `git diff --check` passed on the native Apple-Silicon worktree.

`AGENTS.md`'s library table has no `flow_gpu` row. `specification/backend.md`
describes it (section "Ownership and dependency direction"). Add the row:

```
| `flow_gpu` | Metal emitter from `flow_ir` packed programs, a pipeline cache of 64 and owned runners; depends on `flow`, `flow_ir`, `ogpu`, `rays_execution`, `lru`; never reaches geometry or UI |
```

and extend the "Dependency rules" bullet that lists `flow_ir` with:
`flow_gpu` depends only on `flow`, `flow_ir`, `param`, `rays_math`,
`ogpu_core`, `ogpu`, `rays_execution` and `lru` and never reaches
`procedural`, `rdk`, `flow_sop`, `sketch_support` or any UI library. That is
what `test/dependency_gate.ml` lines 92-96 and 164 already enforce; the
document just has to say it.

Check: `dune build @check` and `git diff --check`. No Astra.

### F1. The checker: full scope

Today the checker (`lib/flow/workspace.ml`, 1,550 lines) types every term
once, retypes `fn`/`defn` bodies per call site with unannotated parameters as
`Ty.Any`, computes three path sets (`live`, `invariant`, `approx`), and
validates catalog parameters through `Check.validate_parameter`. The IR
(`lib/flow_ir/flow_ir.ml` lines 228-237 and 557-558) is where approximate
values are refused at sinks (`E_APPROX_SINK`). The Metal emitter
(`lib/flow_gpu/emit.ml`) is where unsupported forms are refused
(`E_GPU_FORM`). This split works but it means three places decide what a
kernel may be, and two of them run after the user has already pressed a key.
The checker scope below closes that.

#### F1.1 Open `Port_type.t` for `fn` and `image` ports

**Representation review (2026-10-08, GPT 6 Astra; implementation in progress).**
`Ty` has no code dependency on `Port_type`, so `Port_type` may depend on
`Ty` without a library edge. Use `Ty.Fn of fn_signature option` and
`fn_signature = { params : Ty.t list; result : Ty.t }`, with
`Port_type.Fn of Ty.fn_signature`: the recursive port-only signature below
cannot represent record, list, array or text arguments. Bare `fn` stays
uninstantiated (`None`); a checked port argument retains both the instantiated
signature and the retyped body. `Check.term.ty` is a port type, so
`Workspace.to_check` must pass the validated signature rather than a bare
function marker. Preserve captures and named-function identity. The focused
regression must accept an unannotated function taking `{:p vec3}` and returning
float, inspect its retyped body, and reject wrong arity, image results and
function storage in a record. `Attribute_kernel.prepare` currently compiles
evaluated values; it does not yet compile arbitrary function arguments.
The actual Kernel argument and external-kind test remain completion gates.

**Done (2026-10-08, `e36a0ac4`).** Function and
image port constructors, signature round trips, catalog-argument validation,
and call-site function specialization are in the worktree. Each `Call_fn`
retains its checked body; a specialized `Fn` retains the original callable's
captures and call identity. The external `?ops` test accepts a vec3-to-float
port, projects its function zone and edits it through `Flow_edit.Set_arg`.
Focused Flow, graph, IR, SOP and PXUI-graph tests passed; the intended API
manifest diff was reviewed and promoted. Required physical Fn/Image slots now
have generated keyword-input metadata (`sop.node_keywords`, with list-valued
`sop.node_types` for signatures containing commas). The new PPX and live/
serialized-catalog regression passes. The compiled bulk bridge is implemented:
`Procedural.Kernel`/`Payload.Kernel`, `Eval.Private.map_function`, hidden
function resources and captured-geometry dependencies. Its generated-factory
test checks `[9;6]` from distinct offsets, live captures through a `defn`, an
unchanged cache hit, stable consumer IDs after an offset edit, and concurrent
one/eight-domain compiled/reference equality with scalar-to-vec3 conversion.
Nested record/geometry captures and per-point zone captures pass. Kernel
preparation requires an actual `Packed_map` IR node and returns typed
`E_KERNEL_FORM` for signatures/forms outside today's float/vec3 compiler.
Astra reviewed the boundary, residual IDs, capture traversal and zone cache
identity; the deferred-vec3 field projection follows its review. Graph insertion
and parameter editing are covered through generated defaults and Fn zones.
The full workspace sweep passes (35 standard files, two custom-catalog
executables, 13 fixtures, four times, one/eight domains). Its broad test run
caught a factory type-name whitespace regression; the shared validator was
fixed and the mixed-image SOP regression passes directly. The intended API
changes were promoted. The final pure run (`@check @all @runtest`) passes.
Native shipping subsequently passed on the M1 before the checkpoint commit.

**Boundary findings (GPT 6 Astra, 2026-10-08).** A literal
`Flow_ir.Executor.program` in a Procedural factory would add the forbidden
dependency edge. The `flow_sop` bridge must own that compiled program and
forward a backend-neutral bulk executable handle to the factory. That handle
must execute the compiled CPU program, not interpret the function per sample.
Function resources need conservative fresh identity per lowering and cooked
payload IDs, with captured geometry as real dependencies; unchanged cache hits
retain their payload IDs. `Flow.Value.key_of (Fn _)` currently returns only
`"fn"` and is insufficient. Typed keywords are physical inputs, not new Param
field kinds. A function alone cannot compile to a packed map: binding packed
input columns constructs an evaluator-owned residual map, and then
`Attribute_kernel.prepare` creates the program captured by the bulk runner.

**Today.** `lib/flow/port_type.mli`:

```ocaml
type t = Geometry | Float | Int | Bool | Vec3
```

`Check.parameter.ty : Port_type.t option` (`lib/flow/check.mli`) is what a
catalog kind's keyword parameter carries; `None` means a literal-only text or
choice field. `Ty.t` already has `Fn` and the registered nominal `image`
(`Ty.image`). `Workspace.t.kind_fns` records a catalog kind used *as* a
function value; nothing records a function value passed *to* a kind. A `fn`
that flows into a call is `E_FN_ESCAPES` (`Ty.has_fn`). `sop/attr_from_image`
takes an image: look at how, with `git show cb9c1c5b --stat` and
`git show cb9c1c5b -- lib/flow_sop/lower.ml lib/sop_catalog`, before you
design anything, because that commit already threaded one non-geometry slot
type through the catalog. Generalize what it did; do not add a second
mechanism.

**Goal.** A catalog kind can declare a parameter of port type `Fn` (with a
signature: parameter types and result type) and `Image`. The checker types
the argument against that signature, retyping the `fn` body at the call
site exactly as it does for `defn` calls (the `sigs` table and `inputs_fit`
logic around `workspace.ml:985-1000` is the model). `E_FN_ESCAPES` is not
raised for a `fn` passed to an `Fn` port. The IR sees that argument as a
`Kernel` whose body is the compiled packed program (F2.1 consumes this).

**Steps.**

1. `lib/flow/port_type.mli`: add `Fn of Ty.fn_signature` and
   `Image`. `name`, `can_connect`, `coerce` get arms; `coerce` of a function
   or an image is always `Error` (they are never driven by a scalar).
   `of_field_kind` returns `None` for both (no `Param` field view exists).
2. `lib/flow/check.mli`: nothing changes in the record shapes; the new
   constructors flow through `parameter.ty`. `validate_parameter` gets two
   arms: an `Fn` port accepts a term whose `ty` is `Ty.Fn` with a fitting
   signature, an `Image` port accepts `Ty.image`.
3. `ppx/ppx_rays` and `lib/flow_sop/manifest.ml`: the single
   declaration gains typed keyword-input metadata for `fn` and `image`,
   preserving the existing physical mixed-slot mechanism. Read
   `specification/procedural.md`, "one declaration", and the
   `add-sop` skill first. The manifest snapshot `flow_manifest.sexp` will
   diff; review it and `dune promote`.
4. `lib/flow/workspace.ml`: in `call` (the `Call` arm), when the parameter's
   port type is `Fn`, type the argument as a call-site instantiation and do
   not add it to the escaping-fn check. Record the instantiated signature on
   the term (the `Fn` node already has `params` and `zone`).
5. `lib/flow_graph/projection.ml`: an `Fn` port draws as a zone input, the
   way `map`'s `fn` input already does (look for `` `Map `` in `projection.ml`).
   An `Image` port draws as an ordinary wire of the image colour (`Ty.color`
   of `Ty.image`).
6. `lib/flow_sop/lower.ml`: an `Fn` argument reaches the node factory as a
   typed input whose bulk executable owns a compiled
   `Flow_ir.Executor.program` in Flow_sop (reuse `Attribute_kernel.prepare`
   after binding packed inputs; no Procedural-to-Flow_ir dependency).
   An `Image` argument reaches it through the existing image resolver.

**Tests.** `lib/flow/test_check.ml`: `validate_parameter` on each new port
type, including the refusals (a float into an `Fn` port, a `fn` of the wrong
arity, an image into a float port). `lib/flow/test_workspace.ml`: a workspace
declaring a test kind with an `Fn` port through `?ops` and the `test_open_domain`
pattern; the `fn` does not raise `E_FN_ESCAPES`; the same `fn` stored in a
record still does. `lib/flow_ir/test_ir.ml`: the argument appears as a
`Kernel` node. The dependency gate must still pass (no new edges).

**Gate.** `test_open_domain` registers a kind with an `Fn` port without
editing `lib/flow` beyond the port type itself. Every existing `.rays`
workspace still passes `test/test_workspace_ir`.

**Astra brief.** Not needed for the plumbing. Ask Astra only for the
signature representation if you find `Port_type.Fn` needs to carry `Ty.t`
(it does: `Ty.t` is defined in `ty.mli` and `port_type.mli` does not depend
on it today; check the dependency order inside `lib/flow` with
`grep -n "Ty\." lib/flow/port_type.ml` and decide whether `Port_type` gains a
dependency on `Ty` or `Ty` gains the port constructors; Astra decides).

#### F1.2 Precision as a checker class, not only an IR refusal

**Done (2026-10-08, `e36a0ac4`).**
The checker now retains approximate producer paths separately from GPU
eligibility, including aliases and nested containers, and checks catalog
slots/parameters, state seeds, graph overrides and settings/scene arguments.
`Op.is_display_kind` is shared with IR sink classification. `cond` and numeric/
boolean `case` have packed compiler support and emitter/reference parity at
one/eight domains; eager pure branches use the existing `Select` instruction.
The particles seed and Flow kernel geometry consumer now use explicit `exact`
boundaries without removing their producer bindings from the eligible set.
Inline `exact` cards now project their child maps/Fn zones and support checked
argument edits; the shared nested-call recognition fixes every graph gesture
caller. The 37-file approximate-path audit passes with both actual custom
catalogs. `@check @all @runtest` passes, and the intended `Op.is_display_kind`
API addition was promoted. The subsequent skipped-tuple exclusion has focused
Flow/graph/IR/GPU coverage. Native shipping passed before the checkpoint commit.

**Today.** `Workspace.approx` is advisory: `workspace.ml:834` (a single-clause
`for` over packed arrays with a covered body), `:995` (a `map` whose inputs
fit and whose body is eligible), `:1173` (an operator in `Packed_ops.names`
whose arguments are approximable), `:446` (a vec3 literal of approximable
parts), `:564` (`if` of approximable arms), `:1025` (a graph reference
carries its result's class). `(exact x)` (`op.ml:278`) clears it. The IR
refuses at placement (`flow_ir.ml:228-237`): an `Approx` input into a
`Kernel` with `requires_exact`, or into a `Sink` other than `Display`, is
`E_APPROX_SINK` with the message "Approximate values require (exact x)
before catalog calls, exports, state or cache keys." That diagnostic is
raised when the IR is built, which is after check, and it is reported at the
sink, not at the producer.

**Goal.** The checker reports `E_APPROX_SINK` itself, with the producer's
path and the sink's path, for every statically visible case: an approximable
binding used as a catalog slot or keyword argument (other than a display
kind), as a `state` init, as a graph input override, or as the value of a
`settings/*` or `scene/*` form. The IR keeps its refusal as the backstop. The
message is the same text so existing tests keep matching.

**Steps.**

1. In `workspace.ml`, the `v` record (line 90) already carries `approx :
   bool`. At each sink site (the `Call` arm for catalog kinds, the `State`
   arm for `init`, the `Graph_ref` arm for overrides), if the argument's `v.approx`
   is true and the kind is not a `draw/*` or `ui/*` display kind, emit
   `E_APPROX_SINK` through the existing diagnostic callback with both paths.
2. Make the display-kind test one function (`is_display_kind : string ->
   bool`) in `lib/flow/op.ml` next to `draw_op`, and use it from both the
   checker and `flow_ir.ml:414` (which today tests `n.ty = Ty.drawing`).
3. Add to the approx rules what the emitter already supports and the checker
   does not mark: `cond` and `case` whose arms are all approximable (today
   only `if`, line 564). Do not mark reductions, multi-clause products,
   filtered maps or `skip` tuples: the emitter refuses them (`E_GPU_FORM`),
   and F1.3 makes the two sets agree.

**Tests.** `lib/flow/test_workspace.ml`: one workspace per sink kind, each
expecting `E_APPROX_SINK` at check time with the producer path in the
message; one with `(exact x)` in between expecting no diagnostic; one with a
`cond` producer feeding `draw/circles` expecting the `cond` path in
`approx`. `test/test_workspace_ir.ml` must still pass for every file
(`sketches/flow_particles_gpu/sketch.rays` has both the display and the
exact route; it is the reference).

**Gate.** `bench_workspace_lower --approx` prints the same sets as before for
all files plus the new `cond`/`case` paths where present, and no file reports
a new error.

**Astra brief.** Not needed.

#### F1.3 One eligibility set: the checker marks exactly what the emitter compiles

**Done (2026-10-09, `25fb324a`).** Shared width facts,
immutable candidates/refusals and producer/body provenance are connected to
actual static captures. Raw checking publishes an empty definitive set and
pending/refusal reasons; qualification compiles each observed specialization
and applies the production GPU form checks. Actual failures dominate pending
ambiguity and successes; absent/untaken specializations remain pending.
Lowering qualifies once, and the document publishes only derived metadata
without replacing source. Inspector reasons and tool consumers use that result.
Literal patches preserve physical producer references, including generated
empty-span forms, while unchanged documents retain their identity.

Tests cover representable→1e39→representable captures on unchanged candidates,
overflowing/finite instances in either order, ambiguity in either order,
callable aliases, bypass, untaken branches, independent/state-dependent maps,
empty/static/vector/noise kernels, register limits, repeated/zero syntax IDs,
materialized unsupported children and shared-function provenance. The actual
catalog/file routes audit every published path with fused/unfused compilation
and pure emission, reporting every pending/refusal reason and preserving
ordinary evaluation/cook parity. The 39-file report has 23 qualified paths;
shipping covers 37 standard files, both custom-catalog executables and 13
fixtures at four times/domains 1/8. Focused, shipping, pure GPU fixtures and
native GPU checks pass. The five intended public API surfaces are promoted.
Astra's verdict is “met” for F1.3; details and commands are in the performance
log. No timing improvement or image/resident gate is claimed.

**Astra design (2026-10-09; implemented by the checkpoint above).** The current compiler
and emitter support Vec2/Vec4; the older audit below predates that groundwork.
The earlier claim that one-source `for` fails emission was incorrect:
`Packed.Private.view` already treats one source as zipped, including Product.
No CPU iteration change is needed. Name-only noise
recognition also accepts a counterfeit declaration the compiler refuses.
The complete contract needs static candidates with reasons, followed by
qualification of actual captures at the existing `Lower.of_checked`
evaluation boundary. A term-only predicate cannot know captured constants,
folding, concrete record/function bindings or exact register demand. Do not
narrow the supported language to avoid those facts.

The accepted implementation order is:

1. Share width/register/octave/float32 facts in `Packed_ops`, declaration
   capabilities in `Op`, diagnostic `Packed.compile_result`, and the exact
   pure GPU form checks in `Packed.gpu_refusals`. Both `Emit.kernel` and
   execution/placement consume that predicate; hand-built `E_GPU_FORM`
   remains. Explicit noise capability replaces name-only recognition.
2. Checker output records `packed` candidates/refusals and candidate→producer
   provenance for aliases, conditionals and body paths. Preserve precision
   taint independently, propagate state dependence, align Vec2/Vec4, and
   preserve the existing effective Zip behavior for one-source loops.
3. `Eval.Private.static_with_kernels` observes each actual packed-form
   residual before static materialization, including empty maps. Its live
   state clears the observer. `Flow_ir.qualify_workspace` uses production
   fusion/compiler plus shared GPU refusals, aggregates all observed
   instances conservatively, and publishes definitive `approx`/reasons.
   Unobserved producers remain explicitly pending. Rebuild from immutable
   candidates after every capture/input change; never reuse old conclusions
   or retain residual/program proof caches. No per-frame compilation.
4. `Lower.of_checked` qualifies in place of `Eval.static`; lowering publishes
   derived approximation/reason fields. `Contexts` copies only that metadata
   into the current checked document, preserving edited source. Inspector
   displays qualified status or reasons. Attribute count-source kernels stay
   CPU-only. No new dependency edge is needed.
5. Extend `Workspace_parity`'s existing actual-catalog/file routes: every
   definitive path must map to observed authored producers accepted by
   Packed and Emit, with fused/unfused coverage. Report every pending/missing
   instance explicitly. Focused cases cover counterfeit/real noise, vectors,
   one-source loops, capture overflow/requalification, state, registers and
   fused-source restrictions. Ordinary evaluation results must be identical.

Raw `Workspace.check` will publish candidates and pending/refusal reasons;
its definitive `approx` starts empty until qualification above Flow. Update
all checker/IR/tool consumers intentionally, document this two-stage API and
promote its public manifest changes. The promised invariant is every
published approximable path's actual observed specializations compile and
pass the shared emitter form check. Device availability, runtime nonfinite
values and placement profitability remain separate execution checks. This
is an approved design, not evidence of a completed F1.3 gate.

**Shared form-check foundation (2026-10-09).** `Packed.gpu_refusals` now owns
the existing emitter's pure restrictions, consumed by emission, placement
and display dispatch. Register/octave/finite-float32 facts are shared in
`Packed_ops`; code generation and qualification share a fresh reachability
mask. Error ordering/text and effective one-source Zip behavior are preserved.
No instructions, arithmetic, CPU iteration, fusion or dependency edges change.
Focused Flow/IR/GPU tests pass, emitter goldens are unchanged, and the narrow
public manifest additions are reviewed/promoted. Tests pin used versus unused
overflow constants, one-source loops, vectors, noise bounds and existing
product/reduction/skip refusals. A marked map with a used `1e39` constant stays
CPU under zero GPU cost and never prepares/dispatches even in qualification
mode; this test fails when either caller's old incomplete gate is restored.
Astra approves the foundation; `--ship` and native GPU numerics pass (exit 0).
Declaration capabilities are added by the checkpoint below. Diagnostic packed
compilation, checker candidate/provenance/state facts, instantiated capture
qualification, inspector reasons and the full actual-catalog audit remain open.

**Next declaration/diagnostic slice (Astra, 2026-10-09).** Add
`Packed_ops.extension = Noise3`, an explicit `Op.t.packed_extension`, and
`Op.packed_kind` with binary/unary/noise/length/exact/frame/constant-only
cases. Canonical scalar built-ins are recognized by declaration identity;
constant-only preserves folding of built-ins without dynamic instructions.
The sole extension capability asserts intrinsic noise3 semantics and requires
the existing name/context/scalar shape, one vec3 position, optional int seed/
octaves keywords, float result, no positional option/rest/live/arithmetic
behavior. Validate that contract once and in direct classification; changing
a copied declaration's semantics clears its capability (including color
operators and the opaque custom-noise test). Differently named intrinsic
aliases need scalar executor plumbing and are not part of this slice.

`Packed.compile_result` returns the first actual refusal with its producer
span and concrete state/function/capture/type/form/limit/operator/constant/
layout reason. Existing option APIs wrap that result. A separate compile
exception preserves speculative `Unsupported` control flow: deferred-vector
capture projection, unknown counts, declined child/fusion compilation,
over-budget fusion's valid unfused fallback, rebind and runtime preparation.
Preserve evaluator diagnostic codes and all constant folding/arithmetic/order.
Tests pin real/counterfeit/copy noise capabilities and malformed signatures,
64 versus 65 registers, meaningful refusals, folded constant-only operations,
deferred record/vector components and successful declined fusion. This is
approved design; diagnostic compilation and the remaining qualification/provenance/
inspector/full-catalog audit are still pending.

**Declaration capability foundation (2026-10-09, `e7c36ea7`).** Explicit noise capability
and the shared `Op.packed_kind` classifier are implemented in packed and scalar
IR compilation. Canonical scalar built-ins retain frame handling and constant
folding; color operators and opaque copied declarations clear the capability.
Real/counterfeit noise, copied built-ins, invalid signatures and keyword order
are checked; folded constant-only operations retain existing empty/live-map
reference parity. Focused Flow/IR/GPU/SOP checks pass, emitter goldens are
unchanged and the intended public manifest changes are reviewed/promoted.
Astra approves this declaration checkpoint without narrowing or execution
changes. Shipping and native GPU checks pass (exit 0). This is a foundation,
not completion of F1.3; diagnostic compilation and actual-capture qualification
remain required.

**Diagnostic compilation foundation (2026-10-09, `8e55635a`).**
`Packed.compile_result` now reports the first actual refusal with a source
span and a concrete reason, preserving evaluator codes. The legacy compile
APIs and runtime reference fallback consume the same result. Speculative
deferred-vector projection, unknown counts, child compilation and declined
fusion keep their previous behavior. Tests cover state/function/capture/type/
form/limit/operator/constant refusals, preserved nonfinite constant diagnostics,
the 64/65-register
boundary, deferred Vec2/Vec3/Vec4 record components and successful unfused
fallback at four times/domains 1/8. Focused IR/GPU/SOP checks pass, the single
public API addition is reviewed/promoted, and Astra approves this checkpoint.
Shipping and native GPU validation pass (exit 0). Actual-capture qualification,
checker provenance/state facts, inspector reasons and the full authored
producer/emitter audit remain open; this is not completion of F1.3.

**Evaluator observation foundation (2026-10-09).**
`Eval.Private.static_with_kernels` now observes each actual static entry into
map/reduce/loop/array-sum before materialization, including empty/static forms
and unsupported types. The exact checked term, lexical free bindings,
instance and tuple are retained; no path deduplication or manufactured visits
to untaken branches. Observer handles share the existing negative synthetic
allocator, leaving ordinary residual/function identities unchanged. The
observer is cleared in live states and on static evaluation exit. A focused
regression checks static/empty/live/list maps, defn captures, default/override
instances, nested tuples, reduce/array-sum, records/results/identities, capture
adapter recursion and later forcing at four times. Flow checks pass; the
single private API addition is reviewed/promoted. Shipping and native GPU
validation pass (exit 0); Astra approves the observer checkpoint. Observations
include attempted specializations before an enclosing static evaluation defers,
not exhaustive execution coverage. Qualification aggregation, checker candidate/provenance/
state facts, inspector wiring and the full producer/emitter audit remain open.

**Next checker/qualification wiring (Astra, 2026-10-09).** Add shared
`Packed_ops.scalar_width` (Float/Int/Bool/Vec2/3/4) and `array_width` (only
Array Float/Vec2/3/4), then private checker producer/state facts and immutable
candidate/refusal metadata. Candidates are independent of existing
`approx`/`approx_sources` precision taint: uncertainty about captures or
folding must not reject ordinary CPU use at exact sinks. Narrow precision
recognition uses actual `Op.packed_kind` capabilities and preserves taint
through ordinary transformations; canonical exact alone clears it.
Link map/collect body and consumed callable paths after the specialized body
is checked, using a local association table; never rewrite the evaluator's
callable term. Union all producer links, including refused uses. Generic Any
or one specialization's refusal cannot erase a possible candidate at a shared
authored path. State dependency is conservative, not an unconditional refusal
under uncertain graph defaults/calls; independent frame-only maps inside a
state step remain candidates. Authored skips are tuple-sensitive.
Qualification associates roots by authored term.path or a checked-term index
of form ID/lexical owner for anonymous roots; runtime site is provenance,
never a path to shorten heuristically. Do not stamp new paths onto terms.
Switch raw definitive approx to empty only with the connected qualification/
Lower/Contexts/Inspector/tool/test migration; an additive metadata checkpoint
must remain explicitly transitional. The same checked workspace's input must
qualify accepted→refused→accepted for representable→1e39→representable captures,
without changing candidates or retaining old conclusions. The complete
standard/custom-catalog producer/emitter audit remains required.

**Source audit (2026-10-08; predicate/test implementation pending).**
The current 39-file `--approx` audit (including the actual custom catalogs)
prints nine paths: six in particles, one in Flow kernel, two in Flow particles
GPU. Eligibility tests must cover authored producer/body paths, aliases and
state captures rather than compile unrelated scalar records as kernels.
The refusal union read from the current compiler/emitter is:

- `Emit.kernel`: requires collecting Zip iteration, no skipped tuples and no
  accumulator instructions; used noise instructions require 1–32 octaves;
  used constants must remain finite after float32 conversion.
- `Packed.compile`: refuses previous/state-dependent residuals; supports
  map/reduce, selected loop shapes and array/sum, with only float/vec3 sources
  and outputs. Correlated product sources, mismatched arity, destructuring
  parameters and incompatible annotations fail.
- Body compilation has a 64-register ceiling. Captures must resolve to
  numeric/bool/vec3 values or compatible live uniforms; fields must resolve
  through captures/records or a vec3 component. Unsupported scalar widths,
  forms and non-name let patterns fail.
- Operator declarations must be the canonical scalar declaration (or the
  registered noise declaration). Dynamic integer arithmetic, unsupported
  operator/arity pairs, nonconstant noise configuration, invalid octave
  counts and unsupported conditional/case shapes fail. Constant folding can
  introduce a float64 constant outside float32 range even when each literal
  fits, so checking literal magnitude alone is insufficient.
- The earlier audit treated internal Product as a one-source emission
  discrepancy; the public packed view already treats one source as zipped.
  State-fold inputs can still be marked by today's syntactic body rule even
  though packed preparation refuses state-dependent residuals. That remains
  open; this audit does not establish the F1.3 gate.

**Today.** The emitter (`lib/flow_gpu/emit.ml`) refuses ordered
accumulators, multi-source products and skipped elements with `E_GPU_FORM`
after the checker marked the path approximable. `Packed.compile`
(`lib/flow_ir/packed.mli`) returns `None` for unsupported bodies and they stay
on the interpreter, silently. So a path can be in `approx`, compile to a CPU
packed program, and still be refused by the emitter; the user sees a GPU
badge that never lights.

**Goal.** `Workspace.approx` contains a path only if `Packed.compile` will
succeed on it and `Emit.kernel` will accept the result. The three decide from
one table.

**Steps.**

1. Enumerate the forms `Emit.kernel` refuses: grep `E_GPU_FORM` in
   `lib/flow_gpu/emit.ml` and list each condition. Enumerate the bodies
   `Packed.compile` rejects: grep `None` returns in `lib/flow_ir/packed.ml`'s
   compile path.
2. Write the union as a predicate on the checked term in `lib/flow`:
   `Packed_ops.eligible_form : Workspace.term -> bool` is wrong because
   `Packed_ops` is below `Workspace`; put it in `workspace.ml` as
   `packed_body` (defined at `:116`, used at `:838`; extend it) and expose the
   reasons as a list so the inspector can say why a path is not eligible.
3. `lib/flow_gpu/test_emit.ml`: for every path `bench_workspace_lower
   --approx` prints on every `.rays` file, `Emit.kernel` must succeed. This
   is the test that pins the two sets together; it runs on the mock backend
   (no device needed) because `Emit.kernel` is pure.

**Gate.** That test passes; `E_GPU_FORM` becomes unreachable from a checked
workspace (keep the code path; it is the backstop for hand-built programs).

**Astra brief.** Not needed.

#### F1.4 Types the kernels do not have: Vec2, Vec4, Mat4, integers

**Done (2026-10-08, `e36a0ac4`; checker/reference scope below).**
`Ty.Vec2`/`Vec4`, array annotations, type/string round trips and same-width
coercions are implemented. Two/four-component literals execute through the
reference evaluator, including fields, destructuring, scalar broadcasting,
typed function arguments and live values. Mixed-width arithmetic reports
`E_TYPE`; existing Vec3 arithmetic is preserved. Projection supplies the
literal's checked type to the existing two/three/four-cell numeric widget;
component `Set_arg` edits, defaults and probe descriptions pass. Packed
instructions, array constructors/storage and catalog port variants are
unchanged; new widths do not enter `approx`. Focused Flow/graph/IR/GPU tests
pass, and the intended API and generated sketch include are promoted.
`sketches/flow_vectors/sketch.rays` demonstrates both widths through current
drawing ports. Broad `@all @runtest` verification passes, including 37 standard
workspaces, two custom-catalog executables and 13 fixtures at four times and
domains 1/8. Native shipping passed before the checkpoint commit. The F2.2
packed-width extension is recorded separately below.

**Today.** `Ty.t` has `Float | Int | Bool | Vec3 | Text | Color | List | Array |
Record | Fn | Any | Named`. Packed arrays are `Float_array` and `Vec3_array`
only; `Packed.instruction` has no integer arithmetic, no bitwise ops, no
gather or scatter; bools in kernels are the floats 1 and 0. The continuation
doc's Phase 7 ("Kernel forms": 32-bit integers, `:until`, `get`/`set` on
owned arrays, several outputs, an adjacency table, the spatial intrinsic) is
where these land. Do not start Phase 7 from this file. What belongs here is
only the **checker's** side, so Phase 7 finds the types ready:

1. `Ty.Vec2` and `Ty.Vec4` as scalars that fit the same coercion rules as
   `Vec3` (`fits`, `coerce`, `join`), with `Ty.Array` of each. `Port_type`
   does not need them until a catalog parameter does.
2. The vec3 literal grouping in the projection (`specification/flow.md` §5.3)
   generalized to 2 and 4 fields.
3. `E_TYPE` messages for mixed-width arithmetic.

No kernel instruction changes. Tests in `lib/flow/test_ty.ml` and
`test_workspace.ml`. No Astra.

#### F1.5 What stays closed on purpose

`Port_type` beyond F1.1, `Editor_core.Panels.panel` (a new pane kind is an
editor decision), `Scene_execution.pipeline_family` (see F2.4) and probe
summaries stay closed. Do not open them because it "would be cleaner".

### F2. Textures and fields: full scope

**What exists.** Images are a value type (`Ty.image`) with three producers
(`image/load`, `image/render`, `image/noise`) and three consumers
(`draw/image`, `scene/geometry :texture`, `sop/attr_from_image`). An image is
RGBA8 on the CPU (`Rays.Image.t`, `specification/image.md`); `image/render`
draws a Drawing into an offscreen `Rays.Canvas` and reads it back with
`Canvas.to_image`, then the texture consumer uploads it again. The editor
owns at most 64 images (`Workspace_images`). GPU display values from a
kernel are opaque tokens (`Shape_batch.gpu_token`) consumed only by
`draw/circles`-style sinks through `Workspace_gpu.circles`.

OGPU facts you need (`lib/ogpu_core/types.mli`): texture formats are
`Rgba8_unorm | Rgba16_float | Rgba32_float`; all three are filterable and
storage-capable on Apple7+; the float formats **reject `Render_attachment`**
and multisampling with a typed `Unsupported`. `texture_usage` is
`Texture_binding | Storage_binding | Render_attachment | Texture_copy_src |
Texture_copy_dst`. So a per-pixel kernel writing floats cannot be a fragment
shader into a float target; it can be a compute kernel writing a
`Storage_binding` texture, or a buffer copied into a texture.

`Scene_execution.pipeline_family` is a closed variant of eleven families
(`Scene2 | Scene2_textured | Scene3 | Scene3_points | Scene3_textured |
Scene3_shadow | Scene3_stencil | Scene3_textured_stencil |
Scene3_shadow_stencil | Scene3_world | Ui`) with
`pipeline_variants_per_sample` as an invariant the pipeline cache capacity is
sized from. Adding a family is a boundary change: `scene_execution.mli`,
`rays_execution.mli`, `lib/rays/scene3_native_lowering.ml`, the cache sizing,
`specification/backend.md`, and a conformance test on mock and Metal.

`Rdk.Iso_surface` (`lib/rdk/gen/iso_surface.mli`): `extract` takes
`field:(Vec3.t -> float)` and calls it per sample; `extract_dense` takes a
`Field.t` which is `gyroid` or `custom (sample -> float)`, also per sample.
Neither accepts a precomputed sample array. There is no `sop/iso_surface` in
the catalog (grep `flow_manifest.sexp`: none). `Rdk.Kernel.map_points` and
`Voronoi2` are OCaml-only too.

The scope is four pieces, in this order. Each one is a Lisp kind first, with
its projection and gestures, then its lowering.

#### F2.1 Fields: a `fn` of position as data for geometry

**Astra design review (2026-10-08; sampled extractor implemented, SOP in progress).** Use a private
`Sampled of float array` evaluator and one `Array.blit` per plane into the
existing two-pass streaming marcher. Layout is
`x + (rx + 1) * (y + (ry + 1) * z)`; retain exact coordinate arithmetic,
validate products/length/finiteness/cancellation, and borrow the array read-only.
Thread a tunable grain (default 16,384), with the proposed sequential cutoff
`length / grain < 2`; do not change packed register blocks. The required parity
check includes both the 64-cell sphere and an asymmetric `(129,256,2)` lattice
crossing the cutoff, with complete geometry bytes and smooth/flat normals.
First instrument the unchanged dense extractor and preserve its executable;
record at least seven isolated dev-profile sphere/gyroid/asymmetric trials at
one/eight domains, complete geometry hashes and aggregate GC accounting.
The new SOP's timed cook must include grid creation, kernel preparation and
evaluation, validation, marching and geometry construction. There is no old
field-SOP baseline. The principal risk is that 4,096 cells per sphere plane
stay sequential: only the median **whole cook** below 10 ms at eight domains
meets the gate. Send raw CSVs back to Astra for its verdict; no gate verdict
or performance claim has been made. The required strict vec3 `length` Lisp
operator is now implemented with the existing Mul/Add/Sqrt instructions;
static bits, underflow/zero, masked overflow and lazy untaken-branch recovery
pass at one/eight domains. No runtime register-validation pass was added: the
existing intermediate Mul/Add guards already rerun the reference on overflow.
Its shared derived-name metadata/API addition is promoted. Before measurements
are recorded in `specification/performance-log.md` and six `f-field-*-before-*.csv`
files; the untouched extractor executable is `/private/tmp/f-iso-before.exe`.
The sphere's dense median is 27.842 ms at one domain and 30.690 ms at eight;
these are baseline extraction timings, not whole-cook gate results.
The sampled entry point and grain routing now pass complete geometry parity
for smooth/flat sphere and asymmetric fixtures at one/eight domains and three
grains, including malformed cardinality, overflow, nonfinite values and
cancellation checks. Its API manifest is promoted. Seven-trial dense after
measurements preserve all complete hashes: sphere/gyroid medians change by
less than 0.4%; the asymmetric eight-domain median improves 15.0% with variable
trials. Astra approves retaining the scheduling change for SOP plumbing;
the whole-cook gate was still unmeasured at that review.
The single-declaration SOP now passes complete 65³ compiled/reference sample
parity at two times and one/eight domains, complete cooked mesh parity to the
dense custom sphere, typed constructor/factory parity, malformed constructor
checks and graph projection/argument gestures. The generated catalog/API
manifests are promoted. `sketches/flow_field/sketch.rays` is added; its broad
workspace sweep passed at four times and both domain counts; its generated
include and the changed catalog digest in the Lisp compiler golden are promoted.
Selected field-body probes are implemented and pass the large-grid selected
tuple and bounded-memo tests.
Shared-field/map numbering now passes: one function's ordinary map calls and
two differently sized field lattices share stable selectors, including schema
defaults, out-of-range refusal and bounded selected-call memos. An anonymous
function argument also uses the checked nested input path, fixing field-body
record/projection identity at the shared argument parser.
First whole-cook medians are 31.998 ms
at one domain and 30.005 ms at eight (seven isolated dev trials each,
zero-capacity sessions, grid/preparation/evaluation/marching included).
Astra's verdict is “not met, try sampled-marcher phase profiling”; no performance
gate success or confirmed-reference-hardware qualification is claimed.
The approved empty-cell emission guard passes the independent ordered plane
golden with empty/crossing/empty slabs and the existing full parity matrix.
Seven saved-before/rebuilt-after trials at each domain count preserve all
hashes/cardinalities. The eight-domain whole-cook median improves from 31.764
to 24.551 ms and allocated bytes from 110,118,168 to 46,286,896; outliers are
retained. Astra says keep the guard, but the gate is still not met; next
measure both counting passes separately. Details and all raw CSVs are in the
performance log. Broad current `@all @runtest` verification passed, including
36 standard files, two actual custom-catalog executables and 13 fixtures at
four times and domains 1/8. At that stage native qualification and commits
were blocked by the managed sandbox; the later M1 checkpoint resolves that
restriction.
The counting-pass diagnostic is recorded with a reproducible temporary patch;
all instrumentation/dependency changes are restored byte-for-byte. Initial
counting and emission-pass recounting take medians 3.876/3.863 ms with no
measured allocation, versus 17.002 ms instrumented sampled extraction.
Astra approves replacing the six per-cell tetrahedron-count lookups with a
fixed 256-entry cube-count table, preserving both passes, streaming storage,
classification, cancellation and emission. Before editing, save both current
uninstrumented benchmark executables and collect the same before/after fixture
matrix. Add an independent exhaustive 256-mask single-cell count check using
corner-to-flat order `[0;1;3;2;4;5;7;6]`, including equality at iso. This table
change is now implemented: the independent exhaustive masks and full normal/
topology parity matrix pass. Seven isolated before/after trials preserve all
fixture hashes and cardinalities. Eight-domain whole-cook median falls from
23.019 to 20.167 ms; Astra says keep the lookup, but the <10 ms gate remains
not met. Gradient-phase attribution is complete with temporary instrumentation
restored byte-for-byte; XY/Z medians are 1.444/1.090 ms of a 14.522 ms
instrumented extraction. No gradient rewrite is approved or implemented.

**Slab scheduling and exact rounding (2026-10-09).** Consecutive sampled slab
chunks now own rotating planes and global derivative halos, with deterministic
prefixes and disjoint output ranges. Smooth/flat nonlinear seam comparisons,
tail chunks, malformed values, cancellation and source ownership pass at
one/eight domains. Initial paired seven-trial M1 medians are sampled sphere
16.889→6.873 ms and whole cook 20.954→12.937 ms at eight domains; whole-cook
allocation increases about 9.65 MB and one-domain time increases 2.3%.
Astra's review discovered compiler contraction hidden by the dyadic sphere:
scalar `length` fused sum-of-squares, whereas packed primitives round each
multiply/add separately. Opaque squared components now enforce the Lisp
primitive contract; the new 100,230-sample off-centre regression fails before
and passes after, against independently written multiply/add/sqrt Lisp at
two times and domains 1/8. SOP/RDK sampling and the benchmark explicitly use
`Float.fma index step min`; the SOP test checks every actual grid coordinate.
The four original asymmetric sampled CSVs are preserved as a different-field
diagnostic. Corrected comparable samples retain the dense asymmetric hash;
one/eight medians change 9.788→10.661 / 12.850→8.227 ms. The corrected
uninstrumented whole cook is 28.312 / 13.569 ms and retains the existing sphere
hash. Focused Flow/IR/SOP/RDK/Procedural checks pass. Astra's verdict is
“not met, try same-cook SOP phase attribution.” No additional algorithm is
approved: instrument disjoint grid construction, complete `Kernel.prepare`,
runner execution and complete extraction, buffering rows outside the cook
and joining each phase to its own whole-cook trial. Seven isolated trials plus
one warm-up at domains 1/8, and a same-slot uninstrumented comparison, are
required; archive the patch and restore production files byte-for-byte.

**Same-cook attribution (2026-10-09).** The first four-phase diagnostic's
in-cook GC snapshots perturb whole cooking (40.884/50.928 ms), so those totals
cannot select an optimization. Raw allocation evidence is retained separately.
Astra's verdict is “not met, try time-only SOP phase attribution.” That revision
is measured and archived too: seven trials plus warm-up at domains 1/8,
uninstrumented medians 27.619/11.755 ms, instrumented 28.467/12.085 ms.
Joined per-trial whole-minus-phase time is only 0.013–0.047 ms. Eight-domain
phase medians are grid 1.555, preparation 2.585, kernel 2.235, extraction
5.677 ms. Every hash/cardinality is unchanged and both temporary sources are
restored byte-for-byte; field/lattice focused checks pass.
Astra's next verdict is “not met, try allocation-free packed-input validation.”
Replace the shared Value.validate packed-array callback with an indexed
finite check, preserving width validation first and the exact fin diagnostic
on failure. A large finite Vec3 validation allocation regression (<4 KB
increase over a small array), complete malformed/nonfinite/source checks,
saved-before seven-trial whole-cook matrix at domains 1/8 and paired time-only
preparation attribution at eight domains are required. No bridge bypass,
cache or scheduling change is approved for that validation trial.

**Indexed validation (2026-10-09).** The shared packed branch now checks
finite values by index, preserving width-first validation and the exact
failure diagnostic. The allocation regression fails before with 786,384 bytes
and passes after; large Float/Vec2/Vec3/Vec4 storage stays byte-identical and
every-coordinate NaN/±infinity, final-coordinate and malformed-width error
checks pass. Focused Flow/IR/SOP/Procedural checks pass. Seven isolated
uninstrumented M1 trials preserve all hashes/cardinalities; medians change
27.556→27.564 ms at one domain and 12.350→11.300 ms at eight, with exactly
13,182,000 fewer allocated bytes at one domain. Same-cook time-only
preparation falls 2.569→1.859 ms at eight domains. No instrumentation ships.
Astra says keep validation; its verdict is “not met, try deterministic row
chunks for SOP grid filling through the shared Parallel pool.” The next
approved trial chunks complete rows by `1 + (grain-1)/nx`, decodes y/z once
per row, retains the existing three explicit FMA expressions and stable
x-fast disjoint output, and uses the shared pool only at the existing
two-grain cutoff. Cancellation state is chunk-local and checked again after
joining. No grid work moves outside timed cooking. Non-dyadic `(7,5,9)`
actual-coordinate/geometry checks at grains 97, 240 and max_int plus
precancellation must pass; save-before seven-trial one/eight whole cooks
and paired eight-domain time-only attribution are required. That trial is
now measured and rejected; the strict eight-domain whole-cook <10 ms gate remains open.
The validation checkpoint passes `--ship` and native GPU numerics (exit 0).

**Grid trial (2026-10-09).** Complete row chunks preserve all sample and mesh
bytes, including non-dyadic bounds, tail chunks, sequential cutoffs and
precancellation. However, seven isolated uninstrumented whole-cook trials
regress 27.515→30.298 ms at one domain and 11.641→12.343 ms at eight.
Time-only eight-domain grid attribution improves 1.449→0.566 ms, while
extraction increases 5.983→10.919 ms in those instrumented runs. This locates
elapsed time without establishing its cause. Astra says revert production
scheduling and retain tests/evidence. Sequential grid filling is restored.
Its next verdict is “not met, try time-only attribution of bulk preparation
into map construction and IR compilation.” Temporarily measure the existing
`E.Private.map_function` and `Attribute_kernel.prepare` calls as children of
the coarse preparation interval; do not count them twice. Buffer output,
retain warm-up ID -1 and timed IDs 0..6, verify one child pair per cook and
containment in the parent, preserve complete hashes/cardinalities, and run
seven isolated one/eight-domain uninstrumented and instrumented trials.
Restore source byte-for-byte afterward. No algorithm change is approved.

**Preparation attribution (2026-10-09).** This diagnostic is now complete:
seven isolated warm-up/excluded one/eight-domain trials preserve every full
hash and count. At eight domains, the parent preparation median is 1.884 ms,
with map construction 1.863 ms and IR preparation 0.021 ms. At one domain,
the respective medians are 1.861/1.846/0.015 ms. Every cook has exactly one
child pair contained within its parent. Restored uninstrumented whole
medians are 29.789/16.353 ms at one/eight domains; instrumented medians
are 27.629/14.844 ms. All outliers remain in raw CSV, without claiming a
performance improvement or diagnosing the higher whole-cook times.
Both production sources are restored byte-for-byte; focused validation
passes. The strict <10 ms gate remains unmet. Astra's raw-number verdict is
“not met, try moving the packed-validation error call outside its sequential
scan.” Source review identifies validation as map construction's sample-sized
work. The approved trial scans ascending finite coordinates with a while
loop, then calls the unchanged error helper once outside the loop on the
first invalid value. Preserve width-first validation and allocation bounds;
add empty arrays and ±0/±maximum-finite/±smallest-subnormal cases for all four
packed widths. Inspect native assembly, run seven-trial one/eight-domain
whole cooks and repeat the eight-domain pair in reverse order, retain every
row, and repeat the parent/child diagnostic before/after. Keep only with
repeatable preparation improvement and no whole-cook regression; otherwise
revert. No scheduling, grid, compiler or cache change is approved.

**Sequential validation scan (2026-10-09).** Implemented and checked:
empty/boundary-value coverage and the existing every-coordinate error,
width precedence, byte-identity and allocation regressions pass. Native
assembly confirms successful-loop state stays in registers. Seven isolated
whole-cook medians improve 27.539→26.272 ms at one domain and
11.948→10.417 ms at eight. Reverse-order eight-domain medians are
15.840→11.280 ms; every row is retained. Precise time-only attribution
reduces preparation 1.868→0.597 ms at eight domains, and all children fit
their parent. Earlier rounded/mixed-format diagnostic batches remain
separate. No instrumentation ships. Astra says keep the scan; the strict
<10 ms gate remains open. Its next verdict is “not met, try hoisting the
SOP grid's y-coordinate calculation per row and z-coordinate calculation
per plane.” Retain sequential loops/cancellation, unchanged explicit FMA
expressions and x-fast indexing. Reuse complete lattice/mesh/cancellation
checks, inspect assembly/allocation, and measure seven-trial one/eight whole
cooks plus a reversed eight-domain pair and four-phase attribution.
Keep only with exactness and repeatable whole-cook benefit without material
allocation or one-domain regression. No scheduling or cache change.

**Rejected coordinate hoist (2026-10-09).** All coordinate-bit/mesh/cancel
checks and allocation checks pass, and grid attribution improves about
0.8 ms. Initial whole cooking is contradictory: one domain regresses 7.1%,
and eight domains improve in the first order but regress 21.6% in reverse.
Astra required reverting production and one balanced repeat of the unchanged
saved executables. Eight adjacent pairs per domain alternate process order,
with seven cooks per process (56 measured rows per executable/domain).
Pooled one-domain medians are 26.988→26.640 ms; eight-domain medians
11.915→12.688 ms. Both eight-domain order aggregates regress, and only
four of eight pair medians favor the trial. Astra says leave it reverted and
stop testing that candidate. Its patch and every prior/balanced row are
retained; no gate, tolerance or golden changes.

Astra's next verdict is “not met, try time-only attribution of the sampled
extractor's joined count and emission passes within the whole SOP cook.”
Temporarily measure caller-side count through its join; prefix/output
allocation/setup; emission through its join; and packed wrapping/geometry
construction. These are children of coarse extraction, never sums of
overlapping worker times. Buffer all output and use round-trip timestamp
precision; retain warm-up -1 and timed IDs 0..6, one child phase set per
cook, full hashes/counts and child containment in the parent. Run seven
isolated retained uninstrumented and diagnostic cooks at domains 1/8,
report parent-minus-child residuals and overhead, preserve all outliers,
and restore source/Dune byte-for-byte (temporary Unix linkage only if
needed). No algorithm, production dependency or public API change is
approved. The strict <10 ms whole-cook gate remains unmet.

**Joined extractor attribution (2026-10-09).** The approved diagnostic is
complete and all source/Dune restored byte-for-byte. Seven isolated one/eight
whole cooks preserve every full hash/count and paired child containment.
At eight domains, count/setup/emission/finish medians are
1.330/0.084/6.155/0.440 ms within a 7.898 ms extraction parent; one-domain
medians are 3.632/0.073/13.021/0.401 within 17.161 ms. Timed median
parent-minus-child residuals are 1.907/0.954 μs at eight/one domains.
Emission includes gradients, the second count/prefix pass and triangle filling,
not triangle filling alone. Uninstrumented whole medians are 28.687/18.417 ms
at one/eight domains; faster instrumented medians are variability evidence,
not an improvement. The strict <10 ms gate remains open.

Astra next says “not met, try writing interpolated edge positions and normals
directly into the existing packed output arrays.” Before implementing, capture
one aggregate golden of complete geometry bytes across all 256 cube masks,
inside values 1 and equality 0, smooth/flat and existing empty results. Direct
edge writes remove immediate Vec3/pair copies; triangle winding reads its three
owned slots and swaps both position/normal slots together when flipped. Keep
all interpolation, cross product, normalization, thresholds, association and
signed zeros unchanged; flat normals overwrite the three slots as before.
No edge reuse, gradients/scheduling changes, cache or new storage. Preserve
saved-before full hashes plus existing nonlinear seam/asymmetric/domain/grain
coverage. Measure seven isolated one/eight whole cooks, sampled/dense sphere,
gyroid and asymmetric controls, a reversed eight-domain whole pair, and joined
emission attribution. Keep only with exactness, material allocation reduction
and repeatable whole benefit without control regressions; otherwise fix/revert.

**Pre-edge geometry baseline (2026-10-09).** The required aggregate golden
is captured from retained `2c9feb3e` before any edge-emission edit:
`4efce5e9c56d8d5fb9ead44e339bded7`. Existing independent tetrahedron counts
now run all 256 masks with inside 1/equality 0 and both smooth/flat shading.
The aggregate encodes settings, mask, complete authored geometry bytes
(positions, topology, attributes/groups, excluding IDs/caches) and empty
results. It fails with an unset expected hash and passes with the captured
baseline. Focused RDK core/procedural SOP checks pass. Direct packed edge
writes and their complete measurement matrix remain pending; do not refresh
this golden to accept drift from that trial.

**Direct packed edges: done (2026-10-09, `97e5f7bf`).** Edges now write
positions and interpolated normals directly into their existing owned slots;
winding swaps both packed positions and normals. The captured 1,024-case
golden and every saved-before full benchmark hash remain unchanged. Seven
isolated M1/dev trials measure whole cooks 26.191→25.660 ms at one domain
and 9.759→9.132 ms at eight; the reverse eight-domain pair is
10.292→9.861 ms. Allocation falls 42.72→26.99 MB at one domain, and all six
sampled/dense extraction controls improve. Joined emission medians fall
13.146→12.235 ms at one domain and 4.164→3.610 ms at eight; diagnostic
source/Dune changes are restored byte-for-byte. Astra's verdict is “met”
for the measured F2.1 gate; no further F2.1 optimization is requested.
Raw rows, commands and review are in the performance log. Shipping and full
F5 native/pixel qualification pass (exit 0) for this checkpoint; F1.3 and the
image/resident work remain separate requirements.

**Lisp.** A field is an ordinary `fn` of one `vec3` parameter returning a
float, passed to a catalog kind through an `Fn` port (F1.1). No new value
type. The first consumer is a new SOP:

```lisp
(sop/iso_surface :field (fn [p] (- (length p) 1.0))
                 :resolution [64 64 64] :min [-2 -2 -2] :max [2 2 2] :iso 0.0)
```

**Lowering.** Do **not** call `Iso_surface.extract` with a per-sample
closure that runs the interpreter: 64³ = 262,144 samples at 710 ns each is
186 ms per cook, and a million at 1M-sample resolutions. Instead:

1. Build the sample positions as one packed `Vec3_array` of
   `(rx + 1) * (ry + 1) * (rz + 1)` elements: `Iso_surface` resolutions count
   cells, so a 64-cell resolution uses 65³ samples (GPT 6 Astra's source
   audit, 2026-10-08). The grid is static; it is a `Source` in the IR
   with `Count.Static`.
2. Run the field as a packed `map` over that array through
   `Attribute_kernel.prepare` and `Flow_ir.Executor.force` (CPU tier,
   byte-identical at one and eight domains). This gives a `Float_array` of
   samples.
3. Add to `rdk` one entry point `Iso_surface.extract_sampled :
   resolution:int*int*int -> min -> max -> iso -> samples:float array ->
   (Geometry.t, Error.t) result` that consumes the array instead of calling a
   field. Use the `add-rdk-op` skill (interface, tests, bench). The marching
   step is the existing `extract_dense` code with the sample lookup replaced
   by an array read; keep the sample order documented in the `.mli` (x
   fastest, then y, then z, or whatever `extract_dense` iterates: read it,
   do not guess).
4. The SOP's `Node.facts`: irregular, topology-changing, exact (the samples
   are exact floats from the CPU tier; a GPU-sampled field would be `Approx`
   and the IR refuses it into a catalog input, which is right).

**Projection.** The `:field` port draws as a zone with the body cards (F1.1
step 5). `v` on the SOP shows the mesh; a probe on the field body shows the
sample for the selected grid tuple (the probe machinery forces one tuple).

**Tests.** `lib/rdk/test_iso_surface.ml`:
`extract_sampled` on a sphere's samples equals `extract_dense` with the
sphere `custom` field, byte for byte, one and eight domains.
`lib/flow_sop/test_attribute_kernel.ml`: the field kernel over the grid
equals the interpreter's per-sample values. `test/test_workspace_ir.ml`:
a new `sketches/flow_field/sketch.rays` (copy `flow_kernel`) passes at four
times and both domain counts.

**Gate.** A 64³ sphere field cooks in under 10 ms at eight domains on the M1
(the kernel row says 16.5 ns per element, so about 4 ms of samples; the
marching step is the rest). Record before/after in `performance-log.md`
under "F2.1 field kernel".

**Astra brief.** "Design the sample-array entry point for
`Rdk.Iso_surface` so that `extract_sampled` and `extract_dense` share the
marching code with no per-sample closure, keep deterministic chunking under
`Parallel` with the context grain 16,384, and stay byte-identical at one and
eight domains. Say which sample ordering the existing code iterates, what
the sequential cutoff should be, and what the one failing check is."

#### F2.2 Image kernels: a per-pixel `map`

**CPU checkpoint (2026-10-09, `4ba82525`; F2.2 remains open).** `image/map` now has a
strict Vec2-to-Vec4 Lisp declaration, typed graph function zone and argument
gestures. `Flow_sop.Image_kernel` retains the immutable UV grid and actual
packed program, executes once per uncached session cook and converts to one
owned RGBA8 output buffer. No per-pixel interpreter closure is installed.
Float-backed noise/sampling retain their precision; exact byte-image sampling
explicitly expands normalized samples without retaining a float copy. Tests
pin both tie parities, clipping/nonfinite/cancellation, >two-grain asymmetric
UV orientation, reference/packed/domain parity, named functions and live
lexical captures. Workspace display, mesh textures and SOP sampling use the
CPU result. Plan/body edits and resize preserve the image resource identity;
closed owners refuse resolution. Nested image/map→drawing→image/render
invalidates for frame dependencies and same-frame changes to drawing state.
State-dependent pixel bodies retain the compiler's `E_PACKED_STATE` refusal.

Focused checks and `--ship` pass; the 38-file workspace sweep includes the new
`sketches/flow_image_kernel` with both custom catalogs and 13 fixtures.
The odd-width native nested-render/state regression passes. Seven isolated
warm whole cooks at 512²/1024²/2048² preserve every corresponding full-byte
hash between domains 1/8. At 1024², eight-domain medians are **11.874914 ms**
for the gradient and **12.237072 ms** for a live capture. Astra's verdict is
**CPU gate PASS**, covering the prepared producer through conversion and
cleanup. Cold grid/program preparation has separate rows. CPU allocations
still scale with image size, and upload/display is outside this cook gate.
Raw evidence is `performance/f-image-map-cpu-domains{1,8}.csv`; see
"F2.2 image kernel: CPU checkpoint" in `performance-log.md`.

**GPU upload checkpoint (2026-10-09).** `Flow_gpu.Run` reuses its last
successfully uploaded immutable input per slot, keyed by array identity and
covered length, with invalidation on buffer replacement, failed upload and
close. Frame uniforms and the four-byte validation-status read remain live.
Native output checks cover same-sized replacement/reversion and changed frame
uniforms. Injected partial-write tests require reupload of the previous array.
Seven isolated 200-dispatch trials after ten warm-ups at 512²/1024²/2048²
reduce UV upload bytes per frame from 2/8/32 MiB to zero. Raw evidence and
dispatch timings are in `performance/f-image-gpu-uploads-{before,after}.csv`;
the performance log separates this runner checkpoint from the image gate.
Astra accepts the checkpoint; focused/native checks and `--ship` pass.

**GPU producer/converter checkpoint (2026-10-09).** `Flow_gpu.Image_sink`
converts a current validated Vec4 runner output with ties-to-even rounding,
256-byte padded rows and the existing buffer-to-texture blit. It reuses one
buffer/texture pair, replaces resized resources only after successful
completion, and invalidates borrowed generations before writes. Mock tests
pin ordering, failed allocation/dispatch/copy/completion cleanup, reuse and
zero pixel reads. Native 65×3 gradient/live/clipping/tie fixtures at three
times have zero maximum channel difference, differing channels and pixels;
resize and stale outputs are checked separately. Seven isolated 200-frame
producer/converter trials include fresh input preparation, completed dispatch
and finite-status read, conversion/copy completion and converter-token access.
At 1024², medians are 1.915741 ms (gradient) and 1.937801 ms (live capture).
Warm allocation is constant in pixel count, with zero input uploads or
persistent resource creations. Cold and resize rows are separate. Astra's
verdict is “Producer/converter checkpoint accepted.” Raw timing and native
parity are `performance/f-image-map-gpu-converter{,-parity}.csv`.
Focused/native checks and `--ship` pass; this is a converter checkpoint,
not connected GPU image completion.

**Authored image qualification checkpoint (2026-10-09).** Canonical `image/map`
sites now use the existing qualification pipeline: static observation binds
a representative Vec2 column to the actual checked pixel function, preserving
captures, and compiles with production packed/GPU form checks. Unsupported
dynamic operations, state and float32-overflow captures refuse qualification;
folded supported constants qualify. Refusals dominate successes across graph
instances, with finite requalification rebuilding the result. The image recipe
does not taint unrelated exact consumers. Lowering retains authored image paths
separately from runtime named-call prefixes, and ambiguity remains sticky in
either order. Image owners bind only plan/path/site metadata and invalidate
prepared maps at that boundary; unbound or missing provenance remains CPU-only.

Focused tests cover independent image sites sharing a callable, held functions,
canonical declaration identity, captures in both instance orders, named-function
aliases, fused/unfused compilation/emission and qualified executor selection.
Exact CPU snapshots retain full-byte equality at domains 1/8 and survive later
cooks. Native qualification→lowering→prepared executor→production Host→converter
at 65×17 has zero maximum channel difference, differing channels and pixels at
times 0/0.5/1. This verifies producer selection and conversion, not runtime image
publication. Astra approves the authored qualification checkpoint; the 40-file
actual-catalog qualification audit and focused/native checks pass. Commands and
raw channel differences are in the performance log. No new timing gate is claimed.
The final shipping run passes (exit 0), including all 38 standard workspaces,
two actual custom-catalog executables and 13 fixtures at four times/domains 1/8.

**Borrowed runtime image checkpoint (2026-10-09).** Private images now publish
completed GPU output through a validated borrowed-source callback, without a
CPU pixel buffer or publication readback. Replacement preserves identity,
increments generation and supports resize. Descriptor, domain, destroyed,
expired and substituted sources fail before mutation. Explicit snapshots retain
their bytes across later publication and destruction; CPU replacement and Canvas
copying clear GPU backing. Destruction releases the borrow, not its texture.
Both lower-scene caching and retained Scene replay check callback liveness even
without a generation change. Stage stamps include each 2D/UI layer's image
generations. Native tests expire a converter output after two renders of the
same Scene, require both cache paths to fail, then republish and verify changed
pixels against a fresh render. Ordinary images, retained display-list segments
and mixed layers are covered, including empty aggregate resource lists.
Qualified named-image publication at 65×17 and times 0/0.5/1
has zero channel and pixel differences against exact CPU output. The existing
path-tracer film publication remains compatible. Mock coverage includes zero
stored CPU bytes/reads at publication, 1024² construction allocation below a
4 KiB assertion ceiling, leases, CPU transitions and borrowed ownership.
This is private backing groundwork: workspace producer ownership, resident
mesh/offscreen consumers and deferred exact GPU snapshots are still open.
Commands and raw parity are recorded in the performance log.
Final reviewed-code focused/native checks, API validation and `--ship` pass
(exit 0), including the full workspace sweep at four times/domains 1/8.

**Resident consumer checkpoint (2026-10-09, `6636e12b`).** Private Texture views borrow a
runtime GPU image without CPU storage or ownership; identity remains stable
and dimensions follow republication. CPU pixel/sampling/mipmap/subsection
operations explicitly require an immutable snapshot. Mesh staging binds the
borrowed texture directly and retains image-generation dependencies. Offscreen
2D images now use the same resident path as windows, preserving device checks.
Checked fresh staging and pre-replay validation preserve typed resource errors.
Mixed-layer IR caches retain exact frozen resource generations, including their
storage in the byte cap, so resize cannot reuse old image rectangles.
Nine native image/mesh/mixed cases match fresh round-trip renders byte for byte
with zero warm uploads and source reads. Expiry without republication, resize,
CPU authority, wrong-device rejection, retained snapshots and zero handle delta
pass. Removing the layer guard makes mixed resize parity fail; restoration
passes. Astra approves functional consumer support. Focused checks, full F5
native qualification and shipping pass (exit 0), including both workspace
sweeps at four times/domains 1/8. The 2× PXUI goldens skip at the actual 1×
density. Raw parity and commands are in the performance log. Workspace GPU
publication and retained Canvas production are still open.

**Connected workspace publication checkpoint (2026-10-09).** Workspace image
display now scopes its shared GPU owner and executes qualified Image_kernel
programs through `try_display`, Host output, one authored-site sink and validated
runtime image publication. A stable borrowed Texture serves mesh consumers.
CPU payloads and display have independent stamps; exact-first CPU map requests
create no runtime Image and never read or replace an existing GPU display.
Unselected placement keeps the CPU cook; execution/publication errors remain
errors. Production keeps Measured; the native fixture explicitly uses
Qualification. New sinks commit only after publication succeeds; errors and
exceptions leave no slot or native handle behind. Close releases images before
sinks/runners/pipelines and the GPU lease. Pending recursive parents reserve
entries within the 64-image bound, including exact-only entries.
Five actual-editor mixed image/mesh comparisons have maximum channel difference
0 and differing channels/pixels 0. Live lexical capture, body edits, odd-size
resize, CPU/GPU transitions, repeated static GPU failure/retry, independent CPU
domain-1/8 snapshots, saved payloads and zero source reads pass. A nested render
keeps CPU's 127 rounding for 0.499999999 while its child is resident on the GPU;
legacy display A → exact B → display A restores A. The owner fixture covers 80
failed conversions, 80 failed publications, exceptions, all 64 pinned sinks,
capacity refusal and failed existing updates followed by retry. Astra approves
the functional checkpoint. Focused/native/API checks, full F5 qualification
and shipping pass (exit 0), including both complete workspace sweeps at four
times/domains 1/8. The 2× PXUI goldens remain unqualified at the actual 1×
density. Raw parity and commands are in the performance
log. This is functional evidence, not a connected timing/allocation verdict.

The workspace resolver still refuses captured geometry without a cooked-source
resolver. Frozen exact GPU snapshots remain required. The connected GPU timing/
allocation/resource/readback and complete size/parity matrix are verified below.
The producer/converter verdict does not close F2.2,
F2.3 or F.md.

**Connected measurement plumbing (2026-10-09).**
Private actual-owner GPU statistics now retain runner/pipeline/sink creations,
releases, uploads and readbacks through eviction, failed publication and close.
Native regressions cover 65 executed producers, eviction/reacquisition, a saved
explicit readback, 80 failed conversions, 80 failed publications, an exception,
64 pinned sinks and repeated close. Totals remain cumulative; inspection rejects
worker domains for fresh/live/closed owners. Focused/native/API checks pass.
The new `bench_workspace_lower --image-map-connected` mode follows Astra's
actual-qualified-owner design: live lexical gradient and changing-capture
fixtures, fresh Measured route probes, separate Qualification producer,
consumer-only and end-to-end trials, CPU domain parity, native full-image
comparisons, authored replan/resize and separate readback/teardown rows.
Its measurements and verdict follow; the converter-only numbers above do not
establish this connected gate.

**Connected timing/allocation gates PASS (2026-10-09, `32ddcd99`).** The actual owner-qualified
workspace route is measured for both live lexical fixtures at 512²/1024²/2048²,
seven trials of 200 completed frames after ten warmups. At 1024², GPU producer
medians are 1.538370 ms (live-dependency gradient) and 1.557695 ms (changing
capture), including preparation, status validation, conversion/copy completion
and image/texture publication. Exact CPU owner cooks at eight domains measure
13.832092/13.118982 ms with every corresponding hash equal at domains 1/8.
Producer allocation is exactly 51,593/43,105 bytes/frame, respectively, at
every size and trial. All warm producer/end-to-end trials have 200 successful
status reads and Image generation advances, stable Image/Texture identity,
zero persistent resource creation, input uploads, pixel readbacks and CPU storage.
Consumer-only replay has no producer dispatch or generation advance. Independent
source comparisons at times 0/0.5 and authored odd-width resize have zero maximum
channel difference, differing channels and pixels in all 18 cases. Full completed
mesh bytes equal source pixels. Six fresh Measured probes select GPU; repeated
timing uses explicitly labelled Qualification. Cold owner/preparation, source-file
replan/resize, explicit readbacks and teardown are separate rows. Astra's verdict:
“Connected F2.2 timing and allocation gates: PASS for the measured fixtures.”
Raw data: `specification/performance/f-image-map-connected.csv` and
`specification/performance/f-image-map-connected-counters.csv`. Commands, machine,
consumer/end-to-end medians and limits are in the performance log. Broad F5
native qualification and pre-commit `--ship` pass (exit 0); 2× UI goldens remain
unqualified on the actual 1× display. Captured geometry and deferred Lisp
`(exact image)` still prevent overall F2.2 completion.

**Captured geometry foundation (2026-10-09; owner connection remains open).**
`Lower.source_context` finds the actual captured node's graph instance, including
nondefault overrides; `source_cone` keeps its upstream inputs and filters drives
and frame callbacks with `Network.remove_nodes`. The enclosing context stays
available for future nested captures. `Attribute_kernel.source_origins` exposes
the existing point-count proof unchanged. `Image_kernel.with_inputs` rebinds
current compiled sources while sharing the UV/program, refusing changed proofs
or source counts with `E_DATA_SOURCE`. A normal `flow.capture` geometry consumer
uses Session's packed-instance materialization boundary. Focused/API checks pass:
live override source updates change full CPU image bytes equally at domains 1/8,
the program stays physically shared, unrelated downstream image callbacks are
excluded, bad source mappings refuse, and materialized instance P matches the
independent expansion. Astra approves this foundation. Current callback context,
bounded owner capture storage, freshness/recursion, workspace GPU capture
execution and measurements remain required; this does not enable that route.
Broad F5 native qualification and pre-commit `--ship` pass (exit 0). The 2× UI
goldens remain unqualified on the actual 1× display; no golden or tolerance changes.

**Owner bridge (GPT 6 Astra, 2026-10-09; functional checkpoint).**
Pass the current network to its frame-node callbacks; the image callback supplies
its own lowering's compiled map and current network to the resolver. This avoids
the stale outer Environment scope after a document edit. Direct requests obtain
source contexts from the bound lowering. Retain the unrestricted context across
nested calls even when a callback runs inside a restricted source cone.

Prepare source cones before image cache hits, without cooking geometry. Recreate
their Value_lane on a supplied state-stamp change or a new live input for stateful
cones, always forking the supplied caller snapshot. Skip compilation for a
physically unchanged resolved graph; otherwise use `Edit_graph.compile_all`
with its previous result to preserve unchanged compiled roots. A source revision
changes when its root's physical identity or the exact
`Context.cache_projection (Graph.dependencies root)` changes. Revisions are
owner-monotonic, including after eviction. Each image stamp stores the ordered
reachable `(source_plan_id, revision)` vector; parent image/render includes its
children's captures, while unrelated fixed renders retain their own cache hits.
CPU execution rebinds the actual inputs and cooks them with Image_kernel.node.
Display resolves materializing consumers and immutable flattened attributes only
when execution needs them. Source-origin proof changes reprepare the pixel
program; position/attribute changes retain its UV/program where that proof holds.

One request scope owns the active `(plan, node)` path, pending-image reservations
and a lazily created zero-cache Session, balanced with Fun.protect. Recursive
callback entry shares that scope and returns typed cycle errors. Retain at most
64 source records and 64 MiB of charged capture geometry/flattened arrays;
oversized captures execute uncached. This is a capture-cache budget, not a
total-process memory claim. Copy the effective immutable seed/grain/domains from
Core.cook into Workspace_host/Workspace_images at creation, and use one context
helper for source projection, source cooking and CPU image cooking. Standalone
defaults remain seed 0L/grain 16384; export takes the declared window seed.

The connected regression must cover changing transitive captures under a parent
render, same-frame state changes, two override instances, packed instances,
nested acyclic image dependencies, cycle failure/replan recovery and unrelated
fixed-render reuse. A seed/grain-sensitive custom source pins owner configuration
against independent CPU cooks at domains 1/8. Then measure static/changing
captures with source point counts, including complete drive resolution, cooking,
flattening and uploads, and repeat the uncaptured 1024² gate. Earlier uncaptured
measurements do not establish capture costs or zero uploads for changing geometry.

The bridge is implemented. Direct CPU requests install the owner resolver scope;
an image-sampling geometry source and stateful sequential-versus-fresh-owner
requests pass without advancing the caller's state. Live P/Cd captures from two
override instances match complete CPU bytes at domains 1/8. Their actual GPU
images have maximum channel difference 0 in all four time/instance cases, exactly
four status reads and no output readback. Parent renders refresh; an unrelated
fixed render retains its generation. Reachable preparation-time dependency
summaries replace the prior global-plan scan. A real callback re-entry cycle
returns `E_IMAGE_CYCLE` twice, then the same owner recovers with an acyclic context,
unchanged caller state, no published resources and clean handles.

Export lowers with reference evaluation and resolves CPU images recursively.
Two exported PNGs match complete independently cooked CPU nested-render bytes;
the rounding-sensitive 0.499999999 channel stays 127 despite a separately resident
GPU child. Ordinary CPU payload requests still leave resident images untouched.
Astra's functional approval condition (the full native executable including PNG
equality) is satisfied. Effective owner seed/grain/domains match independent CPU
cooks at domains 1/8. A single image capturing 65 sources retains 64 metadata/data
records and 78,720 charged bytes, then reuses the retained source without cooking
or flattening again. Removing only the metadata-ownership guard makes that reuse
assertion fail; the guard is restored. Immutable geometry over 64 MiB stays
uncached across changing pixels with unchanged source projection, then a small
source resumes caching. Display materializer/flatten counters survive close;
exact CPU cooks do not contribute to them. Astra approves the functional
checkpoint. Expanded state/instance coverage and capture measurements remain
required, followed by frozen
`(exact image)`. Broad F5 qualification, including the oversized capture
qualification, passes (exit 0; `/tmp/rays-f-image-capture-owner-full-final.log`).
Pre-commit shipping passes (exit 0;
`/tmp/rays-f-image-capture-owner-ship.log`); this is not an overall F2.2 verdict.

**Captured-source measurement baseline (2026-10-09).** The actual-owner harness
now covers static/changing P/Cd captures with 1,024 source points at
512²/1024²/2048² and 65,536 points at 1024². Each cell has independent complete
CPU cooks at domains 1/8, a fresh Measured-policy route probe and seven completed
200-frame Qualification trials after ten warmups, including producer, consumer
and combined timings. All 24 capture snapshot comparisons have maximum channel
difference 0, with CPU 1/8 byte identity. Static source red/green remain unchanged
while blue changes; changing source red/green and blue all change. Static warm
trials perform no materializer cooks/flattens; changing ones perform 200 cooks
and 400 P/Cd flattens. Bounds, no warm uploads/readbacks, resize/replan and close
checks pass. Producer allocations stay identical across pixel sizes at fixed
1,024-point count (2,500,473 B static; 2,830,587 B changing).

At 1024², small-source CPU8/GPU medians are 16.782045/2.967625 ms static and
17.330885/3.094635 ms changing. The 65,536-point cases are
65.782070/45.126491 ms static and 66.111088/48.500581 ms changing: these exceed
the 40 ms CPU and 5 ms GPU gates. They remain unfinished performance work;
cache reuse alone does not close it. The separate uncaptured 1024² recheck
has CPU8/GPU medians 13.716936/1.663125 ms for the gradient and
12.020111/1.633930 ms for the live lexical capture, with six exact native parity
comparisons. Both commands exit 0; raw capture/regression data and counters are
in `specification/performance/f-image-map-captures*.csv` and
`f-image-map-uncaptured-recheck*.csv`. Astra's verdict: both small-source 1024²
capture cells and both uncaptured cells pass; both large-source cells fail.
Allocation passes pixel-size independence at fixed source count. Separate
attribution remains required; no overall captured-source acceptance is inferred.

**Captured-source attribution (2026-10-09; diagnostic, no optimization).**
Temporary initial-domain inclusive probes over seven 200-frame trials identify
captured-uniform reference evaluation as the large-source GPU cost. Static
65,536-point producer median is 42.957189 ms/frame, with 41.087186 ms inside
Packed preparation and about 20.5 ms each in uniforms 0/1. Source preflight
takes 0.008935 ms/frame across two calls. Changing producer median is
45.413494 ms, with 43.220823 ms in preparation. Its 2.177452 ms materializer
and 0.457065 ms flatten phases are nested inside uniform evaluation, not added
again. The gradient control prepares in 0.006000 ms/frame. Seven CPU8 whole
cooks and nine exact native parity comparisons also pass; worker-internal CPU
phases remain explicitly unobserved. All eight temporary files are restored.
Raw rows, whole-trial/counter CSVs and a reproducible patch from `4d5f3959`
are `specification/performance/f-image-map-capture-attribution*`. Astra accepts
the attribution and designs shared packed evaluation of supported uniform
subexpressions through the existing evaluator hook, plus narrow canonical
`+` reducer support using the actual operation environment. Ordered reduction,
fallback diagnostics and transactional state stay intact; no cross-frame
uniform cache or reassociation is allowed. The focused compiler matrix and
uninstrumented after measurements remain required. These
instrumented numbers do not replace the uninstrumented failing gate evidence.

**Shared uniform preparation correction (2026-10-09; large GPU gate still open).**
CPU `Packed.force` and GPU `Packed.Private.prepare` now share one evaluator
context for captured uniforms. Its existing execution hook runs supported
numeric subexpressions packed while surrounding scalar expressions remain on
the reference walker; compilation refusals keep reference evaluation. Named
canonical `+` reductions use existing ordered accumulator instructions after
checking the actual declaration's packed capability. No reassociation or
cross-frame cache is added. The focused seven-case matrix observes actual
packed execution and exact CPU/prepared-uniform bits at domains 1/8, including
Vec3, cancellation/signed zero over 32,769 elements, changing captures, empty
and integer seeds, unsupported/custom callables, nonfinite diagnostics and
transactional state rollback/recovery. Actual workspace CPU/native checks pass.
The two intentional private API additions are reviewed and promoted.

The unchanged eight-cell and uncaptured 1024² matrices finish with 30 native
parity comparisons at maximum difference 0 and all resource/capture assertions
passing. Large-source CPU8/GPU medians are now 25.685072/9.757650 ms static
and 25.298119/12.211875 ms changing. Astra: “The shared preparation correction
is worth retaining.” CPU gates pass for every measured 1024² cell; GPU gates
pass for small sources and controls but still fail for both large sources.
Allocation remains pixel-size-independent at fixed source size. Raw after
files are `f-image-map-captures-after*.csv` and
`f-image-map-uncaptured-recheck-after*.csv`. Broad F5 validation passes, including
both workspace sweeps, native/pixel checks and oversized capture qualification
(exit 0; `/tmp/rays-f-image-capture-uniform-full.log`). Shipping passes
(exit 0; `/tmp/rays-f-image-capture-uniform-ship.log`).
Next attribution must separate uniform compilation/execution and
whole ordered traversal before any further accumulation change.

**Ordered traversal and accumulator write (2026-10-09; large GPU gate still open).**
The second temporary attribution confirms about 8 ms/frame in the two ordered
P/Cd reduction traversals; callback compilation takes only a few microseconds.
Changing geometry adds about 1.90 ms of materialization and 0.38 ms of flattening,
nested in P source preparation. Traversal includes per-chunk scratch allocation;
worker CPU internals remain unobserved. The eight-file reproducible patch and
raw diagnostic rows are `f-image-map-capture-attribution-after*`; production
probes were restored byte-for-byte and focused checks passed.

Astra approved only replacing the `Accumulator` instruction's generic fill
with indexed float writes. All other instructions, finite checks, scheduling
and ordered accumulation remain unchanged. Existing full-byte fold/scan and
uniform regressions pass, including every scan element, cancellation, signed
zero, changing captures, diagnostics, rollback and domains 1/8. The unchanged
eight-cell and control runs preserve all 30 zero-difference native parity rows
and resource/capture checks. Large CPU8/GPU medians become
23.262978/7.562215 ms static and 22.775888/9.956585 ms changing. Static large
allocation falls by exactly 6,291,456 B/frame to 761,465 B/frame; fixed-source
pixel-size independence and uncaptured allocations remain unchanged.
Astra: “Retain the indexed loop.” CPU gates and small/control GPU gates pass;
both large GPU gates still fail. Raw rows are `f-image-map-captures-accumulator-after*`
and `f-image-map-uncaptured-recheck-accumulator-after*`. The next approved action
is a third temporary attribution preserving this loop, plus an instruction
listing of both reduction programs captured outside timing. No further hot-loop
change is approved yet. Frozen exact images and expanded owner qualification
also remain open.

The indexed-write checkpoint passes full F5 native/pixel qualification,
including both complete workspace sweeps and oversized capture qualification
(exit 0; `/tmp/rays-f-image-accumulator-full.log`). Shipping also passes
(exit 0; `/tmp/rays-f-image-accumulator-ship.log`). Actual display is 1×;
2× goldens remain unqualified.

**Indexed-loop follow-up attribution (2026-10-09; no further optimization yet).**
The third isolated diagnostic preserves committed `0f070d3f`'s indexed writes.
The two ordered traversals still take about 5.5 ms/frame; compiler time remains
only a few microseconds. Changing geometry adds about 1.95 ms materialization
and 0.37 ms flattening. The captured actual programs each contain nine slots
(three Input, three Accumulator, three Binary Add), all scanned per accumulator
step. Only the initial GPU preparation enables the bounded two-program
callback; it disarms before warmups/trials and formats listings at process exit.
All nine parity comparisons and resource/capture checks pass. Raw CSV/listing/
reproducible patch files are `f-image-map-capture-attribution-accumulator*`.
Production probes and collector are restored byte-for-byte. Further design
requires Astra review of this evidence; neither large GPU gate is closed.
Restored focused checks and pre-commit shipping pass (exit 0;
`/tmp/rays-f-capture-attribution-accumulator-restored.log`,
`/tmp/rays-f-capture-attribution-accumulator-ship.log`).

Astra's verdict: “Attribution accepted.” Its next approved design recognizes
only non-collecting, one-input zipped ordered addition at width 1–4, with
exactly the proved Input/Accumulator/Binary Add layout, matching dependency
flags and output slots. Input block loading remains; the component loop adds
the accumulator directly to its input register with the existing finite check
and assignment. Every unmatched program remains unchanged; no reassociation,
new instructions, cache fields or scheduling changes are allowed. Scalar and
Vec2/3/4 matched-pattern regressions, a nearby rejected recurrence and the
unchanged after benchmark matrices remain required. The fast path is not yet
implemented, and the large GPU timing gate stays open.

**Proved ordered-add dispatch bypass (2026-10-09; large GPU gate still open).**
The approved local fast path is implemented: one pure predicate proves the
complete non-collecting, one-input Zip addition layout at width 1–4, including
dependencies and outputs. It loads the input block normally and bypasses
per-element dependent dispatch, using the original finite check and ordered
accumulator assignment. The single reviewed/promoted Private predicate API
lets tests verify the same recognition directly. Scalar/Vec2/3/4 full-byte
reference and prepared-uniform checks pass at domains 1/8 over empty/changing
multi-block sources, cancellation/signed zero, errors and state rollback.
Recurrence, reversed addition, scans and broadcasting remain generic. Review
tightened `zipped` to exact Zip; a Product fold with the same nine instructions
is explicitly rejected and remains byte-exact.

The unchanged eight-cell and control benchmarks finish with all 30 native
parity comparisons at zero difference and every resource/capture assertion
passing. Large CPU8/GPU medians become 19.203901/5.443920 ms static and
19.567013/6.654539 ms changing. Fixed-source allocation remains pixel-size
independent; the bounded predicate adds 528 B/frame static, and uncaptured
allocations stay unchanged. Astra: “Retain the change.” CPU and small/control
GPU gates pass; both large GPU cases still miss <5 ms. Raw rows are
`f-image-map-captures-ordered-add-after*` and
`f-image-map-uncaptured-recheck-ordered-add-after*`.

Astra's next approved trial adds `skip=[]` to recognition and branches once
per chunk. Matched programs read their input directly in ascending element/
component order, allocating no scratch/indices/noise/tables. Generic chunks
regain unconditional dependent execution and output lookup. Seeds, sources,
ordered chunks, empty results and transactional fallback stay unchanged. No
unrolling, parallel reduction, reassociation or cache is allowed. Vec3 counts
around block/chunk boundaries and a nonfinite failure after a chunk boundary
must extend the regression before the unchanged direct-input after benchmarks.
That trial is not implemented yet; if it still misses <5 ms, fresh attribution
is required before broadening.

Full F5 native/pixel qualification passes (exit 0;
`/tmp/rays-f-image-ordered-add-full.log`), including both complete workspace
sweeps, GPU/editor/runtime/oversized-capture tests and all pixel aliases.
Actual display is 1×; 2× goldens remain unqualified.
Shipping passes (exit 0; `/tmp/rays-f-image-ordered-add-ship.log`).

**Direct-input ordered chunks (2026-10-09; changing-source GPU gate still open).**
The approved fast chunk adds `skip=[]` to the exact Zip recognizer, reads
elements/components in ascending order and performs the same finite-checked
add/write without scratch/index/noise/table allocations. Generic execution
returns to its original path. Seed/source/empty/ordered-chunk/transaction
behavior remains. Boundary counts around 1024 and 16384, post-chunk overflow,
input immutability, exact reference errors and state rollback/recovery extend
the existing all-width/domain/fallback regression and pass focused checks.

The unchanged eight-cell/control runs retain all 30 exact native parity rows,
CPU1/8 hashes and resource/capture assertions. Large CPU8/GPU medians are
17.266035/3.510880 ms static and 18.228054/6.159385 ms changing. Static
producer allocation is exactly 89,161 B/frame at every measured source/pixel
size; fixed-source changing allocations and uncaptured allocations retain their
expected bounds. Astra: “Retain the direct-input path.” All CPU8 and small/
control GPU gates pass. The large static GPU gate passes; changing still fails.
Raw after files are `f-image-map-captures-direct-input-after*` and
`f-image-map-uncaptured-recheck-direct-input-after*`.

Approved fresh attribution now measures changing-source materialization at
2.491270 ms and flattening at 0.543628 ms, nested in source preparation;
the two direct traversals take about 1.17 ms total. No scratch work is attributed
to matched chunks. Inclusive/initial-domain limits remain explicit. Nine parity
comparisons and counters pass; the probe-only reproducible patch and raw rows
are `f-image-map-capture-attribution-direct-input*`. Production probes are
restored byte-for-byte. Further optimization requires Astra's review of this
evidence; frozen exact images, expanded owner qualification and F3 remain open.

Astra: “Attribution accepted.” The next approved action is a source-refresh
diagnostic: reuse existing Session.node_timings for line/with_attr/capture,
split Attribute_kernel.write into validation/XYZ storage/attribute installation,
and label P/Cd flattening. Worker node timings and initial-domain write clocks
must retain their distinct coverage and nested accounting; report outside frame
loops and preserve the same seven-trial parity/counter protocol. Inspect the
three Array.init callbacks and Duplicate_input 0 before optimizing. No cache,
dependency or ownership change is approved.

The restored direct-input checkpoint passes full F5 native/pixel qualification
(exit 0; `/tmp/rays-f-image-direct-input-full.log`), including both complete
workspace sweeps and native geometry/image/texture/drawing pixels, oversized
capture and runtime qualification. Actual display is 1×; 2× goldens remain
unqualified. No production probes remain.
Shipping passes (exit 0; `/tmp/rays-f-image-direct-input-ship.log`).

**Source-refresh split (2026-10-09; diagnostic, gate still open).**
The approved nine-file temporary patch reuses Session.node_timings immediately
after each successful materializer cook, asserts exactly one line/with_attr/
capture sample and distinguishes node-own durations across cook domains from
initial-domain inclusive probes. The native line operation is `line` (the Lisp
kind is `sop/line`). Attribute writing retains its execution order while timing
count/finite validation, the three Array.init XYZ planes and installation;
flattening is labeled P/Cd. Missing write clocks remain blank/unobserved.

The isolated seven-trial protocol passes all nine native parity comparisons,
CPU1/8 hashes and resource/capture/resize/replan/close assertions. Changing
producer/materialization medians are 6.248649/2.432431 ms. Node-own line,
with_attr and capture medians are 0.295147/2.128962/0.000290 ms; write validation,
XYZ construction and installation take 0.189129/0.940881/0.001158 ms nested
inside with_attr, alongside the 0.641835 ms packed-map traversal. P/Cd flattens
take 0.263529/0.263864 ms. These overlapping durations cannot be added together.
Static production has no warm materializer/write/flatten calls. Raw rows and
the reproducible probe-only patch are `f-image-map-capture-attribution-source-refresh*`.
All nine production files are restored byte-for-byte; the patch passes
`git apply --check`. This attribution does not substitute for a performance gate.
Astra: “Attribution accepted.” The next approved trial replaces only the
non-P write's three Array.init callbacks with three zeroed float arrays and one
ascending direct XYZ copy loop. Validation stays before allocation, installation
afterward; P, ownership, cache, Duplicate_input policy and parallelism stay
unchanged. Empty/multi-block/signed-zero/domain/ownership/error regressions must
pass before the unchanged eight-cell/control benchmark protocol. The trial is
not implemented in this attribution checkpoint; a remaining GPU miss must be
reported before any broader change.
Restored focused checks and shipping pass (exit 0;
`/tmp/rays-f-image-source-refresh-restored-focused.log`,
`/tmp/rays-f-image-source-refresh-ship.log`). No product behavior changes here;
the direct-input checkpoint's full F5 qualification remains the current evidence.

**Direct XYZ write (2026-10-09; allocation retained, changing GPU gate open).**
Only non-P storage construction changes: three zeroed float arrays and one
ascending direct copy replace the Array.init callbacks. Validation and
installation order, P behavior, ownership and parallelism remain unchanged.
The node-through-Session regression passes before/after: empty and 32,769-point
inputs, distinct XYZ/signed-zero bits, complete domains-1/8 geometry bytes,
input immutability, post-write input mutation and count/nonfinite failure
immutability. Focused checks and benchmark build pass.

The unchanged eight-cell capture matrix and 1024² controls pass all 30 native
pixel comparisons, CPU1/8 hashes and capture/resource assertions. Large static
CPU8/GPU medians are 17.415047/3.555745 ms; large changing medians are
17.284155/6.181384 ms. Changing producer allocation falls from 13,558,975 to
10,413,280 B/frame; static allocation stays exactly 89,161 B/frame. Smaller
changing allocations are pixel-count independent with minor trial variation
(370,181–370,195 B/frame), and control allocations stay unchanged. Raw files
are `f-image-map-captures-xyz-write-after*` and
`f-image-map-uncaptured-recheck-xyz-write-after*`.
Astra: “Retain the XYZ loop for its allocation reduction.” No large-source GPU
timing improvement is established; changing still misses <5 ms. The next
authorized action repeats the same source-refresh attribution on this loop,
comparing all seven phase samples before broadening. No copying, ownership or
cache optimization is approved. Full F5 native/pixel qualification passes (exit 0;
`/tmp/rays-f-image-xyz-write-full.log`), including both complete workspace
sweeps, native owner/image/retained-Canvas tests, oversized capture, runtime
qualification and all pixel aliases. Actual display is 1×; 2× goldens remain
unqualified. No product probes are present.
Shipping passes (exit 0; `/tmp/rays-f-image-xyz-write-ship.log`).

**XYZ-loop source-refresh remeasurement (2026-10-09; diagnostic).**
The approved same-probe comparison confirms XYZ construction falls from
0.940881 to 0.327947 ms/frame and materialization from 2.432431 to 2.047064 ms.
Whole producer time is 6.292236 ms versus 6.248649 ms in the prior diagnostic;
direct reductions, flattening, line/map work and completed dispatch are higher
in this run. Nested timings overlap, and median differences are not a summed
wall-time decomposition. The static diagnostic stays 3.432676 ms. All nine
native pixel comparisons, CPU1/8 hashes and resource/capture assertions pass.
Raw seven-sample rows and the reproducible probe-only patch are
`f-image-map-capture-attribution-xyz-write*`; all nine production files are
restored byte-for-byte and `git apply --check` passes. No production probes
remain. This evidence confirms the measured write benefit without passing
the changing-source GPU gate or approving another optimization by itself.
Astra confirms the seven XYZ ranges do not overlap: 0.817–0.952 ms before,
0.315–0.401 ms after. Its next approved experiment uses local scalar float
references for x/y/z only inside the proved width-3 ordered-add chunk. Preserve
ascending indices and x/y/z finite-check order, write totals back after successful
chunk completion, and keep other widths/predicate/fallback/chunks unchanged.
No reassociation, parallel reduction, vectorization or cache is permitted.
Extend post-chunk overflow independently for x/y/z, preserving reference errors,
caller/input immutability and recovery; repeat the unchanged full eight-cell/
control protocol against XYZ-write results. Retention requires repeatable
measured benefit without regressions. This trial is not implemented here.
Restored focused checks and shipping pass (exit 0;
`/tmp/rays-f-image-xyz-write-attribution-restored.log`,
`/tmp/rays-f-image-xyz-write-attribution-ship.log`). The unchanged production
checkpoint retains its preceding full F5 qualification; actual 1× only.

**Scalar Vec3 ordered-add branch retained (2026-10-09).** Only the recognized
width-3 path uses scalar x/y/z locals and publishes totals after each successful
chunk; all other widths, recognition, traversal and fallback remain unchanged.
The stronger reference/packed preparation tests pin overflow separately in
x/y/z after the chunk boundary, caller-state rollback, unchanged inputs and
recovery at domains1/8. They pass before/after. Assembly retains totals in
floating-point registers with the same ordered additions and finite checks.

The unchanged eight-cell/control matrix retains440 data rows,30 exact native
pixel comparisons and all210 warm resource/capture/counter assertions. Large
static GPU producer median improves3.555745→2.094190 ms; its seven ranges are
3.378–3.679 before versus2.067–2.120 after, with no overlap. Changing-source
median is5.527799 ms versus6.181384 before, but ranges overlap; do not claim a
precisely repeatable0.654 ms saving. Every changing-source sample still exceeds
5 ms. Controls and allocations remain stable. Astra: “Retain the scalar Vec3
branch.” No additional before/after batch is needed for retention.

Raw files are `f-image-map-captures-scalar-vec3-after*` and
`f-image-map-uncaptured-recheck-scalar-vec3-after*`; the production patch and
assembly are preserved separately. Corrected focused checks and full F5 native
qualification pass (exit0; `/tmp/rays-f-image-scalar-vec3-full.log`), including
both complete workspace sweeps, owner/capture/Canvas/oversized-source and runtime
checks and all requested pixel aliases. Actual1× only;2× goldens remain unverified.
Astra approves fresh source-refresh attribution on this
branch with existing three fixtures/probes and seven×200 frames/ten warmups,
including CPU caller/node-own, P/Cd flatten/write/direct reductions, completed
dispatch and conversion. Retain per-trial GC collection-count deltas only from
snapshots outside timing; they cannot measure GC elapsed time. Restore probes;
no further arithmetic/ownership/cache optimization is approved yet. Frozen
images, expanded owner coverage, F3 and the final audit remain open.

**Frozen exact image checkpoint (2026-10-09, `d94b761b`; functional slice complete).** `(exact image)` now creates a
typed deferred image card with an editable input, and Lower routes it through
the existing initial-domain resource owner. The owner first resolves and
validates a successful child display publication, including cache hits, then
keys the snapshot by exact site, plan serial and source identity/generation/size.
Owned RGBA8 CPU bytes and a distinct native image stay immutable across later
publications and replans. The existing 64-entry/native-resource admission pins
versions until close and refuses overflow before snapshot readback/allocation.
Ordinary CPU image requests retain their independent CPU reference; explicit
snapshots intentionally capture the selected display bytes.

Static direct/alias/list/record/called-function/graph-result state refusal and
opaque runtime seed/step refusal pass. Runtime validation recursively resolves
data before exposing a seed or storing next; failed requests preserve caller
state. Numeric and packed-array exact state remains valid. Graph projection,
input gestures and text round-trip pass. Native checks prove CPU blue127 versus
frozen GPU128, one read per version, saved Scene stability through advance,
resize and identical replan, repeated same-generation expired-source refusal,
recovery, legal image graph overrides and retained CPU bytes after clean close.
CPU7×3 and GPU65×17 capacity checks retain63 snapshots plus their source and
refuse the65th resource without another readback. Astra approves the functional
boundary; this checkpoint introduces no performance claim or gate. Full F5
qualification passes (exit0; `/tmp/rays-f-frozen-exact-full.log`), including both
complete workspace sweeps, native owner/capture/Canvas and runtime/pixel checks.
Actual1× only;2× goldens remain unverified. Pre-commit shipping passes (exit0;
`/tmp/rays-f-frozen-exact-ship.log`). Large changing-source
GPU<5 ms, expanded owner coverage, F3 and final audit remain open.

**Expanded owner coverage and graph state correction (2026-10-09, `78a646f6`).** Actual
packed copies retain three prototype points and two instances before capture.
An independent six-point P/Cd oracle checks transformed positions, element order
and attributes under two graph overrides, live time and state. CPU domains1/8
match complete bytes; qualified GPU domains1/8 and composed parent renders
match the oracle (all24 map comparisons have maximum channel error0).
Same-frame fresh state forks and restored caller snapshots refresh captures
without advancing caller state. Warm calls leave source cook/flatten counters,
Host status/readback counters and native child/parent pixel-read counters
unchanged. The resident child has no CPU pixel storage; ordinary CPU requests,
frozen snapshots and unrelated fixed renders retain their separate lifetimes.
All retained CPU bytes survive Image→Canvas→GPU cleanup with handles at baseline.

A valid source changing from three to two points makes index2 fail twice with
`E_ARRAY_RANGE`, invalidates the old parent publication, preserves state/resources
and saved bytes, then recovers under a valid same-frame fork. The actual callback
cycle additionally recovers after a changed-plan rebind at domains1/8. Bypassing
only the packed-instance materializer makes the new fixture fail; the original
owner source is restored byte-for-byte and the checks pass again.

That cardinality fixture exposed inline graph refs using their caller's state
identity. Each private static cell now retains its existing instance ID; live
refs to a known normalized tuple reevaluate under that identity. No live cells
are allocated and plan numbering is unchanged. Pure compiled/reference checks
cover inline/bound refs, independent override tuples, coerced-equivalent sharing,
opposite force orders, repeated calls, caller forks and host-tick/frame clocks.
The pre-fix regression fails; the correction passes. Astra approves this shared
fix and functional coverage. Unknown live override tuples retain the previous
caller-instance fallback; independent state identity for them is not established
by this checkpoint. No performance gate or new performance claim follows from
this correction. Focused checks and full F5 native/pixel qualification pass
(exit0; `/tmp/rays-f-owner-coverage-full.log`), including both complete38+2+13
workspace sweeps, expanded owner/oversized capture, Canvas and runtime checks.
Actual display is1×;2× goldens remain unqualified. Pre-commit shipping passes
(exit0; `/tmp/rays-f-owner-coverage-ship.log`).
The two measured gates and final audit remain open.

**Scalar Vec3 source-refresh attribution and current gate qualification
(2026-10-09, `625b8eaf`).** The approved three-fixture probes retain1050 phase rows,
90 whole rows,71 counter rows and69 per-trial GC snapshot rows. All nine native
pixel comparisons have maximum0; CPU domains1/8 hashes and resource/capture
assertions pass. P/Cd ordered traversals now measure0.121803/0.121765 ms,
versus0.678835/0.677707 in the preceding XYZ-loop diagnostic. Changing-source
materialization takes1.683940 ms and P/Cd flattening0.234637/0.233426 ms inside
packed preparation2.473027 ms. Inclusive/node-own clocks have distinct coverage;
do not add overlapping medians. Trials decline from5.65/5.83 ms toward4.03–4.35 ms
alongside changing allocation-related phases. Sampled GC counts do not establish
the cause or elapsed GC time; CPU worker internals remain unobserved. Astra
accepts attribution and all105 applicable containment checks. All nine temporary
source files are restored byte-for-byte, the saved patch applies cleanly and
restored focused checks pass. Raw evidence is
`f-image-map-capture-attribution-scalar-vec3*`.

Astra then requests the unchanged full uninstrumented capture matrix and controls,
with seven trials,200 completed frames and10 warmups. All440 data rows,
70 CPU domain-hash pairs,30 native snapshots with zero differences,210 warm
resource rows and168 capture rows pass. At1024², CPU8/GPU-producer medians are
16.512156/1.476744 ms (static1024 points),17.276049/1.644295 (changing1024),
18.973112/1.837995 (static65536),19.464016/4.755571 (changing65536).
Gradient/live controls are13.434172/1.408764 and13.276100/1.430500 ms. Fixed-source
producer allocations remain independent of pixel count; static89161 B/frame,
changing1024-point370195 B/frame and changing65536-point10413406 B/frame.

Astra: **“PASS: close the changing-source GPU median gate for this qualified
configuration.”** Every existing1024² CPU<40 ms/GPU<5 ms median gate passes.
Changing-source range4.344505–5.610975 ms includes three of seven trials above5 ms;
this is a median qualification, not a worst-case guarantee. Its separate
end-to-end median is5.575650 ms. This is current measurement evidence, with no
claim of improvement caused by unchanged performance code. No further optimization
or repeat batch is required for this gate. Raw full matrix/control evidence is
`f-image-map-captures-owner-checkpoint-recheck*` and
`f-image-map-uncaptured-owner-checkpoint-recheck*`. Pre-commit shipping passes
(exit0; `/tmp/rays-f-scalar-refresh-gates-ship.log`);
the preceding owner checkpoint's full F5 remains applicable to the identical
production source. F3 and the final audit remain open.

**Astra design and groundwork (2026-10-09).**
Use pixel-center UV coordinates `((x+0.5)/width, (y+0.5)/height)`, top row
first, in immutable packed Vec2 storage; compile the Vec4 body with existing
scalar registers. Packed Vec2/Vec4 storage, maps/loops, fields, uniforms, array
operations and GPU readback reconstruction are implemented;
focused CPU/reference/domain and pure-emitter checks pass. Native width2/width4
and width4-input kernels have zero maximum error at 1,024 and 65,536 elements;
reviewed-code `@check`, focused Flow/IR/GPU/graph/SOP tests, native GPU tests
and `--ship` pass (exit 0), including result-type checks before flattening
native output. Astra accepted the functional
groundwork after restoring the original boolean-accumulator refusal; bool-seed
fold/scan refusal and reference parity are pinned by a regression. No new instruction,
array constructor or catalog port is added. Existing catalog Kernel columns
stay float/vec3; the image bridge belongs in Flow_sop without a Procedural-to-IR
edge. Preserve captures, live uniforms and the 64-image ownership bound.

Astra's conversion design adds owned RGBA8 storage to Procedural.Image,
retaining existing float-backed semantics. Clamp finite channels, multiply by
255, and explicitly round ties to even; reject nonfinite channels. CPU cooks
allocate one final image buffer, not one total allocation. GPU conversion
writes reusable padded rows (`align_up(width*4,256)`), then uses the existing
`Ogpu.Backend.buffer_to_texture`; no new OGPU operation or pipeline family is
needed. Reuse immutable source uploads by array identity/covered length/backing
buffer, with invalidation after replacements. Resident draw/image and texture
consumers reuse existing image/texture plumbing; preserve an explicit deferred
exact-image snapshot so display and frozen consumers cannot alias a mutable
image. Odd-width 65×3 native parity/lifetime tests and an asymmetric >two-grain
CPU rounding/domain fixture are required. Measure 512²/1024²/2048², seven
isolated CPU trials at domains 1/8 and seven 200-frame GPU trials after ten
warm-up frames, completed dispatch/conversion/copy included. Cold preparation,
resize, full display-frame bytes, GPU resource creations and readbacks are
separate rows. No F2.2 gate is established by this design or groundwork.

**Lisp.**

```lisp
(image/map (fn [uv] [uv.x uv.y 0.5 1]) :width 512 :height 512)
```

A `map` over the pixel grid whose body returns a vec4 colour (needs
`Ty.Vec4` from F1.4; until then accept a vec3 and alpha 1). The producer is
an image value like `image/noise`.

**Lowering, CPU.** Same shape as F2.1: the uv grid is a static packed array,
the body is a packed map, the result is a float array converted to RGBA8
once (clamp, multiply by 255, round half to even; write the rounding down in
the spec because exports depend on it). It becomes a cooked `Payload.Image`
(`lib/procedural/session.ml` already carries images; `image/noise` is the
model, `lib/flow/op.ml:269`).

**Lowering, GPU (display only).** When the image feeds only `draw/image` or
a `:texture`, placement may choose `Gpu` by the cost table exactly like
`draw/circles`. The emitter output is the same packed program; the runner
writes a buffer; the sink needs one new piece: a buffer-to-texture copy
(`Texture_copy_dst` usage, `Rgba8_unorm`) producing a resident texture whose
token the sink binds. Add that as an OGPU operation only if it does not exist
(`grep -n "copy" lib/ogpu_core/backend.mli`); if it must be added, use the
`add-ogpu-feature` skill: capability-gated, mock arm returns `Unsupported`,
conformance case on both backends.

**Tests.** Pure: `image/map` of a constant equals `image/noise`-style
expectations pixel for pixel at one and eight domains; the RGBA8 conversion
rounding has a table test. Native (`@runtest-native`): GPU `image/map` vs
CPU `image/map` per-pixel difference recorded, maximum channel difference
and count, in `performance-log.md` under "F2.2 image kernel".

**Gate.** A 1024×1024 `image/map` on the CPU tier under 40 ms at eight
domains (1,048,576 elements at 16.5 ns is 17 ms, plus conversion); on the
GPU under 5 ms including the copy. Allocation per frame on the GPU route
constant in the element count (the Step 4 gate from P5, already true for
circles).

**Astra brief.** "Design the RGBA8 conversion and the buffer-to-texture
sink so that the CPU route allocates one output image per cook and the GPU
route allocates nothing per frame; name the OGPU operation to use and the
exact rounding. One failing check for each."

#### F2.3 Drawing to texture without the readback

**Native camera groundwork (2026-10-09, `3baff757`).** The actual mesh-consumer baseline
exposed missing [-1,1]→[0,1] clip-depth conversion: default orthographic
geometry was clipped before sampling its texture. Native lowering now adapts
ordinary/instance camera matrices, World background inversion and both authored
Shadow3 upload paths once. Fitted sun matrices already use native depth and
remain unchanged. New near/far and visible-pixel regressions fail before the
correction and pass afterward, including close perspective geometry, depth
order, instances, repeated Scene replay and resource cleanup. The float32
recolor oracle now uses the corresponding source colors and a complete legacy
payload key, with its original one-channel tolerance and 36-byte upload check.
Astra approves the correction; focused checks, full F5 native qualification
and shipping pass (exit 0). The 2× PXUI goldens skip at the actual 1× density.
This is correctness groundwork; the resident image/render route is still pending.

**Round-trip baseline (2026-10-09, `10038226`).** The actual workspace texture callback,
live drawing and completed mesh consumer are measured at 512²/1024²/2048²,
seven trials of twenty frames after ten warmups, on the M1/dev/OCaml 5.3 at
one domain. Median times are 43.399990/139.405048/514.362109 ms/frame;
allocation is 67,918,306/250,370,554/980,179,450 bytes/frame. Destination uploads
are exactly one RGBA8 image per frame at every size. Full final source and
destination bytes are equal; every warm hash is stable and differs from the
cold hash. Cold preparation and teardown are separate rows. Astra says
“Accepted as the F2.3 roundtrip baseline.” Raw CSV:
`specification/performance/f-image-render-roundtrip-before.csv`; commands and
limits are recorded in the performance log. The resident allocation gate
remains open.

**Astra retained-Canvas design (2026-10-09; implemented by the checkpoint below).** The
offscreen target already has Texture_binding, Render_attachment and
Texture_copy_src; no OGPU feature is needed. A private completed-frame source
must expire before render attempts, resize, CPU mutation or destruction and
become valid only after successful publication. Display image/render retains
one Canvas per entry and publishes its texture through the existing borrowed
Image/Texture route. Resize retains the old allocation until replacement
rendering and publication succeed, while old callbacks are already invalid.
Exact CPU render cooks CPU children into a separate temporary Canvas, captures
the completed pixels and updates only entry.cpu. It must not overwrite the
resident display Image. Destruction detaches the runtime resource before GPU
execution teardown and does not synchronize discarded CPU pixels. Close destroys
published Images before retained Canvases, then sinks/Host/leases. Native checks
must count actual source captures/readbacks, cover failure/recovery/resize and
retained Scene expiry, and preserve old CPU payloads. Repeat the accepted
seven-by-twenty-frame baseline protocol unchanged, with its upload assertion
disabled; compare full bytes/hashes outside timing and require warm allocation
to stop growing with pixel count. Resident Canvas lands before the separate
deferred Lisp exact-image surface; both remain required.

**Completed-Canvas source groundwork (2026-10-09, `5f0e50b2`).** The private Canvas source
now borrows only a completed GPU frame and expires before later render attempts,
explicit invalidation, CPU mutation or destruction. Runtime context checks
cover both the initial domain and platform main thread, including headless
resources before SDL initialization. Native 65×3 checks cover direct sampling,
retained Scene expiry with unchanged published Image generation, invalid
density and late-Clear failures, recovery, old CPU snapshot leases and zero
native handle delta. Actual source captures/readbacks remain zero during
borrowing; explicit CPU mutation and capture produce the expected (1,2) counters,
unchanged by destruction. Astra approves the Canvas boundary and shared Apple
thread-guard correction. Only the pre-initialization worker-thread assertion is
Apple-specific; post-video rejection retains the platform-neutral SDL contract.
Focused/API, full F5 native qualification and pre-commit shipping pass (exit 0), including both
complete workspace sweeps at four times/domains 1/8. The 2× PXUI goldens remain
unqualified at the actual 1× density. This is borrowing/lifetime groundwork;
workspace retained-Canvas wiring,
size-dependent cache checks and the F2.3 allocation gate remain open.

**Retained workspace Canvas functional checkpoint (2026-10-09).** Display
image/render now reuses a same-size Canvas and publishes its completed texture
through the stable borrowed Image/Texture. Resize publishes the replacement
before destroying the old allocation. Stale requests expire old sources before
argument forcing, including failures before drawing preparation. Exact CPU cooks
use separate temporary targets and leave resident display generations untouched.
Reachable omitted dimensions invalidate explicit-size parents while unrelated
fixed-size images remain cached. Actual target/capture/readback counters survive
close. Native fixtures cover resize, repeated drawing and argument failures,
recovery, failed resized publication cleanup, stable identities, independent old
CPU bytes and zero native live-handle delta. Five actual mixed 2D/mesh comparisons
against the CPU round-trip oracle have zero differing channels/pixels, including
65×17 and 35×33 sources. Astra approves this functional checkpoint. Raw parity:
`specification/performance/f-workspace-retained-canvas-parity.csv`.
Broad qualification passes (exit 0), including both complete workspace sweeps at
four times/domains 1/8. The matched allocation gate passes below; the deferred
Lisp exact-image surface remains required.

**Measured allocation gate PASS (2026-10-09).** The accepted seven-by-twenty-frame
protocol, ten warmups and all three sizes are repeated at one domain. Before →
after median ms/frame: 512² 43.399990 → 0.692904; 1024² 139.405048 → 1.004601;
2048² 514.362109 → 2.203953. Median allocation falls from
67,918,306/250,370,554/980,179,450 to 85,450 bytes/frame at every size. Individual
trials range from 84,021 to 85,450 bytes/frame; this is constant in pixel count
across the tested range, not zero allocation. All 21 warm trials have zero
source target creation/destruction, captures, Canvas/Image readbacks and
destination uploads. Full-byte hashes match the before baseline; explicit
verification readbacks are recorded outside measurement. Cold and teardown
remain separate rows. Astra's verdict: “F2.3 allocation gate: PASS” for the
measured workload. Raw CSVs are `specification/performance/f-image-render-resident-after.csv`
and `specification/performance/f-image-render-resident-counters.csv`; the performance
log records commands, machine, repetitions and limits. Pre-commit shipping
passes (exit 0). Deferred Lisp `(exact image)` and outstanding F2.2 requirements
are not completed by this verdict.

**Today.** Display `image/render drawing :width :height` retains an offscreen
`Rays.Canvas` and binds its completed texture directly. Exact CPU image requests
render separately and capture their own pixels. The original round trip below
is preserved as the measured before baseline.

**Goal.** When the rendered image feeds only a `:texture` or `draw/image`
sink, keep the canvas's texture resident and bind it directly. The CPU
image is produced only when something exact asks for it (`sop/attr_from_image`
or an export), through the same `(exact x)` discipline.

**Steps.** Measure first: `tools/bench_workspace_lower.exe --images` gives
the cooked-image producer rows; add a row for `image/render` at 512², 1024²
and 2048² with the current round trip (time and bytes per frame). Then give
`Workspace_images.texture` a path that returns the canvas's own texture
token when the image is a live `image/render`, and only falls back to upload
for loaded and cooked images. The canvas is owned by `Workspace_images`
already (64-pin rule); the token must be invalidated on resize.

**Tests.** `test/test_workspace_images.ml`: a live `image/render` consumed
by `:texture` does not call `Canvas.to_image` (count it); one consumed by
`sop/attr_from_image` does. Native: the rendered texture on a mesh is pixel
identical to the round-trip version.

**Gate.** Per-frame bytes for a live 1024² `image/render` feeding a texture
drop from the measured round trip to a constant; record both.

**Astra brief.** Only if the resident path needs a new OGPU usage
combination; otherwise not needed.

#### F2.4 Fragment kernels (last, and only if measured need)

A fragment kernel is a per-pixel effect applied where the canvas is drawn,
not into an image. It needs a new `pipeline_family` (closed variant, see
above) and a fragment entry point generated by the emitter. Everything a
fragment kernel can do for a static picture, F2.2 does with an `image/map`
drawn through `draw/image`. The only thing it adds is a per-pixel effect on
a live, moving drawing without an intermediate texture.

Do not build this until F2.2 is in and someone has a workspace where the
`image/map` + `draw/image` route is measured too slow. If that day comes:
one new family `Scene2_shaded`, `pipeline_variants_per_sample` updated, cache
capacity updated, `Emit.fragment : Packed.t -> msl` beside `Emit.kernel`,
conformance on mock (Unsupported) and Metal, and the `Ui` family untouched.
Astra designs the family and the uniform layout; you do the rest.

### F3. The two-chain fan-out gate (Astra only)

**Today.** The fixture is `bench_workspace_lower --branches` (its workspace
text is at `tools/bench_workspace_lower.ml:130-138`: two separately authored
1M-point grids, two `noise_displace` each, merged at the root). P4 Step 3's
gate was 1.5× against Step 0's 75.943 ms at eight domains, i.e. 50.6 ms.
Measured: 57.9 ms (learned), with the per-node table in `performance-log.md`
"P4 two-chain fan-out: per-node evidence": grids 7.8/9.0 ms, noise 4 × about
4 ms, **`merge` 40.0 ms serial** at eight domains, 58.8 ms at one. Fanning
the two chains out hides at best one chain (16-17 ms), which is what
happened. The gate cannot be reached without a faster merge.

`Rdk.Mesh_merge.merge_plain` (`lib/rdk/mesh/mesh_merge.ml:79-199`): three
`Array.blit`s of the position planes into fresh arrays, a `Parallel.for_`
over vertices rewriting `vertex_points` with the point offset, a
`Parallel.for_` over primitives rewriting `primitive_offsets` with the vertex
offset, `Bytes.blit` of primitive kinds, then attribute concatenation
(`concatenate_attribute`), group rebuilding and edge groups. Temporary
timers (section "Merge phases and runtime qualification at 2x") say:
topology and position copy 55.6 ms at one domain, attribute concatenation
7.2 ms, the rest under 0.1 ms.

Two trials are recorded and reverted, do not repeat them:

- 0d16f178: one allocation plus chunked parallel blits of the planes; the
  eight-domain merge stayed 45 ms vs 40 (within noise).
- ce133675: the index-rewrite loops as one closure per chunk with a tight
  inner loop; slower at both domain counts (one-domain 570 ms, eight-domain
  51 ms against 59 and 40).

The second number is suspicious (a tight loop should not be ten times
slower); it probably measured something else (a boxed float, an allocation
in the closure, a cold cache). Astra must look at the diff before deciding.

**What a third attempt has to be.** The merge copies about 72 MB (48 MB of
positions, 16 MB of vertex indices, 8 MB of offsets) for 2M points; memcpy
at memory bandwidth is under 10 ms. 55 ms means the loops are not memcpy.
The candidates, for Astra to rank:

1. The per-element `index land 16383 = 0` cancel check and the closure call
   per element in `Parallel.for_` (look at `lib/rays_math/parallel.ml` (the `Parallel` module `rdk` uses) and
   what `for_` does per element); a chunk-level cancel check with a plain
   `for` loop inside, written so the OCaml compiler keeps the ints unboxed.
2. `Packed.Float3.Private.of_owned_exn` and
   `Topology.Private.create_validated_owned`: "validated" may re-walk the
   topology (grep what it validates); for a merge of validated inputs the
   validation is redundant and could be skipped under a proof.
3. A merge that does not copy: `Sketch_support.Packed_pieces`
   (`lib/sketch_support/packed_pieces.mli`) already exists for display; if
   the root of a workspace is only displayed, `sop/merge` could lower to a
   list of pieces and never materialize. This changes semantics for
   downstream catalog nodes, so it is only legal when the merge feeds a
   display sink; the IR knows that (`Sink (Display _)`).
4. Plane sharing in `Rdk.Geometry` (a rope of planes): the largest change,
   touching 111 files; only if 1-3 fail.

**Protocol.** `RAYS_BRANCH_NODE_TIMES=1 _build/default/tools/bench_workspace_lower.exe --branches 3 off`
prints per-node durations; the `merge` row is the number. Seven cold runs,
one and eight domains, hashes must stay `67c129ecc130f8881a2eaf92c053b64c`
(chains) and `8ef295fbdea12b586200fd1ffcdcb58f` (pieces). Raw CSVs in
`specification/performance/f-merge-*.csv`.

**Gate.** Either the two-chain fixture at eight domains is at or under
50.6 ms with unchanged hashes, or Astra writes the sentence that closes the
gate as unreachable with the reason, and you put that sentence in
`performance-log.md`. Both are acceptable outcomes. "Almost" is not.

**Astra brief.** "Read `lib/rdk/mesh/mesh_merge.ml:79-199`,
`lib/rays_math/parallel.ml`, `lib/rdk/core/packed.ml` and
`lib/rdk/core/topology.ml`; read the two reverted trials (`git show
0d16f178`, `git show ce133675`) and the measurements in
`specification/performance-log.md` sections 'P4 two-chain fan-out: per-node
evidence' and 'Merge phases and runtime qualification at 2x'. Explain why
copying 72 MB takes 55 ms at one domain. Rank the four candidates above (or
a fifth), give me the first one to implement with its one failing check, the
exact measurement protocol, and the number that would make you say the gate
is met."

**Current Astra review (2026-10-09; prefill rejected, phase attribution complete).** The default
triangulated grids invalidate the earlier 72 MB estimate: the merged positions,
vertex indices, primitive offsets and kinds occupy 179,736,140 bytes, plus
48 MB of normals. Their native integer callbacks perform about 15.97 million
rewrites, with checked accesses, an indirect callback and an ARM64 assignment
barrier per store. The private validated constructors do not rewalk topology.
The two cited reverted commits retain log changes, not the implementation
patches, so the 570 ms trial cannot be diagnosed from those diffs.

Astra approves measuring the unchanged tool first. If the learned eight-domain
whole-cook median already meets 50.600 ms, return the evidence before optimizing.
Otherwise its first distinct trial uses Array.concat to initialize vertex indices
only for exactly two inputs, skipping the existing rewrite only for a prefilled
segment whose point offset is zero. Other arities and all nonzero rebasing,
primitive offsets, position/attribute/group work and cancellation stay as before.
Fresh stdlib initialization avoids assignment barriers for the unchanged first
segment; the second segment gains a copy, so improvement is only a hypothesis.

The failing semantic fixture independently pins empty/triangle/free-point/open-
polyline indices, compares complete bytes at domains 1/8 and catches the case
where vertex offset is zero but point offset is nonzero. Seven separate processes
per before/after mode (`--branches 1 learned`, `--branches 1 off`, `--loops 1 learned`)
retain exact hashes and all rows, followed by reverse-order learned comparison.
Learned runs perform untimed training and clear output caches while retaining
timing knowledge; they are not untrained cold runs. The uninstrumented whole
learned-chain median decides the unchanged 50.600 ms gate. There is no current
evidence supporting an unreachable closure, and no new measured verdict yet.
Astra's protocol clarification: `RAYS_BRANCH_NODE_TIMES=1` only reports existing
Session samples after the cook timer stops. Its seven-process learned runs are
valid for the whole-cook gate; no additional env-unset batch is needed. Here
“uninstrumented” means production execution without temporary profiling changes;
the existing Session timing work stays in the measured cook. Keep the variable
identical before/after and in reverse-order comparisons.

The fresh unchanged baseline on the M1 retains all 42 whole-cook rows and
fixed hashes across seven separate processes per mode at domains 1/8. Learned
chains take 148.324013/51.798820 ms; placement-off chains 199.245930/55.030107 ms;
learned pieces 1984.183073/267.518997 ms. Learned merge-own medians are
58.411121/26.059866 ms. The preserved executable is `/private/tmp/f-merge-before.exe`
(SHA256 `198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4`).
Raw stdout/node reports are `f-merge-before-{chains-learned,chains-off,pieces-learned}-{0..6}*`.
Astra: “not met, try two-input vertex-index prefilling with Array.concat,
skipping only zero-point-offset rebasing.” The unchanged learned-eight median
misses by 1.198820 ms; keep all seven samples, including the 65.128803 ms first
run. Implement only the approved trial after the independent fixed regression
passes unchanged code; require the full after/control and reverse-order matrix
before a gate verdict. No unreachable closure is supported.

The independent regression passes before/after: a seven-point triangle/free-
point/open-polyline result with explicit topology, five-input empties, the same
two-input result, free-points followed by triangle (zero vertex offset with
nonzero point offset), and both leading/trailing empty two-input cases. Complete
geometry/input bytes match at domains 1/8; precancellation leaves inputs unchanged.
Whole RDK/procedural focused checks and benchmark build pass.

The approved prefill trial regresses learned-eight whole cook from
51.798820 to 65.582991 ms; the reverse-order run confirms
51.988840 before versus 71.448088 after. Learned merge-own eight-domain medians
are 26.059866 before/39.048910 after in the first matrix and
27.842045 before/45.994043 after in reverse order. Every fixed hash and fanout
count remains correct. Astra: “not met, revert.” The production change is
reverted byte-for-byte; the regression, 112 raw stdout/node CSVs, both preserved
executables and `f-merge-vertex-prefill-trial.patch` remain. The rejected patch
passes `git apply --check` on the restored tree. No unreachable closure is
supported; F3 remains open.

Astra's next approved action is time-only attribution of restored merge:
allocation, position blits, joined vertex rewrites, joined primitive-offset
rewrites, kind blits, attributes and remaining wrapping/groups/construction,
plus the complete interval. Aggregate repeated caller intervals in order,
buffer reports outside measurement, distinguish training/measured cooks,
preserve round-trip time precision and avoid GC samples or callbacks inside
element loops. Seven isolated learned-chain processes and the saved production
baseline retain hashes/cardinalities/fanouts and phase sums contained within
merge time; report instrumentation overhead. Temporary Unix linkage/source
must be restored byte-for-byte. That diagnostic is now complete; see below.
Restored `@check`, complete RDK/procedural focused checks and benchmark build
pass (exit 0; `/tmp/rays-f-merge-restored-focused.log`), as does shipping (exit 0;
`/tmp/rays-f-merge-restored-ship.log`). Production merge is the unchanged
implementation from the preceding full F5 native checkpoint; only its new
regression and evidence are retained here.

Seven diagnostic/baseline pairs retain 28 whole rows and 196 phase rows under
`specification/performance/f-merge-phases-*`. Every hash, cardinality, fanout,
phase count and per-sample containment check passes. The uninstrumented whole
medians are 149.086952/62.613010 ms at domains 1/8; diagnostic medians are
151.123047/63.819885 ms. Median paired overhead is 2.187967/1.014232 ms.
Measured merge intervals are 57.885885/34.251928 ms, with vertex rewrites
29.390097/7.174969 ms, primitive rewrites 9.824038/2.469301 ms, allocation
7.495880/6.633043 ms, attributes 9.441137/6.445885 ms and position blits
1.575232/1.592875 ms. Separate phase medians must not be summed. Training
samples remain separately labeled. All four temporary files are restored
byte-for-byte; the probe patch remains reproducible and focused checks pass.

Astra: “not met, try chunked vertex-index rewrites with a plain inner loop,
leaving primitive-offset rewrites unchanged.” Replace only the per-element
vertex callback with stable grain-sized ranges dispatched through the shared
pool at chunk size 1, with a sequential cutoff `vertices_here / grain < 2`.
Each range uses plain integer load/add/store loops; split large custom grains
into at most 16,384-element subranges with cancellation checked before each.
Use overflow-safe range ends. No other merge phase changes. The independent
regression adds 32,769/16,385-reference open polylines at domains 1/8 and grains
257/16,384/65,536/max_int, comparing full bytes and unchanged inputs. Inspect
generated assembly, repeat the seven-process learned/off/pieces and reverse
matrix, then repeat temporary before/after phase attribution. Keep only for
repeatable whole-cook improvement without material control regression. The
unchanged gate is an uninstrumented learned-eight median ≤50.600 ms; no
unreachable closure is supported.

**Chunked vertex trial rejected (2026-10-09).** The new full-byte boundary,
ownership and precancellation regression passes before/after and on restored
production at all eight domain/grain combinations. Astra approves the diff
and the preserved ARM64 inner loop: direct integer load/add/store, register-held
index/end, no per-element callback/allocation/loop-state store; checked accesses,
runtime polls, closure reloads and the assignment barrier remain. Preserve
`f-merge-vertex-trial.patch` and `f-merge-vertex-inner-loop-arm64.txt`.

All 56 production processes/112 whole rows retain hashes and fanouts. Learned
whole medians at domains 1/8 regress from 152.101994/63.404799 to
817.284822/59.296131 ms; reverse order gives 148.737907/63.197136 before
versus 899.132013/69.355011 after. Placement-off and packed-piece controls
regress too. The one-domain caller/program allocation increase is only 80 B.
Astra: “not met, revert.” Production source/Dune are restored byte-for-byte;
retain the independent regression and all failed evidence. No eight-domain-only
variant is retained.

Seven isolated before→after diagnostic pairs retain 28 whole and 392 phase
rows, with every per-sample count/sum/containment check passing. At one domain,
measured vertex rewriting grows from 29.999256 to 707.682371 ms (training
31.332970 to 707.224846); allocation is 7.629871/7.917881 ms and attributes
9.644032/9.572983 ms. Complete measured merge grows 59.088945 to737.746000 ms.
At eight domains vertex rewriting grows7.277250 to14.573812 ms; complete merge
31.002045 to38.609028 ms. This locates the slowdown inside vertex rewriting
but does not establish its machine-level cause. Raw production/diagnostic CSVs,
the candidate probe patch and executable hashes are recorded in the performance
log. Restored @check/full RDK/procedural checks and shipping pass. Astra's final
phase audit confirms “not met, revert.” Its next approved diagnostic is native
stack sampling of preserved baseline/rejected candidate in seven alternating-
order pairs. Retain initial-thread/worker counts, coverage and exit statuses;
sampling aggregates training/measured and both domains and cannot decide the
gate. F3 remains open above50.600 ms; this rejected design supplies no
unreachable proof.

**Native sampling complete (2026-10-09).** All 14 cook/sampler exits are zero;
13 profiles contain stacks and baseline0 is retained as an empty capture.
Candidate initial-thread rewrite self counts are1008/1063/1016/1053/1148/
1103/1081 out of1698–1875 thread samples, subtracting immediate children to
avoid double-counting duplicated frames. Seven domain workers and eight backup
threads are reported separately. Samples aggregate hashing, training, measured
cooks and both domain counts. They support time in the native loop rather than
a dominant runtime callee, without proving a machine-level cause or absence of
GC. Astra confirms “not met, revert.” All raw profiles/statuses/counts remain.

Astra now approves a controlled trial of a private noncapturing, explicitly
typed integer range helper receiving source/target arrays and offsets directly.
Call it once per cancellation subrange in the rejected chunked design, retaining
boundaries, cancellation, checked accesses and the integer-store barrier.
Before timing, require arrays/offsets/loop state held in registers with no
per-element closure reload/call. Existing boundary/ownership/cancellation
regression must pass unchanged. First run seven alternating-order diagnostic
phase pairs against production; stop if the catastrophe persists. Only if it
disappears run the full production learned/off/pieces/reverse matrix. Retention
compares with production, never the rejected trial; ≤50.600 ms remains the
unchanged whole learned-eight gate.

**Explicit range-helper trial stopped (2026-10-09).** The approved typed helper
passes full focused checks and Astra's assembly review: arrays/offsets/index/end
stay in registers; checked accesses, store barrier and polls remain; the normal
inner path has no captured-value loads/calls/allocations/spills. Nevertheless,
seven alternating-order phase pairs retain the catastrophe: measured vertex
time at one domain grows29.943943→777.833700 ms, training30.824184→736.407042;
at eight domains measured vertex7.259846→10.388851 ms. All hashes, fanouts,
phase counts and containment checks pass; one-domain allocation grows only80 B.
The protocol stops before the full production matrix. Captured-value reloads
are not established as the cause. Production/probe files are restored byte-for-
byte; retain42 raw diagnostic CSVs, both patches and assembly. Restored full
@check/RDK/procedural checks pass. Astra audits all392 rows: “not met, revert.”
Its next approved F3 diagnostic attributes existing attribute concatenation by
storage kind and coordinate plane, with bounded buffers, nested containment
checks and seven alternating diagnostic/baseline pairs; no optimization is
approved. F3 remains open; no unreachable proof exists.

### F4. Full static editor allocation (information, optional, Astra only)

**Today.** `tools/bench_drawing.exe 100000 --static` measures one full
`Editor.update` of a static 100,000-circle canvas: 155,620 bytes per frame
after five P3 follow-ups (camera decode reuse −27,752; linked-child
arrangement loops −4,768; navigation short-circuit −9,224; intrinsic-size
loop −1,136; clipped-rectangle reuse −432; per-run font id −5,688). The
retained Drawing lowering alone is 1,393 bytes per frame and that is the
gate `P3.md` actually stated (the delta bound in `test/test_drawing.ml`,
which passes). The 32 KiB figure for the *whole* editor update is not a
gate; it is recorded as information in "P3 allocation gate reading".

`--static --profile` runs `Gc.Memprof` at sampling rate 0.001 with 20-frame
stacks (`tools/bench_drawing.ml:41`). The last profile (section "P3 full
static editor allocation investigation") grouped 5,142 sampled words as: UI
building and other UI work 1,573; other editor work 1,316; camera decoding
1,169 (now reused); UI painting 853; immutable batch snapshots 104; editor
reduction 75; key routing 48; UI arrangement 4. Concrete sites named:
`lib/pxui/ui.ml:1497` and `:1515` (arrangement closures, since replaced by
the linked-child loops), `:1817-1848` (paint rectangle and clip tuples),
`lib/rays_editor/core_actions.ml:123-151` (`layout_labels` and `routed`
rebuild the command list with `List.filter`/`List.filter_map` every frame).

**If the owner asks for this number to move.** Astra reads the profile,
picks one site, you implement, you measure three alternating before/after
trials with the same protocol (ten warm-up, 200 timed, one domain, all other
work held), Astra judges. The obvious first site is `core_actions.ml:123-151`:
the keymap filter runs per frame and allocates a new list; it only changes
when the panel tree, the level or the text mode changes, so it can be
rebuilt on those transitions and kept in the model. Do not add a cache
without a capacity and an invalidation test.

**Gate.** None. Record each step as the P3 follow-ups did. Stop when Astra
says the remaining bytes are the UI batch snapshot copy that
`Ui_batch.Builder.publish` must make (that copy is required behaviour).

### F5. Native gates are part of shipping (a habit, not a task)

The four branches were qualified in sandboxes with no Metal device. At
consolidation every native alias had to be rerun on the M1, and two
pre-existing failures surfaced that no sandbox could have seen: parity
goldens captured at 1x on a 2x display (fixed in 870210be and b6bdd8c2,
captures keyed by drawable extent) and SDL3's own per-window footprint
growth counted as a Rays leak (fixed in 3ab96c82, the check now subtracts
SDL's baseline measured in the same process).

Rules:

1. Before you write "passes" for anything under `@runtest-native` or
   `@smoke`, you ran it on a machine where
   `Ogpu_metal.Device.system_default` succeeds. The sandbox answer is
   `No_adapter: Ogpu_metal.Device.system_default: Metal has no system
   default device`; when you see it, write "not verified natively" and
   stop claiming.
2. The native aliases that matter for this file: `@lib/flow_gpu/runtest-native`
   (`test_run.exe`: emitted-kernel numerics, 1,024 and 65,536 elements),
   `@lib/rays/test_shape_batch_native`, `@lib/rays/test_scene3_float32_native`,
   `@lib/rays/test_canvas_native`, `@test/runtest-native` (includes
   `test_workspace_images_native`),
   the three `test_workspace_pixels` aliases, `@examples/sop_gallery/test_scene3_float32_gallery`,
   `@lib/runtime/native_qualification/qualification`, `@lib/pxui/test_ui_parity`
   (2x goldens; check display density first, refresh only with
   `RAYS_UPDATE_FIXTURES=<dir>` and only for a design change).
3. `tools/bench_kernel.exe --gpu-check` is the pure half of the GPU check
   and runs anywhere; `--gpu` needs the device.
4. The mock backend (`lib/ogpu_mock/backend_mock.ml:113, 131-133, 245-246`)
   owns pipelines and buffers but does not execute compute or render. A
   test that needs shader numerics is native by construction; do not try to
   make the mock compute.

### F6. Small, known, bounded

**Canvas image input done (2026-10-08, `e36a0ac4`).**
`Workspace.apply_op` wraps an image passed to `ui/canvas` in the existing
`draw/image` operation. The focused regression checks the typed argument,
the evaluated drawing plan and scalar refusal. `@check` and
`@lib/flow/runtest` passed. The complete workspace IR sweep passed 35 standard
files, two custom-catalog executables and 13 fixtures, at four times and one/
eight domains. `--ship` returned exit 1. An isolated `@check @smoke` run
confirmed the native smoke startup failure: `SDL3.Init.init: The video driver
did not add any displays` (`/tmp/rays-f-check.log`). This is not a native pass.
That managed run did not qualify the change; the later native-host shipping
run passed before `e36a0ac4`.

**Managed native environment evidence (2026-10-08).** After the environment changed
to managed execution, `_build/default/tools/check.exe
@lib/flow_gpu/runtest-native` failed with
`Ogpu_metal.Device.system_default: Metal has no system default device`.
Native gates were not verified in that environment. The earlier native-host
F0 validation does not qualify later changes.

**Commit restriction (2026-10-08).** The managed filesystem policy makes
`.git` read-only: staging these changes failed with
`Unable to create '.git/index.lock': Operation not permitted`.
At that point the F1.1 groundwork and F6 changes remained uncommitted.
Filesystem access was subsequently restored and `e36a0ac4` committed them
after native shipping passed.

**Access restored (2026-10-08).** The environment now permits filesystem and
native access. `sysctl` identifies `Macmini9,1`, Apple M1, eight logical CPUs.
The earlier restrictions above describe the managed runs, not current access.
Current `@all @runtest`, unrestricted `--ship` and the F5 native gates have
passed (exit 0); see the current checkpoint above. The historical managed
failures do not qualify or invalidate this later native-host run.

- **`ui/viewport` takes the 3D scene only** (`lib/flow/op.ml:442`,
  `lib/editor_document/contexts.ml:660`). A drawing goes in `ui/canvas`
  (`op.ml:443`), an image in a canvas through `draw/image`, a table in
  `ui/spreadsheet` (`op.ml:448`). This is by decision, not omission. The
  one thing worth adding is `ui/canvas` accepting an image value directly
  (`(ui/canvas (ref my_image))`), which is a checker coercion from
  `Ty.image` to `Ty.drawing` by wrapping in `draw/image` at the origin;
  projection unchanged. Test in `lib/flow/test_workspace.ml`. No Astra.
- **Grain.** 16,384 everywhere (`lib/procedural/context.ml:45`), by
  measurement ("Measured CPU placement and grain decision"). Do not change
  it without the same five-grain, three-size, five-family sweep
  (`bench_rdk_ops --grain`).
- **`Iso_surface`, `Voronoi2`, `Kernel.map_points` reachable only from
  OCaml.** F2.1 covers the first. `Voronoi2` becomes a SOP through the
  `add-sop` skill when someone needs it; no Lisp-first reason to do it now.
- **No 2D polygon offset or 2D Boolean in rdk.** Out of scope; note it when
  a 2D port needs it.
- **`examples/pathtracer`, `procedural_modeling`, `sop_gallery` and the
  sketches `code_quadtree`, `chromatic_drift`, `pastel_flow` stay OCaml.**
  The path tracer is the continuation's Phase 10; `sop_gallery` and
  `voxel_wall` are the custom-catalog oracles and must keep running with
  their own factories (`test_workspace_ir` runs them inside their own
  executables).

### F7. Checks that are red for a known reason

None on `dev` at ce133675 on the M1. `dune build @runtest` is green on a
clean checkout; `@runtest-native` and `@smoke` are green on the M1. If you
find a red check, it is new: bisect it between ce133675 and your tree
before touching anything.

### F8. Hand-off into the continuation

When F0 to F2 are in, the continuation doc's phases start. Their status
against this tree, so you do not redo what exists:

| Continuation phase | Already in the tree | Still to build |
|---|---|---|
| 5 Modules | `(import ...)` of a shared file (`sketches/ws_shared`), library editing (`Workspace.check ~library:true`) | `module`, `use`, a prelude, `defnode` with declared facts resolved through the manifest, signature cards |
| 6 Collapse | fact-guided `with_attr` fusion, component cache keys, learned parallel branches | `with_attr` as a kernel kind (no materialization between kernels), attribute forwarding, the path-based fusion barrier, rate frontiers as the general `hoist` |
| 7 Kernel forms | nothing (F1.4 readies the types) | 32-bit integers, `:until`, `get`/`set`, several outputs, adjacency, the spatial intrinsic |
| 8 GPU tier | all of P5; asynchronous compile and zero-copy measured and declined (8.2 ms compile, write 5 percent of a frame) | the per-pixel difference record for the million-circle sketch (F2.2 gives the tool), a viewport-only `with_attr` placed on the GPU without annotation (today a SOP attribute from the GPU goes through `(exact x)` readback; the display route serves drawing sinks) |
| 9 Precompiled modules | `rays-lisp ml` generates the sketch executable (`tools/lisp`, `sketches/dune`) | Lisp-to-OCaml for modules, native cooks as catalog entries, error positions mapped back |
| 10 Path tracer | the image domain (F2 extends it) | materials as Lisp functions, the ray intrinsic, the image sink, the integrator |
| 11 Panels | `ui/spreadsheet` in OCaml | the kit as ops, a panel as a function from model and input to a drawing and intents |

Do Phase 5 (Modules) first; 6 and 7 both want the setters as Lisp modules.
Phase 8 is paid. The GPU-tier gate items in the row above are the only Phase
8 leftovers and they are small once F2.2 exists.

---

## 3. Astra brief template

Copy this, fill the brackets, send it to the sub-agent, and wait for all
three answers before writing code.

```
You are GPT 6 Astra, reviewing an optimization for the Rays repository
(OCaml, Dune, Apple Silicon Metal through OGPU). The implementing agent is
GPT 6.1 Sol; give it a design it can implement without inventing anything.

Item: F[n] [title] from F.md.
Files: [paths and line ranges from the item].
Current numbers: [the table rows from the item], measured with [commands].
Constraints (non-negotiable): byte-identical results at one and eight
domains on every CPU path; shared Parallel pool with grain 16,384 and a
sequential cutoff; no new dependency; no Metal access above the backend;
approximate values never reach exports, catalog inputs, state seeds or
cache keys; every cache has a capacity; no fallbacks.

Answer with exactly:
1. The design: what changes, in which function, and why it is faster or
   smaller. Name the one thing most likely to make it not work.
2. The one check that fails if the design is wrong (a test or an assert in
   an existing test file; say which file).
3. The measurement protocol: command, repetitions, domain counts, what to
   hold still, and the single number that decides. Say what number means
   "gate met" and what number means "revert".
```

When Sol sends the numbers back, Astra answers with one of: "met", "not
met, revert", or "not met, try [one specific change]". Sol records the
verdict verbatim in `performance-log.md`.

---

## 4. Checklist before you say an item is done

- [ ] `dune build @check` clean, warnings are errors.
- [ ] Focused alias for every file touched is green (`_build/default/tools/check.exe @lib/<name>/runtest`).
- [ ] `test/test_workspace_ir` green (every `.rays` file, four times, one and eight domains).
- [ ] `test/dependency_gate` green; a new edge is in the gate, in `specification/backend.md`, and has a test at the boundary.
- [ ] A new Lisp form has its projection, gestures and test; `specification/flow.md` updated.
- [ ] A new SOP has one declaration, `flow_manifest.sexp` promoted, `Node.facts` set.
- [ ] Public `.mli` change: `api_stable.json` promoted on purpose.
- [ ] Numbers: before and after, same protocol, raw CSV under `specification/performance/f-*.csv`, a `performance-log.md` section with the commands, the machine and what it does not establish.
- [ ] Native: run on a machine with a device, or written down as not verified.
- [ ] Astra's verdict quoted for every non-trivial optimization.
- [ ] `_build/default/tools/check.exe --ship` exit 0.
- [ ] This file updated: the item marked done with the commit hash, or its remaining part rewritten.
