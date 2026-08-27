# Packaging and installed GPU-migration surfaces

Prismel is one opam package and one Dune project. GPU migration libraries stay
under `lib/<name>` and use public Dune sublibrary names; they do not create an
opam package per library. `prismel.opam` is generated from `dune-project` and
must not be edited independently.

The currently installed side-by-side surfaces are:

- SDL: `prismel.sdl3`, `prismel.sdl3_image`, `prismel.sdl3_ttf`, and
  `prismel.sdl3_mixer`;
- native GPU: `prismel.metal` and `prismel.ogpu_metal`;
- portable GPU/software: `prismel.ogpu`, `prismel.raster2`,
  `prismel.ogpu_raster2`, and `prismel.scene_execution`;
- target qualification: `prismel.runtime_next`,
  `prismel.runtime_next_headless`, `prismel.runtime_next_web`,
  `prismel.runtime_next_orchestrator`, and `prismel.runtime_next_input`.

All are emitted by the root `prismel` package. The only additional opam files
are the four existing `packaging/conf-sdl3*` system probes. They test headers,
libraries, versions and pkg-config metadata and contain no Prismel modules.
Legacy Tsdl/SDL2 dependencies remain declared while the old renderer is the
comparison/default implementation; removing them before Phase 5 would make the
package metadata false.

## Native prerequisites

SDL3 and each used extension are declared through `conf-sdl3*`. Dynamic
pkg-config discovery is the default; the documented static and explicit path
modes remain available. Metal and QuartzCore are platform frameworks discovered
by the macOS build and are not opam packages. OCaml dependencies used by the
new stack (`ctypes`, `dune-configurator`, `domainslib`, `yojson`, and threads
from the compiler/runtime) are already owned by the root package.

No Python program participates in SDL3 or Metal generation, provenance, build,
or validation. The mechanical generators and checks are OCaml/Dune targets.
Python tools elsewhere in the repository are unrelated geometry/Houdini
reference utilities and must not become GPU binding glue.

## Install audit, 2026-08-27

The side-by-side tree passed:

```sh
opam exec -- dune build @install --profile release
prefix=$(mktemp -d /tmp/prismel-install-audit.XXXXXX)
opam exec -- dune install --prefix "$prefix" prismel
OCAMLPATH="$prefix/lib" opam exec -- ocamlfind query \
  prismel.sdl3 prismel.metal prismel.ogpu prismel.ogpu_metal \
  prismel.ogpu_raster2 prismel.raster2 prismel.runtime_next \
  prismel.runtime_next_headless prismel.runtime_next_web \
  prismel.scene_execution
```

The temporary prefix contained 2,270 installed files and every queried package
resolved beneath that prefix, not the checkout. This is an install-surface
check, not a fresh-switch dependency proof: Phase 5 still requires a clean
switch without SDL2, full docs/tests, packaging artifacts, and two clean full
validations on one final commit.

Do not publish or split migration subpackages until the atomic selection and
deletion gates pass. Installed comparison libraries may evolve during
qualification, but the public high-level Prismel API remains the compatibility
authority.
