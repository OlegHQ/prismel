# Live sketch workflow

Prismel supports three feedback loops with different state tradeoffs.

## Scene REPL

`dune utop lib/prismel` loads the real library and native SDL3/Metal stack.
`Preview.show scene` starts one persistent window and presents each subsequently
evaluated `Scene.t`. `Preview.step` additionally returns ordered input events.
`Preview.stop` owns backend shutdown and must run before leaving a session that
created extra SDL resources.

This is the closest loop to Lisp-style image construction: redefine a helper,
evaluate one scene expression, and see it immediately without an application
lifecycle or executable rebuild.

## Compiled sketch restart

For complete applications, `watchexec --restart --exts ml,mli,dune -- dune
exec ...` reliably terminates the old process and starts the newly linked one.
Dune's own `exec --watch` does not restart a still-running executable.

Model state does not survive a native-code restart automatically. Sketches that
need continuity should use an explicit, versioned model codec; silently
marshalling arbitrary closures, native handles, or changed OCaml types is outside
the safe public contract.

## Watched media

`Sketch.run_assets ~watch:true` checks cached image stamps between frames and
replaces changed textures in place. Borrowed `Image.t` identities remain
stable, so media iteration does not require rebuilding or reconstructing the
model. Failed replacement keeps the last valid texture.

These loops deliberately compose: use `Preview` for direct scene exploration,
watched assets for visual media, and restart a full sketch when compiled
behavior changes.
