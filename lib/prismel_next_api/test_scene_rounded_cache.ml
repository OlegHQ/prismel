open Prismel_next_api

let require condition message = if not condition then failwith message

let serialize scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Raster2.Render_ir.serialize ir

let () =
  let make x y =
    Scene.[rounded_rect ~at:(x, y) ~w:84 ~h:31 ~radius:7
      ~fill:(Color.rgba 12 34 56 220) ~stroke:(Color.rgb 90 80 70) ()]
  in
  let baseline = serialize (make 17 23) in
  require (baseline = serialize (make 17 23)) "cached rounded geometry changed IR";
  require (baseline <> serialize (make 18 23)) "translation was omitted from cache key lowering";
  for index = 0 to 299 do
    ignore (serialize Scene.[rounded_rect ~at:(index land 7, index land 3)
      ~w:(20 + index) ~h:31 ~radius:7 ~fill:Color.red ()])
  done;
  require (baseline = serialize (make 17 23)) "bounded eviction changed rounded geometry";
  for _ = 1 to 20 do ignore (make 17 23) done;
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  for index = 1 to 1_000 do ignore (make index (index land 31)) done;
  let per_call = (Gc.allocated_bytes () -. before) /. 1_000. in
  require (per_call < 512.) "rounded geometry cache allocation regression";
  Printf.printf "rounded cache deterministic/bounded, %.0f bytes/hit\n" per_call
