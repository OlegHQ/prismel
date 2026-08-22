# SDL3 conf packages

The SDL3 implementation is not in these directories.  It is four ordinary
OCaml/Dune libraries under `lib/sdl3`, `lib/sdl3_image`, `lib/sdl3_ttf`, and
`lib/sdl3_mixer`.  These small `.opam` files only declare and probe the native C
libraries that those OCaml libraries link.  Keeping the probes separate lets
opam install the system dependency before Dune compiles the bindings and lets
applications depend only on the extensions they use.

Prismel owns four standalone opam conf packages for the exact stable SDL3
releases covered by the generated API/ABI inventories. They live outside the
Dune package root so opam treats them as probe packages, not as Dune-built
libraries.

For a checkout whose opam repository does not yet contain these packages, pin
the local definitions before installing Prismel dependencies:

```sh
opam pin add --no-action --yes conf-sdl3 ./packaging/conf-sdl3
opam pin add --no-action --yes conf-sdl3-image ./packaging/conf-sdl3-image
opam pin add --no-action --yes conf-sdl3-ttf ./packaging/conf-sdl3-ttf
opam pin add --no-action --yes conf-sdl3-mixer ./packaging/conf-sdl3-mixer
opam install . --deps-only --with-test --with-doc
```

The package probes use `pkg-config --exact-version`. An OCaml/Dune repository
test also compiles, links, and executes a version probe for each library, which
catches header/runtime mismatches that `pkg-config` alone cannot detect.

## Dune discovery

Dynamic linking is the default.  Set `PRISMEL_SDL3_LINK_MODE=static` to ask
pkg-config for its static/private dependency set and select the component's
`libSDL3*.a` archive.  Static mode fails early when the package metadata or own
archive is absent; it never silently falls back to a dynamic SDL library.
Platform frameworks can remain dynamic even when the SDL archives are static.

Each component also accepts explicit include and library directory overrides:

```text
PRISMEL_SDL3_INCLUDE_DIR       PRISMEL_SDL3_LIB_DIR
PRISMEL_SDL3_IMAGE_INCLUDE_DIR PRISMEL_SDL3_IMAGE_LIB_DIR
PRISMEL_SDL3_TTF_INCLUDE_DIR   PRISMEL_SDL3_TTF_LIB_DIR
PRISMEL_SDL3_MIXER_INCLUDE_DIR PRISMEL_SDL3_MIXER_LIB_DIR
```

Override directories must exist.  In static mode the library directory must
contain the component archive, while pkg-config still supplies its transitive
link flags.

The committed OCaml tests exercise core and all extensions through dynamic,
static, and explicit-path discovery with isolated pkg-config metadata.  Run
both profiles and the installed-consumer checks with:

```sh
opam exec -- dune runtest tools/packaging --force
opam exec -- dune runtest --profile release tools/packaging --force
opam exec -- dune exec tools/packaging/check_installed_consumer.exe -- \
  --root . --profile dev
opam exec -- dune exec --profile release \
  tools/packaging/check_installed_consumer.exe -- --root . --profile release
```

The consumer checker installs `prismel` into a temporary relocatable prefix,
resolves all four packages from that prefix, then builds and executes a separate
Dune project outside the source checkout.
