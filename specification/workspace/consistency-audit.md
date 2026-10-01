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
[Core](../../lib/prismel_editor/core.ml),
[Environment](../../lib/prismel_editor/environment.ml),
[Renderer](../../lib/prismel_editor/renderer.ml).

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

Those auxiliary objects are preview products. Their homes are currently `Looped`, so ordinary
derived edits cannot reconstruct the original overridden call. The safe route is editing the
source graph or the viewport's ref arguments. This limitation should be made explicit in the UI.

Each viewport has an orbit. Focus chooses the orbit used for navigation, overlays and picking.
The common renderer retains at most 16 viewport slots and 64 converted meshes. It shares
converted geometry but keeps viewport output separate. Floating panels use the same PXUI hit
tree and Scene insertion path as docked panels; bounds are placement, not viewport identity.

Lights are now isolated with geometry. World state, active render camera and look-through policy
still have global parts. A comparison viewport's own authored camera does not currently constitute
an independent render-camera controller.

Only the first Graph/List/Lisp/Inspector leaf of a kind builds that pane. A second leaf is shown
as already displayed elsewhere. This is a deliberate current shell constraint, not independent
editors with independent selections.

## Remaining architectural issues and technical debt

| Priority | Evidence and consequence | Minimum remediation and acceptance check |
|---|---|---|
| P1: non-SOP time is accepted but frozen | `Contexts.result`, scene call walking and preview evaluation force `t = 0`. Live SOP drives use Value_lane. A time-dependent scene transform, lamp, World keyword or panel expression can therefore look editable while remaining static. This is confirmed behavior, not fixed here. | First reject unsupported time-dependent non-SOP fields with a precise diagnostic, or label them as static. Add one scene/light test at two times. Implement live context evaluation only where the intended use requires it, retaining stable object/panel identities and unchanged SOP outputs. |
| P1: editable startup settings are not applied to the running host | `Workspace.run` reads title/size/fps/seed once; Cook owns the seed captured at creation. A settings graph edit changes saved state and inspector values without restarting/reconfiguring these services. | Mark startup-only fields as applying on restart. For each field chosen to become live, use the existing native runtime API and explicit cook-context invalidation; compare editor value, runtime result and saved reload. Seed changes must have an exact sequential/multidomain check. |
| P1: Selection Lisp can silently ignore parts of a draft | `Core.binding_edit` extracts closure bindings but ignores the closure's final expression. Its existing partial-patch contract also leaves omitted bindings in the graph; the closure is not a full graph replacement. It validates changed bindings one at a time, so a coherent multi-binding type change can fail at an intermediate state. | Reject changes to the closure result and explain that omitted bindings stay. For genuinely related edits, rewrite all changed bindings in a candidate source and check/lower once. Check result changes, partial binding patches, duplicate names, cross-binding type changes and one-entry undo. Graph/Document tabs already offer whole-form edits. |
| P1 risk: drafts have no source revision | Drafts are keyed by graph/path rather than the document revision they began from. External reload now clears drafts, but another pane/undo/host edit can change the same binding while a draft remains open. | Store the base source identity with a draft; applying to a changed base should preserve it and show a conflict. Test edit-in-inspector → apply-old-draft and undo → apply-old-draft. Do not add a merge engine before a real need. |
| P2: viewport identity and preview provenance are weak | View keys come from panel tree placement; saved panel state uses binding paths where possible. Reordering panels can transfer transient orbit/cache identity. Auxiliary preview homes lose the actual ref/override origin. | Reuse named panel origins as stable viewport keys, with a documented fallback for inline/looped panels. Preserve ref/instance provenance before enabling preview editing. Check swap/dock/rename/reload, distinct instance edits and orphan-state cleanup. |
| P2: navigation and render ownership remain partly coupled | The named inspector now resolves ownership, but several framing/handle/display paths still use the open level or primary active camera. One global World bake and look-through state service multiple views. | Audit each caller of `Document.network`, `Core.render_camera` and `Core.world` against its intended target. Use existing viewport membership/owner helpers. Add named-pane handles and independently authored comparison-camera/World checks before expanding those features. |
| P2: source polling can miss an unchanged-mtime write | `Source_file.poll` reads content only when mtime changes. It ignores read errors. `save` checks the digest before an atomic rename, leaving a race with an external write between those operations. These are identified risks, not newly reproduced races. | Poll content/digest at the existing 2 Hz if measured file sizes allow it; report unreadable source. Keep conflict-to-preset behavior. Test preserved mtime and a changed inode. A fully race-free competing-writer protocol requires cooperation; document that limit instead of claiming a digest makes writes atomic against other editors. |
| P2: renderer errors lack panel identity | Successful panels remain visible now, but error aggregation reports one global message and can retain a failed slot's last good image. | Prefix errors with the viewport key/name and identify retained output as stale. Add fail → recover and fail → switch mode checks; keep resources bounded and joined on close. |
| P3: duplicate layout representations obscure active behavior | Codec fields and historical API prose still describe layout capabilities removed with the flat pane. Some host/view state sits beside the authored layout for live drags and recovery. | Inventory readers of each layout field; update documentation before deleting fields. Keep live drag state transient and commit once on release. Avoid a second persistence format. |
| P3: ownership fallback scans scene networks | `Core.node_owner` keeps the current-network fast path, then scans owners for a named pane. This is intentionally small code with a documented ceiling. | Measure large named-pane scenes; add a compiled-ID-to-owner map in the existing lowering only if the fallback is material. |
| P2 build debt: checked SDL bindings differ from this installed SDK | A fresh scratch build failed the pen event ABI size assertion (checked size 24, installed size 32). Regenerating core SDL bindings in the disposable baseline checkout enabled the benchmark. Existing main-tree build artifacts compiled successfully. | In a separate SDK/bindings change, regenerate with the intended pinned headers and run binding/ABI qualification. Do not interpret an incremental green build as proof of clean-bootstrap compatibility. |

## Ordered remediation plan

1. **Delivered: close the current consistency holes.** Keep source, metadata and derived
   document changes on reconciliation/install; apply text before cooking; compose from actual
   state; isolate preview membership; use renderer keys. Run the new regression alias plus
   existing workspace, text, source, transaction and native renderer checks.
2. **Next: prevent silent interpretation.** Reject unsupported Selection edits, detect stale
   drafts, expose startup-only settings, and reject or clearly label frozen non-SOP time.
   These are small boundary changes. Each should include a concrete before/after reproduction,
   unchanged state on refusal, serialized reload and undo acceptance.
3. **Then: stabilize preview identity and provenance.** Reuse panel origins for keys and carry
   the owning ref/instance into preview products. Do not make preview objects independently
   editable until write-back can round-trip overrides without modifying another viewport.
   Cover dock/swap/rename/close and empty scenes.
4. **Then: make selected runtime behavior live.** Pick the required scene/World/window/seed
   fields explicitly. Re-evaluate only affected contexts and preserve unchanged networks and
   prepared pieces. Require per-view isolation, deterministic seeded results and benchmark
   measurements before broadening this path.
5. **Maintenance: improve source diagnostics, renderer attribution and documentation.**
   Preserve the single codec, shared PXUI frame, history snapshot and bounded caches.
   Resolve the SDK bootstrap mismatch separately from editor changes.

No new framework or dependency is needed for phases 1–3. A full rewrite would obscure the
existing ownership rules and delay checks for the failures already observed.

## Verification and performance

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
  `test_workspace_view_native` and `test_prismel_editor`. Real frame captures
  were inspected; renderer switching and docked/floating preview checks passed.
- `dune build @smoke @doc @tools/api_manifest/runtest` and `git diff --check`.
  Documentation completed with pre-existing reference warnings in other interfaces.
  The API manifest matched; no promotion was needed for these package-private changes.

macOS 26.2 arm64, OCaml 5.3.0, default Dune profile, one cook domain. The command
is `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_prismel_editor.exe 200`. Before reconstructs the starting
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
a frame latency bound. The clean SDK mismatch described above remains separate debt.
