# Retracted in-process Raster2 SDL3 comparison path

This in-process comparison design is invalid and is not registered or
executable. macOS resolves identically named SDL2 and SDL3 C symbols from one
process without library namespaces. Making Prismel depend on the SDL3 presenter
therefore caused the legacy SDL2 initialization path to resolve SDL3 symbols.
The headless smoke gate caught this as an empty SDL initialization failure.

The standalone SDL3-only Runtime presenter remains valid. A future comparison
must either wait until Prismel no longer links SDL2, or use a process boundary
with an explicitly specified bounded frame transport. It must not co-link both
SDL major versions.

The originally attempted migration comparison was opt-in, but its dependency
edge still changed the process link graph even when the environment flag was
unset.

The private Prismel orchestrator produces checked packed RGBA frame facts. A
private Runtime adapter owns SDL3 video initialization, a hidden window, one
streaming texture, presentation, resize, and teardown. No SDL window, renderer,
texture, surface, or native pointer crosses into Prismel. The adapter validates
logical size, drawable size, pitch, and storage length before upload.

The invalid gate was:

```sh
SDL_VIDEODRIVER=dummy PRISMEL_RASTER2_SDL3_COMPARISON=1 \
  dune exec test/raster2_sdl3_comparison.exe
```

It is retained here only as negative architectural evidence and must not be
restored while legacy SDL2 remains linked.
