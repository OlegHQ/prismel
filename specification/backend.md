# Native backend

Prismel ships one backend: the native Metal runtime on Apple Silicon. The supported host is
macOS on Apple Silicon with Metal available. Backend initialization either
creates that native stack or returns a typed startup error; applications do
not select an alternate renderer through environment variables or public API.

## Ownership and dependency direction

```text
examples / sketches / pxui / procedural / pdk
                         |
                         v
                      prismel
                         |
                         v
                      runtime ----------> sdl3
                         |
                         v
                    ogpu_metal --------> ogpu
                         |
                         v
                       metal
```

`runtime` owns process setup, initial-domain lifecycle, the SDL3 window, its
Metal view, resize scheduling, and presentation. `ogpu_metal` owns the
translation from the checked high-level GPU interface to typed Metal bindings.
`metal` owns the safe Metal resource and command API. Prismel owns pure scene
values and records rendering through the narrow GPU boundary; it never exposes
native handles in its public API.

The initial domain owns every window, event, layer, drawable, and resource
operation. Pure geometry and scene preparation may use the shared parallel
pool, but all results join before crossing the native boundary.

## Frame lifecycle

1. Runtime creates an SDL3 Metal view and obtains its `CAMetalLayer`.
2. The layer supplies a drawable for each presented frame; resize updates the
   drawable extent before recording work.
3. Prismel lowers immutable `Scene` data into checked OGPU commands. Native
   implementation code validates device identity, resource lifetime, numeric
   ranges, and command ordering before encoding Metal commands.
4. The command buffer presents the drawable and keeps completion-owned state
   alive until Metal reports completion.

Drawable dimensions are physical pixels. `Frame.width`, `Frame.height`, scene
coordinates, input positions, and PXUI layout remain logical points; the
backend performs the logical-to-drawable conversion exactly once at the native
viewport boundary. Captures read the drawable-sized native framebuffer.

## Resource rules

Images, fonts, canvases, meshes, pipelines, and command resources are owned
native resources. Safe APIs make destruction idempotent, reject use after
release, and preserve same-device validation. Sketch-owned resources are
released through `Sketch.run_state ~on_stop` while the SDL3 and Metal runtime
is still live. Command completion retains any referenced resources until their
submitted work completes.

`Scene`, `Canvas`, `Image`, `Font`, and `Audio` remain high-level Prismel
interfaces. Their implementation lowers to the native GPU stack without
changing public scene semantics. Native framebuffer capture and export use
the same checked readback path as presentation diagnostics.

## Qualification

`NEW_GPU_STUFF.md` is the active migration plan. Its S, M, O, R, and D gates
require focused correctness, ownership, conformance, and performance evidence
before a surface is declared complete. The dependency-direction gate and the
native link audit are release requirements: production artifacts may link only
the declared SDL3, Metal, OGPU, and platform frameworks for this backend.

Evidence is recorded under `specification/evidence/gpu_migration/`. A record
names the exact commit, command, profile, machine context, and artifact hash;
historical records are qualification evidence rather than a substitute for the
final clean-tree gate run.
