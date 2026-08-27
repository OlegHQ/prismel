# R10 workload-equivalence normalization — 2026-08-27

The first full R10 report is valid as process/timing evidence but invalid as a
legacy-versus-candidate performance comparison. The benchmark implementations
did not execute equivalent work:

- legacy Basic/PXUI/Canvas execute the public scenes in `bench_renderer`,
  including images, text, paths/widgets, transforms, and per-frame Canvas
  mutation;
- the candidate lanes execute synthetic three-vertex meshes with repeated
  indices and do not reproduce those public scenes or their pixels; and
- the old web 2D lanes ran hundreds of thousands of unpaced frames while
  legacy/native/headless ran only thousands, making total allocation values
  incomparable.

The Scene3 mismatch was even stronger: 110,592 repeated synthetic triangles
were compared with twelve transformed 96×48 public spheres plus camera,
material, lighting, culling, depth, four-sample MSAA, and text. The canonical
Scene3 artifact and public/staged bridge now pin the real topology, twelve
transforms, camera projection, material/ambient/directional light, culling,
depth, MSAA, representative pixels, and one/four-domain identity.

## Hardened validator

The R10 protocol now refuses to compare Basic/PXUI/Canvas unless every target
reports:

- one identical non-empty workload signature and framebuffer hash;
- one identical positive work-unit cardinality;
- comparable scheduled frame counts within 10%; and
- allocated and promoted bytes normalized per measured frame.

Raw totals remain recorded; normalization does not remove or relax any frozen
timing, memory, or regression threshold.

The focused validator test constructs all 16 target/scenario cells, passes an
equivalent matrix, then changes one web Basic workload signature and proves the
report is rejected. Both canonical Scene3 tests also pass:

```text
R10 validation passed
R10: basic workload signatures differ
R10 equivalence validator rejects mismatched work
R10 legacy-equivalent Scene3 artifact: sphere96x48, instances12, exact 1/4-domain
R10 Scene3 public/staged equivalence: topology/transforms/material/light/camera/MSAA/pixels exact
```

An actual 16-cell short run collected 16 samples with zero child failures. Its
raw report is `_build/r10-equivalence-smoke.json`, SHA-256
`f862a26fdb89923eec351b58a4dd23fd98da0579298d90e84da1d7cb9ac293fc`.
The hardened validator correctly rejects it at
`runtime-next-native/basic lacks required equivalence workload_signature`.
This rejection is the required safety result: native and legacy emitters have
not yet been converted to the same frozen Basic/PXUI/Canvas artifact, so no
performance ratio is accepted or threshold weakened. The smoke ran from a
dirty shared tooling worktree and is integration evidence only.

The target benchmark's fixed-rate checkpoint separately proves headless/web
use identical framebuffer digest `ce338fe6899778aacfc28414f2d9498b` for their
current synthetic Basic workload and reports per-frame allocation. That is
target-to-target pacing evidence, not legacy workload equivalence.
