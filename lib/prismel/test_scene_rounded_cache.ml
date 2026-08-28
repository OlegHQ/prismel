open Prismel_next_api

let require condition message = if not condition then failwith message

let serialize scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Scene_command.Render_ir.serialize ir

let first_geometry scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Array.find_map
    (function Scene_command.Render_ir.Geometry geometry -> Some geometry | _ -> None)
    (Scene_command.Render_ir.Private.commands_readonly ir)
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
  let ellipse_node () = Scene.circle ~at:(44, 37) ~radius:19
      ~fill:(Color.rgba 11 22 33 210) () in
  let ellipse_first=ellipse_node() and ellipse_second=ellipse_node()in
  require(ellipse_first==ellipse_second)
    "stable ellipse did not reuse its immutable scene node";
  for index=0 to 299 do
    ignore(Scene.ellipse~at:(index,index land 15)~rx:(index+2)~ry:11
      ~fill:Color.blue())
  done;
  require(primitive_baseline=serialize(primitive()))
    "bounded ellipse cache eviction changed geometry";
  ignore(ellipse_node());Gc.full_major();
  let ellipse_before=Gc.allocated_bytes()in
  for _=1 to 1_000 do ignore(ellipse_node())done;
  let ellipse_per_hit=(Gc.allocated_bytes()-.ellipse_before)/.1_000. in
  require(ellipse_per_hit<512.)"stable ellipse cache allocation regression";
  ignore (first_geometry (primitive ()));Gc.full_major ();
  let primitive_before = Gc.allocated_bytes () in
  for _ = 1 to 1_000 do ignore (first_geometry (primitive ())) done;
  let primitive_per_stage =
    (Gc.allocated_bytes () -. primitive_before) /. 1_000. in
  require (primitive_per_stage < 4_000.)
    "stable primitive staging allocation regression";
  let curve () = Scene.[bezier [8, 9; 31, 70; 85, 11; 120, 64]
    ~steps:32 ~color:(Color.rgba 20 40 80 220) ()] in
  let curve_first=first_geometry(curve()) and curve_second=first_geometry(curve())in
  require(curve_first.vertices==curve_second.vertices&&curve_first.indices==curve_second.indices)
    "structurally identical bezier rebuilt tessellated geometry";
  let curve_baseline=serialize(curve())in
  for index=0 to 299 do ignore(Scene.bezier[index,0;index+2,5;index+7,1]~steps:9())done;
  require(curve_baseline=serialize(curve()))"bounded bezier cache eviction changed IR";
  Printf.printf "rounded cache deterministic/bounded, %.0f bytes/hit\n" per_call
