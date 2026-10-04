# Editor architecture and maintenance — implementation progress

Source: [audit and acceptance requirements](Editor%20architecture%20and%20maintenance.md).
Baseline: `48c81daa525c91421eb0fd6854332364739ae7fd`.

Scope update: the user explicitly excluded VoiceOver/native accessibility
("i don't need voiceover..."). The unfinished native bridge was removed.
Keyboard input and traversal remain in scope.

Completed: every in-scope audit item is implemented and checked. The final
source review, focused suites, full repository tests, serial native parity,
build/docs/API manifests and smoke checks passed. Native accessibility is
excluded, not implemented. Changes remain in the working tree for review.

Completion means every in-scope requirement below has direct evidence. A passing logic
test does not prove a native rendering or accessibility requirement. The audit
remains the original scope; this ledger records implementation and validation.

| Work | Status | Required evidence |
|---|---|---|
| P0: explicit empty scene/SOP/layer networks; safe save/load/crash presets | Verified | `test_editor_document`: real serializer/loader, public delete-all/save/reload and crash_dump in both hosts; late-result barrier coverage remains in P1 |
| P0: malformed document validation and host level resolution | Verified | `test_editor_document`: 20 malformed cases; both public hosts reject missing networks and preserve document, camera, history availability and preview |
| P0: load/undo/redo and empty-state behavior | Verified | `test_editor_document`: both public hosts, empty SOP undo/redo; Editor3 empty-scene undo/redo and Editor2 safe rejection |
| P0: explain and repair native look-through assertion | Verified | Exact PNG comparison now uses equivalent 16:9 viewport; sequential native test passes |
| P1: sole UI/viewport input owner | Verified | `test_editor_input` parameterizes both hosts: modal wheel/drags/World edits, cross-pane drags, graph capture, same-frame transitions/cancellation; `pxui/test_input` checks ordered owner events through release; source review confirms the viewport consumes PXUI's exact-root ownership |
| P1: hidden shell advances UI state | Verified | `test_shell`: focused/captured control cancellation, disappearance, no stale click; PXUI pruning also clears hover |
| P1: UI-free document/view adapter extraction | Verified | `Network_view` owns conversion; five model/preset modules now live in package-private `editor_document` |
| P1: intents applied after UI construction, one commit policy | Verified | Core reduces graph/tree/settings/parameter/handle intents after `Shell.frame`; shared commit helper; `test_editor_transactions` checks stable-ID selection/inspector and undo/history agreement; source review covers public edits and environment camera/World paths |
| P1: operation/target gesture grouping | Verified | Both hosts separate mixed commands and World drags, latch the operation through Shift release and pane crossing, include the final release point, and cancel on popup/focus/pointer loss; map-layer stable-ID/clamp/undo checks; invalid/cancelled numeric edits preserve redo and document |
| P1/P2: event-time held keys and press context | Verified | Router, PXUI, graph/tree selection, World edits and both cameras use shared ordered key state; regression cases include same-frame releases, later presses, repeat/spurious release, focus loss and disabled cameras |
| P1: cook reuse and submission provenance | Verified | `test_editor_cook`: per-object prepare counts, settings invalidation without cook effects, Time/Frame freshness, delayed provenance, explicit supersession/empty/shutdown barriers |
| P1: hot-path measurements | Verified | `tools/bench_editor_cook.exe`, before/after table below; elapsed and host/prepare allocations, sizes, domains and machine recorded |
| P1: supplied command identity and trigger conflicts | Verified | Both hosts reject reserved/ambiguous IDs, trigger collisions/prefixes/case/modifiers; valid aliases and disjoint scopes retain keyboard/palette equivalence |
| P2: decide private document library after extraction | Verified | Compiler-enforced presentation ban justified the one private library; dependency rule and direct/transitive injected fixtures pass |
| P2: Workspace facade and Private stability contract | Verified | Host and tests use public Shell Layout/Chrome; forwarding module and Private alias removed; typecheck and focused editor suites pass; Private hooks explicitly unstable |
| P2: shortcut comments and prepare domain documentation | Verified | Actual Leader keymap has layout only in menu/palette; corrected graph comment; Editor2/3 create docs restrict prepare to the worker domain |
| P2: keyboard traversal and activation | Verified | `pxui/test_keyboard` covers traversal/activation/value adjustments/text/cancellation/popup scope/no-op stability; both public hosts test same-frame Tab/Space collapse through existing header intent; final native visual parity passes |
| P2: native control semantics | Excluded by user | VoiceOver/native accessibility removed from this refactor at the user's explicit request; unfinished bridge removed |
| P2: modal-height cache bounded/pruned | Verified | Capacity 32, oldest-use eviction; dynamic-key regression verifies retained height then eviction |
| Gates: dependency fixtures/parser coverage | Verified for changed boundary | Private/public names, quoted dependencies, comments and nonlibrary stanzas; parsed transitive bad edge plus all five direct presentation bans; 45 libraries, 42 rules, zero exceptions |
| Gates: architecture/API notes, examples, manifests, docs | Verified | API/backend/scene notes and SOP gallery walkthrough updated; intended History/Router/Private/PXUI API changes reviewed and promoted; final `@doc` passes with existing unrelated reference warnings |
| Gates: focused logic, sequential native, full repository | Verified | Final focused audit aliases and document/camera tests; serial forced PXUI parity/editor native; `@all`, dummy-driver `runtest`, `@smoke`, `git diff --check` pass |

## Evidence log

- 2026-09-27: inspected current worktree; no implementation changes from the
  audit existed. Confirmed stale integer display serialization, acceptance of
  missing networks, and unchecked level lookup in shared Core.
- Decision: Editor3 supports an empty scene. Editor2 accepts an empty SOP
  network but rejects a preset with no geometry object before installation.
  Empty SOP networks clear the current preview; malformed nonempty networks
  continue to retain the last successful preview with an error.
- Added optional display IDs, shared document validation and level resolution,
  the UI-free Document/Network_view seam, empty preview pruning on changed
  object sets or cook publication, and empty layer construction. Fixed stale
  tile positions on tree deletion and preserved intentional empty scenes in
  camera repair. Preview pruning uses the existing int-keyed compiled map
  and does not add an object scan to unchanged idle frames.
- Added `test/test_editor_document.ml`, run with
  `dune build @test/test_editor_document`. It exercises 20 malformed documents,
  round trips (including empty World layers), both public hosts' rejected
  loads, load undo/redo, actual tile delete-all/save/reload, and actual public
  `crash_dump` preset reload. This does not prove late cook cancellation or
  provenance; those retain their full P1 requirements.
- An invalid nonfinite viewport save is also rejected without replacing the
  prior successful file. `examples/sop_gallery/README.md` documents the public
  empty-state save/load/undo workflow and the callback domain restriction.
- Native look-through diagnosis: the old oracle drew the reference over the
  whole 200×150 window; the editor used its camera's centred 16:9 film.
  The export now uses 320×180, keeping the exact `png 0 = png 1` comparison
  and the independent `png 0 <> png 2` camera contrast. The existing aspect
  and letterbox assertions remain. Both scenes use identity object placement
  and the same empty-light mesh scene. No fixtures were promoted.
- Hidden Shell now always advances `Ui.frame`; absent controls prune text
  focus, pointer capture and hover. Regression checks include focus loss,
  hiding without focus loss, and release after reappearance.
- Validation passed:
  - `dune build @check @lib/editor_core/runtest @lib/pxui/runtest @lib/pxui_shell/runtest @test/test_editor_document @test/test_pxui_graph @test/test_rays_editor_logic @test/test_scene_tree @test/test_sop_catalog @test/test_sop_ui @test/test_sketch_support @test/dependency_gate @tools/api_manifest/runtest`
  - Serial `dune build --force @lib/pxui/test_ui_parity` (overlay exact; 640×600
    at 2×, 272 permitted changes), then `dune build @test/test_rays_editor`
    (editor native pass; 23 SOP graphs have exact one/four-domain PNGs).
  - `dune build @all @doc @tools/api_manifest/runtest`.
  - `dune build @all && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune runtest && dune build @smoke && git diff --check`.
- P1 now routes ordered viewport input through PXUI ownership, reduces stable-ID
  graph/tree/parameter/settings/handle intents after construction, and commits
  through one history helper. Both hosts have modal/capture/mixed-command
  regressions. The numeric inspector check verifies same-frame targeting,
  undo, and invalid/cancelled edits preserving redo. Draw reuse now keys both
  graph and prepared value. Induced-subgraph paste preserves physical optional
  input arity; the held-drag duplicate regression exposed and checks that fix.
- Cook result pieces retain submission settings and dependency-context identity.
  Unchanged static objects reuse preparation; settings changes invalidate all;
  Time/Frame seek produces fresh results. Explicit worker barriers verify
  supersession, empty deletion and joined shutdown.
- Construction rejects ambiguous extension IDs/triggers in both hosts and
  retains same-action aliases and disjoint scopes. Five UI-free modules moved
  to package-private `editor_document`; injected direct and parsed transitive
  presentation edges fail the gate (45 libraries, 42 rules, zero exceptions).
- Modal heights retain at most 32 keys; a dynamic-key regression verifies
  reuse then oldest-use eviction.
- Latest P1/private-library checks passed: `@check`, focused audit aliases,
  editor_core/PXUI/shell and procedural tests; `@all @doc` and intended API
  manifests; full dummy-driver `runtest`; serial native PXUI parity and editor
  suites. Static parity captures use neutral pointer input so real hardware
  hover cannot change the oracle. Existing fixtures were retained.
- Workspace callers now use public Shell Layout/Chrome. Compiler dead-export
  reporting was run after migration; forwarding shapes resolve to the live
  Shell definitions, so this facade has no independent dead-value listing.
  Removing the facade and rebuilding checks that no compiler-resolved caller
  still needs it. No unrelated public exports were pruned.
- At this stage, the next required work was native semantics, ordered modifier audit,
  final source/acceptance audit and gates. The
  complete goal remains active.

- Keyboard stops use the existing hit list and signal accumulator. Tab,
  Shift-Tab, Enter/Space, arrows, numeric entry, slider bounds and Escape are
  regression-checked, including popup restriction and hidden-control pruning.
  Kit pointer editing retains prior host shortcut behavior. Collapse, graph
  VIEW/ACTIVE and menu buttons share the same path. A public-host keyboard test
  exposed the existing narrow-status truncation crash when collapsing View;
  the shared truncation helper now handles limits below three.
- Same-frame numeric entry now processes the events after its activating Enter.
  The Router hands unbound Tab and subsequent events to UI, preserving existing
  tree Tab indentation bindings. Both hosts check same-frame Tab/Space activation.
- Both camera controllers now use the event-time pointer for wheel decisions
  and 2D anchoring. Both hosts verify that wheel-then-pane-crossing navigates,
  and inspector-wheel-then-crossing does not. Camera pointer history only changes
  on delivered pointer events, so rejected modal loads preserve camera state.
- Current Apple custom-element APIs verified against the live
  [NSAccessibility documentation](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol).
  Native roles/values/actions implementation and native verification remain
  pending; keyboard checks do not establish native accessibility completion.
- Current keyboard/facade/camera changes also pass `@all @doc`, the intended
  API manifests, full dummy-driver `runtest`, serial native PXUI parity (exact
  overlay, 272 permitted panel pixels), serial native editor/SOP parity
  (23 graphs, exact one/four-domain PNGs), `@smoke`, and `git diff --check`.
  These gates will be repeated after remaining native/gesture implementation.

- World edits now reduce owned pointer events in order and retain the operation,
  stable target and map bounds chosen at press. History seals after environment
  edits, so release-frame movement remains in the same entry. Both hosts check
  same-frame press/move/release, releasing Shift mid-drag, consecutive separate
  drags, popup/focus/pointer cancellation, pane crossing and large negative
  rotation wrapping, including first-frame held motion and two complete drags
  batched into one frame. `test_scene_tree` verifies map-layer bounds clamping,
  stable-node isolation, unchanged camera, and one-step undo. It still checks
  that scene transforms do not re-cook SOPs. Focused editor aliases, `@check`,
  `@all`, `@doc`, API manifests, full dummy-driver `runtest`, and the serial
  forced native editor suite pass (five workspace UI batches, 23 SOP graphs
  with exact one/four-domain PNGs); `@smoke` and `git diff --check` also pass.
  Documentation retains the previously noted
  unrelated reference warnings. Final acceptance/modifier/native-semantics
  work remains open.
- The user initially asked whether native accessibility is necessary. Explained its
  VoiceOver purpose and the explicit P2 requirement, and recommended deferral
  from this refactor. No scope change had been confirmed; native semantics
  remained pending at that stage and were not counted complete.
- The user subsequently explicitly excluded VoiceOver. Removed the unfinished
  native semantics bridge, SDL hooks, Scene metadata and prototype UI actions.
  Existing keyboard traversal and ordered-input fixes remain. Native semantics
  are excluded from the accepted scope and are not claimed as implemented.
- Held keys now advance with each ordered event in the shared Router, PXUI,
  World edits and both cameras. Previous held keys disambiguate repeated or
  spurious releases and focus cancellation. Graph/tree selection retains the
  press's modifiers through release. Checks cover same-frame Command/Shift
  release, later modifier presses, keyboard traversal/slider/text contexts,
  graph/tree additive selection, World movement before focus loss, arbitrary
  camera translation keys and disabled-camera state. Focused editor, camera,
  graph, shell, PXUI, dependency and API checks pass.
- Final acceptance source review followed loaded documents through validation
  and host level resolution; pane construction through the post-frame reducer
  and shared commit helper; owned input through PXUI into World/camera handling;
  and cook submissions through settings/context provenance and publication.
  Document-to-view conversion stays in `Network_view`; the five model/preset
  modules have the compiler-enforced presentation ban. Existing bounded history
  and active/pending cook worker remain. No new persistence format, UI engine,
  worker framework or compatibility facade was introduced.
- Final validation after removing the native prototype passed:
  - `dune build @check` and focused editor_core/PXUI/shell, document, command,
    input, transaction, cook, camera, graph, scene-tree, dependency and API aliases.
  - `dune build @all @doc @tools/api_manifest/runtest`.
  - `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune runtest`.
  - Serial `dune build --force @lib/pxui/test_ui_parity`, then
    `dune build --force @test/test_rays_editor`: exact overlay, 272 permitted
    panel pixels, five workspace UI batches, and 23 SOP graphs with exact
    one/four-domain PNGs. Existing fixtures retained.
  - `dune build @smoke` and `git diff --check`.
  Existing unrelated documentation reference warnings remain as described above.
  All accepted work is complete; VoiceOver/native semantics remain explicitly
  outside this completed scope.

## World input measurement

Command: `dune exec tools/bench_rays_editor.exe -- --world`. Same Apple M1
machine as above; one geometry object with an empty SOP, a transparent World
with no layers, 16 owned Shift-drag movement frames per run, three runs.
Main and cook-worker domains; one kernel domain. Includes UI construction,
history and 512×256 preview baking, without GPU presentation. Both variants
verify the final 0.16-degree rotation. The baseline used HEAD's World-gesture
block in the otherwise edited environment, before the event-time key work.
The final measurement includes the gesture and ordered-key corrections.
The edited source was restored before checks.
Table reports medians of the three per-run summaries.

| Measure | Before | After |
|---|---:|---:|
| Median seconds/frame | 0.011123896 | 0.011201859 |
| p95 seconds/frame | 0.011439085 | 0.011960030 |
| Allocated bytes/frame | 10,499,596 | 10,510,212 |

The measured median increased about 0.7%, with 10,616 extra bytes/frame.
This small workload includes baking; it establishes no whole-editor speed
claim. Same-frame release and pane-crossing fixes are separately proven by
behavioral checks because the baseline mishandles those inputs.

## Cook measurement

Command: `dune exec tools/bench_editor_cook.exe`. Apple M1, arm64, 8 cores,
16 GiB, macOS 26.2 (Darwin 25.2.0). Two static objects of 10,000 points each;
100 edits to one object; one kernel domain, main and cook-worker domains;
64 MiB/16-entry session cache. Preparation copies 30,000 float components.
Three runs per implementation; table reports medians. These measurements
cover this cook/preparation workload, not whole-application performance.

| Measure | Before | After |
|---|---:|---:|
| Elapsed seconds | 0.091374 | 0.057927 |
| Host allocated bytes | 1,931,744 | 1,650,928 |
| Prepare calls | 200 | 100 |
| Prepare allocated bytes | 538,640,000 | 269,320,000 |

## Camera input measurement

Command: `dune exec tools/bench_camera_input.exe`. Same Apple M1 machine as
above, one domain, 500,000 frames per case, three runs; medians below. The
baseline used HEAD's two camera implementations, then the edited sources were
restored before all verification. Fixed input lists, no inertia, no domains
or GPU rendering in the timed loops. Each wheel delta is 0.000001.

| Camera/case | Before seconds | After seconds | Before allocated bytes | After allocated bytes |
|---|---:|---:|---:|---:|
| 3D idle | 0.002107 | 0.001822 | 20,000,096 | 96 |
| 2D idle | 0.002728 | 0.001660 | 44,000,096 | 96 |
| 3D wheel inside View | 0.011538 | 0.027280 | 148,000,096 | 180,000,096 |
| 2D wheel inside View | 0.041474 | 0.059100 | 436,000,096 | 476,000,096 |
| 3D wheel then pane crossing | 0.008840 | 0.032715 | 44,000,096 | 316,000,096 |
| 2D wheel then pane crossing | 0.009115 | 0.061929 | 68,000,096 | 568,000,096 |

The crossing baseline discarded the wheel, so those rows measure different
behavior and establish no speed comparison. Preserving event-time pointer
history and event-time binding keys add 64 bytes/frame (3D) or 80 bytes/frame
(2D) in the comparable wheel case. The final ordered-key implementation was
measured again with the same command and three runs. Empty-event updates now directly advance existing inertia without
allocating an unused input fold or 2D viewport. The benchmark's fixed 96-byte
measurement overhead remains in each reported allocation total. These data do
not imply whole-editor speed or allocation claims.
