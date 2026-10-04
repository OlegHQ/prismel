# Editor state consistency audit and remediation plan

Audit date: 2 October 2026. Scope: workspace Lisp, graph/list/text projections, inspectors,
settings, history, source reload/save, scene composition, viewport previews and the common
3D renderer. The starting point includes the existing uncommitted editor work; those changes
were preserved.

The editor already has the right central boundary: one immutable document and one checked
workspace. Its failures came from bypassing that boundary, treating navigation as ownership,
and incomplete cache identities. Repair those boundaries before adding another state manager,
event bus or rendering layer.

This audit fixes the reproduced consistency bugs listed below. It does not certify that every
editor interaction is bug-free. The remaining items are explicitly identified as design limits,
confirmed behavior gaps or risks requiring a separate reproduction.

## State ownership and data flow

| State | Authority | Changed through | Saved and undone |
|---|---|---|---|
| Graph structure, literals, expressions, scene objects, World layers, authored panels | `Workspace_doc.source`, checked by Flow | `Flow_edit`; derived object edits through `Scene_sync` | Source/preset/recovery; document history |
| Compiled SOP/value networks, object IDs and provenance | Lowering of checked source | `Contexts.of_workspace` / `Lower.workspace` | Restored with the document, then used by cooking |
| Node positions, display node, selected editor layout, panel disclosure/floating bounds | `Workspace_doc.layout` | Layout reducers; paths remapped with source edits | Source/preset/recovery; document history |
| Sketch settings without a settings graph | `Workspace_doc.settings` and the corresponding document record | Inspector or `set_settings`, reconciled together | Nondefault fields in `(settings ...)`; document history |
| Settings owned by a settings graph | Its `settings/config` form | Inspector/host settings edits written back to its home | Source; document history |
| Resolved values at timeline time, cooked geometry, prepared meshes | `Value_lane` / `Cook`, derived from the installed document | Per-frame resolution and asynchronous cook submission | Caches, not authored state |
| Selection, probes, pane navigation, drafts, timeline playback | Core view state | Pane intents and commands | Generally transient; probes are not document history |
| Viewport orbit and common renderer choice | Environment / Viewport adapter | Focused viewport navigation and renderer requests | View preset/recovery; orbit enters document history when an authored camera follows it |
| Guide preference and kit text size | User preference/UI state | Preference command / PXUI | Separate from workspace source |
| Runtime window configuration and cook seed | Values captured when the host starts | `Workspace.run` / editor creation | Authored configuration can change, but the running host is not reconfigured automatically |

The table describes active consumers. Older layout fields such as pins and wire bends remain
in the codec; saving a field does not establish that the current Scope pane consumes it.

~~~mermaid
flowchart LR
  A["Lisp / graph / inspector / panel intents"] --> B["Check and reconcile"]
  B --> C["Installed immutable Document + history"]
  C --> D["Checked workspace + layout + settings"]
  C --> E["Lowered scene and object networks"]
  E --> F["Value_lane at timeline time"]
  F --> G["Cook / prepared pieces"]
  E --> H["Scene composition per viewport"]
  G --> H
  H --> I["Renderer slots by viewport key"]
  I --> J["Pure Scene returned to native renderer"]
  D --> K["Source / preset / recovery serialization"]
~~~

`Ui.frame` builds widgets and returns intents. Core applies document changes before submitting
the frame's cook; Environment composes prepared results afterward. In normal asynchronous
operation the previous successful geometry may remain visible while a new cook runs.
That is a deliberate preview latency. World day-cycle playback has its own timeline path;
it does not make arbitrary World Lisp expressions live. Applied document state and history must nevertheless
agree, and an awaited cook must render the applied edit in the same update.

Primary implementation references:
[Workspace_doc](../../lib/editor_document/workspace_doc.ml),
[Contexts](../../lib/editor_document/contexts.ml),
[Scene_sync](../../lib/editor_document/scene_sync.ml),
[Core](../../lib/rays_editor/core.ml),
[Environment](../../lib/rays_editor/environment.ml),
[Renderer](../../lib/rays_editor/renderer.ml).

## Reproduced bugs repaired in this change

Severity: P1 changes or displays the wrong state, loses an authored value, or raises unexpectedly.
P2 is a misleading presentation or avoidable failure with a recoverable document.

| Finding | Severity and reproduction | Repair |
|---|---|---|
| Saved sketch settings disappeared on opening | P1: load a workspace with `(settings :amount 3)`, create an editor without an explicit settings argument | Creation preserves workspace settings; lowering reads them rather than the previous document's values |
| Host settings edits were absent from Lisp or rolled back on a later graph edit | P1: `set_settings`, edit a graph, serialize/reload | Shared reconciliation updates workspace metadata or the owning settings graph before committing |
| Presets inherited the current session's omitted settings | P1: save defaults, change settings, load that preset | Full preset load starts from schema defaults; an explicit settings form also starts from defaults |
| Lisp Document tab and whole-document copy omitted saved metadata | P1: save floating/layout/settings edits, inspect or copy Document Lisp | Document display and copy use the complete workspace codec, with metadata in the display cache identity |
| Lisp applied after the cook submission and could leave the picture stale | P1: edit box size through Check and apply with `await:true` | Text intents install before cooking; finalized history and probe targets are retained |
| Host scene-only edits left cached composition unchanged | P1: change an object's translation without changing its SOP output | Composition checks scene identity, open level and viewport membership, in addition to cook/effect signals |
| Empty preview fell back to the primary scene | P1: viewport over an empty nondefault scene beside a populated primary scene | Empty overrides keep their viewport mapping and an explicit empty composed scene |
| Comparison viewport lighting used other instances' lights | P1: override only the comparison scene's lamp intensity | Geometry, lights and camera bookkeeping use the same viewport membership predicate |
| Fullscreen used the primary scene instead of the focused preview | P1: focus an empty/comparison viewport and hide the UI | Hidden rendering, its cache and picking resolve the focused instance and its orbit |
| Named SOP pane inspector looked in the navigation level's network | P2: show `ui/graph "g"` while the scene list remains open, edit a selected SOP | Inspector and geometry footer/targets resolve the compiled node's owning network |
| Overlapping floating viewports painted the same renderer slot | P1: different preview instances with identical floating bounds, select Wireframe | Renderer paint resolves the slot by viewport key rather than bounds |
| One failed path-traced preview blanked healthy siblings | P1: a valid box preview beside an unsupported line-mesh preview | Keep successful slots paintable while reporting the renderer error; nested empty Scene3 groups skip tracer creation |
| A valid text edit removing the last 2D SOP network raised | P1: change the only SOP graph into a value graph in Editor2 | Shared installation returns a document diagnostic when its required level cannot resolve |
| Unrecognized/duplicate root forms could be silently discarded | P1: put an unknown form or two settings/layout/workspace forms beside the workspace | Reject them with `E_DOCUMENT_FORM`; preserve the established missing-workspace diagnostic |

Additional boundary repairs: an explicit `(layout)` now clears layout while an absent layout
retains the supplied fallback. Source reload clears obsolete Graph drafts as well as the other
drafts. Camera writes that cannot reconcile keep the previous document and expose the refusal;
they no longer fall back to an unsaved derived-only edit. Authored active-camera selection is
recomputed deterministically from primary cameras instead of inheriting stale selection or
selecting a comparison camera.

The direct regression checks are in
[test_editor_consistency.ml](../../test/test_editor_consistency.ml).
They compare authored text, settings, history, compiled ownership and staged render data,
rather than only comparing two records that could be wrong in the same way. A native check
renders a healthy path-traced viewport beside an unsupported mesh and a nested empty scene,
then verifies that the healthy image is present.

## How preview panels actually behave

An authored viewport evaluates its `(ref scene ...)`. A scene instance whose evaluated calls
differ from the primary scene gets auxiliary objects in the combined scene network and a
`shell.views` membership list. Equal instances can share the primary drawing. An empty different
instance has a membership entry containing no IDs; absence of an entry and an empty entry have
different meanings.

Those auxiliary objects are preview products. `shell.preview_sources` now retains their owning
panel origin, authored scene ref where available, and evaluated instance by viewport key.
Their write-back homes remain `Looped`, so ordinary
derived edits cannot reconstruct the original overridden call. The safe route is editing the
source graph or the viewport's ref arguments. The inspector locks their parameter rows and explains the source-edit route; shared
reconciliation refuses derived writes with the viewport identity.

Unique named viewports now use graph/binding keys; inline, looped and repeated panels use
placement keys. Renaming changes the authored key. Docking retains both panel bindings.
Each viewport has an orbit. Focus chooses the orbit used for navigation, overlays and picking.
The common renderer retains at most 16 viewport slots and 64 converted meshes. It shares
converted geometry but keeps viewport output separate. Floating panels use the same PXUI hit
tree and Scene insertion path as docked panels; bounds are placement, not viewport identity.

Lights are isolated with geometry. World state, the primary active render camera
and look-through/export controller are explicitly shared, with per-viewport free
orbits. An independently authored comparison camera retains its values without
selecting or replacing that primary controller; the isolation checks are C07.

Only the first Graph/List/Lisp/Inspector leaf of a kind builds that pane. A second leaf is shown
as already displayed elsewhere. This is a deliberate current shell constraint, not independent
editors with independent selections.

## Remaining architectural issues and technical debt

| Priority | Evidence and consequence | Minimum remediation and acceptance check |
|---|---|---|
| P1: non-SOP time was accepted but frozen — repaired | Light intensity/color now retain checked residuals and resolve at editor timeline time for primary/comparison composition. Other scene, World, settings and editor residuals give `E_CONTEXT_TIME`, naming the graph and field. A `Geo` reference stays valid when its SOP parameters animate. | `frozen_context_time` checks unsupported transform/light-width/World/settings/panel fields at two times, precise installation/startup/reload refusals, unchanged source/history and literal replacement/undo. Live-light checks cover two times, rendered output, independent overrides, reload/undo, local failures/recovery and seeded one-/three-domain output. See C13. |
| P1: startup settings appeared to apply immediately — repaired | `Workspace.run` reads title/size/fps/seed once; Cook owns the seed captured at creation. These remain explicitly startup-only. | All five built-in field labels say “on restart”; a selected `settings/config` inspector also explains it. `test_editor_consistency.startup_settings` checks labels plus saved edits, serialized reload and one-entry undo for every field. No window or cook-seed field is made live by this repair; selected live context behavior remains tracked separately in C13. |
| P1: Selection Lisp silently ignored draft parts — repaired | The old apply ignored the closure result and checked replacement bindings individually, refusing valid producer/consumer type changes. | `Text_pane.selection_form` now patches the complete graph; `Core.binding_edit` checks/lowers once through `Set_graph`. Changed results and duplicate names are refused. The printed closure explains that omitted bindings stay. `test_text_pane.editor_binding` verifies refusal without document changes, partial patches, coherent list-to-geometry producer/consumer changes, serialized reload and one-entry undo. |
| P1: stale drafts could overwrite another edit — repaired | Selection, Graph and Document drafts now retain their base workspace. Apply and live scrub refuse a changed source with `E_DRAFT_CONFLICT`; Document also checks authored layout/settings. The draft and current document/history are preserved. Successful scrub advances the base; discard and successful reload clear it. | `test_text_pane` exercises Graph draft → undo → apply and Document/Selection draft → host edit → apply. `test_editor_consistency.stale_inspector_draft` types a Selection draft, drags the actual inspector, then verifies refusal, unchanged applied source/history and retained draft. |
| P2: viewport identity and preview provenance — implemented | Unique named viewports now key by editor graph/binding. Docking preserves panel bindings and adds a split wrapper instead of renaming the target. Inline/looped/repeated panels retain a documented placement fallback; rename changes the authored key. `shell.preview_sources` records origin, authored scene ref where available, and evaluated instance. Auxiliary objects remain read-only with an explicit source-edit route in the inspector and shared reconciliation. | `preview_identity` passes reorder/dock/reload/rename/close, independent overrides, empty membership, orphan provenance cleanup, repeated/inline fallback and derived edit refusal. `preview_orbits` also drags the actual camera, checks isolated orbit preservation through reorder/dock/graph reload, and closes/re-adds a viewport to prove obsolete orbit state was removed. Native renderer validation remains in C14. |
| P2: navigation and render ownership — audited and repaired | Named inspector/handles resolve the compiled SOP owner. Scene framing follows focused membership, including viewport-only layouts and empty scenes. World and primary render-camera controllers remain explicitly shared; each view has its own free orbit. | The C07 call-site inventory and passing named-handle/framing/orbit/comparison-camera/World regressions record each intended target. Independent controllers would be an explicit viewport API extension, not an implicit consequence of focusing a comparison. |
| P2: source polling missed same-mtime writes and hid read failures — repaired | Polling now reads content/digest at 2 Hz and suppresses repeated reload attempts by observed digest. Source read failures/recovery are status notices; save reports read errors and retains preset fallback for a differing readable source. | `test_workspace_source` covers preserved mtime, changed inode, unchanged applied source/history on read failure/recovery, and conflict-to-preset. The digest check still precedes rename: an uncooperative writer can race it. This limit is explicit in Source documentation. Measured polling cost and file sizes are recorded in `specification/performance.md`. |
| P2: renderer errors lacked panel identity — repaired and verified | Errors now include every failed viewport key and say either “stale output retained” or “no output.” A failed transition from Wireframe to Path traced no longer paints old wire output as if it were traced. Renderer errors also appear in crash reports. | The window-free `failed_renderer_modes` regression verifies both failed keys, absence of wrong-mode output, and recovery by switching modes. The final native regression passes retained stale output, healthy-primary pixels, fail → recover, fail → mode switch and close. Existing 16-slot/64-mesh capacities and tracer destruction paths are retained. |
| P3: layout readers and drag commits — repaired | `iteration.md` and `Layout_by_path` now distinguish active readers from preserved legacy canvas fields. Held floating-window drags previously wrote layout every frame. | Window movement/resizing now uses transient chrome bounds and one release commit, as splitters and Scope placements do. Held-input, save/reload and one-step undo checks pass; the existing codec is retained. |
| P3: ownership fallback scans scene networks — measured | `Core.node_owner` keeps the current-network fast path, then scans owners for a named pane. This is intentionally small code with a documented ceiling. | Actual named selection measures 0.015720 ms/lookup at 1000 owners; retain the scan for this measured workload. Benchmark and limits are recorded under C11. |
| P2 build debt: SDL bootstrap mismatch — repaired and verified | This host installs SDL 3.4.16. A fresh build exposed the old 24-byte pen-proximity ABI assertion; the current header adds `pen_state` and makes the event 32 bytes. Cached native objects had masked the mismatch. | Regenerated core provenance, inventory, layout and ABI checks, and updated the dependency minimum and version fixture to 3.4.16. A second fresh build passed `@all`, all four binding qualifications and 100,000 surface/window lifecycle cycles. The copied 33-event trace also passes. See C12 for commands. |

## Ordered remediation plan

1. **Delivered: close the current consistency holes.** Keep source, metadata and derived
   document changes on reconciliation/install; apply text before cooking; compose from actual
   state; isolate preview membership; use renderer keys. Run the new regression alias plus
   existing workspace, text, source, transaction and native renderer checks.
2. **Delivered: prevent silent interpretation.** Selection patches and stale-draft detection are repaired.
   Startup-only settings are labeled; unsupported residual time fields are refused with graph/field diagnostics.
   These are small boundary changes. Each should include a concrete before/after reproduction,
   unchanged state on refusal, serialized reload and undo acceptance.
3. **Delivered: stabilize preview identity and provenance.** Reuse panel origins for keys and carry
   the owning ref/instance into preview products. Do not make preview objects independently
   editable until write-back can round-trip overrides without modifying another viewport.
   Cover dock/swap/rename/close and empty scenes.
4. **Delivered: make selected runtime behavior live.** Light intensity/color resolve from
   recorded residuals and checked ports. Scene transforms, World expressions and panel fields
   remain explicitly static; title/size/fps/seed remain restart-only. SOP/prepared/drawing
   caches and object/panel identities are preserved. Per-view failure isolation, seeded
   one-/three-domain regression and before/after measurements are recorded under C13.
5. **Delivered: improve source diagnostics, renderer attribution and documentation.**
   Preserve the single codec, shared PXUI frame, history snapshot and bounded caches.
   The SDK bootstrap mismatch was checked separately; clean build and binding
   qualification pass. Final native presentation also passes under C14.

No new framework or dependency is needed for phases 1–3. A full rewrite would obscure the
existing ownership rules and delay checks for the failures already observed.

## Ownership call-site inventory (C07)

| Authority/callers | Intended target and current evidence |
|---|---|
| `Core.network` / `document` / list rows / document-intent reduction | Open navigation level, resolved on installation. These are list/scene reducers, not named-SOP ownership lookups. Scoped syntax edits use the source. |
| `Core.node_owner` / `compiled_node` / scope records and geometry targets | Compiled SOP owner, independent of navigation. Named inspector, probe/footer and handle paths share these helpers. |
| `Core.selected_node`, `space`, handle intent conversion | Selected scoped SOP first, with its owning object's transform; otherwise navigation selection. `named_handles` drags a projected handle on a translated object while the scene level remains open; only the SOP argument changes. |
| `Core.display_node` / `geometry_objects` | Explicit object network; apply the displayed path only when the shown graph owns that object. Existing display checks remain. |
| `Core` viewport framing / `view_wants` | Focused instance membership at scene level. `focused_framing` verifies `F` works with only viewport panels and that an empty view does not borrow primary bounds. |
| `Core.world_keys`, `edit_node` | Explicit World/level argument, reconciled through authored homes. Missing levels retain the document. |
| `Core.world` → `Environment.bake_world` | Primary shared World and its timeline day cycle. `Environment.update_world` uses that same World for map/rotation gestures. `preview_camera_world` verifies comparison focus/edit/undo retains the baked World. This shared policy is explicit in `iteration.md`; independent Worlds are outside the current viewport API. |
| `Viewport3.active_node` → `render_camera_of`, `render_of`, `on_view`, look-through/export | Primary authored active camera; free orbits are keyed by viewport. `preview_camera_world` retains an independently authored comparison camera while focus/edit/undo preserves the primary controller. Look-through/export use that shared primary controller, as documented in `iteration.md`. |

## Completion ledger

All fourteen remediation items are complete. Final verification below uses a fresh
build against SDL 3.4.16 and includes the previously blocked native gates. Historical
initial-repair results are retained separately; completion rests on the current runs.

| ID | Required work / acceptance | Current status and evidence |
|---|---|---|
| C01 | Initial reproduced consistency repairs; window-free and native regression checks | Complete. Final-tree window-free regressions, broad `runtest` and all four native editor aliases pass from the fresh SDL 3.4.16 build. Current native evidence is recorded under C14. |
| C02 | Frozen non-SOP time: precise refusal or explicit static labeling; scene/light checks at two times, unchanged state on refusal, reload/undo | Complete: `E_CONTEXT_TIME` identifies unsupported graph/field time use. `frozen_context_time` covers scene transform, light width, World, settings and panels at two times, refused source/history, serialized reload, literal replacement/undo and a supported time-driven SOP reference. Selected light intensity/color are now live under C13. Focused consistency and existing workspace-live/doc/shell checks pass with dummy drivers. |
| C03 | Startup-only title/size/fps/seed: label restart behavior; chosen live fields compare runtime, saved reload and editor; live seed must match sequential/multidomain | Complete as explicitly startup-only built-in fields, with no live seed/window change. `startup_settings` checks all five labels, saved edits, reload and undo. The settings graph inspector explains restart behavior. Selected live light behavior and unchanged seeded results are verified under C13. |
| C04 | Selection patches: result refusal, duplicate refusal, omitted bindings, atomic related type edits, reload and one-entry undo | Complete; `test_text_pane.editor_binding` exercises the public editor. `dune build @test/test_text_pane` and final broad `runtest` passed with dummy SDL drivers. |
| C05 | Draft base source identity; preserve conflicted draft after inspector/host edits and undo | Complete. `test_text_pane.editor_text`/`editor_binding` cover all three tabs, host edits and undo. `test_editor_consistency.stale_inspector_draft` covers an actual inspector drag; focused and final broad checks passed with dummy SDL drivers. |
| C06 | Stable named viewport keys, inline/loop fallback, ref/instance provenance; swap/dock/rename/reload/close, independent overrides, empty scenes, orphan cleanup | Complete. Named keys/provenance and shared docking are repaired; derived preview edits remain refused. `preview_identity` passes source/lowering checks for reorder, dock, reload, rename, close, independent override edits, empty views, orphan provenance and inline/repeated fallback. Existing shell/edit/doc tests pass. `preview_orbits` additionally passes actual input orbit preservation and close/re-add cleanup. Native renderer validation also passes under C14. |
| C07 | Audit `Document.network`, `Core.render_camera`, `Core.world` callers; named-pane handles, comparison camera/World isolation | Complete. The call-site inventory identifies actual camera helpers in `Viewport3` (there is no `Core.render_camera` implementation). Named handles resolve the compiled owner; actual translated-object dragging and focused/empty framing checks pass. `preview_camera_world` retains an independently authored comparison camera and verifies focus, ref override edits and undo preserve the primary render camera and physically reused World bake. `iteration.md` explicitly chooses shared primary ACTIVE/look-through/export/World policy with separate free orbits, matching the existing viewport API. |
| C08 | Digest polling at 2 Hz, unreadable-source diagnostic, preserved-mtime/inode tests, retained conflict-to-preset behavior; measure file sizes and document competing-writer limit | Complete; focused `test_workspace_source` and final broad checks passed. Largest checked-in source: 7800 bytes; five 2000-poll samples measured median 0.054431 ms and 8672 bytes per poll. Benchmark command and raw samples are in [performance.md](../performance.md#source-digest-polling--2-october-2026). Public Source docs record the competing-writer limit; its API manifest promotion changes documentation hashes only. |
| C09 | Renderer failure attribution by viewport, explicit stale output, fail/recover/mode-switch checks, bounded resources and joined close | Complete. Window-free `failed_renderer_modes` and native stale-output/healthy-primary/recovery/mode-switch/close checks pass. Renderer slots and converted meshes remain bounded at 16/64; removed slots destroy their tracers, tracer destruction flushes pending work, and editor close joins its cook worker. Broad GPU/path-tracer lifetime checks report zero handle delta. |
| C10 | Layout field reader inventory and corrected documentation; transient drag state with one release commit, single codec | Complete. The field inventory in `iteration.md` and `Layout_by_path` documentation distinguish active readers from preserved legacy fields. A real held-drag check exposed floating windows committing early; `Chrome.Window_drag` now carries transient bounds until release, sharing the existing codec and history reducer. `test_workspace_shell.run_panel_states` verifies held splitter/move/resize keep source unchanged, cancelled window drags discard draft bounds, release/save round-trip, and one undo restores placement. Focused shell, shell-library, typecheck and promoted API gate pass. |
| C11 | Measure named-pane owner fallback on large scenes; add lowering owner map only if measurement warrants it | Complete. `bench_named_owner` measures actual `Editor3.selected_node` with Scene navigation and the last owner selected: 1/100/1000 distinct SOP networks, five 10,000-lookup samples. Median at 1000 owners is 0.015720 ms and 1504 bytes/lookup. The measured fixture does not warrant an index; the existing scan and its documented upgrade path remain. Raw samples, command and limits are in `performance.md`. |
| C12 | Pinned SDK/bindings bootstrap: fresh clean build, regenerated intended headers if needed, ABI qualification | Complete. Installed/checked core SDL version is now 3.4.16. The first fresh build exposed stale generated ABI checks. Regenerated the four core artifacts with `dune exec tools/sdl3/generate.exe -- --root . --extension core --write`, reviewed the added `pen_state` field/32-byte event, and updated the dependency minimum and version fixture. A new `/private/tmp/rays-consistency-sdl3416-clean-20261002` build passed `@all` and all four binding qualification aliases. Inventories match, lifecycle stress passes 100,000 cycles each, and copied typed events pass all 33 cases. |
| C13 | Selected live context evaluation: stable object/panel identities, unchanged networks/prepared pieces, per-view isolation, deterministic seed and before/after benchmark | Complete. Selected fields are scene light intensity/color; scene transforms, World expressions and panels remain static, and window/seed fields restart-only. Lowering retains only affected residuals/checked ports by stable object ID. Environment retains one runtime scene, separate from authored history and keyed by authored scene/drives/time; failures retain only the failed light and identify its view/fields. `live_lights`, `live_light_failure`, `live_light_failure_isolation` and `live_light_determinism` pass actual timeline rendering, source/ID preservation, override/reload/undo, local failure/recovery, exactly one geometry prepare/draw and byte-identical seeded one-/three-domain outputs. The gallery demonstrates a pulse; API/iteration instructions describe the boundary. Five-sample before/after measurements are in `performance.md`: live update median 0.082239 ms at one view / 0.818855 ms at sixteen, with unchanged geometry counters. Native presentation also passes under C14. |
| C14 | Final verification: `@check`, `@all`, dummy-driver `runtest`, focused and native editor checks, `@smoke`, `@doc`, API/manifest gates, `git diff --check`; recorded performance evidence | Complete. Final clean-build `@check`, `@all`, forced dummy-driver `runtest`, focused editor/live/shell checks, `@doc`, API/SOP manifest gates, all four forced Cocoa native editor aliases and both `@smoke` examples pass. The retained four-preview capture was visually inspected; native renderer tests also verify healthy pixels, stale output and recovery. Performance evidence for source polling, owner lookup and live lights is recorded. `tools/plisp/test/ml.t` retains the reviewed catalog digest from the restart labels. Commands and environment are below; `git diff --check` passes. |

Continuation checks (Selection remediation): typecheck passed. The pane regression also exposed
an older test that changed the shown closure result while editing an unrelated binding; that
test now keeps the actual shown result and separately verifies that changing it is refused.
No supported public API was added; the candidate builder and draft bases stay package-private.
Stale-draft checks include actual inspector input, host edits and undo; refusals preserve both
the applied document/history and the draft, and successful reload clears all draft bases.

## Verification and performance

Final verification (2 October 2026): macOS 26.2 arm64, OCaml 5.3.0, Dune 3.24.2,
SDL 3.4.16, SDL_image 3.4.4, SDL_ttf 3.2.2 and SDL_mixer 3.2.4. These commands
all returned exit status 0 after core binding regeneration, using a new build
directory rather than the cached objects that masked the ABI mismatch:

```sh
dune build --build-dir /private/tmp/rays-consistency-sdl3416-clean-20261002 \
  @all @lib/sdl3/qualification @lib/sdl3_image/qualification \
  @lib/sdl3_ttf/qualification @lib/sdl3_mixer/qualification
dune build --build-dir /private/tmp/rays-consistency-sdl3416-clean-20261002 \
  @check @doc @tools/api_manifest/runtest @lib/sop_catalog/runtest
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune runtest \
  --build-dir /private/tmp/rays-consistency-sdl3416-clean-20261002 --force
RAYS_SHELL_PNG=/private/tmp/rays-consistency-final-20261002/variations.png \
  SDL_VIDEODRIVER=cocoa SDL_AUDIODRIVER=dummy dune build \
  --build-dir /private/tmp/rays-consistency-sdl3416-clean-20261002 --force \
  @test/test_editor_consistency_native @test/test_workspace_shell_native \
  @test/test_workspace_view_native @test/test_rays_editor @smoke
git diff --check
```

The forced full suite includes the focused consistency, text, source, transaction,
scene-sync, live, document and shell regressions. The dependency gate reports 47
libraries, 45 rules and no listed exceptions. API/SOP manifests match without a
new promotion. Documentation succeeds with existing formatting/reference warnings
in unrelated interfaces.

The native consistency check retains and attributes stale traced output, verifies
healthy-primary red pixels beside a failing comparison and nested empty scene,
recovers the failed comparison, switches renderer modes and closes the editor.
Native shell checks render independent instances and exercise Raster, Wireframe and
Path traced in docked, undocked and authored floating viewports. The retained
1800 × 1280 Variations capture was visually inspected and shows all four previews;
its pixel checks confirm nonempty, distinct images. The native VIEW check passes
camera movement, parameter editing and returning up. Both 30-frame smoke examples
(`basic` and `sop_gallery`) terminate successfully. The editor UI uses 28 batches
against its 32-batch budget; SOP parity reports equal one-/four-domain PNGs for 23 graphs.

The previous execution session failed before rendering with
`SDL3.Init.init: The video driver did not add any displays`, including retries
after unlocking and with active `caffeinate` assertions. This session has working
Cocoa display access and the final clean-build native run passes. The measurements
and native successes below remain historical initial-repair evidence.

### Historical initial-repair verification

The regression suite reproduces the initial settings, composition, empty-preview, lighting
and 2D refusal failures against the starting implementation. The added Lisp, fullscreen,
named-pane and overlapping-renderer checks exercise the repaired boundaries through the
public editors.

Validation completed successfully:

- `dune build @check` and `dune build @all`.
- Focused editor/workspace/text/source/scene-sync checks, including the 13 new
  window-free consistency cases; editor_core and pxui_shell tests.
- `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune runtest`, including the
  dependency gate (47 libraries, 45 rules, no listed exceptions).
- Native `test_editor_consistency_native`, `test_workspace_shell_native`,
  `test_workspace_view_native` and `test_rays_editor`. Real frame captures
  were inspected; renderer switching and docked/floating preview checks passed.
- `dune build @smoke @doc @tools/api_manifest/runtest` and `git diff --check`.
  Documentation completed with pre-existing reference warnings in other interfaces.
  The API manifest matched; no promotion was needed for these package-private changes.

macOS 26.2 arm64, OCaml 5.3.0, default Dune profile, one cook domain. The command
is `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200`. Before reconstructs the starting
uncommitted tree on HEAD `a0545f73`; after is this repair. Three alternating pairs
ran without concurrent agent tests/builds; other desktop applications remained active.

| Median of run statistics | Before | After |
|---|---:|---:|
| Held-drag median | 8.121 ms | 8.217 ms |
| Held-drag p95 | 8.653 ms | 9.514 ms |
| Undo (one sample per run) | 9.785 ms | 9.786 ms |
| Drag allocation/frame | 6390677 bytes | 6402373 bytes |
| Undo allocation | 7726568 bytes | 7763968 bytes |

The allocation increase is 0.18% per drag frame and 0.48% per undo. Individual
timings varied substantially, so this establishes neither a speedup nor an isolated
timing regression. Raw run statistics and methodology are in
[performance.md](../performance.md#editor-consistency-repair-2-october-2026).
The benchmark does not establish path tracing throughput, large-scene scaling or
a frame latency bound. The later clean SDK mismatch is resolved under C12.
