open Prismel
open Procedural

let get = Result.get_ok
let source = {|(workspace materials
  (graph blue :context material
    (material/standard :name "blue" :color "#2670f5" :roughness 0.3))
  (graph white :context material
    (material/standard :name "white" :color "#eeeeee" :roughness 0.8))
  (graph geo :context sop
    (let* [base (sop/material (sop/box) :material (ref blue))
           group (sop/group_range base :owner "Primitives" :name "accent"
                   :start 0 :end_ 0)]
      (sop/material group :group "accent" :material (ref white)))))|}

let workspace text = match Prismel_editor.Workspace.load text with
  | Ok w -> w | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds))

let cook domains node =
  let session = Session.create ~max_entries:32 ~max_payload_bytes:(1 lsl 24) |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    Session.cook session ~context:(Context.create ~domains () |> get) node
    |> Result.map_error Diagnostic.error_to_string |> get)

let attr name geometry =
  Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive name geometry
  |> Option.get |> Pdk.Attribute.storage

let signature geometry =
  ["shop_materialpath"; "material_roughness"; "material_color"; "material_emission"]
  |> List.map (fun name -> match attr name geometry with
    | Pdk.Attribute.Text a -> `Text (Array.to_list a)
    | Float a -> `Float (Array.to_list a)
    | Float4 a -> `Tuple (List.init (Pdk.Packed.Float4.length a) (Pdk.Packed.Float4.get a))
    | _ -> failwith "unexpected material attribute")

let face_materials_preserve_explosion () =
  let piece x id = Sop.box ~size:(Vec3.create 1. 1. 1.) ()
      |> Sop.transform (Mat4.translation (Vec3.create x 0. 0.))
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"piece" id in
  let geometry = (cook 1 (Sop.merge [piece (-2.) 0; piece 2. 1])).geometry in
  let group = Pdk.Group.init ~owner:Pdk.Group.Primitive ~name:"one_face"
      (Pdk.Geometry.primitive_count geometry) (( = ) 0) in
  let node = Pdk.Geometry.with_group group geometry |> get |> Sop.snapshot
      |> Sop.material ~name:"blue" ~color:(Vec3.create 0.15 0.43 0.96)
          ~roughness:0.3 ~emission:Vec3.zero
      |> Sop.material ~group:"one_face" ~name:"white" ~color:(Vec3.create 1. 1. 1.)
          ~roughness:0.8 ~emission:Vec3.zero
      |> Sop_catalog.Exploded_view.create ~amount:1. in
  let surface = cook 1 node |> Sketch_support.Surface.of_output |> get in
  let drawings = Sketch_support.Surface.scene3 node surface |> Scene3.Private.drawings in
  assert (List.length drawings = 2);
  (* Centers ±2 move to ±4. Painting just one face must leave every face of
     each cube at exactly the same rigid displacement. *)
  List.iter (fun (d : Scene3.Private.drawing) ->
    let v = Mesh.Private.packed_view d.mesh in
    Array.iter (fun index ->
      let x = abs_float v.vertices.x.(index) in
      assert (x >= 3.5 && x <= 4.5);
      assert (abs_float v.vertices.y.(index) <= 0.5);
      assert (abs_float v.vertices.z.(index) <= 0.5)) v.indices) drawings

(* ---- the editor around materials: outline, follow and back, rename, assign, pick ---- *)
module E3 = Prismel_editor.Editor3
module N = Prismel_editor.Private.Navigator
module Edit = Flow_sop.Flow_edit

let fail message = failwith ("test_materials: " ^ message)
let check condition message = if not condition then fail message
let has text sub =
  let n = String.length sub in
  let rec at i = i + n <= String.length text && (String.sub text i n = sub || at (i + 1)) in
  at 0

let follow_source = {|(workspace follow
  (graph cobalt :context material
    (material/standard :name "cobalt blue" :color "#2670f5" :roughness 0.3))
  (graph spare :context material (material/standard :name "spare" :color "#ff0000"))
  (graph shards :context sop
    (let* [m (sop/material (sop/box) :material (ref cobalt))] m))
  (graph scene :context scene
    (let* [obj (scene/geometry (ref shards) :name "shards")] (scene/merge obj))))|}

let frame ?(buttons = []) ?(keys = []) mouse events count : Frame.t = {
  width = 900; height = 640; size = 900, 640; drawable_width = 900; drawable_height = 640;
  drawable_size = 900, 640; pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse; mouse_delta = (0., 0.); keys; mouse_buttons = buttons; events }

let editor () =
  E3.create ~await:true ~workspace:(workspace follow_source)
    ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
      |> Result.map_error Pdk.Error.to_string)
    ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) ()
  |> function Ok e -> e | Error m -> fail m

let dump_line e key =
  let directory = Filename.temp_dir "prismel-materials-dump" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Sys.rmdir directory) (fun () ->
    E3.crash_dump e directory;
    let text = In_channel.with_open_bin (Filename.concat directory "editor.txt") In_channel.input_all in
    match List.find_opt (fun l -> String.starts_with ~prefix:(key ^ ": ") l) (String.split_on_char '\n' text) with
    | Some l -> String.sub l (String.length key + 2) (String.length l - String.length key - 2)
    | None -> fail ("no " ^ key ^ " in the dump"))

let text_of e = fst (Flow.Lisp.print (E3.workspace e).Editor_document.Workspace_doc.source)

let follow_tests () =
  let e = ref (editor ()) and count = ref 0 in
  let step ?(buttons = []) ?(keys = []) ?(mouse = (450., 300.)) events =
    incr count; e := E3.update !e (frame ~buttons ~keys mouse events !count) in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  let click ?(keys = []) (x, y) =
    step ~keys ~mouse:(x, y) [ Event.MouseMoved (x, y) ];
    step ~buttons:[ Input.LeftButton ] ~keys ~mouse:(x, y) [ Event.MousePressed (Input.LeftButton, (x, y)) ];
    step ~keys ~mouse:(x, y) [ Event.MouseReleased (Input.LeftButton, (x, y)) ] in
  let pane () = dump_line !e "pane graph" and route () = dump_line !e "route" in
  let jump name =
    step [ key Input.Space; ch 'j' ]; step [ Event.TextInput name ]; step [ key Input.Enter ]; step [] in
  for _ = 1 to 12 do step [] done;
  check (pane () = "scene" && route () = "scene") ("opens on the scene: " ^ pane ());

  (* the outline: groups, chip, use count, unused *)
  let ws = (E3.workspace !e).Editor_document.Workspace_doc.checked in
  let chips = match Flow.Eval.static ws with
    | Ok ev -> N.chips ev
    | Error d -> fail (Flow.Diagnostic.to_string d) in
  let params : N.params = { workspace = ws; title = "follow"; active = Some "scene"; scope = None;
    records = None; probes = (fun _ -> 0); selected = []; shell = None; chips } in
  let lines = Array.to_list (Array.map N.describe (N.rows N.initial params)) in
  let index text = match List.find_index (fun l -> has l text) lines with
    | Some i -> i | None -> fail (text ^ " is not in the outline: " ^ String.concat " | " lines) in
  check (index "SCENE" < index "GEOMETRY" && index "GEOMETRY" < index "MATERIALS")
    "the groups are in dependency order";
  check (index "MATERIALS" < index "cobalt" && index "shards" < index "MATERIALS") "a graph sits in its group";
  ignore (index "cobalt · ×1 · #2670f5");
  ignore (index "spare · unused · #ff0000");
  check (List.length (List.filter (fun l -> has l "unused") lines) = 1) "only the unread material is unused";
  check (Array.length (N.rows (N.with_query "cob" N.initial) params) = 2) "typing filters across the groups";

  (* Space j, then follow with i and back with u *)
  jump "shards";
  check (pane () = "shards" && route () = "scene > shards") ("Space j jumps: " ^ route ());
  let bx, by, bw, bh = Option.get (E3.node_box !e [ "shards"; "m" ]) in
  click (float bx +. float bw /. 2., float by +. float bh -. 6.);
  step [ ch 'i' ]; step [];
  check (pane () = "cobalt" && route () = "scene > shards > cobalt")
    ("i follows the :material of the selected node: " ^ route ());
  step [ ch 'u' ]; step [];
  check (pane () = "shards" && route () = "scene > shards") ("u goes back one: " ^ route ());
  step [ ch 'u' ]; step [];
  check (pane () = "scene" && route () = "scene") ("and back to the scene: " ^ route ());
  step [ ch 'u' ]; step [];
  check (pane () = "scene") "with nothing to go back to u stays at the scene";

  (* a double-click on the node follows too *)
  jump "shards";
  let bx, by, bw, bh = Option.get (E3.node_box !e [ "shards"; "m" ]) in
  let body = float bx +. float bw /. 2., float by +. float bh -. 6. in
  click body; click body; step [];
  check (pane () = "cobalt") ("a double-click follows: " ^ pane () ^ " / " ^ route ());
  jump "scene";

  (* a pick in the viewport lands in the right graph: the surface says "cobalt blue", the graph is cobalt *)
  let vx, vy, vw, vh = (E3.panes !e (frame (0., 0.) [] !count)).Pxui_shell.Layout.view in
  click ~keys:[ Input.Alt ] (float vx +. float vw /. 2., float vy +. float vh /. 2.);
  step []; step [];
  check (pane () = "cobalt") ("Alt-click opens the material of the surface: " ^ pane () ^ " / " ^ route ());
  jump "scene";

  (* rename: the graph and every (ref) to it, one undo entry *)
  let renamed = match E3.edit !e (Edit.Rename_graph { name = "cobalt"; to_ = "navy" }) with
    | Ok e -> e | Error m -> fail m in
  let text = text_of renamed in
  check (has text "(graph navy" && has text "(ref navy)" && not (has text "(ref cobalt)"))
    ("rename rewrote the graph and its reader: " ^ text);
  check (E3.undo_label renamed = Some "Rename graph") "one history entry";
  check (Result.is_error (E3.edit !e (Edit.Rename_graph { name = "cobalt"; to_ = "spare" }))) "a taken name is refused";
  e := renamed;
  step ~keys:[ Input.Meta ] [ ch 'z' ];
  check (has (text_of !e) "(graph cobalt" && has (text_of !e) "(ref cobalt)") "one undo restores both";

  (* a read material is not deleted, and the refusal names who reads it; an unread one goes *)
  (match E3.edit !e (Edit.Remove_graph { name = "cobalt" }) with
   | Ok _ -> fail "a read material was removed"
   | Error m -> check (has m "shards") ("the refusal names its reader: " ^ m));
  check (Result.is_ok (E3.edit !e (Edit.Remove_graph { name = "spare" }))) "an unread material can go";

  (* I peeks in a floating window *)
  jump "shards";
  let bx, by, bw, bh = Option.get (E3.node_box !e [ "shards"; "m" ]) in
  click (float bx +. float bw /. 2., float by +. float bh -. 6.);
  step ~keys:[ Input.Shift ] [ ch 'i' ]; step [];
  check (has (text_of !e) "(ui/floating (ui/graph \"cobalt\"))" || has (text_of !e) "ui/graph \"cobalt\"")
    ("I opens the material in a floating graph: " ^ text_of !e);
  (* Space a: Material makes a graph and opens it; Material of... fills the reference *)
  jump "scene";
  step [ key Input.Space; ch 'a' ]; step [ Event.TextInput "material" ]; step [ key Input.Enter ]; step [];
  check (has (text_of !e) "(graph material :context material") ("Space a made a material graph: " ^ text_of !e);
  check (pane () = "material" && E3.undo_label !e = Some "New material") "and opened it";
  step [ ch 'u' ]; step [];
  check (pane () = "scene") "u returns from it";
  jump "shards";
  let bx, by, bw, bh = Option.get (E3.node_box !e [ "shards"; "m" ]) in
  click (float bx +. float bw /. 2., float by +. float bh -. 6.);
  step [ key Input.Space; ch 'a' ]; step [ Event.TextInput "spare" ]; step [ key Input.Enter ]; step [];
  check (has (text_of !e) ":material (ref spare)" && has (text_of !e) "(sop/material m")
    ("Material of... adds a sop/material after the selection: " ^ text_of !e);

  E3.close !e

let () =
  face_materials_preserve_explosion ();
  let graph = Prismel_editor.Workspace.sop_graphs (workspace source) |> get
      |> List.assoc "geo" in
  let node = graph in
  let one = cook 1 node and four = cook 4 node in
  assert (signature one.geometry = signature four.geometry);
  assert (Pdk.Geometry.primitive_count one.geometry = 6);
  (match attr "shop_materialpath" one.geometry, attr "material_roughness" one.geometry with
   | Pdk.Attribute.Text names, Float rough ->
       assert (names.(0) = "white" && rough.(0) = 0.8);
       assert (Array.sub names 1 5 = Array.make 5 "blue");
       assert (Array.sub rough 1 5 = Array.make 5 0.3)
   | _ -> assert false);
  let surface = Sketch_support.Surface.of_output one |> get in
  let drawings = Sketch_support.Surface.scene3 node surface |> Scene3.Private.drawings in
  assert (List.length drawings = 2);
  assert (List.fold_left (fun n (d : Scene3.Private.drawing) -> n + Mesh.index_count d.mesh) 0 drawings = 36);
  assert (List.exists (fun (d : Scene3.Private.drawing) -> d.material.diffuse = Color.hex_exn "#2670f5") drawings);
  let assign ?cancel ?group ?(roughness = 0.2) geometry =
    Pdk.Material_assign.run ?cancel ?group ~name:"red" ~color:(1.,0.,0.)
      ~roughness ~emission:(0.,0.,0.) geometry in
  assert (Result.is_error (assign ~group:"missing" one.geometry));
  assert (Result.is_error (assign ~roughness:Float.nan one.geometry));
  let cancelled = Pdk.Cancel.create () in Pdk.Cancel.cancel cancelled;
  (match assign ~cancel:cancelled one.geometry with
   | Error e -> assert (Pdk.Error.code e = "cancelled") | _ -> assert false);
  assert (signature one.geometry = signature (cook 1 node).geometry);
  List.iter (fun text -> assert (Result.is_error (Prismel_editor.Workspace.load text)))
    ["(workspace x (graph m :context material (material/standard :roughness 2)))";
     "(workspace x (graph m :context material (material/standard :color \"invalid\")))";
     "(workspace x (graph m :context sop (material/standard)))"];
  follow_tests ();
  print_endline "material refs, group preservation, render batches, cancellation and domain exactness passed"
