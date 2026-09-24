# Presentation exact-125 public reachability audit

Audited after `df55fd4` and `57c4da5`. The manifest remains exact125 with
digest `82710196daca14152ffc09bf9079d55ce1cd0e8dbdcfe9fbd4fb93055e680d92`.

The current safe API reaches **21 actual native selectors**. Including the 13
inventory property declarations that are semantic companions of those calls,
the exact safe-reachable closure is **34 IDs**. The other **91 IDs are not
publicly reachable**. Generated/native availability does not make those IDs
safe or bound.

The sorted safe-closure digest is
`56d88ea9c2178e70c2b1b8c1cbb48992575c319f927502a564168987899a5721`;
the sorted missing-public digest is
`9cb5b31d2efb89315a5aae04303e0c5819b272791b66d17c9ea24158ecdd8aa7`.
Together they close the exact manifest without overlap.

The 21 selector-backed operations are layer creation/configuration (device,
drawable size, pixel format, framebuffer-only, drawable count, timeout,
display-sync and transaction presentation), drawable acquisition/texture,
three presentation timing modes, scheduled/completed callbacks, render encoder
creation, and render-pass creation plus width/height/array/sample-count setup.
`Metal_layer.config`, `Metal_layer.size`, `Metal_layer.device`, `Drawable.layer`,
and render-pass snapshot getters return retained OCaml metadata and therefore
do not make the corresponding native getter IDs reachable.

## Missing public surface (91 IDs)

The authoritative machine-readable list is
`Binding_presentation_public_audit.missing_public`. It partitions as follows:

- Layer color/HDR policy is absent: colorspace, EDR metadata, and extended
  dynamic range getters/setters; all native layer getters are also absent.
- Command-buffer diagnostics and control are absent from this batch's safe
  route: command queue, error options, GPU/kernel timestamps, logs, retained
  references, enqueue, debug groups, event waits/signals, and specialized
  encoder constructors.
- Render-pass attachment graphs and advanced state are absent: color/depth/
  stencil/sample-buffer attachments, rasterization-rate map, visibility result,
  sample positions, tile/imageblock/threadgroup state, and color mapping.
- `CAMetalDrawable.layer` is not invoked; `Drawable.layer` returns the retained
  OCaml parent. The private layer record ID is metadata-only.

## Conformance gaps before promotion

- No safe color-space/HDR configuration API or capability/rejection matrix.
- No public attachment graph with owned child retention, same-device checks,
  format/sample-count validation, mutation-after-encoding policy, or teardown
  stress.
- No safe event/specialized-encoder paths for the command-buffer IDs.
- The native lifecycle fixture covers resize, timeout, colorspace and stress,
  but the public test does not exercise loss recovery, resize reconfiguration,
  all three timing modes, invalid/NaN times, callback exceptions, callback
  roots across early native failure, or a 10,000-frame no-handle-delta loop.
- Public tests do not verify wrong-device drawable rejection, command-buffer
  destruction before completion, render-pass invalid ranges beyond nonpositive
  dimensions, or native getter agreement with the OCaml snapshots.

Therefore only the exact 34-ID semantic closure is presently safe-reachable;
the presentation125 family is not yet fully safe/bound.
