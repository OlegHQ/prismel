open Prismel_next_api

let require condition message = if not condition then failwith message

let serialize scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Raster2.Render_ir.serialize ir

let first_geometry scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Array.find_map
    (function Raster2.Render_ir.Geometry geometry -> Some geometry | _ -> None)
    (Raster2.Render_ir.Private.commands_readonly ir)
  |> Option.get

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
  let primitive () = Scene.[circle ~at:(44, 37) ~radius:19
    ~fill:(Color.rgba 11 22 33 210) ()] in
  let first = first_geometry (primitive ())
  and second = first_geometry (primitive ()) in
  require (first.vertices == second.vertices && first.indices == second.indices)
    "structurally identical primitive rebuilt geometry arrays";
  let primitive_baseline = serialize (primitive ()) in
  for index = 0 to 299 do
    ignore (serialize Scene.[rect ~at:(index, 0) ~w:(index + 1) ~h:3
      ~fill:(Color.rgba (index land 255) 20 30 255) ()])
  done;
  require (primitive_baseline = serialize (primitive ()))
    "bounded primitive cache eviction changed geometry";
  ignore (first_geometry (primitive ()));Gc.full_major ();
  let primitive_before = Gc.allocated_bytes () in
  for _ = 1 to 1_000 do ignore (first_geometry (primitive ())) done;
  let primitive_per_stage =
    (Gc.allocated_bytes () -. primitive_before) /. 1_000. in
  require (primitive_per_stage < 4_000.)
    "stable primitive staging allocation regression";
  Printf.printf "rounded cache deterministic/bounded, %.0f bytes/hit\n" per_call
