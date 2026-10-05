# Rays UI to the kit rev 3 design: what is left

Delete this file when the list below is empty.

## Goal (the owner's words)

"i need every widget every spacing to be 1:1 to our design ... i don't need per pixel measurements
i just need it to match the design." A side-by-side of the app and the sheet looks the same and
nothing is broken; build what the design draws with a real feature behind it. Where two sheets
disagree, each context follows the sheet of its width (narrow = `workspace.html`, wide = the
single-panel sheet). Smallest working change, reuse, no new abstractions.

## Where things are

- Design: https://claude.ai/artifact/LRpSPHaWTJacRW6RkQM33t, mirrored in `specification/pxui-kit/`
  (`kit.css`: the last "rev 3: lighter" block wins; `<sheet>.html`, `<sheet>@1x.png` / `@2x.png`;
  fixture `kit.rays`: layout 0 = the Workspace sheet at 1440x900, layout 1 = graph 1200 + inspector
  380, render at `1581 785`).
- `sketches/ws_layout/sketch.rays` layout 1 has floating windows.

## Build, render, compare

    eval "$(opam env --switch=. --set-switch)"
    dune build tools/check.exe tools/ui_shot.exe tools/widgets_shot.exe
    _build/default/tools/check.exe --ship          # all, tests, smoke, diff check
    _build/default/tools/check.exe @runtest-native
    SDL_VIDEODRIVER=dummy UI_SHOT_SCALE=2 ./_build/default/tools/ui_shot.exe \
      specification/pxui-kit/kit.rays out.png [W H]

`UI_SHOT_DO` scripts the state first (top of `tools/ui_shot.ml`): `key:space key:[ key:1` (layout
1), `click:X,Y`, `rclick:X,Y`, `move:X,Y`, `hold:X0,Y0,X1,Y1`, `type:TEXT`, `pinch:X,Y,F`,
`scroll:X,Y,DY`, `key:tab`. Crop before looking: `sips -c H W --cropOffset Y X in.png --out c.png`.

## State

`check.exe --ship` and `@runtest-native` are green.

## Open

- The 2x parity goldens (`lib/pxui/fixtures/kit_overlays_2x.png`, `kit_panel_2x.png`) are stale and
  `test_ui_parity` skips them on a 1x display. Regenerate them on a Retina display only (from
  `lib/pxui`, twice: `RAYS_UI_FONT=../../assets/fonts/DepartureMono-Regular.otf
  RAYS_UPDATE_FIXTURES=$PWD/fixtures ../../_build/default/lib/pxui/test_main.exe test_ui_parity`).
  On a 1x display that command overwrites them with 1x pictures: do not run it there.
- `dune exec test/test_main.exe -- bench_scope_big`: `with_scope` on 2,001 nodes is a cold build
  of about 20 ms (5.6 ms before the redesign), 12 ms for a rebuild on an existing view, 2.3 ms a
  warm frame. A profile puts the rest in `Projection`, `Flow_edit` and the Lisp parse (polymorphic
  compare and hash on path-keyed tables). The host only rebuilds when the document changes.
- Not yet put beside their sheets: notice tips, the overlays submenu, the widgets sheet's hover and
  press samples (`widgets_shot` does not draw them).
- A Graph pane in text view has two tab sets in its header; a long subject is cut for one only.
- A wire takes two bends round a card when no one-bend path is clear (a pinned Full card).
- Long parameter names are cut in a 280 to 320 wide inspector (`density_attrib…`); the sheets use
  short names.
- Pragmasevka has no `⌥` or `⌘`; a fallback face draws them small (the sheets show the same).

## Decisions taken that the owner may reverse

- Split keys follow the design: `Split right` = `Space o v`, `Split down` = `Space o h`.
- Narrow Outline has no Layout or Data flow sections and no node rows (as `workspace.html`); the
  wide one keeps them, node rows folded behind the graph row's chevron.
- A Card shows no `+ N more` row; `p` / `o` change the level.
- Letter hints are on `f`; frame-selection is `⇧F`.
- The layout summary reads `Outline | View | Inspector`, not the sheet's `View | Graph / Lisp`.
- `Tab` opens the add menu in the graph canvas (wired after the selection); in the List view Tab
  still indents the row. `Space a` stays.
- The viewport strip lists the app's keys `w e r` for move, rotate, scale (the sheet prints
  `g r s`).
- The key sheet is `Space ?` (was `Space k`); the strip no longer has a clickable `? toggle guide`
  pair, `?` is the control.
- A graph that is the only docked pane shows `N nodes · M selected  ZOOM P%` on the strip's right;
  in a layout of several panes the right side stays the layout summary and the frame rate.
