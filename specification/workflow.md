# Live sketch workflow

Prismel supports compiled sketch restart. For finite visual
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
