# Packaging the native Metal stack

Prismel is one opam package and one Dune project. `prismel.opam` is generated
from `dune-project`; it must not be edited independently. The supported package
target is macOS on Apple Silicon with SDL3 and Metal available.

## Installed boundaries

The root package installs:

- the public creative-coding API as `prismel`;
- foundational native libraries `prismel.sdl3`, `prismel.sdl3_image`,
  `prismel.sdl3_ttf`, `prismel.sdl3_mixer`, `prismel.metal`, `prismel.ogpu`,
  and `prismel.ogpu_metal`;
- native runtime/command libraries including `prismel.runtime`,
  `prismel.runtime_native`, `prismel.scene_command`, and
  `prismel.scene_execution`;
- ordinary feature libraries such as `prismel.geom`, `prismel.pdk`,
  `prismel.procedural`, and the UI/sketch adapters.

Runtime provider/orchestrator sublibraries are native-only internal
qualification boundaries. Their target types contain only `Native`; they do not
install alternate backends or make backend selection extensible.

The package contains no Raster2, Wap, SDL2/Tsdl, OpenGL compatibility, browser
server, or headless renderer dependency. A native link audit checks Dune
external dependencies and every built executable/shared artifact for forbidden
legacy linkage.

## System prerequisites

The four `packaging/conf-sdl3*` opam packages own stable native dependency
probes. They validate pkg-config metadata plus header/runtime versions for SDL3,
SDL3_image, SDL3_ttf, and SDL3_mixer. Dynamic discovery is the default;
documented static and explicit include/library directory modes fail on missing
metadata or archives rather than changing renderer semantics.

Metal, QuartzCore, CoreGraphics, IOSurface, Foundation, and other used Apple
frameworks are supplied by the macOS SDK and are not opam packages. Binding
generation, provenance, and validation use OCaml/Dune tools. Repository Python
utilities are isolated geometry/Houdini reference tools and never participate
in GPU binding or package generation.

## Install validation

The packaging gate runs release-profile SDL3 discovery fixtures and license
checks, builds `@install`, installs into a temporary relocatable prefix, confirms
`ocamlfind` resolves the installed libraries beneath that prefix, and builds an
independent consumer outside the checkout. Its source build uses a separate
workspace-relative build directory so invoking it from Dune cannot contend for
the caller's build lock.

A fresh-switch release qualification additionally installs native-only opam
dependencies, builds documentation and tests, and inspects the produced package
and linked artifacts. Success in the developer switch or an isolated prefix is
useful local evidence but does not replace that final clean-switch run.

Generated and copied material must retain deterministic provenance. Prismel's
source is MIT; SDL3 family libraries use their external zlib licenses; Apple SDK
headers and frameworks remain system inputs governed by Apple platform terms and
are not redistributed by this package.
