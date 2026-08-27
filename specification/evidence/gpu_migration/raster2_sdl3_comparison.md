# Raster2 SDL3 comparison path

The migration comparison is opt-in and does not change Runtime target
selection or the legacy SDL2 renderer. Set
`PRISMEL_RASTER2_SDL3_COMPARISON=1` only for the finite integration fixture.

The private Prismel orchestrator produces checked packed RGBA frame facts. A
private Runtime adapter owns SDL3 video initialization, a hidden window, one
streaming texture, presentation, resize, and teardown. No SDL window, renderer,
texture, surface, or native pointer crosses into Prismel. The adapter validates
logical size, drawable size, pitch, and storage length before upload.

Gate:

```sh
SDL_VIDEODRIVER=dummy PRISMEL_RASTER2_SDL3_COMPARISON=1 \
  dune exec test/raster2_sdl3_comparison.exe
```

The fixture checks real mixed 2D and Scene3 pixels at frames 1, 2, 60, and 600,
then resizes both owners and checks the submitted post-resize framebuffer before
explicit teardown.
