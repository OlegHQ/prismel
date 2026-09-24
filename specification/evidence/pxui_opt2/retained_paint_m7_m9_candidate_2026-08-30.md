# Retained PXUI paint M7-M9 candidate evidence

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

This checkpoint completes the first production all-widget retained-paint
candidate. It does not declare M7-M9 or the overall plan complete. Native
multi-segment submission, retained graph/workspace/status boundaries, shaped
glyph runs, interactive-state pixel qualification, and final whole-frame
budgets remain open.

## Implemented

- complete existing Scene2 display-list command vocabulary: clear, blend,
  clip/transform stacks, solid quads, owned geometry references, images,
  glyph runs, and debug text;
- checked reserve/geometric growth and allocation-free pre-reserved quad
  emission;
- typed managed-image bindings validated once by `Scene.display_list`, with
  generation changes invalidating retained replay;
- shared `Scene_command.Shape2` tessellation used by ordinary Scene and PXUI
  for exact line/polygon/rect/rounded-rect/ellipse topology;
- retained text handles that explicitly own provided-font images or borrow the
  reference-counted automatic-font cache, plus deterministic font generations;
- one reusable builder and stable segment identity/version per visible widget;
- independent panel, scrollbar, and widget paint boundaries;
- all PXUI widget kinds on the retained painter with compatibility command
  order, colors, geometry, text placement, and resource identity;
- runtime synchronization for hover, active, focus, numeric editing, and IME
  composition;
- exact old/new focus/active/hover dirty transitions;
- a 256-entry and 64-MiB widget display-list cache that evicts cold non-visible
  slots and releases builders and text leases;
- display-list build/reuse/eviction/entry/byte diagnostics;
- production Sketch UI inspector and 2D/3D camera panels routed through their
  owned runtime, preserving existing camera overlays;
- bounded native-stage identity caching for physically unchanged retained
  scenes with allocation-light managed-resource generation stamps.

## Exact regressions

- all-widget normal-state compatibility is compared as an exact flattened
  world-space draw stream, including vertices, indices, colors, clips, painter
  order, image destinations, and resource IDs;
- label/button unchanged scene identity allocates 96 bytes total across 10,000
  `Runtime.scene` calls;
- an unchanged all-widget native-stage cache hit allocates 80 bytes/call;
- a three-event 1,000-widget retained slider drag allocates 1,024 bytes;
- hover rebuilds exactly one button segment;
- 10,000-label viewport churn stays within 256 entries/64 MiB, records
  evictions, and returns automatic text references to baseline on destroy;
- display-list reset, payload ownership, validation, capacity, resource
  generation, transformed lowering, and stable identity tests pass.

## Native measurements

Commands:

```sh
PRISMEL_RENDERER_BENCH_WARMUP=2 PRISMEL_RENDERER_BENCH_SECONDS=5 \
  dune exec tools/bench_shattered_renderer.exe -- visible
PRISMEL_RENDERER_BENCH_WARMUP=2 PRISMEL_RENDERER_BENCH_SECONDS=5 \
  dune exec tools/bench_shattered_renderer.exe -- hidden
```

Visible produced 320 frames in 5.003 seconds: 63.97 FPS, 15.422 ms median,
18.675 ms p95, and 24.031 ms p99. It allocated 385,105,840 bytes, or
1,203,456 bytes/frame. This fails the OPT2 visible allocation and p95 gates.

Hidden produced 587 frames in 5.008 seconds: 117.22 FPS, 8.397 ms median,
10.017 ms p95, and 11.225 ms p99. It allocated 14,308,456 bytes, or
24,375 bytes/frame, with about 29 promoted bytes/frame. This remains above the
final hidden allocation gate but close to the preceding hidden baseline.

The built-in visible Memprof lane ranked `List.map`, `List.rev_append`,
`Render_ir.create_internal`, resource `List.sort_uniq`, `Scene.ordered_items`,
`Scene.emit`, and native submission conversions as the largest remaining
owners. This is direct evidence for continuing M10-M11 rather than attributing
the end-to-end result to PXUI paint.

## Verification

```sh
DUNE_CONFIG__BACKGROUND_ACTIONS=disabled dune build @all
DUNE_CONFIG__BACKGROUND_ACTIONS=disabled dune runtest \
  test lib/scene_command lib/prismel lib/pxui lib/sketch_ui --force
git diff --check
shasum -a 256 OPT2.md
```

All build, test, API-manifest, dependency-direction, and native-only gates
passed before commit. The native performance gates above remain explicitly
failing and prevent milestone or goal completion.
