# macOS native memory and sanitizer qualification — 2026-08-27

This is an external-tool qualification of finite real-M1 Runtime-next and Metal
executables. It made no source or Dune changes. Isolated sanitizer build trees
were `_build_asan` and `_build_tsan`; generated logs and reports under `_build`
are not committed.

## Host and toolchain

- macOS 26.4.1 (25E253), arm64 Apple M1
- Apple clang 21.0.0 (`clang-2100.1.1.101`)
- OCaml 5.3.0, Dune 3.20.2
- `/usr/bin/leaks`, report format 4.0
- Apple ASan runtime:
  `/Library/Developer/CommandLineTools/usr/lib/clang/21/lib/darwin/libclang_rt.asan_osx_dynamic.dylib`

## `leaks --atExit`

All commands used `MallocStackLogging=1`. They exited successfully:

```sh
MallocStackLogging=1 leaks --atExit -- \
  _build/default/lib/runtime_next/native_qualification/runtime_next_native_qualification.exe

MallocStackLogging=1 leaks --atExit -- \
  _build/default/tools/runtime_next_native_stability/runtime_next_native_stability.exe \
  --minutes 0.1 --report _build/leaks-runtime-next-stability-smoke.json

MallocStackLogging=1 leaks --atExit -- \
  _build/default/lib/metal/test_metal_stress.exe
```

| Executable | Allocated nodes/bytes visible to `leaks` | Leaks | Peak footprint |
|---|---:|---:|---:|
| Runtime-next native qualification | 50,718 / 9,117 KiB | 0 / 0 bytes | 42.1 MiB |
| Runtime-next stability smoke | 32,686 / 7,170 KiB | 0 / 0 bytes | 29.5 MiB |
| Metal 13-lane ownership stress | 982 / 2,137 KiB | 0 / 0 bytes | 5,329 KiB |

The Metal stress run completed all 13 isolated ownership lanes, including
100,000-handle buffer, argument-table, and texture/sampler lanes and the
10,000 deferred no-copy callbacks. Runtime-next qualification retained exact
native/software hashes and reported Metal live handles 0→0.

On this macOS version `leaks` printed that the launched process was “not
debuggable” and that security restrictions limited reading restricted memory.
The zero-byte result therefore applies to memory reachable by the permitted
inspection; it is not a claim that SIP-protected driver allocations were fully
introspected. MallocStackLogging also warned that its own pages could not be
tagged `no_footprint`, so reported footprints include diagnostic overhead.

## Address and undefined behavior sanitizers

The repository's existing typed sanitizer switch was used without modifying
the build:

```sh
PRISMEL_METAL_SANITIZERS=address,undefined opam exec -- dune build \
  --build-dir _build_asan \
  lib/metal/test_metal_presentation_safe.exe \
  lib/metal/test_metal_command_support121_safe.exe

ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  _build_asan/default/lib/metal/test_metal_presentation_safe.exe

ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  _build_asan/default/lib/metal/test_metal_command_support121_safe.exe
```

Both bridge-owning safe suites exited 0 with no ASan or UBSan report. Leak
detection was deliberately disabled in ASan because `/usr/bin/leaks` supplied
the separate leak qualification above.

Two broader ASan attempts are not counted as passes:

- `test_metal_stress.exe` aborted its own deterministic RSS gate because ASan
  overhead produced a 138,133,504-byte settled delta against its ordinary
  8,388,608-byte limit. The test did not reach a sanitizer finding.
- Full `test_metal.exe` encountered an Apple ASan/AGX interoperability failure:
  `AddressSanitizer failed to deallocate 0x20000 ... error code: 22`, followed
  by an internal `unable to unmmap` CHECK failure. The module map points at the
  system `AGXMetal13_3` driver and the Apple ASan runtime; no project stack or
  UBSan diagnostic was emitted. This host/tool combination cannot qualify a
  full real-GPU ASan run.

An attempted isolated Runtime-next qualification rebuild was also stopped by
concurrent source evolution adding new required render-state fields; it was a
compile-time fixture drift, not a sanitizer result, and is not represented as
coverage.

## Thread sanitizer

TSan was kept separate from ASan/UBSan as required by the repository build
configuration:

```sh
PRISMEL_METAL_SANITIZERS=thread opam exec -- dune build \
  --build-dir _build_tsan lib/metal/test_metal.exe

TSAN_OPTIONS=halt_on_error=1:report_signal_unsafe=0 \
  _build_tsan/default/lib/metal/test_metal.exe
```

The full Metal conformance executable exited 0 with no TSan report. This run
includes its OCaml Domain wrong-domain/rejection checks and the real Apple M1
command, resource, compiler, reflection, and pipeline coverage. It does not
claim that Metal driver internals are TSan-instrumented, nor does it replace a
dedicated stress test for independent CPU worker algorithms.

## Outcome

No isolated bridge ownership defect was identified, so no bridge source was
changed. Reachable-memory leak checks and the feasible sanitizer suites are
green. Full real-GPU ASan remains unavailable because of the documented Apple
ASan/AGX VM incompatibility; that limitation is not treated as a pass.
