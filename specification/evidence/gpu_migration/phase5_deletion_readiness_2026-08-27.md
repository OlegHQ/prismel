# Phase 5 deletion readiness — 2026-08-27

This is a readiness audit, not deletion authorization. The frozen plan defines
only **D1–D8**; there are no authoritative D9–D12 gates. R1–R12 remain the
renderer prerequisites and must all pass before D1 begins. This matrix does not
rename R9–R12 as deletion gates.

| Gate | Current evidence | Readiness / exact blocker |
| --- | --- | --- |
| D1 Source deletion | SDL3, Metal, OGPU, Raster2 and private runtime-next replacements exist side by side. | **Not ready.** Legacy `tsdl_gfx`, SDL2 compatibility, OpenGL renderer, discovery logic and comparison paths are intentionally still present because default selection and R1–R12 are not complete. |
| D2 Textual absence | Dependency-direction gates constrain new foundational edges. | **Not ready.** The frozen `rg` command necessarily has production matches while D1 is undone. Every eventual residual must be listed; no broad textual exemption is approved here. |
| D3 Link absence | New SDL3/Metal compositions have focused link gates. | **Not ready.** Repository executables still link legacy SDL2/OpenGL through the active stack. A complete `dune describe external-lib-deps` plus `otool -L` artifact sweep is absent. |
| D4 Clean dependency install | Binding/build prerequisites are increasingly explicit. | **Not run.** No fresh switch without SDL2 and no final `opam install . --deps-only --with-test --with-doc` artifact is recorded. |
| D5 License and provenance | Metal/SDL generation audits and committed inventory provenance exist. | **Partial.** Final copied/generated-file census, package notices, extension licenses and release artifact review require human sign-off on the selected commit. |
| D6 Documentation | `AGENTS.md`, backend and Phase 4 evidence describe the side-by-side graph. | **Partial.** Documents must be rewritten after the atomic switch; current documents correctly retain legacy as active/selectable and therefore cannot satisfy final-stack wording. |
| D7 Full validation | Focused libraries and many full subsystem suites are green at their commits. | **Not run.** The frozen clean-build command list has not passed twice on one final clean commit; unchanged examples, docs, web, sanitizer, hardware matrix and shattered-cube release evidence remain. |
| D8 No legacy fallback | Typed runtime-next selection exists privately. | **Not ready.** Public/default Runtime still permits and uses legacy behavior. Capability failure policy cannot be certified until the atomic switch removes every old selection path. |

## Preconditions still open

- R1–R8 need the atomic selected Runtime/Prismel application matrix, unchanged
  public API/examples, native tolerance images and final target/resource runs.
- R9 has useful portable structural evidence in `62447a5`, but native Metal
  upload/pass/encoder/FFI counters are still required.
- R10 has local runtime-next release numbers, not the required interleaved
  same-M1 Phase-0 comparison with five warmed 30-second samples per scenario.
- R11 has exact synthetic prepared cardinality/batching, not the actual
  shattered-cube sketch, cook invariants, 835,104 render vertices or native
  visible/hidden residency and pacing.
- R12 has one passing fixed-ring 30-minute SDL-free Raster2/Wap lane in
  `51cc55d` (23,464,561 frames, 1.73% final-window RSS range, zero target/view
  teardown). It still requires separate selected native, headless and web
  long-run qualification with SDL/audio ownership before deletion.
- Fresh-machine packaging, full Xcode offline shader artifacts, sanitizers,
  leak tooling, ray tracing/capability lanes and required human reviewers are
  external release gates.

Deletion must be one atomic, reviewed phase after those prerequisites pass.
No current Phase 4 commit, including `62447a5` or `8648d38`, is deletion-ready.

## Exact legacy-reference manifest

Captured at `2026-08-27T14:40Z`. This is a deletion plan, not authorization.
The source census used the case-insensitive expression
`tsdl_gfx|\bTsdl\b|SDL2|OpenGL`, excluding `_build`, this evidence directory,
and the frozen plan. It found exactly 64 files. Every match is assigned below;
an exception means the text remains valid after deletion, not that production
may retain a legacy dependency.

### Delete

- Entire standalone binding: `tsdl_gfx/discover.ml`, `tsdl_gfx/dune`,
  `tsdl_gfx/tsdl_gfx.ml`, `tsdl_gfx/tsdl_gfx.mli`, and
  `tsdl_gfx/tsdl_gfx_stubs.c`.
- Superseded legacy-only implementations once their public callers select the
  replacement: `lib/prismel/renderer3d_gpu.ml` and
  `lib/prismel/sdl_compat.ml`.
- Legacy-only direct smoke fixture and dependency:
  `test/headless_smoke.ml` and its stanza in `test/dune`; retain equivalent
  runtime-next headless coverage under its existing typed tests.

### Replace during the atomic switch

- Runtime authority: `lib/runtime/runtime.ml`, `lib/runtime/runtime.mli`,
  `lib/runtime/target.ml`, and `lib/runtime/dune`. Replace SDL2 selection and
  lifecycle with the qualified runtime-next native/headless/web orchestrator;
  do not merely remove the old branches.
- Prismel implementation owners: `lib/prismel/app.ml`, `audio.ml`, `canvas.ml`,
  `event.ml`, `font.ml`, `graphics.ml`, `image.ml`, `image_snapshot.ml`,
  `preview.ml`, `renderer3d.ml`, `scene.ml`, `texture.ml`, `time.ml`, and
  `window.ml`. Their selected execution must move to the already-qualified
  SDL3/OGPU/Raster2/resource adapters before their Tsdl calls disappear.
- Public/private interface leaks: `lib/prismel/app.mli`, `backend.mli`,
  `font.mli`, `graphics.mli`, `image.mli`, `scene.mli`, and `window.mli`.
  Preserve the high-level API manifest while removing raw `Tsdl.Sdl.*` types
  from stable/private surfaces or moving compatibility types to an explicitly
  retired legacy module.
- Snapshot comparison fixtures:
  `lib/prismel/canvas_raster2_snapshot_test.ml`,
  `font_raster2_snapshot_test.ml`, and `image_raster2_snapshot_test.ml`.
  Replace their SDL2 half with frozen artifacts or runtime-next resource
  fixtures before removing the dependency.
- Build/package roots: `lib/prismel/dune`, `dune-project`, and `prismel.opam`.
  Remove `tsdl`, `tsdl-image`, `tsdl-ttf`, `tsdl-mixer`, all four
  `conf-sdl2*` packages, `tsdl_gfx`, and the deleted C-stub discovery inputs
  only after the source switch above.
- User/current-architecture documentation to rewrite after selection changes:
  `README.md`, `AGENTS.md`, `specification/3d-parity.md`, `3d.md`, `api.md`,
  `backend.md`, `color.md`, `composition.md`, `geom.md`, `graphics.md`,
  `image.md`, `input.md`, `packaging.md`, `performance.md`, `project.md`,
  `vec2-mat3.md`, `window.md`, and `workflow.md`.

### Historical/generated exceptions

- `OPTIMIZATION_PLAN.md` is a dated legacy baseline and must retain its measured
  SDL2/OpenGL names with an explicit historical marker.
- `tools/gpu_migration/capture_environment.ml`, `fixture_manifest.ml`, and
  `run_baseline_benchmarks.ml` describe or reproduce the frozen Phase-0 legacy
  environment. Keep them only as non-production evidence tools; they must not
  be dependencies of installed libraries or final default validation.
- `lib/sdl3/generated_inventory.json` contains upstream SDL3 header, hint,
  property, and enum spellings containing “OpenGL”. These are pinned SDK
  inventory data, not an OpenGL dependency, and remain protected by generator
  provenance/drift checks.
- `tools/native_next_link_gate.ml` currently proves that old Prismel/SDL2 and
  SDL3 cannot co-link. After deletion replace it with an absence assertion (or
  retire it if D2/D3 cover the same invariant); do not count its diagnostic
  strings as a production blocker.

### Still-blocking owners

The blockers are the Runtime and Prismel groups above, not the standalone
`tsdl_gfx` directory itself. In particular, current stable/private signatures
still expose `Tsdl.Sdl.renderer`, texture, window, and GL-context values; Scene,
Graphics, Canvas, Image, Font, Audio, Event, Window, and native Scene3 still
execute through them. `lib/prismel/dune` therefore pulls all five SDL2 dynamic
libraries into every transitive consumer, including otherwise geometry-only
benchmarks. D1 cannot begin until the selected runtime-next application/resource
matrix replaces these owners and the unchanged-public-API gate passes.

## Build and link observations

`dune describe external-lib-deps --format=sexp` reports these exact roots:

- `prismel.tsdl_gfx` requires external `tsdl`;
- `prismel.runtime` requires `tsdl`, `tsdl-image`, and `tsdl-ttf`;
- `prismel` requires `tsdl`, `tsdl-image`, `tsdl-ttf`, and `tsdl-mixer`, plus
  internal `tsdl_gfx` and `runtime`;
- `test/headless_smoke` directly requires `tsdl`.

An `otool -L` sweep over every built `.exe`, `.cmxs`, and `.dylib` found 288
linked artifacts: 286 link all of `libSDL2`, `libSDL2_gfx`, `libSDL2_image`,
`libSDL2_ttf`, and `libSDL2_mixer`; one links SDL2/image/TTF; one links only
SDL2_gfx. No artifact declares the OpenGL framework directly; the legacy code
loads its entry points through SDL at runtime.
By top-level build directory the affected artifacts are 171 under `lib`, 52
under `test`, 32 under `tools`, 31 under `examples`, one under `tsdl_gfx`, and
one under `sketches`. This confirms that source-only removal without rebuilding
and sweeping all artifacts would be insufficient for D3.

## Dependency-ordered atomic batches

These are review batches inside one deletion branch. Do not merge an
intermediate batch as the default renderer.

1. **Freeze comparisons and selected replacements.** Convert the three snapshot
   tests and any remaining parity harness to immutable artifacts/runtime-next;
   prove application/resource/input/audio/canvas coverage and the unchanged API
   manifest.
2. **Switch owners.** Make Runtime select only runtime-next and redirect the
   Prismel modules listed above to typed SDL3/OGPU/Raster2 adapters. Remove raw
   Tsdl types from interfaces without changing the high-level API.
3. **Remove implementation leaves.** Delete `renderer3d_gpu.ml`, `sdl_compat.ml`,
   the old headless smoke, then delete the complete `tsdl_gfx/` directory.
4. **Prune build/package edges.** Remove legacy libraries/conf packages from
   Prismel/Runtime/test Dune stanzas, `dune-project`, and `prismel.opam`; perform
   a clean dependency install without SDL2.
5. **Rewrite current documentation.** Update the current-architecture files;
   retain explicitly marked baseline/evidence exceptions and generated SDL3
   inventory.
6. **Prove absence from a clean tree.** Delete `_build`, rebuild twice, then run
   the textual, dependency, install, link, license, API, functional, performance,
   and long-run gates before merging the batches atomically.

## Validation commands for the deletion branch

```text
rg -n -i 'tsdl_gfx|\bTsdl\b|SDL2|OpenGL' \
  --glob '!NEW_GPU_STUFF.md' --glob '!specification/evidence/gpu_migration/**'
opam exec -- dune describe external-lib-deps --format=sexp
opam exec -- dune exec tools/gpu_migration/api_manifest.exe -- --root . --check
opam exec -- dune exec test/gpu_dependency_direction.exe
opam exec -- dune build @all @doc --force
opam exec -- dune runtest --force
opam exec -- dune runtest --profile release tools/packaging --force
```

The final `rg` result may contain only reviewed historical/generated exceptions;
use an exact allowlist rather than excluding broad directories. After the clean
build, enumerate every `.exe`, `.cmxs`, `.dylib`, and installed artifact and
require `otool -L` (and Linux `ldd` in that lane) to contain no SDL2,
SDL2_gfx/image/TTF/mixer, or OpenGL framework/library. Finally run a fresh
temporary-prefix/switch dependency install without those packages and repeat
the installed-consumer, native/headless/web, 30-minute, performance, and
teardown gates required by D4–D8.
