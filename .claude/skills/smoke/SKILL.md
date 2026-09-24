---
name: smoke
description: Run a prismel example or sketch for a bounded number of frames and capture its last frame as a PNG. Use to check a rendering, UI, or lifecycle change in the real native app.
---

1. `eval "$(opam env --switch=. --set-switch)"`.
2. One program: `PRISMEL_MAX_FRAMES=30 dune exec examples/<name>/main.exe`
   (or `sketches/<name>/main.exe`). `Sketch` stops after that many frames.
3. Screenshot: most programs save on `s`; otherwise add a temporary
   `~after_present` that calls `Canvas.save_screen_png` into the scratch
   directory, never the repo root.
4. Everything: `dune build @smoke` runs every example and sketch at 30
   frames. Any `Fatal error` line names the failing program in the `dune`
   rule just above it.
