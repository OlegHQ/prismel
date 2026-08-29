# D3 native dependency and link audit — 2026-08-29

Source revision: `d38b19d25eed5b89722e4de74da9506538748a41` (`Retire native
migration compatibility facades`). The worktree was clean before the fresh
release build.

## Command

```sh
d3_dir=$(mktemp -d /tmp/prismel-d3-clean-XXXXXX)
opam exec --switch=. -- dune build --build-dir "$d3_dir" --profile release \
  examples/basic/main.exe
opam exec --switch=. -- dune describe external-lib-deps --format=sexp \
  --build-dir "$d3_dir" > "$d3_dir/external-deps.sexp"
/usr/bin/otool -L "$d3_dir/default/examples/basic/main.exe" > "$d3_dir/basic.otool"
awk 'NR == 1 { next } { print "examples/basic/main.exe\\t" $0 }' \
  "$d3_dir/basic.otool" > "$d3_dir/basic.links"
_build/default/tools/phase5_link_audit/phase5_link_audit.exe \
  --deps-file "$d3_dir/external-deps.sexp" --otool-file "$d3_dir/basic.links"
rg -n -i 'tsdl|sdl2|opengl|libgl|wap|web' \
  "$d3_dir/external-deps.sexp" "$d3_dir/basic.links"
```

Profile: `release`. The final `rg` produced no matches. The link-audit parsed
5,242 Dune dependency lines and 13 dynamic-link lines, with zero violations of
its `tsdl`, `tsdl_gfx`, `sdl2`, `libSDL2`, `OpenGL.framework`, and `libGL`
forbidden set.

## Representative executable links

`examples/basic/main.exe` links Foundation, Metal, QuartzCore, CoreGraphics,
IOSurface, libc++, SDL3, SDL3_image, SDL3_ttf, SDL3_mixer, CoreFoundation,
libSystem, and libobjc. It has no SDL2, Tsdl, OpenGL, browser, or Wap dynamic
link.

This is D3 evidence for the representative native executable only. It does not
replace D7's final clean-tree, repeated full-build and release-matrix gate.
