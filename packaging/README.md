# SDL3 conf packages

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
