# Deferred after the lean restructure

State on 2026-10-10: nothing is committed. `dune build @all`, `dune build @doc`,
`git diff --check` and window-free `dune runtest` pass. Restore points are the git refs
`refs/checkpoints/lean-0` (HEAD before the work) to `lean-6` (after renames and splits).

## Not verified

- `dune build @runtest-native` has not completed once. The only attempt was stopped after
  `test_workspace_ir.exe` ran for 15 minutes under `RAYS_SCENE3_FLOAT32_COMPARE`: the rule
  that replaced the old gallery-only float32 check sweeps every workspace. That rule
  (`test_scene3_float32_gallery` in `test/dune`) is now under `@qualification`, and the
  native run has not been repeated since.
- `dune build @smoke` and `@smoke-all` have not been run. `examples/particles` and
  `examples/procedural_modeling` now generate `lisp.exe` like the other examples (built,
  not launched).
- `@qualification` has not been run. The path tracer, runtime and OGPU changes from the
  optional-parameter removal are covered only by the build and the window-free tests.
- `lib/pxui/fixtures/kit_panel_2x.png` was regenerated after six widgets were deleted and
  was checked by eye only.
- The gallery shapes rebuilt in Lisp (`fibonacci`, `disc`, `gyroid`, the star as a
  `sop/sweep`) were not compared visually with the old OCaml ones.

## Tests that got weaker

- Many `rdk`, `sop` and `scene_execution` tests were cut statement by statement when their
  subject was pruned. The survivors pass, but nobody has read what each one still covers.
  `test_scene_execution_metal`, `test_automatic_scratch` and `test_offscreen_metal` were cut
  twice.
- `test_instances` can no longer pass `~grain`, so its one-domain against four-domain
  comparison runs at the default grain only.
- The zero-budget carry case in `test_materials` is gone; an over-budget carry is untested.
- About 130 "rejected" cases in `lib/sop/test_nodes.ml` were removed because Lisp cannot
  write a non-finite number (`nan` and `inf` are unbound). Non-finite input is now tested
  only through `Node.apply_parameters` in the inspector tests.
- The gallery's own `--check-all` cook is gone; `test/test_workspace_ir` sweeps the gallery
  instead.

## Leftovers still in the tree

- Test-only hooks kept because native tests, benches or pure tests use them: `Session`
  `Private` hooks, `Scene.Private.stage` and `to_ir`, `Mesh.Private.triangle_count`,
  `Predicates.Private.segment_triangle_code_packed`, runtime and execution counters.
- Optional parameters kept: those passed by PPX output (`Param.field`,
  `Edit_graph.factory_slots`), `Workspace.load ?ops`, `Ty.register ?color ?default`,
  `Shape_batch.Builder.circle ?stroke_width`, the 12 in `rays_editor/native_qualification`,
  and `Editor.create ?lights ?presets`.
- Fields that are constant but still threaded: `Paint.scale/tx/ty` and the `Ui_batch`
  transform in `pxui`, `Scene3.depth_clear` and `stencil_clear`, the `Easy_camera` binding
  `key`, `Light.attenuation.linear`, the path tracer `scale`.
- `lib/sop/sop_topology.ml` keeps its prefix (`Topology` would shadow `Rdk.Topology`), and
  `Leader.keymap3` keeps its suffix (`Leader.keymap` is taken).
- `lib/rays` is still 30 modules: the editor is built on `Sketch`/`Frame`/`Scene`, and
  `examples/pathtracer` plus sketches `cube_cage`, `shattered_cube` and `voxel_wall` are
  still OCaml.
- Large files not split, or only partly: `lib/rdk/test_rdk.ml` (3,914 lines, one `run ()`),
  `lib/pxui_graph/scope_pane.ml` (2,682 lines after the wires moved out),
  `lib/rays_editor/environment.ml` (about 940 lines).
- `_out/` (53 MB, untracked) was not deleted.

## Known costs and behaviour changes to confirm

- A `sop/merge` that names `:source_attribute` merges its inputs twice.
- `/ e` on a scene with no World writes a `scene/world` member plus a `sky` world graph; it
  used to adopt a host-made daylight World.
- Deleting a World from the scene leaves the world graph alone; it used to write
  `(world/none)`.
- The gallery build prints two `W_SOFT_RANGE` warnings for `sop/grid :columns 100 :rows 100`.

## Lisp gaps

- No literal for a non-finite number.
- No kind that builds a polygon from explicit points (`poly_fill` returns a closed curve
  unchanged); the gallery star uses `sop/sweep :caps true` instead.
- An image-typed external cannot be passed through `Lisp_sop.node ~with_`.
- What `chromatic_drift`, `pastel_flow` and `code_quadtree` need before a port is listed in
  `README.md`, "Not yet ported to Rays Lisp".

## Docs

- The proposal artifact has not been updated with the outcome.
