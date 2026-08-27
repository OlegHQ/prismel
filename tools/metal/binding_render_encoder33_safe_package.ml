let ids = Binding_render_encoder33_native_closure.ids
let validate () =
  Binding_render_encoder33_native_closure.validate ();
  if List.length ids <> 33 || List.length (List.sort_uniq String.compare ids) <> 33
  then invalid_arg "RenderEncoder33 safe closure drift"

let public_groups =
  [ "owned encoder/protocol", 1
  ; "checked draw-indirect value layouts", 2
  ; "draw, mesh, tile and patch commands", 9
  ; "owned buffer arrays and offsets", 11
  ; "owned sampler arrays and clamps", 5
  ; "counter sampling and color mapping", 2
  ; "threadgroup memory", 3 ]
