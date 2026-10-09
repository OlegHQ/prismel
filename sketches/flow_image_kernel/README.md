# Flow image kernel

`sketch.rays` maps pixel-center UV coordinates to RGBA channels and displays a
live image. The image owner updates the same display resource each frame.

For a frozen image value, wrap an image producer or reference with `exact`:

```lisp
(graph frozen :context image
  (exact (image/map (fn [uv] [uv.x uv.y 0.5 1])
           :width 256 :height 256)))
```

This static producer reuses one snapshot. A changed source publication creates
a new immutable version, so a previously constructed Scene keeps its frozen
pixels. Versions and source images count toward the workspace's64 owned images;
close releases native resources while retained CPU payloads remain readable.
An ordinary CPU image request independently cooks the CPU reference; explicit
`exact` captures the selected display publication and intentionally reads a GPU
publication back once. Frozen images can feed drawing, texture and SOP image
inputs; state accepts data rather than image resources.
