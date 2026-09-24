# D3 native dependency and link audit — 2026-08-29

Source revision: `c35a372008ecc3d6fbc90cd4d472c50a827a40e9` (`Replace legacy
diagnostic font data`). The worktree was clean before the release build and
complete artifact sweep.

## Command

```sh
opam exec --switch=. -- dune build --profile release @all
opam exec --switch=. -- dune exec --profile release \
  tools/phase5_link_audit/phase5_link_audit.exe -- --root . \
  > /tmp/prismel-link-audit-final.json
jq '{dependency_lines,artifact_link_lines,violations,passed}' \
  /tmp/prismel-link-audit-final.json
```

Profile: `release`. The link-audit parsed 5,242 Dune dependency lines and 5,692
dynamic-link lines across every `.exe`, `.cmxs`, `.dylib`, and `.so` under the
complete build tree. It found zero violations of its `tsdl`, `tsdl_gfx`,
`sdl2`, `libSDL2`, `OpenGL.framework`, and `libGL` forbidden set.

## Representative executable links

`examples/basic/main.exe` links Foundation, Metal, QuartzCore, CoreGraphics,
IOSurface, libc++, SDL3, SDL3_image, SDL3_ttf, SDL3_mixer, CoreFoundation,
libSystem, and libobjc. It has no SDL2, Tsdl, OpenGL, browser, or Wap dynamic
link.

This closes the local D3 whole-artifact absence gate. It does not replace D7's
final clean-tree, repeated full-build and release-matrix gate.
