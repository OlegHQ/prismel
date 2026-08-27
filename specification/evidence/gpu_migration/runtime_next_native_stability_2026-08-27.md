# Runtime-next native stability — 2026-08-27

This evidence covers the real Apple M1 SDL3 + Metal + OGPU Metal path. It does
not cover the concurrent headless or web stability runs. The implementation
under test is `6f072b3`, `05ab699`, `4e28cbb`, and `2b66c59`.

## Result

R12 native long-run stability remains **open**. Resource ownership is bounded,
but the second 30-minute run failed its settled RSS high-water criterion. This
is not recorded as a passing plateau.

The first release run used schema 1:

```sh
_build/default/tools/runtime_next_native_stability/runtime_next_native_stability.exe \
  --minutes 30 --report _build/runtime-next-native-stability-30m.json
```

It ran from `2026-08-27T14:00:45Z` through `2026-08-27T14:30:45Z`, rendered
215,765 frames, and produced deterministic rolling hash `ed1f9fcf05a686c5`.
The fixed ring retained 256 of 359 observations (elapsed 520.30–1796.96 s).
Mesh cache cardinality was exactly 64 and pipeline cache cardinality exactly 1
through every retained sample; teardown reported mesh 0, pipeline 0, and Metal
live handles 0 before and after. RSS was a non-monotonic allocator sawtooth:
55,088–110,160 KiB, first retained sample 107,328 KiB, final 86,560 KiB.
That schema did not settle GC/release state or record per-sample Metal handles,
so the RSS result alone was insufficient to qualify the gate.

Schema 2 therefore performs a full major collection and drains the bounded
Metal release queue before each sample. It records live and pending Metal
handles and rejects a second-half retained-window RSS high-water more than
8,192 KiB above the first half. A three-minute discriminator rendered 21,555
frames with hash `ef325520272addf4`: all 35 observations had Metal live handles
104, pending releases 0, mesh cache 64, and pipeline cache 18. Teardown returned
mesh and pipeline caches to 0 and Metal live handles 0→0. Settled RSS still rose
from 87,168 to 109,968 KiB during this short allocator warmup.

The fresh full schema-2 command was:

```sh
_build/default/tools/runtime_next_native_stability/runtime_next_native_stability.exe \
  --minutes 30 --report _build/runtime-next-native-stability-30m-schema2.json
```

It ran from `2026-08-27T14:49:50Z` through `2026-08-27T15:19:50Z`. Cache and
Metal teardown assertions completed, then the explicit plateau assertion
failed: first-half settled RSS high 118,464 KiB, second-half high 134,656 KiB,
a 16,192 KiB increase. Because schema 2 currently raises before serializing a
failed report, no JSON artifact or rolling hash was produced for this failed
run. The exact terminal diagnostic was:

```text
Fatal error: exception Failure("native settled RSS high-water grew: 118464 -> 134656 KiB")
```

## Diagnosis and exclusions

The constant per-sample Metal live count, zero pending releases, fixed cache
cardinalities, and zero teardown delta rule out an unbounded OCaml wrapper or
deferred-release queue. The workload deliberately replaces a shared Metal
buffer nearly every frame across 80 logical keys, resizes every 300 frames, and
allocates readback bytes every 600 frames. The remaining RSS growth is therefore
in transient OCaml/native/driver allocator high-water under churn, but its
16 MiB retained-window increase is still outside the declared gate and is not
waived as harmless.

The run does not qualify MSAA, software-only public Shader3, a host-provided 2×
Retina display, or the separate headless/web targets.
