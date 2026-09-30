(* W6: viewport provenance.  The triangle to primitive map, the tags of nested
   merges through the editor's cook path, a CPU ray pick on a known seed and a
   known petal, the highlight (a per-corner colour, no recook), and the bench
   (`dune exec test/test_main.exe -- bench_viewport_pick`). *)
open Flow_sop
module Session = Procedural.Session
module Cook = Prismel_editor.Private.Cook
module Pick = Prismel_editor.Private.Pick
module Int_map = Network.Int_map
module Geometry = Pdk.Geometry

let fail message = failwith ("test_viewport_pick: " ^ message)
let check condition message = if not condition then fail message
let case name = In_channel.with_open_bin
  (Filename.concat "../specification/workspace/cases" (name ^ ".lisp")) In_channel.input_all

let lower name =
  match Flow.Syntax.parse (case name) with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok forms -> (match Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories:Sop_catalog.Editor.factories forms with
      | Ok lowered -> lowered | Error d -> fail (Flow.Diagnostic.to_string d))


(* the cooked piece of a lowered fixture *)
let cooked ?(lit = Pick.Set.empty) ?cook lowered ~prepared =
  let cook = match cook with
    | Some cook -> cook
    | None ->
        let cook = Result.get_ok (Cook.create ~await:true
          ~prepare:(fun _ output -> incr prepared; Ok output.Session.geometry)
          ~seed:42L ~grain:97 ~domains:1 ~max_entries:512
          ~max_payload_bytes:(256 * 1024 * 1024) ()) in
        Cook.set_volatile cook (Lower.is_volatile lowered); cook in
  let timeline = Sketch_support.Timeline.create () in
  let update = Cook.update ~live:false ~lit
      ~definitions:Editor_document.Document.String_map.empty
      ~compiled_ids:lowered.compiled_ids cook ~settings:Prismel_editor.Settings.none
      ~objects:(Lower.objects lowered) ~edit_error:None
      ~effects:Procedural.Parameter.no_effects ~timeline_changes:[] ~timeline
      ~frame:{ (Test_editor_input.frame (0., 0.) [] 0) with dt = 0. }
      ~frame_request:None in
  check (update.edit_error = None) "cook error";
  update.cook

let primitives_of tags tag =
  List.filter (fun p -> tags.(p) = tag) (List.init (Array.length tags) Fun.id)

(* a point just above the highest primitive of [tag] *)
let above geometry tag =
  let tags = Option.get (Pick.tags geometry) in
  let topology = Geometry.topology geometry and points = Geometry.positions geometry in
  let centre primitive =
    let first, last = Pdk.Topology.primitive_vertex_range topology primitive in
    let sum = ref (0., 0., 0.) in
    for v = first to last - 1 do
      let x, y, z = Pdk.Packed.Float3.get points (Pdk.Topology.point_of_vertex topology v) in
      let a, b, c = !sum in sum := (a +. x, b +. y, c +. z)
    done;
    let n = float (last - first) and a, b, c = !sum in a /. n, b /. n, c /. n in
  let best = List.fold_left (fun best p ->
    let (_, y, _) as c = centre p in
    match best with Some (_, (_, by, _)) when by >= y -> best | _ -> Some (p, c))
    None (primitives_of tags tag) in
  let x, y, z = snd (Option.get best) in
  Prismel.Vec3.create x (y +. 1e-3) z

let present geometry tag = Array.exists (( = ) tag) (Option.get (Pick.tags geometry))

let down = Prismel.Vec3.create 0. (-1.) 0.

let pick_run () =
  (* --- sunflower: one merge, tag = the seed --- *)
  let sunflower = lower "sunflower" in
  let prepared = ref 0 in
  let cook = cooked sunflower ~prepared in
  let piece = List.hd (Cook.pieces cook) in
  let tags = Option.get (Pick.tags piece.output.geometry) in
  let of_iteration lowered i = Int_map.fold (fun tag (o : Lower.origin) found ->
    if o.iter = [ i ] then tag :: found else found) lowered.Lower.provenance [] in
  let tag83 = List.hd (of_iteration sunflower 83) in
  let origin = Int_map.find tag83 sunflower.provenance in
  check (origin.iter = [ 83 ] && origin.input = 83) "the provenance table names iteration 83";
  check (Array.length tags = Geometry.primitive_count piece.output.geometry
    && Int_map.cardinal sunflower.provenance = 240) "a tag per primitive, 240 origins";
  (match Cook.pick piece ~origin:(above piece.output.geometry tag83) ~direction:down with
   | Some (_, tag) -> check (tag = tag83) "the ray finds seed 83"
   | None -> fail "the ray missed seed 83");
  check (Cook.pick piece ~origin:(Prismel.Vec3.create 0. 9. 9.) ~direction:down = None) "a miss";
  (* instanced pieces: the prototype is picked at every instance, hits compare in world units *)
  let module M = Prismel.Mat4 in
  let module V = Prismel.Vec3 in
  let over = above piece.output.geometry tag83 in
  let instanced transforms = { piece with output = { piece.output with instances = Some transforms } } in
  let hit p origin = Cook.pick p ~origin ~direction:down in
  let d1 = match hit piece over with Some (d, _) -> d | None -> fail "no plain hit" in
  let shifted = V.create (over.V.x +. 100.) over.y over.z in
  (match hit (instanced [| M.identity; M.translation (V.create 100. 0. 0.) |]) shifted with
   | Some (d, tag) -> check (tag = tag83 && Float.abs (d -. d1) < 1e-9) "the second instance was not picked"
   | None -> fail "an instanced piece was not picked");
  check (hit (instanced [| M.translation (V.create 100. 0. 0.) |]) over = None) "the prototype at the origin was picked without an instance there";
  let big = V.create (2. *. over.V.x) (2. *. over.y) (2. *. over.z) in
  (match hit (instanced [| M.scaling (V.create 2. 2. 2.) |]) big with
   | Some (d, tag) -> check (tag = tag83 && Float.abs (d -. 2. *. d1) < 1e-7) "a scaled instance's distance is not in world units"
   | None -> fail "a scaled instance was not picked");
  (match hit (instanced [| M.translation (V.create 0. (-5.) 0.); M.identity |]) over with
   | Some (d, _) -> check (Float.abs (d -. d1) < 1e-9) "the nearest instance wins"
   | None -> fail "the nearest instance was not picked");
  (* --- the highlight: prepared again from the kept output, never recooked --- *)
  let misses = (Cook.stats cook).misses and before = !prepared in
  let lit = Pick.Set.singleton tag83 in
  let cook = cooked ~lit ~cook sunflower ~prepared in
  check (!prepared = before + 1) "a new highlight prepares the piece once";
  check ((Cook.stats cook).misses = misses) "the highlight does not recook";
  let lit_piece = List.hd (Cook.pieces cook) in
  let colours = Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "Cd" lit_piece.prepared in
  (match Option.map Pdk.Attribute.Private.storage colours with
   | Some (Pdk.Attribute.Float4 c) ->
       let c = Pdk.Packed.Float4.Private.view c and topology = Geometry.topology lit_piece.prepared in
       let corner primitive = fst (Pdk.Topology.primitive_vertex_range topology primitive) in
       let seed = List.hd (primitives_of tags tag83)
       and other = List.hd (primitives_of tags (List.hd (of_iteration sunflower 0))) in
       check (Float.abs (c.x.(corner other) -. 0.3) < 1e-9) "the rest is dimmed";
       check (c.x.(corner seed) > c.x.(corner other)) "the probed iteration is tinted"
   | _ -> fail "no vertex colour");
  let cook = cooked ~lit ~cook sunflower ~prepared in
  check (!prepared = before + 1) "an unchanged highlight prepares nothing";
  let cook = cooked ~cook sunflower ~prepared in
  check (!prepared = before + 2) "deselecting prepares once";
  check ((List.hd (Cook.pieces cook)).prepared == piece.output.geometry) "deselect restores the geometry";
  Cook.close cook;
  (* --- bloom: petals sit inside a merge of merges; the tag is the innermost --- *)
  let bloom = lower "bloom" in
  let cook = cooked bloom ~prepared in
  let piece = List.hd (Cook.pieces cook) in
  let petal = Int_map.filter (fun _ (o : Lower.origin) -> o.iter = [ 4 ]) bloom.provenance in
  check (Int_map.cardinal petal = 1 || Int_map.cardinal petal = 2) "petal 4 of the first flower";
  let tag, o = List.hd (List.filter (fun (t, (o : Lower.origin)) ->
    present piece.output.geometry t && o.iter = [ 4 ]) (Int_map.bindings bloom.provenance)) in
  (match Cook.pick piece ~origin:(above piece.output.geometry tag) ~direction:down with
   | Some (_, hit) ->
       let hit = Int_map.find hit bloom.provenance in
       check (hit.iter = [ 4 ] && hit.site = o.site) "a petal picks its iteration through two merges"
   | None -> fail "the ray missed petal 4");
  let heart = List.find (fun (t, (o : Lower.origin)) -> o.iter = [] && o.input = 1
    && present piece.output.geometry t) (Int_map.bindings bloom.provenance) in
  check ((snd heart).site <> o.site) "the heart is another site";
  Cook.close cook;
  print_endline "viewport pick tests passed"

let run = pick_run

(* Command: dune exec test/test_main.exe -- bench_viewport_pick *)
let bench () =
  let time repeats f =
    let start = Unix.gettimeofday () in
    for _ = 1 to repeats do ignore (Sys.opaque_identity (f ())) done;
    (Unix.gettimeofday () -. start) /. float repeats *. 1000. in
  List.iter (fun (name, iteration) ->
    let lowered = lower name and prepared = ref 0 in
    let cook = cooked lowered ~prepared in
    let piece = List.hd (Cook.pieces cook) in
    let geometry = piece.output.geometry in
    let tag, _ = List.find (fun (t, (o : Lower.origin)) -> o.iter = iteration
      && present geometry t) (Int_map.bindings lowered.provenance) in
    let origin = above geometry tag in
    let first = time 1 (fun () -> Cook.pick piece ~origin ~direction:down) in
    let pick = time 1000 (fun () -> Cook.pick piece ~origin ~direction:down) in
    let lit = Pick.Set.singleton tag in
    let tint = time 200 (fun () -> Pick.tint piece.output lit) in
    let mesh = time 200 (fun () -> Pdk_prismel.Prismel_mesh.to_mesh geometry) in
    let lit_mesh = time 200 (fun () ->
      Pdk_prismel.Prismel_mesh.to_mesh (Pick.tint piece.output lit).geometry) in
    let quiet = time 200 (fun () -> cooked ~cook lowered ~prepared) in
    let cook = cooked ~lit ~cook lowered ~prepared in
    let held = time 200 (fun () -> cooked ~lit ~cook lowered ~prepared) in
    let cook = cooked ~cook lowered ~prepared in
    Printf.printf "%s: %d prims, %d tags; first pick (BVH build) %.3f ms, pick %.4f ms, \
      tint %.3f ms, to_mesh %.3f ms, tint + to_mesh %.3f ms, idle Cook.update %.4f ms, with a highlight held %.4f ms\n%!"
      name (Geometry.primitive_count geometry) (Int_map.cardinal lowered.provenance)
      first pick tint mesh lit_mesh quiet held;
    Cook.close cook) [ "sunflower", [ 83 ]; "bloom", [ 4 ] ]
