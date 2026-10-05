# Live sketch workflow

Rays supports compiled sketch restart. For finite visual
experiments, `Sketch.export` writes deterministic frames from a pure scene.

## Compiled sketch restart

For complete applications, `watchexec --restart --exts ml,mli,dune -- dune
exec ...` reliably terminates the old process and starts the newly linked one.
Dune's own `exec --watch` does not restart a still-running executable.

Model state does not survive a native-code restart automatically. Sketches that
need continuity should use an explicit, versioned model codec; silently
marshalling arbitrary closures, native handles, or changed OCaml types is outside
the safe public contract.

These loops compose: use `Sketch.export` for finite scenes and restart a full sketch when compiled behavior changes.

## Validation with multiple agents

Bootstrap once with `dune build tools/check.exe`. Agents sharing a worktree
then run the built launcher directly, so its advisory lock queues requests
before Dune's own exclusive build lock:

```sh
_build/default/tools/check.exe                       # cached standard tests
_build/default/tools/check.exe @check                # typecheck
_build/default/tools/check.exe @lib/rdk/runtest        # focused tests
_build/default/tools/check.exe --ship                 # all, tests, smoke, diff check
_build/default/tools/check.exe @qualification-scale  # optional large algorithms
```

The launcher uses the workspace root, preserves arguments and command failures,
and releases its lock when it exits. All cooperating agents must use it;
direct Dune invocations still compete for Dune's build lock. The persistent
`.rays-check.lock` is ignored by Git and survives `dune clean`. After cleaning,
rebuild the launcher before starting agents. A queued request checks the current
worktree when it acquires the lock; it does not pin an earlier revision.

Standard shipping excludes the large studio fracture and high-density
procedural parallel exactness fixtures, the all-field catalog cache-key sweep,
and the sketch's exhaustive control-boundary sweep. They retain all their checks under
`@qualification-scale` (also part of `@qualification`), with focused aliases
`@test/test_shattered_studio`,
`@lib/procedural/test_procedural_parallel_exact`,
`@test/test_sop_catalog_exhaustive` and
`@sketches/pastel_flow/test_control_boundaries`. The catalog still checks every
factory's metadata and targeted cache invalidation by default; the sketch still
checks its preset, repeatability, seed behavior and settings round-trip.
Regular algorithm and one/four-domain regressions remain in `@runtest`.
Display-dependent tests
and GPU rendering integration tests remain under `@runtest-native`;
pure prepared-command validation remains in `@runtest`. `@qualification`
includes the longer native and machine-specific checks as well.
Path-tracer GPU checks (`test_pathtracer`, `test_world`, `test_scene`) are also
under `@runtest-native` and `@qualification`, with their focused aliases in
`lib/rays_pathtracer`; shader compilation and convergence checks stay optional.

Ordinary validations reuse Dune's action cache. Reserve `--force` for measuring
execution or explicitly repeating tests; do not clear `_build` between agents.
For a window-free run, set `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy` when
launching standard tests, but run `--ship` with native drivers for smoke windows.
Agents should request the alias for their changed subsystem; one final shipping
check covers the complete standard suite and native smoke examples.
