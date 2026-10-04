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
  print_endline "material refs, group preservation, render batches, cancellation and domain exactness passed"
