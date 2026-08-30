# Retained Scene2 display-list M7 foundation evidence

Frozen `OPT2.md` SHA-256:
`2c59594e53eb236cd108867f653d61deb30ded2b987ffc9fffee55062fcb383b`.

This commit establishes the resource-free retained Scene2 segment boundary. It
does not declare M7 complete. Typed image/glyph resource bindings, complete
shape/state command coverage, PXUI widget pixel parity, and 100,000-frame
resource/cache bounds remain required.

## Implemented

- renderer-neutral `Scene_command.Display_list` segments with explicit positive
  identity and non-negative version;
- reusable structure-of-arrays builder storage with a minimum capacity of 16,
  geometric growth, retained capacity across reset, and high-water/growth
  diagnostics;
- checked publication through the existing `Render_ir` validator;
- stable physical publication for an unchanged builder/identity/version;
- exact reset invalidation, including reuse of the same identity/version;
- solid rectangle, clip stack, and debug-text commands in the initial packed
  opcode/value/color/text planes;
- a pure `Scene.display_list` node and direct native `Scene2_segment` layer;
- direct single-segment staging that returns the segment's validated IR by
  physical identity without Scene command reconstruction;
- ordinary Scene2 fallback for nested/transformed segments, preserving exact
  transform and command order;
- retained native identity `scene2-segment:<id>` plus version for renderer
  replay;
- the native benchmark and native lowering authority consume the new layer
  without importing renderer details into producers.

## Exact regressions

`lib/scene_command/test_display_list.ml` proves geometric growth from 16 to 32
commands, exact high-water/growth counters, clip order, stable publication,
reset invalidation, retained capacity, and rejection of an unbalanced clip.

`lib/prismel/test_scene_display_list.ml` proves direct IR physical identity,
direct native segment identity/version, and transformed fallback command order.

## Verification

```sh
dune runtest lib/scene_command lib/prismel
dune build @all
dune runtest test
git diff --check
shasum -a 256 OPT2.md
```

The focused tests and `dune build @all` passed. The dependency-direction and
native-only tests in `dune runtest test` passed. That alias then correctly
reported the public API manifest stale; the manifest was regenerated and must
pass on the final rerun before commit.

