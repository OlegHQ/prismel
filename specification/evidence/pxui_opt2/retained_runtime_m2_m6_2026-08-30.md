# Retained PXUI runtime M2-M6 candidate evidence

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

This commit introduces the owned runtime authority used for the M2-M6
migration. It does not declare M2-M6 complete: all widgets, text/IME, retained
painting, and the old compatibility path still require vertical migration and
deletion.

## Implemented

- public `Pxui.Spec` compatibility boundary and explicitly owned
  `Pxui.Runtime`;
- generation-checked IDs and free-slot reuse;
- geometrically growing packed planes for kind, hierarchy, flags, dirty bits,
  numeric/text values, row/control bounds, depth, and z-order;
- explicit-name reconciliation and deterministic positional fallback for
  unnamed nodes;
- keyed state preservation across reorder and stale focus/capture rejection;
- typed reconcile/style/layout/prepaint/text/paint/compose/accessibility queues
  with packed membership planes and pass-order guards;
- coalescing of repeated writes to one queued visit;
- hidden-runtime visual-pass suppression and one-time drain after showing;
- fixed-row retained layout, visible-slice virtualization, packed hitboxes,
  and O(visible rows) scrolling;
- per-node paint-validity retention;
- O(1) captured slider/int-slider routing after the initial visible-slice hit;
- explicit runtime destruction and cold payload release;
- Sketch UI ownership/reconciliation/teardown for inspector and 2D/3D camera
  runtimes.

## Exact regressions

`lib/pxui/test_pxui_layout_snapshot.ml` now proves:

- unchanged spec performs zero mutation and changes no counter/generation;
- one slider value touches one stable node and does not dirty layout;
- keyed reorder preserves exact IDs;
- accordion children retain exact parent IDs;
- removed focus/capture IDs are stale and rejected;
- 100,000 distinct create/delete reconciles remain at capacity 8 with exact
  create/remove cardinality;
- three writes schedule one text and one paint visit;
- a hidden runtime visits no visual nodes and showing drains once;
- a 10,000-row panel lays out/hit-tests the committed visible slice;
- scrolling the 10,000-row panel visits/repaints at most 12 rows;
- a 1,000-widget three-event retained drag allocates 928 bytes in the strict
  regression run, below OPT2's 8-KiB final interaction gate.

## Logarithmic sweep

Command:

```sh
for n in 10 100 1000 10000; do
  PRISMEL_PXUI_BENCH_WIDGETS=$n PRISMEL_PXUI_BENCH_REPEATS=5 \
    dune exec tools/bench_pxui.exe
done
```

| Widgets | Compatibility drag | Retained drag | Unchanged reconcile |
| ---: | ---: | ---: | ---: |
| 10 | 12,984 B / 4 us | 1,072 B / 1 us | 96 B / <1 us |
| 100 | 82,104 B / 21 us | 1,072 B / <1 us | 96 B / <1 us |
| 1,000 | 773,304 B / 376 us | 1,072 B / 1 us | 96 B / <1 us |
| 10,000 | 7,685,304 B / 3.703 ms | 1,072 B / 1 us | 96 B / <1 us |

Times are five-run medians from the M1 host and are diagnostic at submicrosecond
resolution. Allocation and asymptotic behavior are the primary evidence.

## Native integration diagnostic

The exact five-second hidden shattered run after Sketch UI runtime ownership
produced 587 frames at 117.25 FPS, 8.366 ms median, 10.076 ms p95, and 11.145
ms p99. It allocated 14,176,744 bytes, or 24,151 bytes/frame. This is within
measurement noise of the preceding 24,135 bytes/frame, showing that hidden
retained runtimes add no recurring frame allocation. Whole-frame native wrapper
allocation remains separate from the UI/Scene staging budget.

## Verification

```sh
dune runtest lib/pxui lib/sop_ui lib/pxui_graph lib/sketch_ui
dune exec test/test_prismel.exe
dune exec test/test_easy_camera2.exe
dune exec lib/prismel/test_scene3_native_lowering.exe
dune build @all
git diff --check
```

All commands passed before commit.
