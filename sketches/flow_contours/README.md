# flow_contours

A contour map typed in glyphs, every pixel computed by a Rays Lisp kernel on the GPU lane.

One animated height field, `(noise3 [x y drift])`, is read two ways. `lines` reads it per pixel
and draws the levels as lines about a pixel wide (the distance to the level divided by a
one-pixel finite difference of the height). `glyph` reads it once per cell of the grid and
marks the cells inside one contour band: `x` on the outermost, then dots, `0` and `1`, and solid
blocks innermost. A glyph is a box, a ring or two diagonals of the cell-local distances, so
there is no font and no texture.

A cell's glyph is chosen by a hash of the cell index, not of the height, so a glyph only
appears or leaves as a contour passes over its cell and never flickers between kinds.

The picture is six kernels composited by alpha (`contours`, `xs`, `dots`, `zeros`, `ones`,
`blocks`); together they would not fit one 64-register packed program.

The dataflow is `speed`, `scale`, `cell`, `levels`, `base` -> `field` -> six layers -> `result`.
The value cards at the left are the controls, scrubbed in place: `speed` is the drift, `scale`
the blob size (smaller is bigger), `cell` the side of a glyph cell in pixels, `levels` the
contour density, `base` the height of the outermost contour. `field` is the one record every
layer reads; its `width` and `height` are `(frame/width)` and `(frame/height)`, so the picture
fills its canvas pane at any size, and its `columns` and `rows` follow from `cell`.
Select a layer chip to edit its rows in
the inspector: `level` (which band it follows), `share_from`..`share_to` (the share of cells
marked), its shape (`narrow`, `radius`, `stroke`, `diagonal`) and `grey`.
Run: `dune exec sketches/flow_contours/main.exe`.
