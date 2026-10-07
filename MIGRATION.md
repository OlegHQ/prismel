# One description per SOP: migration strategy

Date: 2026-10-06. Base: `audit-cleanup` plus the pilot branch `sop-one-declaration`.
Status (2026-10-07): complete in the working tree. All 159 original nodes use one
declaration, `rays.sop_catalog` declares none, and no node writes its own parameter text.
`@all`, window-free `@runtest`, `@smoke` and `git diff --check` pass. The assertions that
pinned pre-Lisp behaviour or hand-written key text were updated under decisions 6 to 9
below. The log that follows is the history of how it got here; where it says "pending",
read the Final status section first.

## Current progress (2026-10-07)

- The owner-approved Intersection Analysis replacement assertions now use
  nonempty intersection fixtures. A crossing-curve case proves a blank input
  output is absent while primitive provenance remains, and all blank outputs
  retain the intersection point without provenance attributes. A self-surface
  case proves an ignored disconnected collision group preserves nonempty
  geometry and provenance byte signatures. The focused run reports Intersection
  Analysis and declaration audits passing; its procedural prerequisites retain
  the same Randomize, Boolean Detect and Triangulate 2D refusal failures.
  Existing assertions outside the approved replacements remain unchanged.

- The PPX shares identical inferred literal numeric ranges within each schema.
  Explicit kind overrides and computed bounds retain their own evaluations;
  signed-zero bounds remain distinct. The compiled vector fixture checks range
  identity, and generated-code checks cover signed zero and computed bounds.
  Typecheck, PPX and SOP UI checks pass. Broad tests retain the same six pending
  failures; all 21 stock/host-aware workspaces pass. Serial workspace measurements
  save another 25,480 startup live bytes: before catalog 926,296→900,816;
  after 1,224,856→1,199,376. The post-catalog gap against the pilot is now
  13,376 bytes; full memory parity remains unproven. Node/cache counts and payload
  remain unchanged; Tree warm samples are 0.024/0.025 ms. Serial session cook
  measures 1.186 ms, with unchanged allocated/promoted/major bytes, cardinality
  and geometry hash. This timing sample does not establish a speed improvement.
  Key inventory remains 57. Git metadata access still prevents commits and the
  merge to dev.

- The memory audit removes retained duplicate default/current value boxes
  from factory metadata. Both factory constructors share equal immutable
  displayed values once, at construction; per-frame Parameter.view is unchanged.
  Float comparisons use exact bits, so signed-zero metadata stays distinct.
  One regression checks both constructor paths, float/text sharing and signed
  zero. Existing editable-graph and declaration audits pass; broad tests retain
  the same six pending failures. All 21 stock/host-aware workspaces pass. The
  serial workspace command measures 31,024 fewer startup live bytes: before
  catalog 957,320→926,296; after 1,255,880→1,224,856. Against the pilot's
  1,186,000 bytes, the post-catalog gap falls 69,880→38,856 bytes; parity remains
  unproven. Workspace node/cache counts and payload are unchanged, rounded live
  samples fall approximately 0.03 MB, and Tree warm samples remain 0.024 ms.
  Serial cook is 1.020 ms with unchanged allocation counters/cardinality/hash.
  Process peak is 46.23 MB in this sample. Key inventory remains 57. RDK and
  existing assertions are unchanged; whitespace checks pass. Git metadata
  write access remains required for regular commits and the merge to dev.

- The memory audit removes unnecessary immutable record copies in the shared
  Parameter.schema/normalize path. Every field is still validated and clamped;
  the setter runs only when normalization changes its value, including signed-
  zero bits. One regression covers unchanged default/record identity, clamped
  defaults and values, input immutability, signed-zero bits and nonfinite refusal.
  On arm64 / OCaml 5.3.0, a serial nine-repeat construction probe (1,000 Grid
  nodes, 17 columns / 13 rows / size 2) changes allocated bytes 25,504,096→
  22,144,096, or 25,504→22,144 per node. Medians are 9.342→9.268 ms; timing is
  essentially unchanged. The temporary Dune probe is removed; its source and
  runnable binary are retained at /tmp/rays-normalize-bench.ml and .exe.
  The existing workspace command (`_build/default/tools/bench_workspace_lower.exe
  _build/default/specification/workspace/cases 7`) confirms 17,000 fewer startup
  live bytes: before catalog 974,320→957,320; after 1,272,880→1,255,880. The
  post-catalog gap against the fresh pilot falls 86,880→69,880 bytes; memory
  parity remains unproven. Workspace node/cache counts and payload are unchanged;
  rounded live samples fall approximately 0.02 MB. Tree warm samples are 0.025 ms.
  Serial cook is 1.029 ms with unchanged allocation counters/cardinality/hash.
  Param/Flow/editor/declaration/catalog/UI checks pass; broad tests retain the
  same six pending failures. All 21 stock/host-aware workspaces pass. The key
  inventory remains 57. RDK and existing assertions are unchanged; whitespace
  checks pass. Git metadata write access remains required for commits/dev merge.

- Step 6 removes the origin-point generator's duplicate key through a scoped
  OCaml AST codemod; its separate input-based Point Generate constructor retains
  the diagnostic key pending the requested spelling exception. Existing origin
  generator default/nondefault typed/factory and every-field cache audits pass
  without assertion edits. Broad tests retain the same six pending failures;
  all 21 stock/host-aware workspaces pass. The AST inventory decreases 58→57
  sites (48 explicit + 9 shorthand). The serial session is 1.021 ms with
  unchanged allocation counters/cardinality/hash; startup live bytes, workspace
  counts, payload and rounded live figures match the previous checkpoint. Tree
  warm samples are 0.025/0.024 ms and process peak is 39.25 MB. RDK and existing
  assertions are unchanged; whitespace checks pass. The memory audit identifies
  an independent path to measure: Parameter.schema and Parameter.normalize call
  every immutable field setter even when normalization leaves its value unchanged.
  No normalization change or memory-parity claim is made at this checkpoint.
  Git metadata write access remains required for regular commits and the dev merge.

- Step 6 removes Remesh, Clean and Boolean's duplicate keys and ten dead
  local formatters with OCaml AST codemods. Remesh and Boolean's original
  diagnostic/geometry assertions pass unchanged. An isolated runner copies
  Clean's original pipeline assertion unchanged and passes; it is removed after
  validation. Declaration typed/factory/every-field cache, typecheck, catalog
  and SOP UI checks pass; broad tests retain the same six pending failures. All
  21 stock/host-aware workspaces pass. The AST inventory decreases 61→58 sites
  (49 explicit + 9 shorthand). The serial session is 1.020 ms with unchanged
  allocation counters and geometry cardinality/hash. Workspace node/cache
  counts, payload and rounded live figures match the previous checkpoint; Tree
  warm samples are 0.024/0.027 ms and process peak is 33.73 MB. Retained-memory
  parity against the pilot is still unproven. RDK and existing assertions are
  unchanged; whitespace checks pass. Git metadata write access remains required
  for the requested regular commits and merge to dev.

- Step 6 removes Attribute Noise, Attribute Randomize, Scatter and Sweep's
  shorthand duplicate keys. Scatter's dead density formatter and nine unused
  support formatters are removed; the final unused-support audit is empty. The
  original Sweep identity, geometry, cache and missing-group assertions pass in
  an isolated runner calling the unchanged test function; the temporary runner
  is removed. Declaration typed/factory/every-field cache audits, typecheck,
  catalog and SOP UI checks pass. Broad tests retain the same six pending failures;
  no existing assertion changes. All 21 stock/host-aware workspaces pass. The AST
  inventory decreases 65→61 sites (52 explicit + 9 shorthand). The serial session
  is 1.027 ms with unchanged allocation counters and geometry cardinality/hash;
  startup bytes, node/cache counts, payload and rounded live figures match the
  previous checkpoint. Tree warm samples are 0.025/0.024 ms; process peak is
  45.05 MB. Retained-memory parity against the pilot remains unproven. RDK is
  unchanged; whitespace checks pass. Commits/dev merge remain blocked by denied
  Git metadata writes.

- Step 6 removes eleven further shorthand keys: Box, Circle, UV Sphere, Torus,
  Tube, Platonic, Snap to Grid, Mountain, Extract Point from Curve, Ray and Match
  Size. The OCaml AST codemod removes each duplicate formatter and converts the
  shorthand argument after validating the complete edit count. Nine compiler-
  reported dead local formatters and 29 support helpers with no remaining callers
  are removed. The follow-up unused-support audit is empty. Existing generator
  spelling/geometry assertions pass unchanged (the procedural run reaches only
  its later pending fraction-seed refusal); declaration typed/factory and every-
  field cache audits, typecheck, catalog and SOP UI checks pass. Broad tests retain
  exactly the same six pending failures. All 21 stock/host-aware workspaces pass.
  The AST inventory decreases 76→65 sites (52 explicit + 13 shorthand). The
  serial session sample is 1.023 ms with unchanged 3,023,896 allocated bytes and
  geometry cardinality/hash. Startup bytes, node/cache counts and payload match
  the previous checkpoint. Sunflower retained live samples change from 2.84/4.04
  to 2.87/3.99 MB at capacities 32/512; other rounded live samples are unchanged.
  Tree warm samples remain 0.025/0.024 ms; process peak is 33.98 MB. These samples
  do not prove retained-memory parity against the pilot. RDK and existing
  assertions are unchanged; whitespace checks pass. Git metadata write access
  is still required for the requested regular commits and merge to dev.

- Step 6 removes Measure Curvature, Smooth and quaternion noise's explicit
  duplicate keys, plus Peak, Bend, Bound and Attribute Remap's shorthand keys.
  One dead local ramp formatter and eight unused support formatters are removed.
  Existing assertions are unchanged; Measure Curvature's diagnostic assertions
  and declaration typed/factory/every-field cache audits pass. Broad tests retain
  the same six pending failures. All 21 stock/host-aware workspaces pass. The
  serial session is 1.020 ms with unchanged allocation counters/cardinality/hash;
  startup bytes, node/cache counts, payload and rounded live figures are unchanged.
  Tree warm samples are 0.024/0.025 ms; process peak is 41.39 MB in this sample.
  Retained-memory parity against the pilot remains unproven.
  The AST inventory corrects the earlier grep count: that count omitted every
  shorthand `~parameters` argument. Before this batch there were 83 total sites
  (55 explicit + 28 shorthand); now **76 remain (52 explicit + 24 shorthand)**.
  This supersedes earlier total-key estimates; the historical grep reductions
  counted explicit sites only. The inventory examines every `Node.Private.make`
  argument in all four shared declaration files, including the dynamic shared
  Polywire/Sweep Circle constructor. A shorthand edit caught by typecheck is
  restored before validation; the codemod now validates its edit count before
  writing. RDK and existing assertions are unchanged; whitespace checks pass.

- Step 6 removes seven more duplicate keys with no existing assertion edits:
  UV Auto Seam, Attribute Transfer All, Attribute Transfer Surface, Attribute Copy,
  Group by Bounds, Group Ordered and Group by Normal. Six compiler-reported dead
  local formatters and five support formatters with no remaining callers are
  removed by OCaml AST codemods. Declaration typed/factory parity, every-field cache,
  typecheck, catalog and SOP UI checks pass. Broad tests retain exactly the same
  six pending failures. All 21 stock/host-aware workspaces pass. Nonempty hand-written
  key sites decrease 62→55. The serial 21-repeat session sample is 1.016 ms with
  unchanged 3,023,896 allocated bytes and geometry cardinality/hash. Startup live
  bytes, workspace node/cache counts, payload and rounded live figures are unchanged;
  Tree warm samples are 0.025 ms. Process peak is 49.12 MB in this sample versus
  43.42 MB in the previous checkpoint; retained-memory parity is still unproven,
  and these samples do not waive that requirement. RDK and existing assertions
  are unchanged; whitespace checks pass. Git-write access remains required for
  the requested commits and dev merge.

- Step 6 removes Enumerate's redundant hand-written key, its local storage
  formatter and the now-unused shared mode formatter through the OCaml codemods.
  The existing piece-mode diagnostic strings are already generated from the
  declared schema. An isolated runner copies the original identity, integer/text
  storage, geometry and missing-piece assertions unchanged; all pass. Declaration,
  typecheck, catalog and SOP UI checks pass; the run retains the three pending
  refusal assertions. Nonempty hand-written key sites decrease 63→62. The temporary
  runner is removed after validation; no existing assertion or RDK source changes.
  Broad `@runtest` retains the same six pending failures (three refusal assertions,
  two row snapshots and the hard-coded focus ID). Whitespace checks pass. Staging
  is retried and denied at `.git/index.lock`; commits/dev merge remain blocked.

- Step 6 removes seven further duplicate keys through the OCaml AST codemod:
  Material, Delete Attributes, Connectivity, UV Transform, UV Project, Attribute
  Blur and Promote Attributes. Their existing assertions do not pin legacy text;
  existing default/nondefault typed/factory and every-field cache audits pass
  without assertion edits. The compiler identifies UV Project's four dead range
  aliases; those and six dead support formatters are removed mechanically.
  Declaration/UI/catalog/workspace checks pass. Broad tests retain the three
  pending refusal assertions, two pending row snapshots and the pending hard-coded
  focus-ID assertion. All 21 stock/host-aware workspaces pass. The serial session
  sample is 1.029 ms with unchanged 3,023,896 allocated bytes and geometry hash;
  workspace counts, payload, startup bytes and rounded live figures are unchanged.
  Tree warm samples remain 0.024 ms. Nonempty hand-written key sites decrease
  70→63. RDK, the manifest and existing assertions are unchanged. Staging is
  retried and still denied at `.git/index.lock`; commits/dev merge remain blocked.

- The completion audit compares the pilot and current manifests structurally
  using an isolated OCaml/Flow reader. Language kinds increase 172→173. Existing
  fields, choice labels, defaults, numeric kinds/ranges, labels/folders/primary
  flags/units, aliases, outputs and input-slot prefixes are retained. The three
  Set Vector components gain the declared `value` vector group; their previous
  empty vector metadata is an addition, not a removed group. No incompatible
  removal/default/slot change is found. This verifies manifest compatibility,
  not overall completion: 70 nonempty hand-written parameter-text sites remain
  in the four shared declaration files, and Switch is still in the catalog.
  Removed PPX function/argument/default/presence annotations do not occur in
  the declarations or PPX. Pending contract/assertion decisions, duplicate-key
  cleanup, retained-memory parity, native smoke and commit/dev-merge access
  remain required; none is waived by the passing manifest audit.

- The workspace benchmark now reports startup live bytes and factory/field
  counts before and after creating the workspace catalog. The same reporter in
  the isolated pilot measures 159 factories / 1,689 fields, 910,488 live bytes
  before the catalog and 1,186,000 after. Current measurements are 160 factories /
  1,863 fields, 974,320 bytes before and 1,272,880 after: a startup increase of
  63,832 bytes and a total post-catalog difference of 86,880 bytes. Thus most of
  the previously observed 0.09–0.18 MB workspace difference already exists before
  cooking, alongside the added fields and factory; it is not additional retained
  geometry payload. A smaller per-workspace difference remains and the no-regression
  requirement is not yet proven. Tree's warm 0.024 ms sample confirms the reuse
  improvement (fresh pilot samples 0.142/0.150 ms). No lazy diagnostic-text cache
  is added: graph/document inspection already reads that text, so delaying it
  would not establish a retained-memory improvement. Node's API comment now
  accurately describes intrinsic identity plus schema key rather than inspection
  text. Remaining duplicate keys and the memory audit remain outstanding.

- The performance audit now has a fresh isolated pilot baseline at
  `ff1f31a8adb1c4cd28f07b5aa6d673f6b5d9d9b9`, built from a Git archive in `/tmp`.
  Only the workspace benchmark's live/heap/peak reporting is copied into it;
  the library code is unchanged. Its serial session reproduces 3,024,088 allocated
  bytes and the original geometry hash. On the identical 12 workspace fixtures,
  current retained node/cache counts and payload match, but rounded live memory
  is 0.09–0.18 MB above this baseline; that increase remains under audit.
  Tree's slowdown is traced to compiling unchanged, fully connected repeated
  inputs through the factory on every cook. `Edit_graph.rebuild` now reuses its
  stored node when physical inputs match and the original slots are connected;
  sparse optional/rest slots retain their factory rebuild path. A new physical
  reuse regression and all existing editable-graph/declaration/workspace-cook
  checks pass. Tree cold/warm samples improve from 0.688/0.450 to 0.338/0.023 ms
  at capacity 512 (pilot 0.499/0.145); at capacity 32, 0.706/0.420 becomes
  0.370/0.024 ms (pilot 0.500/0.147). The session sample is 1.023 ms with unchanged
  3,023,896 allocated bytes and geometry hash. Workspace counts/payload/live
  figures are unchanged by the reuse fix. RDK and existing assertions are unchanged.
  Broad validation exposes two hard-coded workspace-shell focus-ID assertions
  (336 becomes 330 because six needless node allocations are gone). The focus
  and filter behavior is correct; updating those assertions to derive the node
  ID from the document awaits the requested exception. This failure remains
  visible rather than preserving dummy allocations.

- Step 6 removes the six attribute setters' redundant hand-written keys through
  an OCaml AST codemod: Set Float, Set Integer, Set Vector, Set Orientation,
  Set Transform and Set Color now use only their declared schema for parameter
  text/cache identity. Existing default/nondefault typed/factory comparisons at
  one/four domains and every-field cache checks pass without assertion edits.
  Typecheck, declaration, SOP UI/catalog and build checks pass; the broad run
  retains the three pending refusal assertions. All 21 stock/host-aware workspaces
  pass. The serial session sample is 1.033 ms with unchanged 3,023,896 allocated
  bytes, promotion/major counters and geometry cardinality/hash. Workspace node
  counts, retention/evictions, payload and rounded live memory (2.18–4.56 MB)
  remain unchanged. RDK and the manifest are unchanged; whitespace checks pass.
  Other hand-written diagnostic keys still need cleanup and the requested
  assertion exception remains pending. Counts remain 158 migrated / 150 verified.

- The workspace-shell Size-row failure is fixed without changing its assertion.
  Unowned status-strip clicks were forwarded to the viewport by `Ui.input ~owner`,
  producing a background pick that cleared the graph selection between menu
  picks. Explicit owner routing now excludes unowned pointer events while default
  input still returns them; held buttons and motion follow the same ownership.
  No second hit-test path is introduced. The new focused regression, existing
  capture/popup checks, PXUI tests and workspace-shell/scene-sync/text-pane/source/
  editor-logic suites pass. Temporary traces are removed; the event contract is
  documented. Default autosaves still report sandbox write denials, but those
  did not cause this assertion. The subsequent broad typecheck/build/API/runtest
  run retains five failures: the three pending refusal assertions and two pending
  projection/pane-count snapshots. The workspace-shell failure is gone. RDK and
  existing test assertions are unchanged.

- The full operations benchmark now completes at one and four domains with
  reduced configurable workloads and the normal UV solver budget. All 143 rows
  have identical input counts, cardinalities and hashes across domains. This is
  a full-path execution/exactness check with one repeat, not a timing baseline:
  columns/rows 16, curve points 129, attributes 32, scatter 128, box/platonic/fill
  batches 16, grain 16384 and UV iterations 500. `@doc` succeeds (with documentation
  reference warnings, including unchanged RDK interfaces). A current `@smoke`
  run fails at SDL startup because the sandbox video driver exposes no displays;
  no renderer fallback is added. The native shipping gate therefore remains
  unverified, alongside the pending contract decisions and Git-write limitation.
  A current window-free `@runtest` run reports six failures: the three pending
  refusal assertions, two pending projection/pane count snapshots, and the
  workspace-shell Size-row gesture. Isolating `RAYS_EDITOR_PREFERENCES` does not
  resolve that gesture failure; denied default autosaves are also reported and
  must not be mistaken for proof of its cause. The shell failure needs diagnosis.

- The UV benchmark setup failure is diagnosed: a reduced two-iteration budget
  cannot converge on the fixed 200×200 grid. Flatten now reports the structured
  RDK error instead of hiding it behind `benchmark setup failed`; the insufficient
  budget still fails correctly. At the normal 500-iteration budget, all seven UV
  cases pass three repeats at one and four domains, with matching cardinalities
  and hashes. Their CSV input counts now report the actual fixed fixtures (40,401
  grid points and 130,562 sphere points), rather than the unrelated terrain size.
  Grid flatten medians are 858.554/384.591 ms at one/four domains; relax is
  39.762/37.026 ms. These are verification samples, not before/after kernel speed
  claims: RDK is unchanged. The benchmark executable builds and whitespace checks
  pass. The full operations benchmark and final shipping audit remain.

- The serial session allocation regression is removed by returning the empty
  context projection directly for static dependencies. This avoids allocating
  an unused buffer on each static-node cook; dependent projections retain their
  encoding. A new declaration-audit check covers all 32 dependency combinations.
  Two serial 21-repeat runs (128×128, one domain, grain 16384) measure 1.015 and
  1.026 ms, both allocating 3,023,896 bytes: 624 fewer than the previous checkpoint
  and 192 fewer than the original 3,024,088-byte baseline. Promotion/major bytes
  remain 0/2,949,392; geometry cardinality/hash are unchanged. All 12 workspace
  fixtures retain node counts, cache retention/evictions and payload, with live
  memory 2.18–4.56 MB. Typecheck and the declaration audit pass; broader checks
  retain the three pending refusal assertions. All 21 stock/host-aware workspaces
  pass. This resolves the measured serial allocation increase; the full final
  performance/shipping audit remains. RDK is unchanged.

- Step 6's compiler-driven dead-export audit identified three obsolete support
  formatters (`color_key`, `grid_counts_key`, `grid_orientation_key`); an OCaml
  AST codemod removes them. The declaration audit and typecheck pass; broader
  validation retains the three pending refusal assertions. All 21 stock or
  host-aware workspaces pass. After the dynamic-schema change and this cleanup,
  the serial session benchmark is 1.019 ms, with unchanged 3,024,520 allocated
  bytes, promotion/major counters, cardinality and hash. Workspace node counts,
  cache retention/evictions and payload remain unchanged, with live memory
  2.18–4.56 MB. The original allocation increase remains under audit. A renewed
  staging attempt still fails because `.git/index.lock` cannot be created;
  post-pilot work remains uncommitted and unmerged.

- Switch's dynamic-schema foundation is verified. Generated builders accept
  an optional schema callback that derives input labels from the actual node,
  evaluates the operator once, and refreshes on edits and rewiring. Regression
  checks cover integer choices and ports, declared defaults, constructor/factory
  parity, logical identity, invalid selections, selective cooking at one/four
  domains, and cache reuse after label-only edits. Switch's existing selector
  now retains Lisp's default index 0 even when constructed with another selection.
  Typecheck, PPX, SOP UI/catalog, declaration and workspace checks pass; broader
  checks retain the three pending refusal assertions. The fixed a/b ports remain
  pending the requested port-contract decision. Counts remain 158 migrated and
  150 fully verified; RDK is unchanged.

- Step 6's constructor cleanup now derives every migrated typed signature
  from its node key, record order, vector groups and input slots. The separate
  `sop.fn`, `sop.args`, `sop.arg_default` and argument-presence mechanisms are
  removed from the PPX and declarations. A unit record derives an input-only
  constructor; a generator gets the final unit argument; fixed/optional/rest
  inputs retain their established layouts. PPX inference checks, generated
  optional-rest constructor checks, SOP UI checks, declaration/cook audits,
  workspace cooks, typecheck/API and `@all` pass. The reviewed API diff puts
  optional labels in record order, uses Lisp's `axis`, `set` and `add` vector
  names, and makes UV Sphere's existing radius vector one typed argument.
  The interface/caller edits are OCaml AST codemods; RDK call sites are untouched.
  Two final presence-based default drifts are removed: Group Random and Noise
  Displace now expose their existing `context_seed` field, defaulting to explicit
  seed 0 as Lisp does. Three old seed-omitting callers explicitly retain context
  seeding; new omitted-default and explicit-flag/seed factory parity checks pass.
  The obsolete catalog `Shared` module and `tools/sop_merge` are deleted.
  No migration test is cut. The API diff is reviewed/promoted and all 21 stock
  or host-aware workspaces still pass. The serial session sample is 1.027 ms
  with unchanged 3,024,520 allocated bytes and cardinality/hash. Workspace
  node/cache/payload figures and rounded live memory (2.18–4.56 MB) remain
  unchanged. The counts remain 158 migrated / 150 fully verified. Switch,
  hand-written diagnostic/key cleanup, the pending test-contract decisions,
  final performance audit and shipping validation remain. RDK is unchanged;
  whitespace checks pass.

- Blend Shapes now shares one declaration. Its existing fields, defaults and
  five ports remain; the additive optional repeated `shapes` port supports
  unlimited targets. A one-column `weights` table gives finite signed extra
  weights (missing rows use zero). `shape_masks` rows give a one-based slot,
  mask attribute and source (`first`/`shape`); blank cells inherit global
  controls. Fixed slots keep indices 1–4 through disconnects; connected extras
  start at 5. Unused rows remain available for later connections. Five typed
  calls and the finite-weight helper assertion are mechanically flattened;
  shaped calls explicitly retain their old unset global mask and shape-source
  defaults. The old descriptor and hand keys are removed. The weight decoder
  is shared with Composite. The empty catalog `attributes.ml` is deleted.
  1,176 native comparisons pass across both modes, all three masking policies,
  both mask sources, independent overrides and escaped names, signed/zero
  weights, empty/sparse/unlimited targets, integer/text matching, partial-ID
  targets of different sizes, missing attributes and large parallel cooks.
  Typed/factory one/four-domain parity, every-field cache checks and constructor/
  inspector validation pass. Positional/named Lisp rest lists cook identically;
  extra-weight and mask tables project/edit through Flow_edit with stable IDs.
  Typecheck/API, declaration, catalog, workspace and `@all` checks pass; intended
  flat API and additive manifest diffs are reviewed/promoted. The old empty-list
  identity and diagnostic-string assertions remain intact pending the requested
  exception, so the fully verified count remains 150. The count is 158/159;
  only Switch remains. All 21 stock or host-aware workspaces pass. The serial
  session sample is 1.039 ms, with unchanged 3,024,520 allocated bytes and
  cardinality/hash. Workspace node/cache/payload figures remain unchanged;
  live memory is 2.18–4.56 MB. Final performance cleanup remains outstanding.
  RDK is unchanged; whitespace checks pass.

- Attribute Composite now shares one declaration, preserving its five original
  ports and all Lisp fields/defaults while adding an optional repeated `layers`
  port and a one-column `weights` table. Four fixed slots keep their own weights;
  additional connected layers use the table in order, missing rows default to 1,
  and unused rows remain available for later connections. Finite signed weights
  are supported. Patterns and encoded weights fail at construction; blank alpha
  disables masking as in Lisp. Four typed calls and the finite-weight helper
  assertion are mechanically flattened; the old descriptor and hand key are
  removed. 611 native comparisons pass across all five operations, all owners,
  Float/Float2/Float3/Float4 storage, zero/signed weights, empty/sparse/unlimited
  layers, alpha controls and distinct input ordering. Typed/factory one/four-domain
  parity includes large parallel cooks. Every-field cache probes and constructor/
  inspector refusals pass. Positional and named Lisp rest lists cook identically;
  their weight rows project and edit through Flow_edit with stable identity.
  Typecheck/API, declaration, workspace and `@all` checks pass. The additive
  manifest and intended flat API diff are reviewed/promoted. The old diagnostic
  spelling assertion is intact pending the requested owner exception, so the
  fully verified count stays 150. The count is now 157/159; Switch and Blend
  Shapes remain. All 21 workspaces pass stock or host-aware checks. The serial
  session sample is 1.024 ms with unchanged 3,024,520 allocated bytes and
  cardinality/hash; final performance cleanup remains required. RDK is unchanged.

- The repeated-input path now supports a fixed required/optional prefix and a
  final Optional_rest slot with zero or more extras. PPX declarations select
  it by including the final rest index in `sop.node_optional`. Typed calls,
  sparse factory inputs and parameter rebuilds preserve the fixed slot layout
  while filtering disconnected extras in order. Flow checking, callable-kind
  slot signatures, manifest round trips, lowering, projection and Flow_edit
  use that same contract. Geometry lists and `map` work; named rest lists are
  editable rows, and connecting the add row pads missing fixed slots with nil.
  Required Rest behavior is unchanged. Focused PPX, editor, generated-constructor,
  Flow and workspace checks pass, including exact one/three-domain cooks and
  stable IDs after connect/disconnect. Typecheck/API and `@all` builds pass;
  the public input-requirement and callable-signature API changes are reviewed
  and promoted. This prepares the additive unbounded-input migration for Blend
  Shapes and Attribute Composite without replacing their existing fixed ports.
  It does not yet migrate those declarations: the count remains 156/159,
  with three remaining. Broad tests retain the pending refusal assertions.
  The workspace benchmark retains its node/cache/payload figures and rounded
  live-memory figures (2.18–4.55 MB). RDK is unchanged; whitespace checks pass.

- Attribute Transfer now shares one declaration. Its existing Lisp fields,
  ports and defaults remain; exact-name table controls and Auto distance are
  additive fields. Nine typed calls are codemodded, preserving omitted
  unbounded distance and Smoothstep falloff explicitly and flattening the
  inverse/kernel records and four exact-name lists. The old kernel diagnostic
  text remains. 948 native parity cases pass across all owners, five sampling
  modes, three falloffs, bounded/unbounded distance, blend bands, miss policies,
  exact/pattern selection, source-vertex all/any selection and escaped names.
  Typed/factory one/four-domain parity, every-field cache probes and construction/
  inspector refusal checks pass. The API and three-field additive manifest
  diff are reviewed/promoted; typecheck, API, catalog and `@all` builds pass.
  Lisp projection/Flow_edit checks pass before the pending row snapshots;
  all 21 workspaces still pass their stock or host-aware checks. The old
  exact/pattern refusal assertion remains pending, so the fully verified count
  stays 150. Three original declarations remain: Switch, Blend Shapes and
  Attribute Composite. The serial session sample is 1.022 ms with unchanged
  3,024,520 allocated bytes and cardinality/hash. Workspace node/cache/payload
  figures are unchanged; live memory is 2.18–4.55 MB. Final performance cleanup
  remains required. RDK is unchanged and whitespace checks pass.

- Attribute Interpolate now uses one declaration with flat driver, computed
  array and escaped attribute-rule fields. Its Lisp manifest and defaults are
  unchanged. Five typed calls are codemodded, explicitly retaining the old
  driver attribute spellings, normalization and threshold defaults. The audit
  passes 821 native parity cases across all destination owners, four drivers,
  signed scales, normalization, thresholds, blend/miss policies, computed
  arrays, exact/pattern selections, attribute/group patterns and escaped names.
  Typed/factory one/four-domain parity, every-field cache probes, construction
  and inspector validation pass. Lisp projection/Flow_edit checks pass before
  the pending row snapshots. Invalid driver/owner combinations, duplicate
  targets and invalid computed-array controls fail at construction. An old
  exact/pattern refusal assertion remains intact pending the owner decision,
  so the fully verified count stays 150. The flat API is reviewed/promoted;
  typecheck, API, catalog and `@all` builds pass. Broad tests retain the prior
  pending assertions. Four original declarations remain: Switch, Blend Shapes,
  Attribute Composite and Attribute Transfer. The serial session sample is
  1.022 ms with unchanged 3,024,520 allocated bytes and cardinality/hash.
  Workspace node/cache/payload and live-memory figures match the preceding
  sample. Final performance cleanup remains required; RDK is unchanged.

- All 21 checked-in `.rays` files pass loading/checking with their actual
  catalogs: 19 through `rays-lisp check`, SOP Gallery through its existing
  headless `--check-all`, and Voxel Wall through its new `--check-workspace`
  runtest. The gallery cooks every entry and prepares its render mesh; the
  wall cooks to 24 prototype points and 2,160 packed instances without opening
  a window. Both host aliases pass. Cube Cage retains its explicitly allowed
  soft-range warning. This closes the custom-catalog workspace verification
  gap; final shipping and performance checks remain outstanding.

- Attribute Randomize is moved to one declaration, adding the three custom
  distribution choices, ramp/numeric/text table fields, explicit typed selection
  fields and per-component limit fields while retaining existing Lisp fields
  and defaults. Fifteen typed calls are codemodded: omitted legacy seeds retain
  context-seed mode explicitly; numeric distributions, ramps, weighted tables,
  selections and limits become flat arguments. All tables reuse the existing
  escaped tab/newline codec. The construction validator checks distribution
  constraints, including isotropic multidimensional Cauchy scales. The legacy
  group/typed-selection exclusivity assertion is preserved through flat fields.
  Fraction sampling follows Lisp and ignores seed controls; updating its old
  refusal assertion awaits owner approval. More than 3,000 distribution cases,
  per-field cache checks, construction refusals and Lisp projection/Flow_edit
  checks pass. The expanded audit covers dimensions, operations, selections,
  scalar/vector limits, text tables, position writes and context seeds, with
  native parity and one/four-domain checks. Randomize awaits the old assertion
  update before it is counted fully verified.
  The additive manifest and flat API are reviewed/promoted; typecheck/API and
  catalog checks pass with the proposed Vec3 inventory count 101 (owner decision
  pending). Broader checks retain the three pending refusal assertions and
  projection row snapshots. Five original declarations remain to migrate;
  the fully verified count stays 150. The serial session benchmark is 1.025 ms
  with unchanged 3,024,520 allocated bytes and cardinality/hash. Workspace node,
  retained-cache and payload figures are unchanged. The benchmark's former
  "heap" figure was the process-wide high-water mark (`top_heap_words`), not
  retained memory. It now reports live/current/peak memory after collection
  outside the timed region: live 2.18–4.55 MB, current heap 3.86–6.47 MB and
  peak 41–43 MB. No pre-migration live-memory baseline exists yet; final
  performance cleanup still requires that comparison. RDK is unchanged and
  whitespace checks pass.

- Attribute Noise now derives optional flat sampling/range/seed controls and
  grouped Vec3 bounds/frequency/offset from its existing Lisp record. Defaults
  remain Point/noise/Float/Position/Positive with explicit seed zero; the
  context-seed switch retains stable label mixing and its Seed dependency.
  Its one typed caller is codemodded without changing its explicit seed or
  geometry. 1,281 native/typed/factory cases at one/four domains cover owners,
  output kinds, sampling, ranges, supported operations, selected groups,
  existing targets, position writes, boundaries and context seeds. Per-field
  cache probes pass in explicit and context-seed modes. Context changes hit
  with explicit seeds and change output with context seeds. Construction and
  inspector validation refuse invalid numeric controls and incompatible
  quaternion operations while preserving set-initial behavior for P.
  The manifest is unchanged; reviewed flat API additions are promoted.
  Typecheck/API, declaration, procedural and catalog tests pass; broader
  checks still retain the pending Boolean Detect/Triangulate 2D assertions.
  The serial session benchmark is 1.044 ms with 3,024,520 allocated bytes,
  unchanged cardinality/hash. Workspace node/cache/payload figures remain
  unchanged (heap 35–38 MB). RDK and whitespace checks are unchanged/clean.
  Six original declarations remain to migrate.

- Transform now shares one declaration for TRS and Matrix modes. Existing Lisp
  defaults and fields remain; flat matrix coefficients, orders, shear, pivots,
  inversion and group selection are added. The 28 typed callers are codemodded,
  retaining matrix evaluations and exact coefficients. Translation and X-rotation
  constructors only spell the coefficients that differ from identity; general
  matrices spell all sixteen. The TRS alias shares the generated constructor.
  1,232 native/typed/factory cases at one/four domains, per-field cache checks,
  construction/inspector refusal checks and the legacy Transform tests pass.
  Lisp projection and Flow_edit checks for matrix/shear/pivot pass before the
  existing fixture row-count mismatch; updating those snapshots and the catalog
  Vec3 inventory count (97 to 99) awaits owner approval under the test restriction.
  The additive manifest and public API are reviewed/promoted. Typecheck/API
  checks pass. Broader checks still retain the pending Boolean Detect and
  Triangulate 2D refusal assertions. The serial session benchmark is 1.030 ms,
  allocating 3,024,520 bytes with unchanged cardinality/hash. Workspace node,
  cache-retention and payload figures are unchanged (heap 40–42 MB). RDK is
  unchanged and whitespace checks pass. Seven original declarations remain.
  Checking all 21 checked-in `.rays` files passes 19. The gallery and voxel
  wall still require their host-owned custom factories; the generic checker
  reports unknown custom kinds. Three documents mark their intentional values
  outside soft slider ranges with the existing `^:allow-warnings` metadata,
  preserving their numeric values and geometry. Host-aware verification remains
  required for the two custom catalogs.

- Switch incremental preparation adds Lisp's integer `:input` field while
  retaining its existing fixed a/b ports pending the owner decision. The
  inspector retains dynamic branch labels through an integer-index choice;
  values, drives and cache keys use integers and survive label changes. The
  focused typecheck, shared parameter, shell UI, catalog and API checks pass;
  projection/Flow_edit regressions
  pass before the existing fixture row-count mismatch stops that suite.
  The additive Switch field and parameter API are reviewed/promoted. This
  preparation does not increase the migrated/verified declaration counts.

- Incremental cleanup separates intrinsic operator parameters from schema
  display text in session cache identity. `Node.parameterize` retains intrinsic
  parameters before attaching fallback display text, and the session reads that
  intrinsic identity plus the complete schema cook key. A regression proves
  custom-wrapped snapshots with equal logical/schema identities still miss for
  distinct data and hit for repeated data. Grid and Color by Height's redundant
  handwritten keys are removed; per-field parity/cache checks remain green.
  The obsolete Shapes.Merge wrapper is removed, retaining its exported create
  adapter at registration. Unused catalog helpers are pruned; Shared is now
  122 lines. Procedural/declaration/catalog checks and typecheck/API checks pass;
  the reviewed Node.Private API addition is promoted and the design note updated.
  The manifest and RDK are unchanged. Broader validation retains the two pending
  refusal assertions. The serial session benchmark is 1.035 ms with 3,024,520
  allocated bytes, 544 fewer than the previous checkpoint and 432 more than
  the original baseline. Cardinality/hash and workspace node/cache/payload
  figures are unchanged. Further key cleanup/performance work remains required.
- Quaternion Noise derives optional flat owner/name/seed controls, grouped
  frequency and the existing text-encoded location/range contract. The catalog
  create helper remains a thin adapter that encodes its structured arguments.
  Existing encoding helpers move to Support; unused encoded-field templates
  are removed. All 252 owner/selection/location/range/seed/octave combinations
  match native cooks with one/four-domain typed/factory parity. Defaults,
  unset groups, explicit-seed dependencies and every cache field are checked.
  Shared construction/inspector validation covers names, detail selection,
  frequency/octaves, malformed encodings and finite ordered four-component
  range bounds. The fixed quaternion output cannot replace point P.
  Declaration/parity/catalog tests and typecheck/API checks pass; the reviewed
  API addition is promoted. The Lisp manifest and RDK are unchanged. Broader
  validation retains the two pending Boolean Detect/Triangulate 2D refusal
  assertions. The serial session benchmark is 1.038 ms with 3,025,064 allocated
  bytes and unchanged cardinality/hash. All workspace node/cache/payload
  figures remain unchanged.
- PolyWire derives flat segment/UV ranges, enable toggles and optional
  scalar/text controls. Sweep Circle uses the same record, generated typed
  arguments and cook while retaining its runtime identity and default label;
  it now has a Lisp factory. The manifest adds that entry and two U/V range
  toggles (default true), preserving the former explicit-range Lisp behavior.
  Thirteen calls are codemodded, pinning omitted divisions, ranges, valence
  and cap names so the kernel's legacy omitted-range path remains available.
  The catalog's mechanical count changes to 160 for the added shared entry.
  All 1,028 alias/enable/joint/smoothing/UV/cap/attribute-override combinations
  match native cooks with one/four-domain typed/factory parity. Defaults, blank
  names, distinct identities/labels and every cache field are checked. Shared
  construction/inspector validation covers numeric values, radius, divisions,
  segments, valence, active segment ordering and buckling-attribute dependency.
  Existing PolyWire and declaration/parity/catalog tests pass. Typecheck/API
  checks pass and the reviewed API/additive manifest changes are promoted.
  The now-empty catalog topology module is removed and the design note updated.
  RDK is unchanged. Broader validation retains the two pending Boolean Detect/
  Triangulate 2D refusal assertions. The first serial session sample is 1.172 ms
  with 3,025,064 allocated bytes and unchanged cardinality/hash; a repeat is
  1.033 ms with the same allocation/hash. Workspace node/cache/payload
  figures remain unchanged.
- Triangulate 2D derives flat projection choices, plane vectors, point-
  attribute and refinement toggles, retaining all Lisp metadata/defaults.
  Fourteen calls are codemodded: projection choices and seed spelling change,
  and explicit area controls enable the corresponding toggle. The two minimum-
  angle default expressions have identical float bits; no override is retained.
  All 448 valid projection/refinement/constraint/cleanup combinations match
  native cooks with one/four-domain typed/factory parity. Defaults, blank names
  and every cache field are checked. Construction/inspector validation covers
  finite values, nonzero active plane normals, active attribute names and
  refinement bounds. Typecheck/API checks pass; the reviewed API change is
  promoted and the Lisp manifest/RDK are unchanged. The declaration/parity
  tests pass, while the existing blank-point-group refusal assertion awaits
  owner approval to follow Lisp; broader validation also retains Boolean
  Detect's pending failure. The serial session benchmark is 1.091 ms with
  3,025,064 allocated bytes and unchanged cardinality/hash. Workspace node,
  cache-retention and payload figures are unchanged.
- Duplicate derives its existing 16 matrix fields as flat typed arguments,
  retaining Lisp metadata/defaults and its exported catalog create adapter.
  Five callers are codemodded, preserving their translations. All 240 matrix/
  copy-count/cumulative/selection/group-output combinations match native cooks
  with one/four-domain typed/factory parity, including general projective
  matrices. Defaults, blank names and every cache field are checked. Shared
  construction/inspector validation refuses nonfinite matrix entries and copy
  counts outside the nonnegative array limit. Existing Duplicate tests and
  declaration/parity tests pass; typecheck/API checks pass and the reviewed API
  change is promoted. The Lisp manifest and RDK are unchanged. Broader checks
  still stop at Boolean Detect's pending conflicting refusal assertion.
  The serial session benchmark is 1.033 ms with 3,025,064 allocated bytes and
  unchanged cardinality/hash. All workspace node/cache/payload figures remain
  unchanged.
- Boolean Detect derives flat optional output/group names and positional
  source/optional-collision inputs with the existing Lisp defaults. Nine typed
  calls are codemodded, explicitly preserving their prior self-output choices.
  All 476 valid output-mask/collision/coplanar/group combinations match native
  cooks with one/four-domain typed/factory parity. Defaults, blank names,
  inactive collision fields and every cache field are checked. Construction
  and inspector validation covers tolerances, missing outputs and duplicate
  active output names. The API diff is reviewed and promoted; the Lisp manifest
  is unchanged. The declaration/parity tests pass, but the broader validation
  stops at the existing refusal assertion for a disconnected collision group;
  changing that assertion awaits the owner's test-edit decision. The serial
  session benchmark is 1.028 ms with 3,025,064 allocated bytes and unchanged
  cardinality/hash. Workspace cache/node/payload figures are unchanged.
- Boolean derives optional flat closed-output/group controls and positional
  left/right inputs, retaining Lisp metadata/defaults. Six typed calls are
  codemodded; the exported catalog create helper remains a thin adapter.
  All 348 valid operation/treatment/seam/polygon/conflict/closed/resolution/
  cleanup combinations match native cooks with one/four-domain typed/factory
  parity. The fixture omits point normals so Reject can produce geometry
  without a legitimate payload conflict. Defaults, unset shatter groups,
  inactive duplicate groups and every cache field are checked. Shared
  construction/inspector validation covers tolerances, cleanup batches,
  duplicate shatter names and Shatter's two-solid-operand requirement.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  the reviewed API change is promoted and the manifest is unchanged. RDK is
  unchanged. The serial session benchmark is 1.029 ms with 3,025,064 allocated
  bytes and unchanged cardinality/hash. All 12 workspace fixtures retain node
  counts, cache retention and payload (heap 37–39 MB).
- Subdivide derives flat crack/bias controls and positional source/optional-
  crease inputs. Lisp gains Explicit/Auto crease weighting, retaining the
  existing explicit default. All 42 typed callers are codemodded with their
  five differing defaults preserved; omitted weights select Auto, explicit
  weights remain explicit. The nonfinite all-edge assertion now checks
  construction refusal under the owner's consistent-validation approval.
  All 912 scheme/crack/crease/interpolation/hole/normal combinations match
  native cooks with one/four-domain typed/factory parity. Auto crease fixtures
  share the source topology, as the kernel requires. Defaults, unset names,
  every cache field and construction/inspector checks cover iteration, bias,
  weights, generated-group dependencies and missing crease inputs.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  reviewed API and additive manifest changes are promoted. RDK is unchanged.
  The serial session benchmark is 1.022 ms with 3,025,064 allocated bytes and
  unchanged cardinality/hash. All 12 workspace fixtures retain node counts,
  cache retention and payload (heap 42–44 MB).
- Fuse derives optional flat targeting/rule-table controls and positional
  source/optional-target inputs. Lisp gains attribute and group rule tables,
  using the existing Snap to Grid decoders. Nine typed callers are codemodded;
  their old tolerance and two cleanup defaults are explicitly preserved, and
  rule-list bindings become table strings. All 624 valid targeting/position/
  matching/retention/cleanup combinations match native cooks with one/four-
  domain typed/factory parity. Four degenerate-curve cleanup cases check
  cardinality, and a rule-table fixture checks changed payload/membership.
  Defaults, unset names, every cache field and construction/inspector checks
  cover tolerances, targeting/matching constraints, weighted reducers, rules,
  fused-point retention and unavailable external-target modification.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  reviewed API and additive manifest changes are promoted. RDK is unchanged.
  The serial session benchmark is 1.045 ms with 3,025,064 allocated bytes and
  unchanged cardinality/hash. All 12 workspace fixtures retain node counts,
  cache retention and payload (heap 44–45 MB).
- Intersection Analysis derives optional flat output names and positional
  source/optional-collision inputs, retaining Lisp metadata/defaults. Its nine
  existing calls are codemodded; the two owner-approved assertions now check
  blank output disabling and ignored disconnected collision groups. All 128
  output-mask/coplanar/group/input configurations match native cooks with
  one/four-domain typed/factory parity. Defaults, unset names, all cache fields
  (including the inactive collision group), duplicate/reserved output names
  and construction/inspector tolerance validation are checked. Procedural/
  catalog/API checks, the broader SOP catalog test and `@all` pass; the reviewed
  API change is promoted and the manifest is unchanged. RDK is unchanged.
  The serial session benchmark is 1.021 ms with 3,025,064 allocated bytes and
  unchanged cardinality/hash. All 12 workspace fixtures retain node counts,
  cache retention and payload (heap 39–41 MB).
- Boolean Fracture derives positional source/cutters inputs and retains its
  Boolean runtime operation identity. Lisp gains the existing point-conflict
  and assume-flat capabilities with kernel defaults. Its single typed caller
  is flattened; the exported catalog create helper remains a thin adapter.
  All 192 cutter-resolution/polygon/closed/conflict/flat/cleanup combinations
  match native cooks with one/four-domain typed/factory parity, including
  primitive piece identities. The fixture omits point normals so Reject can
  produce geometry without a legitimate corner-payload conflict. Every cache
  field and construction/inspector tolerance, batch-count and name validation
  is checked. Procedural/catalog/API checks, the broader SOP catalog test and
  `@all` pass; reviewed API and additive manifest changes are promoted. RDK
  is unchanged. The serial session benchmark is 1.028 ms with 3,025,064
  allocated bytes and unchanged cardinality/hash. All 12 workspace fixtures
  retain node counts, cache retention and payload (heap 39–40 MB).
- Point Replicate derives optional flat count/shape/noise controls, grouped
  vectors and positional source/optional-custom inputs, retaining Lisp
  metadata/defaults. Its two pipelines retain their behavior through the
  caller codemod; the noisy caller explicitly enables noise. All 576 shape/
  velocity/noise/quasi-stratification/input-retention/seed cases have one/four-
  domain typed/factory parity, with explicit seeds also matching native cooks.
  Every cache field, seed dependencies, zero count, unset names and inactive
  custom connections are checked. Connected custom geometry remains in the
  graph while inactive, allowing later shape edits to use it. Construction/
  inspector validation covers finite vectors/numbers, count/size/scale/noise
  bounds, ID/source metadata, patterns and missing custom geometry.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  the reviewed API change is promoted and the manifest is unchanged. RDK is
  unchanged. The serial session benchmark is 1.029 ms with 3,025,064 allocated
  bytes and unchanged cardinality/hash. All 12 workspace fixtures retain node
  counts, cache retention and payload (heap 38–40 MB).
- Poly Bevel derives optional flat shape/convexity controls and its distance
  default from Lisp, retaining all metadata. Two structured round-shape callers
  are flattened. The existing catalog create helper remains a thin adapter.
  All 64 shape/division/filter/clamp/normal/scale cases match native cooks with
  one/four-domain typed/factory parity; defaults, unset names and every cache
  field are checked. Construction/inspector validation refuses nonfinite and
  out-of-range distance, convexity, angle and division values. Procedural/
  catalog/API checks, the broader SOP catalog test and `@all` pass; the reviewed
  API change is promoted and the manifest is unchanged. RDK is unchanged.
  The serial session benchmark is 1.024 ms with 3,025,064 allocated bytes and
  unchanged cardinality/hash. All 12 workspace fixtures retain their node
  counts, cache retention and payload (heap 42–43 MB).
- Ray derives optional flat direction/selection controls and positional source/
  collision inputs, retaining Lisp metadata/defaults. Five typed callers are
  flattened while preserving their pipelines. All 576 method/direction/mode/
  surface/combine/sample/distance cases and four selection-owner cases match
  native cooks with one/four-domain typed/factory parity. Unset names, inactive
  vector controls and every cache field are checked. Construction/inspector
  validation covers finite and bounded distances, sample constraints, active
  direction controls, provenance pairing, output names and patterns. Procedural/
  catalog/API checks, the broader SOP catalog test and `@all` pass; the reviewed
  API change is promoted and the manifest is unchanged. RDK is unchanged.
  The serial session benchmark is 1.036 ms with 3,025,064 allocated bytes,
  unchanged cardinality/hash; workspace node counts, retention and payload
  remain unchanged across all 12 fixtures (heap 36–38 MB).
- Attribute Copy derives optional flat matching/rule-table controls and
  positional source/target inputs, retaining all Lisp metadata/defaults.
  Three structured rule callers become table strings, including the existing
  empty-rule refusal assertion. All 16 valid selection-owner/matching/position
  combinations match native cooks with one/four-domain typed/factory parity,
  copying four attribute owners with renamed payload and canonical position.
  Pattern precedence, unset groups and every cache field are checked; the
  rule probe uses a valid rewrite. Shared construction/inspector validation
  covers rule/table syntax, rewrites, active matching names, unsupported
  vertex value matching and group patterns. Procedural/catalog/API checks,
  the broader SOP catalog test and `@all` pass; the reviewed API change is
  promoted and the manifest is unchanged. RDK is unchanged.
- Attribute Transfer Surface derives optional flat attribute-table/falloff
  controls and positional source/target inputs. Lisp gains Explicit/Auto
  distance; existing fields/defaults remain, including Linear falloff. Two
  structured-list callers become Lisp table strings and explicitly retain
  Smoothstep; both input pairs become positional. All 72 target-owner/falloff/
  distance/unmatched/vertex-selection cases match native cooks with one/four-
  domain typed/factory parity. Pattern precedence, unset names/empty rules
  and every cache field are checked. Shared construction/inspector validation
  covers table shape, spatial owners, names/output conflicts, finite distance
  controls, bounded distance windows, bias and patterns. Procedural/catalog/API
  checks, the broader SOP catalog test and `@all` pass; reviewed API/additive
  manifest changes are promoted. RDK is unchanged.
- Boolean Seam derives positional left/right inputs and optional flat group
  names, retaining all Lisp metadata/defaults. Its single caller is flattened
  with explicit blank strings preserving omitted self groups. All 32 output/
  treatment/self-resolution combinations match native cooks with one/four-domain
  typed/factory parity; a separate nonempty coincident-area fixture also
  matches native. Unset groups, inactive duplicate names and every cache
  field are checked. Shared construction/inspector validation refuses duplicate
  active output names. Procedural/catalog/API checks, the broader SOP catalog
  test and `@all` pass; the reviewed API change is promoted and the manifest
  is unchanged. RDK is unchanged.
- Sweep derives positional backbone/profile inputs and optional flat names,
  retaining all Lisp metadata/defaults, including cap naming only when caps
  are enabled. Three callers lose labelled inputs/trailing unit; one optional
  UV payload becomes a string. All 480 valid connectivity/tangent/closure/
  payload/reversal/cap combinations match native cooks with one/four-domain
  typed/factory parity on mixed open/closed backbones and a closed profile.
  Four selection combinations also match native cooks. Unset cap/UV outputs
  and every cache field are checked. Construction validates finite transform
  controls, cap connectivity, NUL-free prefixes and reserved P output; invalid
  inspector writes are refused. Procedural/catalog/API checks, the broader
  SOP catalog test and `@all` pass; the reviewed API change is promoted and
  the manifest is unchanged. RDK is unchanged.
- Scatter derives optional flat count/density controls and its existing
  context-seed toggle, retaining all Lisp metadata/defaults. The single
  structured density caller is flattened; its explicit seed and 100,000-point
  weighted fixture remain unchanged. All 32 density-owner/enabled/context-seed/
  group-interpolation cases have one/four-domain typed/factory parity; all
  16 explicit-seed cases match native cooks with selected surface, transferred
  attributes/groups and provenance. Seed dependencies, zero count, unset names
  and every cache field are checked with valid provenance/pattern companions.
  Construction validates array limits, active scalar density names, copy
  patterns, interpolation requirements and paired/distinct/reserved provenance
  outputs; invalid inspector writes are refused. Procedural/catalog/API checks,
  the broader SOP catalog test and `@all` pass; the reviewed API change is
  promoted and the manifest is unchanged. RDK is unchanged.
- Soft Transform derives optional flat metric/selection/shear controls,
  retaining existing Lisp metadata/defaults and grouped TRS/pivot vectors.
  Two selection callers and one structured metric are flattened; the invalid
  transform assertion checks construction refusal. All 144 owner/metric/
  rolloff/falloff/inversion cases and 36 transform/rotation orders match
  native cooks with one/four-domain typed/factory parity, including advanced
  TRS/shear/pivot controls and falloff output. Unset names, raw mask with zero
  radius and every cache field are checked. Shared validation refuses
  non-finite controls/composed matrices, singular inversion, invalid radii,
  active metric names/storage and reserved P output; inspector edits use the
  same refusal. Procedural/catalog/API checks, the broader SOP catalog test
  and `@all` pass; the reviewed API change is promoted and the manifest is
  unchanged. RDK is unchanged.
- Poly Reduce derives optional flat target/ratio/count controls and the
  existing normal-deviation toggle, retaining all Lisp metadata/defaults.
  Two structured target callers are flattened; both explicit normal-deviation
  callers retain their enabled limits. All 16 target/boundary/position/limit
  combinations and four named-selection cases match native cooks with
  one/four-domain typed/factory parity. Ratio/count endpoints, unset groups
  and every cache field are checked. Construction validates finite controls,
  ratio bounds, nonnegative counts/equalization and normal deviation in
  [0, pi]; invalid inspector writes are refused. Procedural/catalog/API checks,
  the broader SOP catalog test and `@all` pass; the reviewed API change is
  promoted and the manifest is unchanged. RDK is unchanged.
- Poly Cut derives optional flat detection, attribute, crossing value and change
  threshold controls, retaining all Lisp metadata/defaults. Three structured
  crossing callers are flattened; the invalid P-crossing assertion checks
  construction refusal. All 24 element/strategy/detection/closure cases match
  native cooks and have one/four-domain typed/factory parity, reusing the
  existing curve fixture with point/edge selection. Unset groups and every
  cache field are checked. Construction validates finite controls, nonnegative
  thresholds, active attribute names, scalar crossing storage and positive
  change thresholds for cutting; invalid inspector writes are refused.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  the reviewed API change is promoted and the manifest is unchanged. RDK is unchanged.
- Point Generate derives optional flat total/per-point/probability controls,
  retaining all Lisp metadata/defaults and its existing context-seed toggle.
  Three structured mode callers are flattened; the caller without a seed
  explicitly retains context seeding. Twelve mode/seed/input-retention cases
  have one/four-domain typed/factory parity; the six explicit-seed cases also
  match native cooks with selection, count scaling, copied payload and generated
  provenance/grouping. Unset names/patterns and every cache field are checked,
  reusing the existing generation fixture. Construction validates counts,
  finite per-point controls, metadata/probability names and copy patterns;
  invalid inspector writes are refused. Procedural/catalog/API checks, the
  broader SOP catalog test and `@all` pass; the reviewed API change is promoted
  and the manifest is unchanged. RDK is unchanged.
- Extract Point from Curve derives optional flat cut, constant and primitive
  attribute fields, retaining all Lisp metadata/defaults. Two structured cut
  callers are flattened; distance attribute becomes optional with Lisp's
  default. The existing current-time dependency and recook tests remain.
  All 12 cut/copy/selection combinations match native cooks and have
  one/four-domain typed/factory parity, reusing the existing curve fixture.
  Unset diagnostics and every cache field are checked. Construction validates
  finite constants, distance/cut/output names, distinct diagnostic outputs and
  both attribute patterns; invalid inspector writes are refused.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  the reviewed API change is promoted and the manifest is unchanged. RDK is unchanged.
- Mountain derives optional flat controls and adds Explicit/Auto seeds,
  direction normalization and grouped offset to Lisp. Existing fields/defaults
  remain; the former required height uses Lisp's default. The context-seeded
  caller explicitly selects Auto, retaining the existing context-dependency
  regression. The catalog create entry aliases the derived constructor with
  all fields optional. Eight seed/normalization/normal-recomputation cases have
  one/four-domain typed/factory parity; the four explicit-seed cases also
  match native cooks with selection, direction, mask, height output and
  advanced fractal controls. Unset names and every cache field are checked.
  Construction validates finite controls, Lisp's nonnegative height/frequency,
  octaves, lacunarity, roughness and reserved height output; invalid inspector
  writes are refused. Procedural/catalog/API checks, the broader SOP catalog
  test and `@all` pass; reviewed API/additive manifest changes are promoted.
  The vector inventory includes the new offset group. RDK is unchanged.
- Tube derives optional flat controls and adds custom axis, rotation order
  and Explicit/Auto normals to Lisp. Existing fields/defaults remain; radii
  and height become optional with Lisp defaults. Six callers in two files
  preserve omitted normals/UV/cap groups and old cap consolidation, and
  flatten custom axes; the zero-axis assertion checks construction refusal.
  All 354 valid topology/normal/cap-sharing/tip combinations and 24 axis/
  rotation choices match native cooks and have one/four-domain typed/factory
  parity, including unset UV/cap names. Every cache field is checked using
  a blank cap group when disabling caps. Construction validates finite controls,
  nonnegative/scaled radii with at least one positive, positive height, axes,
  UV names, normal ownership, cap/group constraints and exact point/topology
  array limits; invalid inspector cap edits are refused. Procedural/catalog/API
  checks, the broader SOP catalog test and `@all` pass; reviewed API/additive
  manifest changes are promoted. The vector inventory includes the new axis
  group. RDK is unchanged.
- Torus derives optional flat controls and adds custom axis, rotation order
  and Explicit/Auto normals to Lisp. Existing fields/defaults remain; radii
  become optional with Lisp defaults. Four callers in two files preserve
  omitted normals/UV and flatten custom axes; the zero-axis assertion checks
  construction refusal. All 254 valid topology/normal/wrap/cap combinations
  and 24 axis/rotation choices match native cooks and have one/four-domain
  typed/factory parity, including unset UV. Every cache field is checked using
  valid companion controls for caps. Construction validates finite/positive
  radii and scale, finite nonzero angle spans, axes, UV names, normal ownership,
  cap/wrap/endpoint constraints and exact point/topology array limits; invalid
  inspector cap edits are refused. Procedural/catalog/API checks, the broader
  SOP catalog test and `@all` pass; reviewed API/additive manifest changes are
  promoted. The vector inventory includes the new axis group. RDK is unchanged.
- UV Sphere derives optional flat controls, retaining its existing radius
  vector group and scalar typed radius components. Lisp gains a custom axis
  group, six rotation orders, base radius, independent Explicit/Auto radius
  fallbacks and Explicit/Auto normals. Existing fields/defaults remain; the
  previous required typed radius is now optional `base_radius`. AST edits
  across four caller files preserve omitted radii, normals and UV output,
  rename the base radius and flatten custom axes. The zero-axis assertion
  now checks construction refusal. All 164 valid topology/normal/pole-sharing
  combinations, 24 axis/rotation choices and eight radius-fallback combinations
  match native cooks and have one/four-domain typed/factory parity, including
  unset UV output. Every cache field is checked. Construction validates finite
  controls, positive/scaled radii, nonzero axes, reserved UV names, normal
  ownership and exact point/topology array limits; invalid inspector writes
  are refused. Procedural/catalog/API checks, the broader SOP catalog test and
  `@all` pass; reviewed API/additive manifest changes are promoted. The vector
  inventory includes the new axis group. RDK is unchanged.
- Attribute Transfer All derives optional flat sampling/falloff controls and
  positional source/target inputs, reusing the transfer family's definitions.
  Lisp adds an Explicit/Auto distance choice; its existing point pattern,
  distance and Linear falloff defaults win. The three typed callers preserve
  omitted distance/falloff, flatten Uniform and explicitly blank the point
  pattern in the no-owner refusal test. All 60 sampling/falloff/distance/
  unmatched combinations and four individual owner patterns match native
  cooks with one/four-domain typed/factory parity. Every cache field is checked.
  Construction validates owner patterns, neighbor counts, finite controls,
  inverse power, safely squarable distances and bounded blend windows; invalid
  inspector writes are refused. Procedural/catalog/API checks, the broader
  SOP catalog test and `@all` pass; reviewed API/additive manifest changes are
  promoted. RDK is unchanged.
- Facet derives optional flat selection-owner, consolidation and cusp controls.
  The previous Lisp builder always passed both mutually exclusive consolidation
  distances and could not cook its default. Consolidation now defaults to None;
  Points/Normals retain both existing distance fields at zero. This is the
  stated default assumption while the optional owner preference is pending.
  Lisp gains all four selection owners and an Explicit/Auto cusp choice,
  retaining all existing fields/defaults. AST edits preserve all 15 typed
  callers' omitted cusp/inline controls and flatten three typed selections.
  All 48 owner/consolidation/cusp/unique-point combinations match native cooks
  and have one/four-domain typed/factory parity with the normal, orientation,
  degenerate and planar controls enabled. Inline removal, unset group, every
  cache field and construction/inspector invalid-value refusal are checked.
  Procedural/catalog/API checks, the broader SOP catalog test and `@all` pass;
  reviewed API/additive manifest changes are promoted. RDK is unchanged.
- Blast by Attribute derives optional flat comparison/output choices and fields,
  retaining all Lisp defaults and metadata. Four structured typed calls are
  flattened. All 30 valid owner/mode/output/inversion/cleanup combinations
  match native cooks and have one/four-domain typed/factory parity; every
  cache field and unset base/inactive output names are tested. Construction
  rejects invalid names, non-finite controls, reversed ranges, overflowing
  width intervals and cleanup outside primitive deletion. Invalid inspector
  writes are refused. Procedural/catalog/API checks and `@all` pass; the
  reviewed API change is promoted and the manifest is unchanged. RDK is unchanged.
- Grid derives optional flat fields, sharing Circle's plane choices and axis
  validation. Lisp gains custom horizontal/vertical axes and independent
  Explicit/Auto dimensions; existing defaults/fields/choices remain. AST
  codemods across 13 caller files preserve omitted typed dimensions as Auto,
  flatten custom planes, and pin the two catalog callers' resolved dimensions
  explicitly to preserve their parameter-edit behavior. The catalog create
  entry aliases the derived constructor. All 256 count/connectivity/plane/
  dimension-mode combinations match native cooks and have one/four-domain
  typed/factory parity, as do singleton point counts and unset UV names.
  Every cache field is tested. Construction validates dimensions, finite
  controls, count/connectivity minima, axes, UV names and both point/topology
  cardinalities; invalid inspector writes are refused. Zero counts and
  collinear axes now assert construction refusal. Lazy-switch and error-trace
  tests retain their purpose using a missing-attribute cook failure, including
  structured RDK cause/trace checks. Procedural/catalog/API checks, the broader
  SOP catalog test and `@all` pass; reviewed API/additive manifest changes are
  promoted and dead orientation copying is removed. The vector inventory guard
  includes Circle/Grid's four new axis groups. RDK is unchanged.
- Circle derives optional flat arc/plane choices and grouped vectors. Lisp
  gains custom plane axes, the base radius and independent Explicit/Auto
  radius modes, keeping existing fields/choices/defaults and 48 segments.
  Exact recipes flatten the structured callers; an AST codemod pins Auto only
  where old radius overrides were absent. Existing geometry/cache assertions
  remain, while the old collinear-axis cook refusal now checks construction.
  All 128 arc/plane/radius-mode/traversal combinations match native cooks and
  have one/four-domain typed/factory parity; every cache field is probed.
  Construction checks finite controls, positive radii/scales, scaled-radius
  overflow/underflow, nonzero arc sweeps, independent axes and cardinality;
  invalid inspector edits are refused. Procedural/catalog/API checks and
  `@all` pass; reviewed API and additive manifest changes are promoted,
  dead orientation copying is removed, RDK unchanged.
- Spiral derives optional flat extent/radius/division modes and grouped vectors,
  reusing the existing axis orientation choice. Lisp gains both ordered ramp
  fields; the shared ramp parser retains the kernel's single-knot constant
  form as well as blank/multi-knot curves. Exact OCaml recipes preserve the
  existing advanced callers' values and output/cache assertions. All 64
  extent/radius/sampling/angle/direction combinations match native cooks and
  have one/four-domain typed/factory parity. All orientations/rotation orders,
  constant ramps, unset names and every cache field also pass. Finite/range,
  radius profile, custom axis, output names, ramps and cardinality checks run
  at construction, including invalid inspector edits; the old zero-axis
  cook-error assertion now checks the authorized construction refusal.
  Procedural/catalog/API checks and `@all` pass; reviewed API and additive
  manifest changes are promoted, RDK unchanged.
- Point Velocity's record/cook move into Procedural with a derived typed entry,
  flat initialization choices and positional previous/next option inputs.
  Existing Lisp metadata is unchanged. Defaults, all three difference methods,
  both unmatched policies, central acceleration, all four initializations and
  all optional-input combinations have one/four-domain typed/factory parity;
  advanced cooks match native results. Every cache field is tested, including
  an acceleration companion that selects its required central method. Actual
  missing matches exercise Zero and the retained structured Error diagnostic.
  Rewiring preserves next-source roles, ID and label through parameter edits.
  Invalid timing, vectors, names and acceleration combinations fail at
  construction and invalid inspector edits are rejected. Procedural/catalog/
  API checks, `@all`, and the broader SOP catalog test pass; reviewed API
  additions are promoted, RDK unchanged. The catalog test's Exploded View
  caller explicitly pins its old default label; its metadata assertion stays
  intact. Exploded View's pending every-field cache decision is unaffected.
- Attribute Fade derives its flat timing fields and positional optional source
  nodes. Lisp gains both ordered ramp text fields, retaining every existing
  field/slot/default; ramp decoding shares Attribute Remap's parser. OCaml
  codemods flatten the retime/ramp fixture and convert pipeline source arguments
  while preserving their roles and existing output/cache assertions. Defaults,
  all four source connection combinations, custom ramps and unset names pass
  one/four-domain typed/factory parity and match native timing/ramp cooks.
  Every cache field is tested. Optional source rewiring retains roles, ID and
  label through parameter edits. Invalid timing, ramps and reserved output
  names fail at construction; the negative-duration assertion now checks that
  refusal, while invalid geometry still produces its original cook diagnostic.
  Procedural/catalog/API checks and `@all` pass; reviewed API and additive
  manifest changes are promoted, RDK unchanged.
- Attribute Mirror derives optional flat method/transform choices, grouped
  plane vectors, UV channels and string replacement controls from its Lisp
  record. An OCaml codemod preserves all four existing structured callers'
  values and diagnostic assertions. Defaults, all three mapping owners, both
  group-use choices, Copy/UV mapping and all four Point/Primitive plane
  transforms pass one/four-domain typed/factory parity; advanced cases also
  match native cooks. Every cache field and blank unset name is checked.
  Construction rejects invalid finite/range, normal, UV, pattern, name and
  method/owner/transform combinations, including failed inspector edits.
  Procedural/catalog/API checks and `@all` pass; the reviewed API change is
  promoted, Lisp metadata and RDK are unchanged.
- Attribute Remap derives optional flat choices and range fields, grouping XYZ
  as vectors and keeping W separate. Lisp gains its typed ramp as ordered
  position:value text. Two exact caller recipes preserve scalar and Vec4 ranges
  and the original ramp knots, including the existing empty-name refusal.
  Defaults, all four owners/kinds, both range choices, all policies, selections,
  canonical P and unset names pass one/four-domain parity; all 96 owner/kind/
  range/policy combinations also match direct native cooks. Every cache field
  is probed. Finite bounds, increasing active explicit ranges, canonical-P
  constraints and valid ordered/end-point ramps are checked at construction.
  Procedural/catalog/API checks and `@all` pass; additions are promoted and RDK
  remains unchanged.
- Copy to Points derives optional flat fields and positional source/targets.
  Lisp gains escaped-table target transfer rules with all three owners and five
  operations. One exact recipe retains the structured transfer fixture; an AST
  codemod converts labelled inputs and removes the trailing unit across five
  caller files, with a reversed-input-order self-check. Catalog create aliases
  the derived constructor. Defaults, selections, piece matching, unset names
  and every cache field pass one/four-domain parity. All 15 transfer combinations
  also match native cooks; packed transforms compare byte for byte at both
  doors/domain counts. Bad rules and incompatible packed-source settings fail
  at construction. Procedural/catalog/API checks, the tool self-check and
  `@all` pass; additions are promoted and RDK is unchanged.
- Exploded View's record/cook now live in Procedural with a derived typed entry;
  its catalog create entry aliases that constructor. Defaults and advanced
  controls pass one/four-domain parity and preserve source geometry. Finite
  controls, nonnegative noise frequency and a nonblank piece attribute are
  validated at construction. Procedural/catalog/API checks and `@all` pass,
  and the reviewed API additions are promoted; Lisp metadata and RDK are
  unchanged. Its existing view-only impacts remain intact. The owner's decision
  is pending on testing cook-cache hits for view-only fields, versus the blanket
  every-field-miss requirement below; its per-field cache audit is not complete.
- Join Curves derives optional flat fields, including Lisp's group-size toggle.
  Lisp gains ordered picked-end text; blank is unset and [] preserves the
  explicit-empty selection capability. Exact recipes convert four dynamic
  array calls and the fixed duplicate fixture, while the toggle codemod retains
  existing group limits. Existing order/ownership assertions stay unchanged.
  Duplicate picks now fail at construction under the authorized validation rule;
  invalid sizes, tolerance, syntax and conflicting selection modes do too.
  Defaults, orientation/order/wrap choices, grouped limits, retained originals,
  connected-only mode, unset names and every cache field pass one/four-domain
  parity. Picked traversal and empty selection also match native cooks.
  Procedural/catalog/API checks and `@all` pass; additions are promoted, RDK
  unchanged.
- Point Jitter derives optional flat fields, with its existing axis grouping
  retained through the typed axis_scales alias. Lisp gains Explicit/Auto seed
  mode and the previously typed-only point-scale toggle; its explicit-zero
  seed default remains. The one formerly context-seeded caller explicitly
  selects Auto through an exact codemod. The catalog create entry aliases the
  derived constructor. Defaults, both seed modes, point-scale use, masks, IDs,
  unset names and every cache field pass one/four-domain parity. Existing
  context-seed output checks still pass, with their assertions unchanged.
  Scale and axes are finite/nonnegative at construction. Procedural/catalog/
  API checks and `@all` pass; reviewed additions are promoted, RDK unchanged.
- Snap to Grid derives its optional flat fields and grouped vectors, including
  Lisp's limit-distance toggle. Its formerly typed-only attribute/group rules
  are escaped-table text fields, retaining all 16 attribute and five group
  reductions; both decoders reuse the existing table format. No existing caller
  used structured rules or an optional distance. All rounding/limit choices,
  15 position reductions, both attribute policies, unset names and every cache
  field have one/four-domain parity. Every rule method also matches a direct
  native cook. Invalid vectors, distances and rule tables fail at construction.
  Procedural/catalog/API checks and `@all` pass; reviewed API/manifest additions
  are promoted, with RDK unchanged.
- Clean derives optional flat fields and adds Auto choices for kernel epsilon,
  omitted consolidation and omitted overlap cleanup. Its existing Lisp defaults
  stay Explicit/Explicit/Keep first, with cleanup toggles enabled. Both existing
  typed callers have their old omitted modes and toggles explicitly pinned by
  the codemod. All 12 mode/overlap combinations, all four attribute owners,
  unset names and every cache field have one/four-domain byte parity. Invalid
  numbers and patterns fail at construction; all eight pattern fields reject
  malformed inspector edits. Procedural/catalog/API checks and `@all` pass;
  reviewed API/manifest additions are promoted, with RDK unchanged.
- Merge now derives its final repeated input slot from `sop.node_rest`, using
  the existing Rest graph contract. Its optional source attribute/base are
  also Lisp fields; existing fields and ports are retained. One, three and five
  inputs, tagging, unset names and every cache field pass typed/factory byte
  parity at one/four domains. Appending and sparsely disconnecting inputs,
  then editing parameters, preserves input order, parameters, label and ID.
  The first input is required by both surfaces. PPX metadata rejects misplaced
  Rest slots and optional prefixes. Procedural/catalog/PPX/API checks and
  `@all` pass; reviewed API/manifest additions are promoted, RDK is unchanged.
- Cache verification now fails on every rejected parameter edit instead of
  silently skipping invalid text. Valid changed tables probe combine steps,
  swap/rename rules, group delete/rename/copy/transfer rules and both boundary
  attribute lists. The strict declaration check passes with all fields probed;
  the full 159-node completion audit still remains.
- Platonic derives optional radius and separate orientation/axis fields, with
  Lisp's Dodecahedron/Vertex defaults. Old omitted values are explicitly pinned;
  its two structured orientations are rewritten exactly. The catalog create
  entry aliases the typed constructor. All six kinds, three normal policies,
  four orientations and six rotation orders have one/four-domain parity and
  every-field cache checks. Invalid radius, vectors and zero custom axes fail
  at construction; the old cook-time axis assertion now checks construction.
  Two accidental matches in kernel calls were restored before verification.
- Edge Transport exposes Lisp's root choice and optional attribute, and uses
  its Zero root-value default. Existing callers explicitly retain Hold and
  select grouped roots. Default/all roots, directions, operations, split/merge
  and normalization choices have one/four-domain parity and full-field cache
  checks. Constant integration and edge-length scaling now require Total at
  construction in all three transport nodes, with valid companion cache edits.
  The existing explicit blank-root refusal remains pending the owner's unset
  decision. Focused checks and `@all` pass; API diffs are reviewed/promoted,
  Lisp manifest metadata and RDK remain unchanged.
- Revolve derives optional vectors, divisions and flat output names from the
  record. The one option-valued UV call was rewritten exactly; the decimal
  end-angle default equals the former `2 * pi` value. Both arc types and all
  eight connectivity modes, caps, unset names and every-field cache edits
  pass one/four-domain parity. Resolution, vector, arc-span, cap-mode and UV
  constraints fail at construction. The Lisp manifest is unchanged; API
  changes are reviewed/promoted and focused checks plus `@all` pass.
- Rewire Vertices derives optional selection owner/name and target fields.
  Lisp deletes the target attribute by default; old callers explicitly retain
  false where omitted. Two structured selections were rewritten exactly.
  Defaults, all three target owners, all four selection owners, recursion,
  unset names and every-field cache edits have one/four-domain parity. Detail
  ownership, non-Point recursion and invalid names fail at construction.
- Distance Along Geometry, Distance from Target and Distance from Geometry derive optional selection
  fields, a shared radius choice plus scalar radius, and output names. Two
  callers per family were rewritten exactly. Default, all selection owners,
  falloffs, radius modes, point/surface references, analytic projections and planar signed distance
  have one/four-domain parity and every-field cache checks. Invalid radius,
  output names, projection/metric combinations and vectors fail at construction.
  Their existing Lisp fields/defaults/ranges remain unchanged. Focused checks
  and `@all` pass; API diffs are reviewed/promoted.
  Distance from Geometry takes source/reference positionally, preserving
  both original structured calls through exact rewrites.
- Match Size derives separate axis toggles, positional source/optional-target
  inputs and grouped vectors. Lisp gains its existing three selectors as six
  owner/name fields and an Auto target-justification choice; the existing
  Explicit-zero default remains. Eight exact caller recipes preserve prior
  values. All ten fits, four owners for each selector, Auto inheritance,
  target disconnection and all-field cache checks pass at one/four domains.
- Origin Point Generate derives optional fields and exposes its existing group
  and two metadata-name options in Lisp. Defaults, custom names, unset group,
  one/four-domain parity and every-field cache edits pass. Lisp's existing
  1–50 limit and kernel metadata-name constraints run at construction. API
  and manifest additions are reviewed/promoted; focused checks and `@all` pass.
- Bound derives optional selection, shape, resolution, padding and output fields
  from its record. Five structured callers were rewritten exactly. Defaults,
  both shapes, all four selection owners, output metadata and unset names have
  one/four-domain parity and every-field cache checks. Invalid resolution,
  padding and output names fail at construction. API changes are reviewed and
  promoted; focused tests and `@all` pass, with RDK unchanged.
- Attribute Blur and Smooth expose the existing Laplacian/custom choices and
  separate step fields, sharing the same typed mode. Pattern, iteration and
  finite-step/blend checks live on the records. Exact recipes rewrote the two
  structured calls per family; an accidental match in an RDK test was restored
  before validation. Smooth uses Lisp's 10 iterations and disabled normal
  recomputation; old callers explicitly retain 1/true where previously omitted.
  Default and advanced methods/modes/boundaries, masks, blends and unset names
  have one/four-domain parity and every-field cache checks. RDK is unchanged.
- Promote Attributes derives optional source/destination/pattern fields.
  Lisp keeps source attributes by default; the codemod pins the old deletion
  behavior at existing calls. Pattern/rewrite and source-index checks live on
  the record, with the unused helper removed by `drop-unused`. Defaults, all
  12 methods, all source/destination owners, piece output and renamed source
  indices have one/four-domain parity and all-field cache checks.
- PolyFrame exposes optional flat style, style-attribute, selection and output
  fields. Four structured callers were rewritten exactly. All six styles,
  all four selection owners, disabled tangent/bitangent output and unset group
  have one/four-domain parity and every-field cache checks. Invalid, duplicate
  or canonical-P output names fail at construction. Intended APIs are reviewed
  and promoted; this batch changes no Lisp manifest metadata.
- Set Transform now takes all 16 optional matrix fields. Its one structured
  rotation caller was rewritten exactly, retaining the original matrix
  calculation. Finite/affine checks moved from cook time to construction;
  the geometry-dependent array limit stays at cook time. Default, full-matrix
  one/four-domain parity and every-field cache edits pass, including valid
  small edits within the existing affine tolerance. The compiler identified
  the now-unused node wrapper, which `drop-unused` removed.
- Set Color and Set Color Float alias the same derived constructor, with
  optional owner, group, grouped Vec3 color and alpha. Seven exact codemod
  recipes preserve the existing byte-color calls' channel values. Defaults,
  all four owners, selection, the alias and unset group have one/four-domain
  parity and every-field cache checks. Invalid channels and grouped Detail
  colors fail at construction. No Lisp fields or defaults changed.
- Rest Position was catalog-only. Its existing record and cook now live in
  Procedural, with a derived typed constructor taking positional input and
  optional reference. Default/connected references, all modes, all normal
  policies and cache fields have one/four-domain checks. Its existing kernel
  attribute-name constraints now also run at construction. The public typed
  entry is new; the Lisp manifest remains unchanged.
- Enumerate derives the optional owner, name, storage and separate prefix
  from its record. Its one structured text-storage call was rewritten exactly.
  Default, all three supported owners, both piece modes, negative steps and
  unset optional names pass one/four-domain parity; every cache field is probed.
  Detail ownership, blank output names and canonical Point P replacement fail
  at construction. The public API is reviewed and promoted.
- Graph Color now exposes optional selection and workset fields directly.
  Four structured calls were rewritten exactly by the codemod. Default,
  three connectivity choices, four selection owners and sorted worksets have
  one/four-domain typed/factory parity; output-name and workset constraints
  run at construction. Cache checks edit every field using valid combinations.
- Set Float, Set Integer, Set Vector and Set Orient use one record each with
  optional Lisp defaults. The positional-value codemod rewrote the first three
  families; Set Orient's one structured caller retains its original quaternion
  calculation before passing the four channels. Common attribute installation
  is reused from the existing helper. Checks cover defaults, all four owners
  where exposed, explicit values, zero-quaternion normalization and every cache
  field. Non-finite floats and canonical Point P replacement fail at construction.
  Set Vector adds only Vec3 grouping metadata to its existing scalar fields.
- Connectivity separates storage choice and text prefix; an exact table
  rewrote its two text-output calls. Default, point/primitive text outputs,
  edge seams, UV seams and unset optional names have one/four-domain parity.
  Point selection in primitive mode, UV selection in point mode and combined
  edge/UV seams fail at construction. The existing cache check accepts companion
  edits so point-group identity is tested in its valid point mode.
- UV Transform and UV Project now use flat Lisp fields, grouping only Vec3
  projection frames. Five structured projection calls and two Vec2 transform
  calls were rewritten exactly with the codemod. UV Project defaults to the
  Lisp X/Z plane; previous X/Y calls explicitly retain their old V axis.
  Both nodes cover defaults, all projection/owner choices, advanced fields,
  one/four-domain factory parity and all-field cache edits. Non-finite values,
  invalid projection frames and cylindrical zero heights fail at construction.
- Color by Height now takes its separate optional color channels from the
  record. Lisp exposes two additional alpha fields to retain the existing
  typed capability. Existing color callers, including both benchmark graphs,
  preserve all channels through exact codemod rewrites. Defaults, explicit RGBA,
  one/four-domain factory parity, all-field cache edits and invalid byte values
  have focused checks. The alpha metadata additions and flat API are reviewed.
- Pilot merged into `audit-cleanup` at `ff1f31a8`.
- Six more nodes moved with `sop_merge`: Crease, Poly Path, Ends, Measure,
  UV Unitize, and Swap Attributes. Each has typed/factory byte comparison at
  one and four domains and per-field cache checks in `test_sop_nodes`.
- Group Invert, Group Combine and Separate Pieces also use one declaration.
  The compiler identified one structured caller each for Group Invert and
  Group Combine; `codemod rename --exact` rewrote those two callers.
- Group Promotions and Group Ranges now derive optional labelled rules from
  their Lisp defaults. The codemod updated six promotions calls and two ranges
  calls. Empty/disabled rules preserve geometry while retaining node-owned
  parameter/cache identity, per the owner decision below. Their tests cover
  one/four-domain factory parity and valid rule-table cache edits.
- Box normals now include `Auto`, with `None` selecting the kernel default.
  Existing callers explicitly select Auto or wrap their prior normal choice,
  preserving cooked geometry. Lisp's existing Vertex default remains. Tests
  cover defaults, Auto surface/point output, and per-field cache misses.
- Reverse now exposes Lisp's operation choice and separate shift field.
  The compiler identified one structured caller, rewritten with the codemod.
  Material uses optional record fields (including `material`, replacing
  typed-only `name`); its two callers were rewritten by the codemod. Its
  finite/range checks derive from the existing Lisp channel bounds. Both
  nodes have default and explicit-value parity plus per-field cache checks.
- Group Bounds uses Lisp's separate shape, center, size, and radius fields.
  Six structured callers were rewritten through the codemod; the two min/max
  boxes convert exactly to their fixture centers and sizes. Default, box and
  sphere parity and all-field cache checks pass. Finite/non-negative bounds
  checks derive from the record; the unused copy helper was removed by
  `codemod drop-unused` from the compiler warning.
- The pilot's remaining required labelled fields are now optional in 23
  constructors, taking record defaults. `sop_merge --optional-fields` edits
  only those argument labels and the existing `.mli` types; it does not
  generate the interface or rewrite callers. Its self-check proves that
  nested callback types and input labels remain intact. Omitted-field
  one/four-domain factory parity covers all 23 constructors. Group Random
  and Noise Displace pin seed zero in these cases: their seed-absence/Auto
  contract is still outstanding.
- Ends, Measure and UV Unitize now take optional labelled mode/kind fields;
  their positional callers were rewritten with `--label-first`. Measure's
  output labels now match `attribute` and `total_attribute` in the record;
  an exact rename table rewrote its callers. Their omitted-mode/kind cases
  pass one/four-domain parity.
- Group Copy and Group Transfer now take positional source/target inputs and
  expose Lisp's explicit `use_rules` toggle. Group Edges exposes its four
  limit toggles. Existing callers explicitly enable their previous rules or
  limits; enabled and disabled field cases have one/four-domain parity and
  cache checks. Group Transfer rejects invalid distances at construction;
  Group Edges rejects non-finite limits and negative lengths. Both boundary
  grouping constructors reject negative/non-finite tolerances as well.
- Sort now exposes the existing Lisp key choice and its separate component,
  seed, shift and point/vector fields. The compiler identified four structured
  calls; an exact codemod table rewrote them. Legacy diagnostic text remains,
  while the complete record owns the cache key. All 13 key choices have
  one/four-domain typed/factory parity, with all-field cache checks and
  construction-time finite/component validation.
- Group Range now exposes the existing range, filter, connectivity, region
  and collision fields as optional labelled arguments. A six-entry codemod
  table rewrote its structured callers; `drop-unused` removed their obsolete
  collision record from the compiler warning. Legacy diagnostic-text checks
  remain unchanged. Four range modes, three connectivity modes and an advanced
  combined case have one/four-domain typed/factory parity and full cache checks.
  Numeric refusal follows the record's existing hard ranges.
- Null and Compact Points now declare unit parameters, deriving empty schemas
  and their input-only constructors. The PPX and merge tool accept unit without
  artificial fields. Compact Points' sole-use wrapper was expanded before the
  merge, then `drop-unused` removed the dead helper from the compiler warning.
  Both nodes have one/four-domain typed/factory parity and equal-value cache
  checks; the PPX metadata check also exercises unit generation.
- Extract Centroid separates run mode and piece attribute; its three
  structured calls were rewritten by an exact table. Ordered Group takes the
  optional immutable `elements` list from Lisp; nine array callers were
  labelled and rewritten through the codemods. Existing array-ownership and
  duplicate-index checks still pass. Group by Normal now takes record defaults
  for every field, with no caller rewrites. Its blank optional names follow
  Lisp's unset convention. All three nodes retain legacy diagnostic text and
  have one/four-domain typed/factory and full-field cache checks.
- Record-level `[@@sop.validate]` supports pure checks involving several fields
  or encoded values, covering Centroid's reserved names, Ordered Group's
  negative indices, and Normal's zero direction/unsupported owner. The builder
  applies it before operator creation for typed/factory calls; failed inspector
  rebuilds return errors and keep the existing node. Regression checks exercise
  failed edits. The merge tool recognizes `Float.pi` as the exact constant;
  its self-check covers that match against the record's existing hard bound.
- Delete Attributes now has positional input/reference slots and validates
  all four patterns through its record. The codemod rewrote three pipeline
  callers and the documentation example; `drop-unused` removed the old check
  helper. The parity helper explicitly supports absent optional slots, so tests
  cover both reference absence and connection. Edge Transport Curves and Parent
  also derive optional record fields and constructor validation. Their root
  value revealed two additional Hold/Zero drifts: existing calls now explicitly
  pin Hold, while defaults follow Lisp's Zero. All three nodes retain legacy
  diagnostics and have default/explicit one/four-domain parity, every-field
  cache checks, and invalid-value checks.
- Edge Equalize's strict positive-tolerance check now lives on its record,
  alongside finite/hard-range checks derived by the merge tool. Zero remains
  invalid, including during inspector edits. Default and all three method
  cases have one/four-domain typed/factory parity and all-field cache checks;
  existing call sites and diagnostic assertions remain intact.
- An owner decision is pending for blank optional-name assertions. Lisp uses
  blank names as unset; existing Edge Transport, Edge Equalize and Graph Color assertions
  require construction failure. Those assertions have not changed while the
  remaining migration proceeds independently.
- Remesh derives optional fields from its record, including target length,
  and rejects invalid numeric values at construction. Resample exposes the
  existing segment-count and maximum-length toggles; codemods explicitly
  preserve sizing at all six old callers. Its record validates sizing
  combinations and generated attribute names. Carve validates finite cuts,
  ordering and its extraction exception through the record. These three nodes
  retain legacy diagnostics and have default/explicit one/four-domain parity,
  every-field cache checks and failed-edit checks.
- Poly Loft and Skin use positional input/rest slots, including explicit
  absence of the optional rest input. Four pipeline callers were rewritten by
  exact codemods. Omitted output groups now follow Lisp's `loft`/`skin` defaults;
  old omitted calls explicitly pin unset output. Their record validates
  collinearity tolerance without changing existing metadata. Tests compare
  defaults, connected rest and all explicit fields at one/four domains, with
  every-field cache checks and invalid numeric construction checks.
- Poly Bridge follows Lisp's output-group and normal defaults; two old calls
  explicitly pin prior values. Circle from Edges exposes the existing radius
  toggle; three old radius calls explicitly enable it. Its scale/radius checks
  live on the record and existing blank-name assertions remain intact pending
  the owner decision. Convex Hull exposes the flat owner/name selection and
  Lisp's output defaults. One structured caller was rewritten by an exact
  codemod, and old omitted outputs explicitly pin unset values. The existing
  selection helpers moved unchanged into shared procedural code, with the
  public group type re-exported. All three nodes have one/four-domain parity
  and every-field cache checks; Hull also tests all four selection owners.
- Edge Relax uses flat selection fields and positional source/reference
  inputs. Six callers were rewritten through an exact table, with omitted
  iterations explicitly pinned to 20 while Lisp's 32 wins the new default.
  Point Split uses flat selection fields and Lisp's attribute/tolerance
  defaults; two structured callers and one bare pipeline call were rewritten,
  and all five old calls retain prior defaults. Both have record-level numeric
  and owner validation, one/four-domain parity for supported selection owners,
  and every-field cache checks. Existing diagnostic assertions remain intact.
- UV Auto Seam derives its constructor from its record, with finite angle and
  tolerance validation. Its numeric default is the exact existing Lisp value,
  equivalent to the old `Float.pi /. 3.` expression. Attribute Laplacian uses
  optional record defaults for source/output; five old omitted-output calls
  explicitly preserve unset output. Its canonical-position refusal lives on
  the record, while existing blank point-group/source assertions still pass.
  Measure Curvature exposes six output-name labels instead of an output record;
  two structured calls were rewritten by an exact table, preserving `shape`
  as the shape-index output name. An exact codemod removed the unused old test
  record. Its output/numeric checks now live on the record. All three nodes
  have default/explicit one/four-domain parity and every-field cache checks.
- The default-pinning codemod now handles bare constructor references and
  bare pipeline calls, as well as applications. Its runnable self-check proves
  these rewrites are idempotent and do not double-pin an applied constructor.
- Group Expand now exposes flat normal/collision fields and optional owner/name
  defaults. Three structured arguments were rewritten through an exact table,
  and all eight old calls pin their previous connectivity tolerance. A full
  pi spread without an override is unconstrained, including vertex/edge
  growth. Numeric, owner, collision and flood checks live on the record.
  Its tests cover all four owners, combined constraints and valid encoded
  boundary-attribute cache edits. The emptied catalog group file is removed.
- Normal, Peak, Bend and Clip expose their previously OCaml-only selections
  through Lisp's owner/name fields, using the shared selection helper. Normal
  also exposes existing kernel Primitive/Detail owners. Exact codemods rewrite
  their 11 structured selection calls. Existing Normal calls pin Point/Face-area
  defaults, Peak calls pin automatic direction, Bend calls pin direction/up
  and continuous twist, and Clip calls pin group replacement; new omitted calls
  follow Lisp's defaults. Record validation covers finite distances/planes,
  positive Bend length and valid capture frames, Clip split/output names,
  and finite Normal cusp angles. All four nodes have default/explicit parity
  at one/four domains, tests for all selection owners and every-field cache
  checks. Clip's cap fixture uses a closed mesh with shared points. The Lisp
  manifest adds selection fields and Normal owner choices only.
- The merge tool follows `sop.vec3` metadata and declared component order,
  including RGB groups. A self-check rejects reordered components. Material's
  cook needed a local `open Rays_math` after moving into its destination.
- Step 2's ten drifts are settled: Dissolve's two defaults; Group From
  Attribute Boundary and Group Promote Boundary tolerance; Name From Groups
  overlap; Group Copy and Group Transfer conflict; Box connectivity; Tube
  connectivity and end caps. `sop_merge --explicit-default` preserves the
  old defaults at existing callers. No record has `sop.arg_default` left.
  New omitted-default parity cases cover the migrated constructors.
- The PPX's documented argument aliases now work for optional arguments
  (`?name=attribute`), exercised by Measure. The merge tool accepts positional
  record fields and can preserve diagnostic text separately from the schema
  cache key, needed by the existing Ends and Swap Attributes identity checks.
- Crease negative/NaN weight and Poly Path NaN distance tests now assert
  refusal at construction, following the owner decision below. Other existing
  test edits spell out old defaults or migrated argument shapes through the
  codemod, apart from the two authorized disabled-rule identity checks.
- `@check`, procedural runtests, catalog runtests and the defaults codemod
  self-check pass. The Lisp manifest adds Box's Auto choice; intended public
  signature changes and factory exports are accepted in the API snapshot.
  Native smoke cannot open a display in the current sandbox. Broad runtest
  also reports a workspace-shell Size-row assertion; it remains unresolved.
- On this arm64 host, the seven-repeat, one-domain SOP session benchmark at
  128×128 grid divisions measured 1.123 ms before / 1.120 ms after the six-node
  batch, with identical 3,024,088 allocated bytes and geometry hash.
  `bench_workspace_lower` ran before and after on all 12 fixtures, with the
  same node counts, cache retention and payload sizes. The reduced full
  `bench_rdk_ops` run stopped with `benchmark setup failed`; full benchmark
  verification remains outstanding.
- After the 48-node checkpoint, a serial 21-repeat session run measured
  1.098 ms with the original allocation/promotion counts and geometry hash.
  The 12 workspace fixtures retain their original node counts, cache retention
  and payload sizes. These focused checks do not replace the outstanding full
  benchmark and native shipping checks.
- At 52 nodes, the serial 21-repeat session run measured 1.118 ms with
  unchanged allocation/promotion counts and geometry hash. The 12 workspace
  fixtures still have their original node counts, retention and payload sizes.
- At 58 nodes, two serial 21-repeat session runs measured 1.114 and 1.165 ms,
  with unchanged allocated bytes and geometry hash. Both reported 320 more
  promoted/major bytes than the baseline; that difference is recorded rather
  than treated as proven noise. The workspace benchmark completed all 12 cases.
- At 67 nodes, the serial 21-repeat session benchmark measured 1.158 ms,
  with the original allocation, promotion, major-byte and geometry-hash values.
  The seven-repeat workspace benchmark completed all 12 fixtures with their
  original node counts, retention and payload sizes. `@all` and the focused
  procedural/catalog/merge-tool checks pass; API changes are reviewed/promoted.
- At 70 nodes, the same serial session benchmark measured 1.160 ms with
  unchanged allocation/promotion/major bytes and geometry hash. The workspace
  benchmark completed all 12 fixtures with unchanged node counts, retention
  and payload sizes. `@all`, procedural/catalog runtests and merge-tool checks
  pass; the reviewed API snapshot includes the flat group-owner type.
- At 75 nodes, the serial 21-repeat session run measured 1.159 ms with
  unchanged allocation/promotion/major bytes and geometry hash. The workspace
  benchmark completed all 12 fixtures with unchanged node counts, retention
  and payload sizes. `@all` and procedural/catalog/merge-tool checks pass;
  intended API changes are reviewed and promoted.
- At 80 nodes, the serial 21-repeat session run measured 1.032 ms with the
  original allocated bytes and geometry hash. Promoted bytes were 0 and major
  bytes 2,949,392 (both 4,360 below the baseline); the GC difference is recorded
  without attributing it to the migrations. The workspace benchmark completed
  all 12 cases with unchanged node counts, retention and payload sizes. `@all`
  and focused procedural/catalog/merge-tool checks pass. The manifest additions
  and public API changes are reviewed and promoted.
- At 83 nodes, the serial 21-repeat session run measured 1.025 ms and retained
  the original cardinality and geometry hash. Allocated bytes were 3,024,360,
  272 above the original baseline after the Color by Height record gained two
  alpha channels; promoted/major bytes remained 0/2,949,392. This allocation
  increase remains part of the performance audit, rather than a claim of
  unchanged allocations. All 12 workspace cases retained their node counts,
  session retention and payload sizes. Focused procedural/catalog/API checks
  and `@all` pass; the manifest adds only the two alpha fields in this batch.
- At 89 nodes, the serial 21-repeat session run measured 1.046 ms with the
  same allocation counters as node 83 and the original geometry hash and
  cardinality. All 12 workspace cases retained their node counts, cache
  retention and payload sizes; reported heap size was 40–42 MB. Focused
  procedural/catalog/API checks and `@all` pass. This batch adds only Set
  Vector's grouping metadata; existing field names, defaults and ranges stay
  unchanged. The 272-byte allocation increase remains outstanding for the
  final performance audit. Git staging is still denied at this checkpoint.
- At 93 nodes, the serial 21-repeat session run measured 1.037 ms with the
  original geometry hash/cardinality and unchanged counters from node 83.
  All 12 workspace cases retained their node counts, cache retention and
  payload sizes; heap size was 36–39 MB. Focused procedural/catalog/API checks
  and `@all` pass. This batch changes no Lisp manifest metadata. The 272-byte
  allocation increase and full shipping audit remain outstanding; Git staging
  is still denied at this checkpoint.
- At 97 nodes, the serial 21-repeat session run measured 1.072 ms with the
  original hash/cardinality and allocation counters unchanged since node 83.
  All 12 workspaces retained node counts, cache retention and payload sizes;
  heap size was 43–46 MB. Focused procedural/catalog/API checks and `@all` pass.
  The 272-byte increase and broad shipping audit remain outstanding. Staging
  is still denied (`.git/index.lock: Operation not permitted`).
- At 98 and 100 nodes, the same 21-repeat session benchmark measured 1.027
  and 1.042 ms respectively, retaining the original geometry hash/cardinality.
  Both allocated 3,024,360 bytes, promoted 0 and used 2,949,392 major bytes,
  unchanged since node 83. All 12 workspace cases retained their node counts,
  cache retention and payload sizes; heap sizes were 31–33 and 36–38 MB.
  The 272-byte allocation increase remains for the final performance audit.
  A further staging attempt after node 104 was denied at `.git/index.lock`.
- At 105 nodes, the 21-repeat session benchmark measured 1.031 ms, with the
  original hash/cardinality and the same allocation counters as node 100.
  All 12 workspace fixtures retain their node counts, retention and payload;
  heap size was 39–41 MB and timings varied. Focused procedural/catalog/API
  checks and `@all` pass. The 272-byte allocation increase, full shipping audit,
  regular commits and `dev` merge remain outstanding; Git metadata is read-only.
- At 107 nodes, the same session benchmark measured 1.026 ms with the original
  hash/cardinality and unchanged allocation counters. All 12 workspace fixtures
  retain their node counts, cache retention and payload sizes; heap size was
  39–42 MB. Focused checks and `@all` pass, including strict cache-field probing.
  The 272-byte allocation increase and full shipping audit remain outstanding.
  Staging is still denied at `.git/index.lock`; no post-pilot commit or `dev`
  merge has been made.
- At 108 nodes, serial 21-repeat session runs measured 1.451 and 1.077 ms,
  retaining the original geometry hash/cardinality and allocation counters
  unchanged since node 83. All 12 workspace cases retain node counts, retention
  and payload sizes; heap size was 40–42 MB. Timing variation is recorded without
  claiming unchanged timings. The 272-byte allocation increase and full shipping
  audit remain outstanding, as do post-pilot commits and the `dev` merge.
- At 109 nodes, the serial 21-repeat session run measured 1.031 ms, retaining
  the original geometry hash/cardinality and the same allocation counters.
  All 12 workspace cases retain node counts, retention and payload sizes;
  heap size was 37–38 MB. The 272-byte allocation increase, full shipping audit,
  post-pilot commits and `dev` merge remain outstanding.
- At 110 nodes, the same session command measured 1.031 ms, retaining the
  original geometry hash/cardinality and allocation counters unchanged since
  node 83. All 12 workspace cases retain node counts, cache retention and payload
  sizes; heap size was 36–37 MB. The 272-byte allocation increase and the full
  shipping audit remain outstanding. Git staging is still denied at index.lock.
- At 111 nodes, the same session command measured 1.138 ms, retaining the
  original hash/cardinality and unchanged allocation counters. All 12 workspace
  fixtures retain node counts, retention and payload sizes; heap size was
  39–41 MB. The 272-byte allocation increase and full shipping audit remain
  outstanding; post-pilot commits and the `dev` merge remain blocked by Git
  metadata permissions.
- At 112 nodes, the same session command measured 1.040 ms, retaining the
  original hash/cardinality and unchanged allocation counters. All 12 workspace
  cases retain node counts, retention and payload sizes; heap size was 44–46 MB.
  The 272-byte allocation increase and full shipping audit remain outstanding.
  Git staging is still denied at index.lock; commits and the `dev` merge remain
  outstanding.
- With the 113th declaration moved (cache decision still pending), the same
  session command measured 1.026 ms with the original geometry hash/cardinality
  and unchanged allocation counters. All 12 workspace cases retain node counts,
  retention and payload; heap size was 36–38 MB. The allocation increase and
  full shipping audit remain outstanding.
- With 114 declarations moved and 113 fully verified, the same session command
  measured 1.031 ms, retaining the original hash/cardinality and unchanged
  allocation counters. All 12 workspace cases retain node counts, retention
  and payload; heap size was 42–43 MB. The allocation increase, Exploded View
  cache decision and full shipping audit remain outstanding.
- With 115 declarations moved and 114 fully verified, the same session command
  measured 1.030 ms, retaining the original hash/cardinality and unchanged
  allocation counters. All 12 workspace cases retain node counts, retention
  and payload; heap size was 39–41 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 116 declarations moved and 115 fully verified, the same session command
  measured 1.044 ms, retaining the original hash/cardinality and unchanged
  allocation counters. All 12 workspace cases retain node counts, retention
  and payload; heap size was 40–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 117 declarations moved and 116 fully verified, the same session command
  measured 1.022 ms, retaining the original hash/cardinality and unchanged
  allocation counters. All 12 workspace cases retain node counts, retention
  and payload; heap size was 39–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 118 declarations moved and 117 fully verified, the serial session
  command measured 1.036 ms, retaining the original hash/cardinality and
  unchanged allocation counters. All 12 workspace cases retain node counts,
  retention and payload; heap size was 39–41 MB. The allocation increase,
  pending cache decision and full shipping audit remain outstanding.
- With 119 declarations moved and 118 fully verified, the serial session
  command measured 1.042 ms, retaining the original hash/cardinality and
  unchanged allocation counters. All 12 workspace cases retain node counts,
  retention and payload; heap size was 35–38 MB. The allocation increase,
  pending cache decision and full shipping audit remain outstanding.
- With 120 declarations moved and 119 fully verified, the serial session
  command measured 1.028 ms, retaining the original hash/cardinality and
  unchanged allocation counters. All 12 workspace cases retain node counts,
  retention and payload; heap size was 41–43 MB. The allocation increase,
  pending cache decision and full shipping audit remain outstanding.
- With 121 declarations moved and 120 fully verified, serial session runs
  measured 1.025/1.023 ms, retaining the original hash/cardinality. Allocation
  is 3,025,064 bytes in both runs: +704 from the prior checkpoint and +976
  from the original baseline; promoted/major counters remain unchanged.
  Cache-key cleanup and the performance audit must account for this increase.
  All 12 workspace cases retain node counts, retention and payload; heap size
  was 35–38 MB. The pending cache decision and full shipping audit remain.
- With 122 declarations moved and 121 fully verified, the same serial session
  command measured 1.018 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 39–40 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 123 declarations moved and 122 fully verified, the same serial session
  command measured 1.025 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 35–38 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 124 declarations moved and 123 fully verified, the same serial session
  command measured 1.034 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 40–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 125 declarations moved and 124 fully verified, the same serial session
  command measured 1.027 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 44–45 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 126 declarations moved and 125 fully verified, the same serial session
  command measured 1.024 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 30–33 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 127 declarations moved and 126 fully verified, the same serial session
  command measured 1.023 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 36–39 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 128 declarations moved and 127 fully verified, the same serial session
  command measured 1.035 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 40–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 129 declarations moved and 128 fully verified, the same serial session
  command measured 1.036 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 41–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 130 declarations moved and 129 fully verified, the initial benchmark
  overlapped a rebuild and measured 1.457 ms. Repeating both commands after
  validation finished measured 1.021 ms for the serial session with unchanged
  allocation counters, hash and cardinality. All 12 workspace cases retain
  node counts, retention and payload; heap size was 44–45 MB. The allocation
  increase, pending cache decision and full shipping audit remain outstanding.
- With 131 declarations moved and 130 fully verified, the same serial session
  command measured 1.025 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 37–38 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 132 declarations moved and 131 fully verified, the same serial session
  command measured 1.027 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 40–42 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 133 declarations moved and 132 fully verified, the same serial session
  command measured 1.027 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 37–38 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 134 declarations moved and 133 fully verified, the same serial session
  command measured 1.051 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 36–39 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 135 declarations moved and 134 fully verified, the same serial session
  command measured 1.020 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 36–38 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 136 declarations moved and 135 fully verified, the same serial session
  command measured 1.032 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 36–37 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 137 declarations moved and 136 fully verified, the same serial session
  command measured 1.021 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 31–33 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- With 138 declarations moved and 137 fully verified, the same serial session
  command measured 1.033 ms with unchanged allocation counters, hash and
  cardinality. All 12 workspace cases retain node counts, retention and
  payload; heap size was 39–40 MB. The allocation increase, pending cache
  decision and full shipping audit remain outstanding.
- A blanket `rays-lisp check` reaches custom operators in `sop_gallery` and
  `voxel_wall` that need their host catalogs, and reports existing soft-range
  warnings. Host-aware verification now passes as recorded above.
- Git staging is currently denied (`.git/index.lock: Operation not permitted`).
  The post-pilot batches are uncommitted and have not been merged to `dev`.

PolyWire and Sweep Circle now share one declaration and cook, preserving both
runtime identities. The added Sweep Circle Lisp entry uses that same record:
there are 160 factories but still 159 original declarations to migrate.

## Final status (2026-10-07)

| Requirement | Result |
|---|---|
| All 159 original declarations migrated | Done. Switch lives in `sop_shapes.ml`; `lib/sop_catalog/shapes.ml` is deleted and the catalog only registers. |
| Step 6: no duplicate keys | Done. The last 57 hand-written parameter texts are gone (48 explicit, 9 shorthand), with 27 dead locals and 95 dead `Sop_support` formatters removed by `codemod drop-unused` / `prune`. The five node files lose about 1,290 lines. No removed line raised or validated. |
| Tests | `@all` and window-free `@runtest` pass with no failure; `@smoke` passes on a display; `git diff --check` is clean. |
| Manifest | Additions only: Switch gains the optional repeated `inputs` slot. |
| Benchmark | `bench_workspace_lower ... 7`: node counts, retention and payload unchanged. Startup live bytes after the catalog are 1,199,624 against the pilot's 1,186,000: 13,624 bytes more for 174 more fields and one more factory. Accepted as the cost of the added Lisp fields, not claimed as parity. |
| Commits and merge to `dev` | Not done here: left to the owner. |

Switch keeps its required `a` and `b` ports, so every existing `.rays` reads as before,
and takes further branches through `inputs` (the Composite and Blend Shapes pattern).
`Sop.switch ?input a b rest` replaces `Sop.switch ~index list`; four callers changed.
An `input` outside the connected branches is still refused at construction. It is a
passthrough, so it has typed/factory parity for two, three and five branches and a Lisp
cook test, not the every-field cache probe.

Assertions changed in this last pass, all under decisions 6 to 9:

- Refusal became acceptance: Triangulate 2D blank point group; Boolean Detect collision
  group without a collision input; Attribute Randomize fraction sampling with a seed;
  Attribute Interpolate and Attribute Transfer exact group together with a pattern.
- Identity became unchanged geometry: Blend Shapes with no shape; Group Range with fields
  its mode ignores. Group Ranges now expects a disabled rule to stay in the node's text.
- Key spelling: about 90 `contains (Node.parameters n) "..."` literals in
  `lib/procedural/test_*.ml` respelled from the hand-written text to the schema text
  (`selection=point:g` is `group_owner=point;group=g`, `%S` quoting is gone, an option is
  its toggle field). A handful named input wiring (`collision_input=`, `start_source=`,
  `hold_source=`, `roles=`), which is not a parameter; they now name a field of the same
  node, and the wiring stays checked by the input-count assertions beside them.
- Snapshots: projection and pane row totals for the twelve fixtures, and Merge's rows,
  grow by the added fields. The cards do not: a non-primary row left at its default is not shown.
- The workspace-shell focus row is matched by shape, not by the literal node id 336.

Schema text prints a float as the shortest decimal that reads back to the same value
(`radius=1.5`); the cache key keeps its own exact `%.17g` encoding.

## Goal

A SOP node is described once, by its parameter record. The existing PPX derives the Lisp
form, the editor fields, the OCaml function `Procedural.Sop.<key>`, validation and the cache
key from it, so OCaml and Lisp cannot disagree. `rdk` is the lower level and does not change.
No node and no capability is removed. Mechanical edits go through codemods.

## Where we are (measured)

- At the start: 165 typed functions, 159 of them with a node; 36 nodes are on one description (pilot, no regression: `sop.mli` and the
  manifest unchanged, no test edited, byte-identical cooks on one and four domains).
- 123 nodes are still declared twice. `sop_merge --dry-run` over each gives the reason:

| | Why the two declarations do not merge today | Nodes |
|---|---|---|
| A, C | OCaml takes a structured value where Lisp has flat fields; the catalog `build` converts | 62 |
| B, H | The typed function returns its input or builds several nodes; or a small shape difference (no record: Merge, Null, Switch) | 29 |
| D, E | "Not given" means the kernel decides (`?normals` on Box, `?seed` on Mountain, an optional text) | 15 |
| F, I | A hand check the record does not state; a test that pins NaN accepted at construction | 11 |
| G | OCaml has a parameter the editor lacks (`selection` on Clip, Peak, Bend, Normal; two more) | 6 |

- 10 defaults differ between the two declarations (Box connectivity is triangles in OCaml,
  quads in Lisp; list in the pilot report).

One cause sits under every row: the OCaml door and the Lisp door have different shapes.

## Target

The record is the signature. Per node, two things are written by hand: the record and the
cook (record → `rdk` call). The conversion from flat fields to structured kernel values that
the catalog `build` does today stays in the cook, once.

```ocaml
(* Lisp:  (sop/group_invert in :owner "Points" :pattern "top*") *)
Sop.group_invert ~owner:(Owner Group_points) ~pattern:"top*" input
```

Four rules:

1. **Flat.** Each field is an optional labelled argument with the record's default; a vec3
   group is one `Vec3.t`; inputs are positional. Structured values are for callers of `rdk`.
2. **One default**, the Lisp one.
3. **"Kernel decides" is a choice**, not an absent argument: an `"Auto"` entry in the
   field's existing choice list (Group Invert already does this with `Any`). Lisp gains it.
4. **Nothing OCaml-only.** A typed parameter the editor lacks becomes a field. Lisp gains it.

## Steps

Each step leaves the tree green and is worth having without the next one.

| | Step | How | Nodes |
|---|---|---|---|
| 1 | Merge the pilot. Run `sop_merge` on B and H. | Existing tool; they need no decision. | 36 + 29 |
| 2 | Settle the 10 drifts. | Codemod: write the old OCaml default explicitly at each call site that omits it (tests then cannot change), then delete `[@sop.arg_default]`. | — |
| 3 | D, E: add the `"Auto"` choice. F: move the check into `[@sop.validate]`, which the pilot already has. I: update the three tests to refusal at construction, listed in the commit. Then `sop_merge`. | Hand edit of the record, tool for the merge. | 26 |
| 4 | G: add the six fields, each with a cook test. | Hand; `Shared.optional_element_group` already encodes a selection. | 6 |
| 5 | A, C: flatten, one family per commit. | Change the signature, build, and let the compiler list the call sites that pass a structured value. Rewrite those with `codemod rename` plus a per-node table of constructor → field spelling; what the table cannot say is fixed by hand and listed. Then `sop_merge`. | 62 |
| 6 | Delete what is dead. | `codemod prune` and `drop-unused` (never `--cut-tests`); remove the emptied catalog files, `tools/sop_merge`, and the pilot's `[@sop.fn]`, `[@sop.args]`, `[@sop.arg_default]`. | — |

Steps 1 to 4 need no change to any existing OCaml caller except the explicit defaults of
step 2, and bring 97 of 159 nodes to one description. Step 5 is the only large one: 1,650
typed call sites exist, but only those passing a structured value to one of 62 functions
change. Take the count from the compiler before starting it.

## No regression

The pilot's `test_sop_nodes` already does this for 36 nodes; extend it to every node as it
is merged, nothing new is needed:

- cook through the typed function and through the factory with the same values, one and four
  domains, compare bytes (this is also the "OCaml agrees with Lisp" check);
- equal values hit the session cache, each changed field misses it.

Plus, per commit: `flow_manifest.sexp` shows additions only; every checked-in `.rays` passes
`rays-lisp check`; no existing test is deleted, and test edits are the codemod's spelling
changes only; `bench_rdk_ops` and `bench_workspace_lower` show no change at the end of each step.
The construction-refusal, disabled-rule identity and Intersection Analysis assertions explicitly
authorized below are exceptions to the test-spelling restriction.

## Decisions (owner, 2026-10-06)

Lisp is the first-class surface; OCaml is second-class, for tests and integrations
(`AGENTS.md`, Direction). So:

1. The OCaml signatures become flat, the Lisp shape (step 5 goes ahead).
2. The Lisp default wins all 10 drifts.
3. Invalid values are refused when a node is constructed, as the Lisp checker and the editor
   already do. The owner explicitly approved applying this consistently,
   including Group Transfer and any further cook-time invalid-value assertions,
   beyond the three originally identified tests.
4. Group Promotions and Group Ranges follow the Lisp node/cache contract even
   with all rules disabled: retain the node's own parameter/cache identity and
   unchanged cooked geometry. Their two exact-input-object assertions may change.
5. Intersection Analysis follows Lisp for optional text fields: blank output
   names disable attributes, and collision groups are ignored with a
   disconnected collision input. The owner explicitly approved updating its
   two conflicting refusal assertions to verify that behavior.
6. (2026-10-07, applied from the Direction rule in `AGENTS.md` when the owner asked for
   the migration to be finished; say so if any of 6 to 9 should be reversed.) Decision 3's
   other side: where Lisp accepts a value, so does OCaml. A blank group is no group, a
   control the mode ignores is ignored, an exact group and a pattern select their union.
7. A node's parameter text and cache key come from its record only. Tests that pinned
   hand-written key text follow the schema spelling, and fields a mode ignores are still
   identity (decision 4 applied to every node).
8. Switch keeps `a` and `b` and gains the optional repeated `inputs` port.
9. Row-count snapshots and a hard-coded node id are fixtures, not contracts: they follow
   the declared fields.

## Skipped on purpose

- New PPX features (`option` fields, derived range checks): the `"Auto"` choice and the
  existing `[@sop.validate]` cover the same nodes. Add when a node needs a value no choice
  list can hold.
- A separate OCaml-versus-Lisp agreement test and a "no hand-written node" gate test: the
  byte comparison covers the first; the second is one `grep` in review once step 6 is done.
- Generating `sop.mli`: the compiler already checks it against the derived functions.
- An automatic inverter of the `build` mappings for step 5: the compiler finds the sites and
  a rename table rewrites them.
- Line-count promises: the pilot removed about 1,400 lines of node code for 36 nodes; the
  rest is not measured.
