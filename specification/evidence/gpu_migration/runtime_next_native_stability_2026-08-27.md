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

## Controlled diagnosis and repair

Schema 3 (`8289fdf`, `a926db6`, `5d94462`) adds independent payload, resize,
and capture switches plus settled OCaml heap/live-word, Metal created/released,
live/pending, and resident-byte observations. Two-minute release A/B runs
isolated payload replacement without resize or capture:

| Case | Settled RSS first→last | Range | Metal created/released | Live/pending |
|---|---:|---:|---:|---:|
| Stable payload | 86,224→87,280 KiB | 86,224–87,280 | +66,000/+66,000 | 102/0 |
| Changing payload, before repair | 87,328→103,536 KiB | 87,328–103,536 | +79,200/+79,200 | 165/0 |

Thus resize and capture were not necessary to reproduce the growth. A changing
single draw lost its logical key during one-mesh coalescing, then allocated and
destroyed one extra shared Metal buffer every frame. Commit `275b3bf` preserves
single-mesh keys, reuses a same-sized completed buffer in place, reserves every
buffer already referenced by the current submission, and acquires before cache
mutation so device loss remains atomic. Commit `20ce803` makes the bounded
64-entry cache repurpose a same-sized evicted buffer when cycling 80 keys.
Focused mock coverage proves duplicate-key/different-payload isolation,
device-loss non-mutation, exact upload cardinality, and zero live objects; the
real Metal pixel/resize fixture is exact with zero teardown delta.

After repair, a three-minute payload-only run rendered 21,568 frames. RSS was
76,432–87,296 KiB and ended 9,920 KiB below its first sample; live handles were
constant 165, pending releases 0, and created/released deltas were exactly
+102,000/+102,000 (five handles per sampled frame interval, equal to the stable
baseline rather than the former six).

The unchanged full payload + resize + capture discriminator then ran five
minutes/35,921 frames with hash `93e0aa1c2f881d96`. Settled RSS was
80,144–83,776 KiB and ended 83,328→80,352 KiB. All 59 observations held mesh
cache 64, pipeline cache 48, Metal live handles 165, and pending releases 0;
created/released deltas matched at +174,232, and teardown returned caches and
Metal live handles to zero. This short combined run qualifies a fresh
30-minute attempt; it does not itself close R12.
