# M10 local memory and capture harness audit — 2026-08-29

This audit started from
`2cd7fbe3ad27d1670dab2c4c9e16c12e664af160` on the local Apple M1. It
classifies which M10 qualification work is executable on this host and repairs
one concrete false-pass hole in the memory-check harness. It does not close M10:
the evidence predates the final clean release commit, and the Xcode GPU trace
inspection lane is unavailable on this installation.

## Host and tool availability

The read-only host audit used:

```sh
git rev-parse HEAD
sw_vers
uname -m
xcode-select -p
clang --version
command -v leaks
test -f /usr/lib/libgmalloc.dylib
/usr/bin/xctrace version
xcrun --find xctrace
xcrun --find metal
find /Library/Developer/CommandLineTools/usr/lib/clang \
  -path '*darwin/libclang_rt.*san*' -type f
man -w MetalValidation
```

The host reports macOS 26.4.1 (25E253), arm64, and Apple clang 21.0.0
(`clang-2100.1.1.101`). `/usr/bin/leaks`, `/usr/lib/libgmalloc.dylib`, and the
ASan, UBSan, and TSan Darwin runtimes are installed. The selected developer
directory is `/Library/Developer/CommandLineTools`. Although the system
`/usr/bin/xctrace` shim exists, it exits with:

```text
xcode-select: error: tool 'xctrace' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

`xcrun --find xctrace` and `xcrun --find metal` likewise fail. This is not an
offline-shader blocker: Prismel compiles MSL at runtime and must not acquire an
Xcode command-line shader dependency. It does mean that recording and opening
an actual `.gputrace` with Xcode Instruments remains an optional external
qualification lane rather than a build or runtime dependency.

The installed `MetalValidation(1)` manual documents `MTL_DEBUG_LAYER` and
`MTL_SHADER_VALIDATION`, so API and shader validation can be exercised locally
against the real conformance executable when GPU execution is scheduled. The
safe counter fixture is also real hardware work: it creates a counter sample
buffer, samples command boundaries when supported, submits the command buffer,
and resolves nonempty counter bytes. By contrast,
`test_metal_capture_manager_safe.ml` currently validates capture descriptor,
scope, capability, ownership, and rejection behavior but deliberately does not
claim that it recorded or inspected a GPU trace.

## Memory-check harness repair

The build switch already instruments the Objective-C++ bridge, bytecode stub,
and final executable, and it permits combined `address,undefined` while keeping
ThreadSanitizer exclusive. The checker previously had four qualification holes:

- the documented combined build was executed through `--mode address`, so no
  `UBSAN_OPTIONS` or UBSan report scan was installed;
- sanitizer modes did not prove that the executable was instrumented, allowing
  an ordinary executable to exit zero and appear to pass;
- the report scan omitted ASan deadly-signal/abort, LeakSanitizer, Apple ASan
  `failed to munmap`, and several TSan/Guard Malloc fatal forms;
- mode parsing and report/linkage policy lived inside the process runner and had
  no pure focused test.

The repaired checker adds a canonical `address-undefined` mode, installs both
ASan and UBSan runtime options, and scans both report families. Before launch,
sanitizer modes inspect each executable rather than trusting its artifact path.
`otool -L` must show the selected sanitizer runtime. On Darwin, Apple clang's
combined ASan/UBSan link uses `libclang_rt.asan_osx_dynamic.dylib`, which also
supplies UBSan handlers, rather than a second UBSan dylib. The combined checker
therefore additionally requires `ubsan_handle_` imports in `nm -u` output.

This linker behavior was confirmed without producing an artifact:

```sh
clang -### -x c /dev/null -fsanitize=address,undefined \
  -o /tmp/prismel-memory-check-link-dry-run
```

The printed Apple linker invocation includes
`libclang_rt.asan_osx_dynamic.dylib`, UBSan-instrumented compilation, and no
separate `libclang_rt.ubsan` dylib. Standalone `undefined` mode still requires
the UBSan dylib. The policy is now a private pure module with a focused test for
canonical mode parsing, runtime and instrumentation requirements, ordinary
binary rejection, combined diagnostic families, and stronger Guard Malloc
fatal markers.

## Qualification boundary

The following lanes are locally executable once exclusive Dune/GPU access is
available:

- pure checker-policy tests and an ordinary-binary negative preflight;
- isolated combined ASan/UBSan and TSan Metal builds and checker runs;
- `/usr/bin/leaks` ownership/conformance checks and Guard Malloc conformance;
- Metal API/shader validation and real counter sampling on this M1.

The prior 2026-08-27 memory record remains useful historical evidence, including
its honest Apple ASan/AGX VM interoperability blocker, but it does not qualify
the current commit. Actual Xcode GPU trace recording/inspection and hardware
that this M1 does not provide remain external. No xctrace, Xcode, offline shader
tool, or capture-framework dependency was added.

## Focused non-GPU verification

After the R10 lane released Dune, the checker and its pure policy fixture were
built in the release profile and the fixture was executed:

```sh
opam exec --switch=. -- dune build --profile release \
  tools/metal/test_check_memory_rules.exe tools/metal/check_memory.exe
opam exec --switch=. -- dune exec --profile release \
  tools/metal/test_check_memory_rules.exe
```

Both commands exited 0. The fixture reported:

```text
Metal memory-check rules: linked-runtime preflight and diagnostic families passed
```

Before testing the negative preflight, read-only `otool -L` and `nm -u` checks
confirmed that `_build/default/lib/metal/test_metal.exe` had no sanitizer
runtime or UBSan-handler match. The exact checker invocation was:

```sh
_build/default/tools/metal/check_memory.exe \
  --mode address-undefined --artifacts _build/default
```

It exited 1, as required, before launching the executable:

```text
Metal conformance is not instrumented for address-undefined; missing linked runtime(s): libclang_rt.asan
```

No real Metal, sanitizer, Leaks, Guard Malloc, counter, validation, or GPU
capture lane was executed by this bounded harness verification. Those remain
qualification work to schedule exclusively against the intended final
artifacts.
