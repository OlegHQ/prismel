# Phase 5 resource semantic probes

The resource comparison uses two separate executables. The legacy probe links
Prismel/SDL2 and runs with the headless dummy target; the next probe links only
`prismel_next_resources` and its SDL3 extension stack. They are never co-linked.

Commands:

```sh
PRISMEL_RENDER_TARGET=headless SDL_VIDEODRIVER=dummy \
  dune exec tools/resource_probe_legacy.exe -- test/sdl3_image_fixtures > legacy.json
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  dune exec tools/resource_probe_next.exe -- test/sdl3_image_fixtures > next.json
dune exec tools/compare_resource_probes.exe -- legacy.json next.json > comparison.json
```

Schema 1 records deterministic image/canvas hashes, image replacement and
failed-reload retention, font glyph/wrap/empty behavior, and audio lifecycle
and PCM facts. Two differences are deliberately classified rather than
papered over: watched-image generation and encoded/decoded audio snapshots are
not public legacy Prismel APIs. The next probe records both through its typed
resource boundary.

On the 2026-08-27 qualification host the next probe completed under SDL3's
dummy video/audio drivers; its frozen output is
`phase5_resource_probe_next.json`. The legacy SDL2 probe could not initialize
under its supported headless dummy invocation and reported
`Failure("SDL initialization failed: ")` before allocating resources. That
precise blocker is frozen in `phase5_resource_probe_legacy.json`; no legacy
semantic result is inferred from the failed run.
