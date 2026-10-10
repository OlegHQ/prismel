open Rays

let require condition message = if not condition then failwith message

let first_geometry scene =
  let ir = Result.get_ok (Scene.Private.to_ir scene) in
  Array.find_map
    (function Scene_command.Render_ir.Geometry geometry -> Some geometry | _ -> None)
    (Scene_command.Render_ir.Private.commands_readonly ir)
  |> Option.get

let require_geometry_reuse label make =
  let first = first_geometry [make ()]
  and second = first_geometry [make ()] in
  require (first.vertices == second.vertices && first.indices == second.indices)
    (label ^ " rebuilt tessellated geometry arrays")

let measure calls make =
  for _ = 1 to 20 do ignore (Sys.opaque_identity (make ())) done;
  Gc.full_major ();
  let gc_before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes () in
  for _ = 1 to calls do ignore (Sys.opaque_identity (make ())) done;
  let gc_after = Gc.quick_stat () and allocated_after = Gc.allocated_bytes () in
  let bytes_per_word = float (Sys.word_size / 8) in
  ((allocated_after -. allocated_before) /. float calls,
   ((gc_after.promoted_words -. gc_before.promoted_words) *. bytes_per_word)
     /. float calls)

let run () =
  let make x y =
    Scene.[rounded_rect ~at:(x, y) ~w:84 ~h:31 ~radius:7
      ~fill:(Color.rgba 12 34 56 220) ~stroke:(Color.rgb 90 80 70) ()]
  in
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
  let ellipse_node () = Scene.circle ~at:(44, 37) ~radius:19
      ~fill:(Color.rgba 11 22 33 210) () in
  let ellipse_first=ellipse_node() and ellipse_second=ellipse_node()in
  require(ellipse_first==ellipse_second)
    "stable ellipse did not reuse its immutable scene node";
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
  let polygon () = Scene.polygon [11, 7; 83, 13; 72, 61; 19, 55]
      ~fill:(Color.rgba 17 41 89 213) ~stroke:(Color.rgb 220 170 90) () in
  require_geometry_reuse "polygon" polygon;
  require_geometry_reuse "rect" (fun () -> Scene.rect ~at:(13, 17) ~w:71 ~h:29
    ~fill:(Color.rgba 27 51 93 207) ~stroke:(Color.rgb 201 151 71) ());
  require_geometry_reuse "line" (fun () -> Scene.line ~from_:(7, 9) ~to_:(93, 67)
    ~width:5 ~color:(Color.rgba 61 103 149 219) ());
  let evicted_before = first_geometry Scene.[polygon [-71, -53; -19, -47; -23, -11]
    ~fill:(Color.rgba 23 59 101 227) ()] in
  for index = 0 to 299 do
    ignore (Scene.polygon [index, 0; index + 17, 3; index + 11, 29]
      ~fill:(Color.rgba (index land 255) 37 73 211) ())
  done;
  let evicted_after = first_geometry Scene.[polygon [-71, -53; -19, -47; -23, -11]
    ~fill:(Color.rgba 23 59 101 227) ()] in
  require (evicted_before.vertices != evicted_after.vertices
    && evicted_before.indices != evicted_after.indices)
    "native path cache did not deterministically evict its oldest geometry"
