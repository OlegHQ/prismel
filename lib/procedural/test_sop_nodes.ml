(* Nodes declared once ([Procedural.Nodes]): the typed [Sop] constructor and
   the editor factory cook byte-identical geometry at one and four domains,
   and the schema key they share hits the session cache for equal values and
   misses it for every changed field. *)

open Rays_math
open Procedural
open Rdk_test_support

let get = function Ok value -> value | Error message -> fail message

let cook domains graph =
  let context = Context.create ~domains ~grain:97 ~seed:42L () |> get in
  let session = Session.create ~max_entries:8 ~max_payload_bytes:200_000_000 |> get in
  let output = match Session.cook session ~context graph with
    | Ok value -> (Result.get_ok (Procedural.Payload.geometry value.payload))
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

(* The factory node carrying [values], built on [inputs]. *)
let from_factory ?optional_inputs factory values inputs =
  let node = (match optional_inputs with
    | None -> Edit_graph.instantiate factory inputs
    | Some inputs -> Edit_graph.instantiate_optional factory inputs) |> get in
  fst (Node.apply_parameters node values |> get)

let same_node name ~typed ~catalog =
  check (Node.parameter_key typed = Node.parameter_key catalog && Node.parameter_key typed <> "")
    (name ^ ": typed constructor and factory share the schema key");
  let one = cook 1 typed in
  List.iter (fun (what, geometry) -> check (equal_geometry one geometry)
      (name ^ ": " ^ what ^ " cooks the same geometry"))
    [ "typed at four domains", cook 4 typed;
      "factory at one domain", cook 1 catalog;
      "factory at four domains", cook 4 catalog ]

let same_cook ?(inputs = []) ?optional_inputs name ~typed ~factory values input =
  same_node name ~typed ~catalog:(from_factory ?optional_inputs factory values (input :: inputs))

let same_generator name ~typed ~factory values =
  same_node name ~typed ~catalog:(from_factory factory values [])

(* A value that differs from [current] and stays inside the hard range. *)
let changed (view : Parameter.field_view) = match view.kind, view.current with
  | Parameter.Toggle_view, Parameter.Bool_value value -> Parameter.Bool_value (not value)
  | Integer_view range, Int_value value ->
      Int_value (if Some value = range.hard_max then value - 1 else value + 1)
  | Floating_view range, Float_value value ->
      Float_value (if Some value = range.hard_max then value -. 0.25 else value +. 0.25)
  | Text_view, Text_value value -> Text_value (value ^ "_changed")
  | Choice_view options, Choice_value value ->
      Choice_value (Option.get (Array.find_opt (fun option -> option <> value) options))
  | _ -> fail (view.name ^ ": view and value disagree")

let cache_identity ?(changes = []) ?(companions = []) name node =
  let session = Session.create ~max_entries:64 ~max_payload_bytes:200_000_000 |> get in
  let context = Context.create ~domains:1 ~grain:97 ~seed:42L () |> get in
  (* a changed text may name a group the input lacks: that cook fails, which
     is still a miss, but nothing is cached to hit afterwards *)
  let cook node = Result.is_ok (Session.cook session ~context node) in
  let misses () = (Session.stats session).misses in
  check (cook node) (name ^ ": cooks");
  let before = misses () in
  ignore (cook node);
  check (misses () = before) (name ^ ": equal parameters hit the session cache");
  List.iter (fun (view : Parameter.field_view) ->
    let value = match List.assoc_opt view.name changes with
      | Some value -> value | None -> changed view in
    match Node.apply_parameters node ((view.name, value) ::
        Option.value ~default:[] (List.assoc_opt view.name companions)) with
    | Error message -> fail (name ^ ": cannot probe " ^ view.name ^ ": " ^ message)
    | result ->
    let edited = fst (get result) in
    let before = misses () in
    let cooked = cook edited in
    check (misses () = before + 1) (name ^ ": changed " ^ view.name ^ " misses the cache");
    ignore (cook edited);
    check (misses () = before + (if cooked then 1 else 2))
      (name ^ ": edited " ^ view.name ^ " then hits the cache"))
    (Node.parameter_fields node);
  Session.close session

let transport_cache_companions =
  ["integrate_constant", ["operation", Parameter.Choice_value "Total"];
   "scale_by_edge_length", ["operation", Parameter.Choice_value "Total"];
   "operation", ["integrate_constant", Parameter.Bool_value false; "scale_by_edge_length", Bool_value false]]

let run () =
  let field = Node.Private.make ~operation:"test.field" ~version:1 ~parameters:""
      ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs:[||]
      (fun ~node_id:_ _ _ ->
        let kernel = Kernel.create ~payload_bytes:0 (function
          | [Kernel.Vec3s positions] -> Ok (fun _ -> Ok (Kernel.Floats
              (Array.init (Array.length positions / 3) (fun i ->
                let x = positions.(3*i) and y = positions.(3*i+1) and z = positions.(3*i+2) in
                sqrt ((x *. x +. y *. y) +. z *. z) -. 1.))))
          | _ -> assert false) in
        Ok Node.Private.{payload = Payload.Kernel kernel; diagnostics = []; instances = None}) in
  let resolution = Vec3.create 8. 9. 7. in
  same_node "iso_surface" ~typed:(Sop.iso_surface ~resolution ~field ())
    ~catalog:(from_factory Nodes.Iso_surface.factory
      ["resolution_x", Parameter.Float_value 8.; "resolution_y", Float_value 9.;
       "resolution_z", Float_value 7.] [field]);
  let facts = Node.facts (Sop.iso_surface ~resolution ~field ()) in
  check (facts.elementwise = Node.None && facts.topology = Changed && facts.exact)
    "iso_surface: irregular, topology-changing, exact";
  List.iter (fun resolution ->
    check (try ignore (Sop.iso_surface ~resolution ~field ()); false
      with Invalid_argument _ -> true) "iso_surface: invalid resolution rejected")
    [Vec3.create 0. 2. 2.; Vec3.create 1.5 2. 2.; Vec3.create nan 2. 2.;
     Vec3.create 1e15 1e15 1e15];
  check (try ignore (Sop.iso_surface ~min:(Vec3.create 2. 2. 2.) ~field ()); false
    with Invalid_argument _ -> true) "iso_surface: invalid bounds rejected";
  let projection_context = Context.create ~frame:7L ~time:2.5 ~seed:11L
      ~domains:1 ~grain:3 () |> get in
  let projection_facts = Context.Dependencies.[
      Frame, "f7;"; Time, "t4612811918334230528;"; Seed, "s11;";
      Domains, "d1;"; Grain, "g3;";
    ] in
  let rec check_projections dependencies expected = function
    | [] -> if Context.cache_projection dependencies projection_context <> expected
        then fail "context cache projection changed"
    | (fact, token) :: rest ->
        check_projections dependencies expected rest;
        check_projections
          (Context.Dependencies.union dependencies (Context.Dependencies.one fact))
          (expected ^ token) rest in
  check_projections Context.Dependencies.static "" projection_facts;
  let transform_source = Sop.grid ~columns:4 ~rows:3 ()
      |> Sop.normals
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1|])
      |> Sop.group ~name:"selected" (Select.vertex_indices [|0;1|])
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selected" ~incidence:Rdk.Group_mesh.Boundary_edge in
  let transform_geometry = cook 1 transform_source in
  let transform_input = Sop.snapshot transform_geometry in
  let transform_default = Sop.transform transform_input in
  same_cook "transform defaults" ~typed:transform_default ~factory:Nodes.Transform.factory [] transform_input;
  check (Node.parameter_key (Sop.transform_trs transform_input) = Node.parameter_key transform_default)
    "transform aliases share Lisp defaults and schema";
  cache_identity "transform all fields" transform_default;
  let transform_selections =
    [Sop.Element_point,"Point",Rdk.Transform_ops.Selected_points (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" transform_geometry |> Option.get);
     Element_vertex,"Vertex",Selected_vertices (Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "selected" transform_geometry |> Option.get);
     Element_primitive,"Primitive",Selected_primitives (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" transform_geometry |> Option.get);
     Element_edge,"Edge",Selected_edges (Rdk.Geometry.find_edge_group "selected" transform_geometry |> Option.get)] in
  let transform_orders = [Rdk.Transform_ops.Transform_srt,"SRT";Transform_str,"STR";Transform_rst,"RST";Transform_rts,"RTS";Transform_tsr,"TSR";Transform_trs,"TRS"]
  and transform_rotations = [Rdk.Transform_ops.Transform_xyz,"XYZ";Transform_xzy,"XZY";Transform_yxz,"YXZ";Transform_yzx,"YZX";Transform_zxy,"ZXY";Transform_zyx,"ZYX"] in
  let translate = Vec3.create 0.2 0.3 (-0.1) and rotate = Vec3.create 0.1 0.2 0.3
  and scale = Vec3.create 1.1 0.9 1.2 and pivot = Vec3.create 0.1 (-0.1) 0.2
  and pivot_rotation = Vec3.create 0.2 0.1 (-0.1) in
  let transform_values = ["translate_x",Parameter.Float_value translate.x;"translate_y",Float_value translate.y;"translate_z",Float_value translate.z;
    "rotate_x",Float_value rotate.x;"rotate_y",Float_value rotate.y;"rotate_z",Float_value rotate.z;
    "scale_x",Float_value scale.x;"scale_y",Float_value scale.y;"scale_z",Float_value scale.z;
    "shear_xy",Float_value 0.1;"shear_xz",Float_value 0.2;"shear_yz",Float_value (-0.1);"uniform_scale",Float_value 0.8;
    "pivot_x",Float_value pivot.x;"pivot_y",Float_value pivot.y;"pivot_z",Float_value pivot.z;
    "pivot_rotation_x",Float_value pivot_rotation.x;"pivot_rotation_y",Float_value pivot_rotation.y;"pivot_rotation_z",Float_value pivot_rotation.z] in
  List.iter (fun (order,order_name) -> List.iter (fun (rotation_order,rotation_name) ->
    List.iter (fun (group_owner,owner_name,selection) -> List.iter (fun invert ->
      List.iter (fun preserve_normal_length -> List.iter (fun recompute_normals ->
        let typed = Sop.transform ~order ~rotation_order ~translate ~rotate ~scale ~pivot ~pivot_rotation
            ~shear_xy:0.1 ~shear_xz:0.2 ~shear_yz:(-0.1) ~uniform_scale:0.8 ~invert
            ~group_owner ~group:"selected" ~preserve_normal_length ~recompute_normals transform_input in
        same_cook "transform TRS controls" ~typed ~factory:Nodes.Transform.factory
          (transform_values @ ["order",Parameter.Choice_value order_name;"rotation_order",Choice_value rotation_name;
            "group_owner",Choice_value owner_name;"group",Text_value "selected";"invert",Bool_value invert;
            "preserve_normal_length",Bool_value preserve_normal_length;"recompute_normals",Bool_value recompute_normals]) transform_input;
        let matrix = Rdk.Transform_ops.compose_transform ~order ~rotation_order ~translate ~rotate ~scale ~pivot ~pivot_rotation
            ~shear:(Vec3.create 0.1 0.2 (-0.1)) ~uniform_scale:0.8 ~invert () |> Result.get_ok in
        let native = Rdk.Transform_ops.transform_selected ~selection ~preserve_normal_length ~recompute_normals matrix transform_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "transform TRS controls match native") [false;true]) [false;true]) [false;true])
      transform_selections) transform_rotations) transform_orders;
  List.iter (fun matrix -> List.iter (fun (group_owner,owner_name,selection) ->
    List.iter (fun preserve_normal_length -> List.iter (fun recompute_normals ->
      let m row column = Mat4.get matrix ~row ~column in
      let typed = Sop.transform ~mode:Sop.Transform_matrix ~group_owner ~group:"selected" ~preserve_normal_length ~recompute_normals
          ~m00:(m 0 0) ~m01:(m 0 1) ~m02:(m 0 2) ~m03:(m 0 3)
          ~m10:(m 1 0) ~m11:(m 1 1) ~m12:(m 1 2) ~m13:(m 1 3)
          ~m20:(m 2 0) ~m21:(m 2 1) ~m22:(m 2 2) ~m23:(m 2 3)
          ~m30:(m 3 0) ~m31:(m 3 1) ~m32:(m 3 2) ~m33:(m 3 3) transform_input in
      let values = List.init 16 (fun index -> Printf.sprintf "m%d%d" (index/4) (index mod 4),Parameter.Float_value (m (index/4) (index mod 4))) in
      same_cook "transform matrix controls" ~typed ~factory:Nodes.Transform.factory
        (["mode",Parameter.Choice_value "Matrix";"group_owner",Choice_value owner_name;"group",Text_value "selected";
          "preserve_normal_length",Bool_value preserve_normal_length;"recompute_normals",Bool_value recompute_normals] @ values) transform_input;
      let native = Rdk.Transform_ops.transform_selected ~selection ~preserve_normal_length ~recompute_normals matrix transform_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "transform matrix controls match native") [false;true]) [false;true]) transform_selections)
    [Mat4.identity;Mat4.translation translate;Mat4.rotation_x 0.2;Mat4.scaling (Vec3.create 1. 0. 1.);
     Mat4.of_rows (1.,0.1,0.,0.2) (0.,1.,0.2,0.3) (0.,0.,1.,0.4) (0.1,0.,0.,1.)];
  same_cook "transform blank selection" ~typed:(Sop.transform ~group:" " transform_input)
    ~factory:Nodes.Transform.factory ["group",Parameter.Text_value " "] transform_input;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "transform refuses invalid construction")
    [(fun () -> Sop.transform ~translate:(Vec3.create Float.nan 0. 0.) transform_input);
     (fun () -> Sop.transform ~scale:Vec3.zero ~invert:true transform_input);
     (fun () -> Sop.transform ~scale:(Vec3.create Float.max_float 1. 1.) ~uniform_scale:Float.max_float transform_input);
     (fun () -> Sop.transform ~mode:Sop.Transform_matrix ~m33:Float.infinity transform_input)];
  List.iter (fun (field : Parameter.field_view) -> match field.kind with
    | Parameter.Floating_view _ -> check (Result.is_error (Node.apply_parameters transform_default [field.name,Parameter.Float_value Float.nan]))
        "transform inspector refuses every nonfinite field"
    | _ -> ()) (Node.parameter_fields transform_default);
  let intrinsic_schema = Parameter.schema ~name:"snapshot_wrapper" ~default:() [] in
  let wrapped_snapshot geometry = Custom.node ~operation:"snapshot" ~schema:intrinsic_schema ~values:() []
      (fun ~label ~inputs:_ ~parameters:() -> Sop.snapshot ~label geometry) in
  let intrinsic_first = wrapped_snapshot (Rdk.Line_geometry.points [|1.,0.,0.|]) in
  let intrinsic_second = wrapped_snapshot (Rdk.Line_geometry.points [|2.,0.,0.|])
      |> Node.Private.adopt_identity ~source:intrinsic_first in
  check (Node.parameter_key intrinsic_first = Node.parameter_key intrinsic_second
      && Node.Private.cache_parameters intrinsic_first <> Node.Private.cache_parameters intrinsic_second)
    "custom schemas retain distinct intrinsic snapshot identity";
  let intrinsic_session = Session.create ~max_entries:8 ~max_payload_bytes:200_000 |> Result.get_ok in
  let intrinsic_context = Context.create ~domains:1 () |> Result.get_ok in
  let first = Session.cook intrinsic_session ~context:intrinsic_context intrinsic_first |> Result.get_ok in
  let before = Session.stats intrinsic_session in
  let second = Session.cook intrinsic_session ~context:intrinsic_context intrinsic_second |> Result.get_ok in
  let after = Session.stats intrinsic_session in
  check (after.misses > before.misses && not (equal_geometry (Result.get_ok (Procedural.Payload.geometry first.payload)) (Result.get_ok (Procedural.Payload.geometry second.payload))))
    "custom snapshot data changes miss despite equal logical and schema identity";
  let repeated = Session.cook intrinsic_session ~context:intrinsic_context intrinsic_second |> Result.get_ok in
  check ((Result.get_ok (Procedural.Payload.geometry repeated.payload)) == (Result.get_ok (Procedural.Payload.geometry second.payload)) && (Session.stats intrinsic_session).hits > after.hits)
    "custom snapshot repeated intrinsic identity hits";
  Session.close intrinsic_session;
  let schema_only = Sop.grid () in
  check (Node.Private.cache_parameters schema_only = "" && Node.parameters schema_only <> ""
      && Node.parameter_key schema_only <> "") "schema-only nodes keep display text outside intrinsic cache identity";
  let quat_base = Sop.grid ~columns:3 ~rows:3 ()
    |> Sop.group ~name:"selected" Select.all_points
    |> Sop.group ~name:"selected" Select.all_vertices
    |> Sop.group ~name:"selected" Select.all_primitives
    |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"loc" ~value:(Vec3.create 0.2 0.3 0.4)
    |> Sop.set_vector ~owner:Rdk.Attribute.Vertex ~name:"loc" ~value:(Vec3.create 0.2 0.3 0.4)
    |> Sop.set_vector ~owner:Rdk.Attribute.Primitive ~name:"loc" ~value:(Vec3.create 0.2 0.3 0.4)
    |> Sop.set_vector ~owner:Rdk.Attribute.Detail ~name:"loc" ~value:(Vec3.create 0.2 0.3 0.4) in
  let quat_geometry = cook 1 quat_base in
  let quat_source = Sop.snapshot quat_geometry in
  let randomized = Sop.attribute_randomize quat_source in
  same_cook "randomize defaults" ~typed:randomized ~factory:Nodes.Attribute_randomize.factory [] quat_source;
  cache_identity ~companions:["direction_bias",["distribution",Parameter.Choice_value "Direction";
    "kind",Choice_value "Vector 3";"a_x",Float_value 1.]] "randomize all fields" randomized;
  let a = Vec3.create 0.2 0.3 0.4 and b = Vec3.create 1.1 1.2 1.3 in
  let native_a = Rdk.Attribute_ops.Vec3 a and native_b = Rdk.Attribute_ops.Vec3 b in
  let distributions = [
    Sop.Random_constant,"Constant",Rdk.Attribute_ops.Random_constant native_a;
    Random_two_values,"Two values",Random_two_values {a=native_a;b=native_b;probability_b=0.5};
    Random_uniform,"Uniform",Random_uniform {min=native_a;max=native_b};
    Random_uniform_discrete,"Uniform discrete",Random_uniform_discrete {min=native_a;max=native_b;step=Vec3 (Vec3.create 1. 1. 1.)};
    Random_normal,"Normal",Random_normal {middle=native_a;scale=native_b};
    Random_exponential,"Exponential",Random_exponential {median=native_a};
    Random_log_normal,"Log normal",Random_log_normal {median=native_a;stddev=native_b};
    Random_cauchy,"Cauchy",Random_cauchy {median=native_a;scale=Vec3 (Vec3.create 1.1 1.1 1.1)};
    Random_direction,"Direction",Random_direction {direction=native_a;cone_angle=0.7853981633974483};
    Random_inside_sphere,"Inside sphere",Random_inside_sphere {dimensions=3};
    Random_inside_sphere_cone,"Inside sphere cone",Random_inside_sphere_cone {direction=native_a;cone_angle=0.7853981633974483};
    Random_custom_ramp,"Custom ramp",Random_custom_ramp {ramp=[0.,0.;1.,1.];fit_min=native_a;fit_max=native_b};
    Random_custom_discrete,"Custom discrete",Random_custom_discrete [native_a,1.;native_b,2.]] in
  List.iter (fun (distribution,choice,native_distribution) ->
    List.iter (fun (owner,owner_choice) ->
      let b = if distribution = Sop.Random_cauchy then Vec3.create 1.1 1.1 1.1 else b in
      let typed = Sop.attribute_randomize ~owner ~kind:Sop.Numeric_vec3 ~distribution ~a ~b
          ~entries:"0.2\t0.3\t0.4\t1\n1.1\t1.2\t1.3\t2" quat_source in
      same_cook "randomize distributions" ~typed ~factory:Nodes.Attribute_randomize.factory
        ["owner",Parameter.Choice_value owner_choice;"kind",Choice_value "Vector 3";"distribution",Choice_value choice;
         "a_x",Float_value 0.2;"a_y",Float_value 0.3;"a_z",Float_value 0.4;
         "b_x",Float_value b.x;"b_y",Float_value b.y;"b_z",Float_value b.z;
         "entries",Text_value "0.2\t0.3\t0.4\t1\n1.1\t1.2\t1.3\t2"] quat_source;
      let native = Rdk.Attribute_ops.randomize ~seed:(Rand.seed 0) ~owner ~name:"random" native_distribution quat_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "flat randomize distributions match native")
      [Rdk.Attribute.Point,"Point";Vertex,"Vertex";Primitive,"Primitive";Detail,"Detail"])
    distributions;
  same_cook "randomize custom text" ~typed:(Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete_text quat_source)
    ~factory:Nodes.Attribute_randomize.factory ["distribution",Parameter.Choice_value "Custom discrete text"] quat_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "randomize refuses invalid construction")
    [(fun () -> Sop.attribute_randomize ~distribution:Sop.Random_direction quat_source);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete ~entries:"" quat_source);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete ~entries:"1\t-1" quat_source);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete_text ~operation:Rdk.Attribute_ops.Random_add quat_source);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_uniform_discrete ~step:Vec3.zero quat_source);
     (fun () -> Sop.attribute_randomize ~use_minimum:true ~use_maximum:true ~minimum:2. quat_source)];
  let random_owners = [Rdk.Attribute.Point,"Point";Vertex,"Vertex";Primitive,"Primitive";Detail,"Detail"] in
  let random_kinds = [Sop.Numeric_scalar,"Scalar",1;Numeric_vec2,"Vector 2",2;Numeric_vec3,"Vector 3",3;Numeric_vec4,"Vector 4",4] in
  let numeric dimension x y z w = match dimension with
    | 1 -> Rdk.Attribute_ops.Scalar x | 2 -> Vec2 (Vec2.create x y)
    | 3 -> Vec3 (Vec3.create x y z) | _ -> Vec4 (x,y,z,w) in
  let random_geometry = List.fold_left (fun geometry (owner,_) ->
    let count = match owner with Rdk.Attribute.Point -> Rdk.Geometry.point_count geometry
      | Vertex -> Rdk.Geometry.vertex_count geometry | Primitive -> Rdk.Geometry.primitive_count geometry | Detail -> 1 in
    let install name storage = Rdk.Attribute.create_owned ~owner ~name storage |> Result.get_ok
      |> fun attribute -> Rdk.Geometry.with_attribute attribute geometry |> Result.get_ok in
    let geometry = install "seed_values" (Rdk.Attribute.Int (Array.init count (fun i -> 3*i+7))) in
    List.fold_left (fun geometry dimension ->
      let values value = Array.make count value in
      let storage = match dimension with
        | 1 -> Rdk.Attribute.Float (values 0.25)
        | 2 -> Rdk.Attribute.Float2 (Rdk.Packed.Float2.of_owned ~x:(values 0.25) ~y:(values 0.5) |> Result.get_ok)
        | 3 -> Rdk.Attribute.Float3 (Rdk.Packed.Float3.of_owned ~x:(values 0.25) ~y:(values 0.5) ~z:(values 0.75) |> Result.get_ok)
        | _ -> Rdk.Attribute.Float4 (Rdk.Packed.Float4.of_owned ~x:(values 0.25) ~y:(values 0.4) ~z:(values 0.6) ~w:(values 0.75) |> Result.get_ok) in
      let attribute = Rdk.Attribute.create_owned ~owner ~name:("fraction" ^ string_of_int dimension) storage |> Result.get_ok in
      Rdk.Geometry.with_attribute attribute geometry |> Result.get_ok) geometry [1;2;3;4]) quat_geometry random_owners in
  let random_input = Sop.snapshot random_geometry in
  let random_operations = [Rdk.Attribute_ops.Random_set,"Set";Random_add,"Add";Random_minimum,"Minimum";Random_maximum,"Maximum";Random_multiply,"Multiply"] in
  let modes = List.map (fun (mode,label,_) -> mode,label) distributions in
  let expected_random_seed () =
    let mixed = Int64.logxor 42L (Int64.mul 0x3b6ee50efd923331L 0x9e3779b97f4a7c15L) in
    Int64.to_int (Int64.logxor mixed (Int64.shift_right_logical mixed 32)) in
  List.iter (fun (kind,kind_label,dimension) ->
    let a = Vec3.create 0.2 0.3 0.4 and b = Vec3.create 1.1 1.1 1.1 in
    let av = numeric dimension 0.2 0.3 0.4 0.5 and bv = numeric dimension 1.1 1.1 1.1 1.1 in
    let entries = String.concat "\n" [String.concat "\t" ((List.init dimension (fun i -> List.nth ["0.2";"0.3";"0.4";"0.5"] i)) @ ["1"]);
      String.concat "\t" (List.init dimension (fun _ -> "1.1") @ ["2"])] in
    List.iter (fun (distribution,distribution_label) ->
      let directional = distribution = Sop.Random_direction || distribution = Sop.Random_inside_sphere_cone in
      if dimension > 1 || not (directional || distribution = Sop.Random_inside_sphere) then (
      let native_distribution = match distribution with
        | Sop.Random_constant -> Rdk.Attribute_ops.Random_constant av
        | Random_two_values -> Random_two_values {a=av;b=bv;probability_b=0.5}
        | Random_uniform -> Random_uniform {min=av;max=bv}
        | Random_uniform_discrete -> Random_uniform_discrete {min=av;max=bv;step=numeric dimension 1. 1. 1. 1.}
        | Random_normal -> Random_normal {middle=av;scale=bv}
        | Random_exponential -> Random_exponential {median=av}
        | Random_log_normal -> Random_log_normal {median=av;stddev=bv}
        | Random_cauchy -> Random_cauchy {median=av;scale=bv}
        | Random_direction -> Random_direction {direction=av;cone_angle=0.7}
        | Random_inside_sphere -> Random_inside_sphere {dimensions=dimension}
        | Random_inside_sphere_cone -> Random_inside_sphere_cone {direction=av;cone_angle=0.7}
        | Random_custom_ramp -> Random_custom_ramp {ramp=[0.,0.;0.5,0.2;1.,1.];fit_min=av;fit_max=bv}
        | Random_custom_discrete -> Random_custom_discrete [av,1.;bv,2.]
        | Random_custom_discrete_text -> assert false in
      List.iter (fun (owner,owner_label) ->
        let count = match owner with Rdk.Attribute.Point -> Rdk.Geometry.point_count random_geometry
          | Vertex -> Rdk.Geometry.vertex_count random_geometry | Primitive -> Rdk.Geometry.primitive_count random_geometry | Detail -> 1 in
        let values value = Array.make count value in
        let storage = match dimension with
          | 1 -> Rdk.Attribute.Float (values 0.6)
          | 2 -> Rdk.Attribute.Float2 (Rdk.Packed.Float2.of_owned ~x:(values 0.6) ~y:(values 0.7) |> Result.get_ok)
          | 3 -> Rdk.Attribute.Float3 (Rdk.Packed.Float3.of_owned ~x:(values 0.6) ~y:(values 0.7) ~z:(values 0.8) |> Result.get_ok)
          | _ -> Rdk.Attribute.Float4 (Rdk.Packed.Float4.of_owned ~x:(values 0.6) ~y:(values 0.7) ~z:(values 0.8) ~w:(values 0.9) |> Result.get_ok) in
        let attribute = Rdk.Attribute.create_owned ~owner ~name:"random" storage |> Result.get_ok in
        let random_geometry = Rdk.Geometry.with_attribute attribute random_geometry |> Result.get_ok in
        let random_input = Sop.snapshot random_geometry in
        List.iter (fun (operation,operation_label) ->
      List.iter (fun sampling ->
        let context_seed = sampling = 1 and use_fraction = sampling = 2 in
        let fraction_dimension = match distribution with
          | Sop.Random_two_values | Random_custom_discrete -> 1
          | Random_direction -> dimension - 1 | _ -> dimension in
        let fraction_attribute = if use_fraction then "fraction" ^ string_of_int fraction_dimension else "" in
        let seed_attribute = if sampling = 0 || use_fraction then "seed_values" else "" in
        let bias = if directional then 0.4 else 0. in
        let typed = Sop.attribute_randomize ~owner ~kind ~distribution ~operation ~context_seed ~seed:17 ~seed_attribute
          ~fraction_attribute ~a ~a_w:0.5 ~b ~b_w:1.1 ~cone_angle:0.7 ~dimensions:(max 2 dimension)
          ~ramp:"0:0,0.5:0.2,1:1" ~entries ~direction_bias:bias ~scale:0.8
          ~use_minimum:true ~minimum:(-2.) ~use_maximum:true ~maximum:2. random_input in
        same_cook "randomize dimension/operation/sampling" ~typed ~factory:Nodes.Attribute_randomize.factory
          ["owner",Parameter.Choice_value owner_label;"kind",Choice_value kind_label;"distribution",Choice_value distribution_label;
           "operation",Choice_value operation_label;"context_seed",Bool_value context_seed;"seed",Int_value 17;
           "seed_attribute",Text_value seed_attribute;"fraction_attribute",Text_value fraction_attribute;
           "a_x",Float_value 0.2;"a_y",Float_value 0.3;"a_z",Float_value 0.4;"a_w",Float_value 0.5;
           "b_x",Float_value 1.1;"b_y",Float_value 1.1;"b_z",Float_value 1.1;"b_w",Float_value 1.1;
           "cone_angle",Float_value 0.7;"dimensions",Int_value (max 2 dimension);"ramp",Text_value "0:0,0.5:0.2,1:1";
           "entries",Text_value entries;"direction_bias",Float_value bias;"scale",Float_value 0.8;
           "use_minimum",Bool_value true;"minimum",Float_value (-2.);"use_maximum",Bool_value true;"maximum",Float_value 2.] random_input;
        let seed = Rand.seed (if use_fraction then 0 else if context_seed then expected_random_seed () else 17) in
        let native = Rdk.Attribute_ops.randomize ~seed ~owner ~name:"random" ~operation ~direction_bias:bias ~scale:0.8
          ?seed_attribute:(if sampling = 0 then Some "seed_values" else None)
          ?fraction_attribute:(if use_fraction then Some fraction_attribute else None)
          ~minimum:(numeric dimension (-2.) (-2.) (-2.) (-2.)) ~maximum:(numeric dimension 2. 2. 2. 2.) native_distribution random_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "expanded randomize controls match native";
        check (Context.Dependencies.mem Context.Dependencies.Seed (Node.dependencies typed) = context_seed)
          "randomize declares only the active context seed dependency") [0;1;2]) random_operations) random_owners)) modes) random_kinds;
  let selection_source = quat_source
    |> Sop.group ~name:"partial" (Select.point_indices [|0|])
    |> Sop.group ~name:"partial" (Select.vertex_indices [|0|])
    |> Sop.group ~name:"partial" (Select.primitive_indices [|0|])
    |> Sop.group_edges ~name:"partial" ~incidence:Rdk.Group_mesh.Boundary_edge in
  let selection_geometry = cook 1 selection_source in
  let selection_input = Sop.snapshot selection_geometry in
  let selectors = [
    Sop.Element_point,"Point",Rdk.Attribute_ops.Random_points (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "partial" selection_geometry |> Option.get);
    Element_vertex,"Vertex",Random_vertices (Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "partial" selection_geometry |> Option.get);
    Element_primitive,"Primitive",Random_primitives (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "partial" selection_geometry |> Option.get);
    Element_edge,"Edge",Random_edges (Rdk.Geometry.find_edge_group "partial" selection_geometry |> Option.get)] in
  List.iter (fun (kind,kind_label,dimension) ->
    List.iter (fun (owner,owner_label) -> if owner <> Rdk.Attribute.Detail then
    List.iter (fun (selection_owner,selection_label,element_selection) ->
    List.iter (fun vector_limits ->
      let typed = Sop.attribute_randomize ~owner ~kind ~selection_owner ~selection_group:"partial" ~seed:17
        ~use_minimum:true ~minimum:(-1.) ~use_maximum:true ~maximum:1. ~use_vector_limits:vector_limits
        ~minimum_vector:(Vec3.create (-1.) (-2.) (-3.)) ~minimum_w:(-4.)
        ~maximum_vector:(Vec3.create 1. 2. 3.) ~maximum_w:4. selection_input in
      same_cook "randomize selection and component limits" ~typed ~factory:Nodes.Attribute_randomize.factory
        ["owner",Parameter.Choice_value owner_label;"kind",Choice_value kind_label;"selection_owner",Choice_value selection_label;
         "selection_group",Text_value "partial";"seed",Int_value 17;"use_minimum",Bool_value true;"minimum",Float_value (-1.);
         "use_maximum",Bool_value true;"maximum",Float_value 1.;"use_vector_limits",Bool_value vector_limits;
         "minimum_vector_x",Float_value (-1.);"minimum_vector_y",Float_value (-2.);"minimum_vector_z",Float_value (-3.);"minimum_w",Float_value (-4.);
         "maximum_vector_x",Float_value 1.;"maximum_vector_y",Float_value 2.;"maximum_vector_z",Float_value 3.;"maximum_w",Float_value 4.] selection_input;
      let minimum = if vector_limits then numeric dimension (-1.) (-2.) (-3.) (-4.) else numeric dimension (-1.) (-1.) (-1.) (-1.)
      and maximum = if vector_limits then numeric dimension 1. 2. 3. 4. else numeric dimension 1. 1. 1. 1. in
      let native = Rdk.Attribute_ops.randomize ~element_selection ~seed:(Rand.seed 17) ~owner ~name:"random" ~minimum ~maximum
          (Rdk.Attribute_ops.Random_uniform {min=numeric dimension 0. 0. 0. 0.;max=numeric dimension 1. 1. 1. 1.}) selection_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "randomize selection and component limits match native") [false;true]) selectors) random_owners) random_kinds;
  List.iter (fun (owner,owner_label) ->
    let text = "low\t1\nhigh\\tvalue\t3" in
    let typed = Sop.attribute_randomize ~owner ~distribution:Sop.Random_custom_discrete_text ~text_entries:text
      ~fraction_attribute:"fraction1" ~seed_attribute:"ignored" ~context_seed:true ~seed:99 random_input in
    same_cook "randomize text fractions ignore seeds" ~typed ~factory:Nodes.Attribute_randomize.factory
      ["owner",Parameter.Choice_value owner_label;"distribution",Choice_value "Custom discrete text";"text_entries",Text_value text;
       "fraction_attribute",Text_value "fraction1";"seed_attribute",Text_value "ignored";"context_seed",Bool_value true;"seed",Int_value 99] random_input;
    let native = Rdk.Attribute_ops.randomize ~seed:(Rand.seed 0) ~owner ~name:"random" ~fraction_attribute:"fraction1"
      (Rdk.Attribute_ops.Random_custom_discrete_text ["low",1.;"high\tvalue",3.]) random_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "randomize weighted text matches native";
    check (not (Context.Dependencies.mem Context.Dependencies.Seed (Node.dependencies typed))) "fraction text ignores context seed") random_owners;
  let session = Session.create ~max_entries:32 ~max_payload_bytes:2_000_000 |> Result.get_ok in
  let context seed = Context.create ~domains:1 ~seed () |> Result.get_ok in
  List.iter (fun mode ->
    let node = Sop.attribute_randomize ~context_seed:(mode <> 0) ~seed:17
      ~fraction_attribute:(if mode = 2 then "fraction1" else "") ~seed_attribute:(if mode = 2 then "ignored" else "") random_input in
    let first = Session.cook session ~context:(context 42L) node |> Result.get_ok
    and second = Session.cook session ~context:(context 43L) node |> Result.get_ok in
    check (if mode = 1 then not (equal_geometry (Result.get_ok (Procedural.Payload.geometry first.payload)) (Result.get_ok (Procedural.Payload.geometry second.payload))) else (Result.get_ok (Procedural.Payload.geometry first.payload)) == (Result.get_ok (Procedural.Payload.geometry second.payload)))
      "randomize context invalidation follows the active sampling mode") [0;1;2];
  Session.close session;
  same_cook "randomize blank optional names" ~typed:(Sop.attribute_randomize ~group:" " ~selection_group:" " ~seed_attribute:" " ~fraction_attribute:" " random_input)
    ~factory:Nodes.Attribute_randomize.factory ["group",Parameter.Text_value " ";"selection_group",Text_value " ";"seed_attribute",Text_value " ";"fraction_attribute",Text_value " "] random_input;
  List.iter (fun (field : Parameter.field_view) -> match field.kind with
    | Parameter.Floating_view _ -> check (Result.is_error (Node.apply_parameters randomized [field.name,Parameter.Float_value Float.nan]))
        "randomize inspector refuses every nonfinite field"
    | _ -> ()) (Node.parameter_fields randomized);
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "randomize rejects invalid distribution controls at construction")
    [(fun () -> Sop.attribute_randomize ~name:" " random_input);
     (fun () -> Sop.attribute_randomize ~owner:Rdk.Attribute.Detail ~selection_group:"partial" random_input);
     (fun () -> Sop.attribute_randomize ~group:"a" ~selection_group:"b" random_input);
     (fun () -> Sop.attribute_randomize ~kind:Sop.Numeric_vec3 ~distribution:Sop.Random_cauchy ~b:(Vec3.create 1. 2. 3.) random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_normal ~b:(Vec3.create (-1.) 0. 0.) random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_exponential random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_log_normal ~a:(Vec3.create 0.1 0.1 0.1) ~b:(Vec3.create (-1.) 0. 0.) random_input);
     (fun () -> Sop.attribute_randomize ~kind:Sop.Numeric_vec3 ~distribution:Sop.Random_direction ~a:Vec3.unit_x ~cone_angle:(Float.pi +. 0.1) random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_inside_sphere ~dimensions:1 random_input);
     (fun () -> Sop.attribute_randomize ~direction_bias:0.2 random_input);
     (fun () -> Sop.attribute_randomize ~kind:Sop.Numeric_vec3 ~distribution:Sop.Random_direction ~a:Vec3.unit_x ~direction_bias:(-1.) random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_ramp ~ramp:"0:0,0:1" random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete ~entries:"1\t0\n2\t0" random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete ~entries:"1\tinf" random_input);
     (fun () -> Sop.attribute_randomize ~kind:Sop.Numeric_vec3 ~distribution:Sop.Random_custom_discrete ~entries:"1\t1" random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete_text ~scale:0.5 random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_custom_discrete_text ~use_minimum:true random_input);
     (fun () -> Sop.attribute_randomize ~name:"P" random_input);
     (fun () -> Sop.attribute_randomize ~distribution:Sop.Random_inside_sphere ~dimensions:4 ~use_minimum:true random_input)];
  cache_identity ~companions:["direction_bias",["distribution",Parameter.Choice_value "Direction";
    "kind",Choice_value "Vector 3";"a_x",Float_value 1.]] "randomize context-seed fields"
    (Sop.attribute_randomize ~context_seed:true ~seed:17 random_input);
  List.iter (fun (operation,operation_label) ->
    let typed = Sop.attribute_randomize ~name:"P" ~kind:Sop.Numeric_vec3 ~operation selection_input in
    same_cook "randomize positions" ~typed ~factory:Nodes.Attribute_randomize.factory
      ["name",Parameter.Text_value "P";"kind",Choice_value "Vector 3";"operation",Choice_value operation_label] selection_input;
    let native = Rdk.Attribute_ops.randomize ~seed:(Rand.seed 0) ~owner:Rdk.Attribute.Point ~name:"P" ~operation
      (Rdk.Attribute_ops.Random_uniform {min=Vec3 Vec3.zero;max=Vec3 (Vec3.create 1. 1. 1.)}) selection_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "randomize position writes match native") random_operations;
  let noise_input = quat_source and noise_geometry = quat_geometry in
  let noise = Sop.attribute_noise noise_input in
  same_cook "attribute noise defaults" ~typed:noise ~factory:Nodes.Attribute_noise.factory [] noise_input;
  cache_identity ~changes:["blend",Parameter.Float_value 0.75] "attribute noise all fields" noise;
  let kinds = [Rdk.Attribute_ops.Noise_float,"Float",1;Noise_vector,"Vector",3;Noise_quaternion,"Quaternion",4] in
  let operations = [Rdk.Attribute_ops.Noise_set_initial,"Set initial";Noise_set,"Set";Noise_add,"Add";
    Noise_subtract,"Subtract";Noise_multiply,"Multiply";Noise_minimum,"Minimum";Noise_maximum,"Maximum"] in
  let noise_owners = [Rdk.Attribute.Point,"Point",Some Rdk.Group.Point;
    Rdk.Attribute.Vertex,"Vertex",Some Rdk.Group.Vertex;Rdk.Attribute.Primitive,"Primitive",Some Rdk.Group.Primitive;
    Rdk.Attribute.Detail,"Detail",None] in
  let expected_noise_seed context_seed =
    let hash = ref 0xcbf29ce484222325L in
    String.iter (fun character -> hash := Int64.mul (Int64.logxor !hash (Int64.of_int (Char.code character))) 0x100000001b3L)
      "attribute_noise:attribute_noise";
    let mixed = Int64.logxor context_seed (Int64.mul !hash 0x9e3779b97f4a7c15L) in
    Int64.to_int (Int64.logxor mixed (Int64.shift_right_logical mixed 32)) in
  List.iter (fun (owner,owner_choice,group_owner) ->
    List.iter (fun (kind,kind_choice,dimension) ->
    List.iter (fun (operation,operation_choice) ->
    if kind <> Rdk.Attribute_ops.Noise_quaternion || operation = Rdk.Attribute_ops.Noise_set || operation = Rdk.Attribute_ops.Noise_set_initial then (
    List.iter (fun (location,location_choice,native_location) ->
    List.iter (fun (range,range_choice,native_range) ->
    List.iter (fun context_seed ->
      let typed = Sop.attribute_noise ~owner ~name:"sample" ~kind ~operation ~location ~location_attribute:"loc" ~range
          ~min:(Vec3.create (-0.5) (-0.4) (-0.3)) ~min_w:(-0.2) ~max:(Vec3.create 0.5 0.6 0.7) ~max_w:0.8
          ~context_seed ~seed:17 ~blend:0.6 ~frequency:(Vec3.create 0.5 1. 1.5) ~offset:(Vec3.create 0.1 0.2 0.3)
          ~octaves:3 ~lacunarity:1.7 ~roughness:0.3 noise_input in
      same_cook "attribute noise controls" ~typed ~factory:Nodes.Attribute_noise.factory
        ["owner",Parameter.Choice_value owner_choice;"name",Text_value "sample";"kind",Choice_value kind_choice;
         "operation",Choice_value operation_choice;"location",Choice_value location_choice;"location_attribute",Text_value "loc";
         "range",Choice_value range_choice;"min_x",Float_value (-0.5);"min_y",Float_value (-0.4);"min_z",Float_value (-0.3);"min_w",Float_value (-0.2);
         "max_x",Float_value 0.5;"max_y",Float_value 0.6;"max_z",Float_value 0.7;"max_w",Float_value 0.8;
         "context_seed",Bool_value context_seed;"seed",Int_value 17;"blend",Float_value 0.6;
         "frequency_x",Float_value 0.5;"frequency_y",Float_value 1.;"frequency_z",Float_value 1.5;
         "offset_x",Float_value 0.1;"offset_y",Float_value 0.2;"offset_z",Float_value 0.3;
         "octaves",Int_value 3;"lacunarity",Float_value 1.7;"roughness",Float_value 0.3] noise_input;
      let seed = if context_seed then expected_noise_seed 42L else 17 in
      let native = Rdk.Attribute_ops.noise ~owner ~name:"sample" ~kind ~operation ~location:native_location ~range:native_range
          ~seed ~blend:0.6 ~frequency:(Vec3.create 0.5 1. 1.5) ~offset:(Vec3.create 0.1 0.2 0.3)
          ~octaves:3 ~lacunarity:1.7 ~roughness:0.3 noise_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "attribute noise controls match native";
      check (Context.Dependencies.mem Context.Dependencies.Seed (Node.dependencies typed) = context_seed)
        "attribute noise declares its context seed dependency") [false;true])
      [Sop.Noise_positive,"Positive",Rdk.Attribute_ops.Noise_positive;
       Sop.Noise_zero_centered,"Zero centered",Rdk.Attribute_ops.Noise_zero_centered;
       Sop.Noise_min_max,"Minimum / maximum",Rdk.Attribute_ops.Noise_min_max
        ((match dimension with 1 -> Rdk.Attribute_ops.Scalar (-0.5) | 3 -> Rdk.Attribute_ops.Vec3 (Vec3.create (-0.5) (-0.4) (-0.3)) | _ -> Vec4 (-0.5,-0.4,-0.3,-0.2)),
         (match dimension with 1 -> Rdk.Attribute_ops.Scalar 0.5 | 3 -> Rdk.Attribute_ops.Vec3 (Vec3.create 0.5 0.6 0.7) | _ -> Vec4 (0.5,0.6,0.7,0.8)))])
      [Sop.Noise_position,"Position",Rdk.Attribute_ops.Noise_position;
       Sop.Noise_element_number,"Element number",Rdk.Attribute_ops.Noise_element_number;
       Sop.Noise_attribute,"Attribute",Rdk.Attribute_ops.Noise_attribute "loc"];
    Option.iter (fun group_owner ->
      let typed = Sop.attribute_noise ~owner ~kind ~operation ~group:"selected" noise_input in
      same_cook "attribute noise selected group" ~typed ~factory:Nodes.Attribute_noise.factory
        ["owner",Parameter.Choice_value owner_choice;"kind",Choice_value kind_choice;
          "operation",Choice_value operation_choice;"group",Text_value "selected"] noise_input;
      let selection = Rdk.Geometry.find_group ~owner:group_owner "selected" noise_geometry |> Option.get in
      let native = Rdk.Attribute_ops.noise ~selection ~seed:0 ~owner ~name:"noise" ~kind ~operation noise_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "attribute noise selected group matches native") group_owner
    )) operations) kinds) noise_owners;
  List.iter (fun (owner,owner_choice,_) -> List.iter (fun (kind,kind_choice,dimension) ->
    let count = match owner with Rdk.Attribute.Point -> Rdk.Geometry.point_count noise_geometry
      | Vertex -> Rdk.Geometry.vertex_count noise_geometry | Primitive -> Rdk.Geometry.primitive_count noise_geometry | Detail -> 1 in
    let values value = Array.make count value in
    let storage = match dimension with
      | 1 -> Rdk.Attribute.Float (values 0.4)
      | 3 -> Rdk.Attribute.Float3 (Rdk.Packed.Float3.of_owned ~x:(values 0.2) ~y:(values 0.3) ~z:(values 0.4) |> Result.get_ok)
      | _ -> Rdk.Attribute.Float4 (Rdk.Packed.Float4.of_owned ~x:(values 0.) ~y:(values 0.) ~z:(values 0.) ~w:(values 1.) |> Result.get_ok) in
    let attribute = Rdk.Attribute.create_owned ~owner ~name:"existing" storage |> Result.get_ok in
    let geometry = Rdk.Geometry.with_attribute attribute noise_geometry |> Result.get_ok in
    let input = Sop.snapshot geometry in
    List.iter (fun (operation,operation_choice) ->
      if kind <> Rdk.Attribute_ops.Noise_quaternion || operation = Rdk.Attribute_ops.Noise_set || operation = Rdk.Attribute_ops.Noise_set_initial then (
        let typed = Sop.attribute_noise ~owner ~kind ~name:"existing" ~operation ~blend:0.5 input in
        same_cook "attribute noise existing target" ~typed ~factory:Nodes.Attribute_noise.factory
          ["owner",Parameter.Choice_value owner_choice;"kind",Choice_value kind_choice;"name",Text_value "existing";
            "operation",Choice_value operation_choice;"blend",Float_value 0.5] input;
        let native = Rdk.Attribute_ops.noise ~seed:0 ~owner ~kind ~name:"existing" ~operation ~blend:0.5 geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "attribute noise existing target matches native")) operations
    ) kinds) noise_owners;
  List.iter (fun (operation,operation_choice) ->
    let typed = Sop.attribute_noise ~kind:Rdk.Attribute_ops.Noise_vector ~name:"P" ~operation noise_input in
    same_cook "attribute noise positions" ~typed ~factory:Nodes.Attribute_noise.factory
      ["kind",Parameter.Choice_value "Vector";"name",Text_value "P";"operation",Choice_value operation_choice] noise_input;
    let native = Rdk.Attribute_ops.noise ~seed:0 ~owner:Rdk.Attribute.Point ~kind:Rdk.Attribute_ops.Noise_vector ~name:"P" ~operation noise_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "attribute noise positions match native") operations;
  List.iter (fun (kind,kind_choice) ->
    same_cook "attribute noise initial P keeps geometry" ~typed:(Sop.attribute_noise ~name:"P" ~kind ~operation:Rdk.Attribute_ops.Noise_set_initial noise_input)
      ~factory:Nodes.Attribute_noise.factory ["name",Parameter.Text_value "P";"kind",Choice_value kind_choice;
        "operation",Choice_value "Set initial"] noise_input) [Rdk.Attribute_ops.Noise_float,"Float";Noise_quaternion,"Quaternion"];
  List.iter (fun roughness -> List.iter (fun blend -> List.iter (fun octaves ->
    let frequency = Vec3.create (-1.) 0. 2. in
    let typed = Sop.attribute_noise ~frequency ~lacunarity:0.5 ~roughness ~blend ~octaves noise_input in
    same_cook "attribute noise boundaries" ~typed ~factory:Nodes.Attribute_noise.factory
      ["frequency_x",Parameter.Float_value (-1.);"frequency_y",Float_value 0.;"frequency_z",Float_value 2.;
        "lacunarity",Float_value 0.5;"roughness",Float_value roughness;"blend",Float_value blend;"octaves",Int_value octaves] noise_input;
    let native = Rdk.Attribute_ops.noise ~seed:0 ~owner:Rdk.Attribute.Point ~name:"noise" ~kind:Rdk.Attribute_ops.Noise_float
        ~frequency ~lacunarity:0.5 ~roughness ~blend ~octaves noise_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "attribute noise boundaries match native") [1;64]) [0.;1.]) [0.;1.];
  same_cook "attribute noise blank group" ~typed:(Sop.attribute_noise ~group:" " noise_input)
    ~factory:Nodes.Attribute_noise.factory ["group",Parameter.Text_value " "] noise_input;
  let fixed = Sop.attribute_noise ~seed:17 noise_input
  and seeded = Sop.attribute_noise ~context_seed:true ~seed:17 noise_input in
  cache_identity ~changes:["blend",Parameter.Float_value 0.75] "attribute noise context-seed fields" seeded;
  let session = Session.create ~max_entries:16 ~max_payload_bytes:1_000_000 |> Result.get_ok in
  let context seed = Context.create ~domains:1 ~seed () |> Result.get_ok in
  let first = Session.cook session ~context:(context 42L) fixed |> Result.get_ok in
  let second = Session.cook session ~context:(context 43L) fixed |> Result.get_ok in
  check ((Result.get_ok (Procedural.Payload.geometry first.payload)) == (Result.get_ok (Procedural.Payload.geometry second.payload))) "explicit noise seed hits across context changes";
  let first = Session.cook session ~context:(context 42L) seeded |> Result.get_ok in
  let second = Session.cook session ~context:(context 43L) seeded |> Result.get_ok in
  check (not (equal_geometry (Result.get_ok (Procedural.Payload.geometry first.payload)) (Result.get_ok (Procedural.Payload.geometry second.payload)))) "context noise seed changes the cooked output";
  Session.close session;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "attribute noise refuses invalid construction")
    [(fun () -> Sop.attribute_noise ~name:" " noise_input);
     (fun () -> Sop.attribute_noise ~owner:Rdk.Attribute.Detail ~group:"selected" noise_input);
     (fun () -> Sop.attribute_noise ~location:Sop.Noise_attribute ~location_attribute:" " noise_input);
     (fun () -> Sop.attribute_noise ~blend:1.1 noise_input);
     (fun () -> Sop.attribute_noise ~octaves:65 noise_input);
     (fun () -> Sop.attribute_noise ~lacunarity:0. noise_input);
     (fun () -> Sop.attribute_noise ~roughness:(-0.1) noise_input);
     (fun () -> Sop.attribute_noise ~kind:Rdk.Attribute_ops.Noise_quaternion ~operation:Rdk.Attribute_ops.Noise_add noise_input);
     (fun () -> Sop.attribute_noise ~range:Sop.Noise_min_max ~min:(Vec3.create 2. 0. 0.) noise_input)];
  List.iter (fun (field : Parameter.field_view) -> match field.kind with
    | Parameter.Floating_view _ -> check (Result.is_error (Node.apply_parameters noise [field.name,Parameter.Float_value Float.nan]))
        "attribute noise inspector refuses every nonfinite field"
    | _ -> ()) (Node.parameter_fields noise);
  let quat = Sop.attribute_noise_quaternion quat_source in
  same_cook "quaternion noise defaults" ~typed:quat ~factory:Nodes.Attribute_noise_quaternion.factory [] quat_source;
  cache_identity "quaternion noise all fields"
    ~changes:["location",Parameter.Text_value "position";"range",Text_value "positive"] quat;
  List.iter (fun (owner,owner_choice,group_owner) -> List.iter (fun selected ->
    List.iter (fun (location,native_location) -> List.iter (fun (range,native_range) ->
    List.iter (fun seed -> List.iter (fun octaves ->
      let group = if selected then "selected" else "" in
      let frequency = Vec3.create 0.5 1. 1.5 in
      let typed = Sop.attribute_noise_quaternion ~group ~owner ~name:"orient" ~location ~range ~seed ~frequency ~octaves quat_source in
      same_cook "quaternion noise controls" ~typed ~factory:Nodes.Attribute_noise_quaternion.factory
        ["group",Parameter.Text_value group;"owner",Choice_value owner_choice;"name",Text_value "orient";
         "location",Text_value location;"range",Text_value range;"seed",Int_value seed;"frequency_x",Float_value 0.5;
         "frequency_y",Float_value 1.;"frequency_z",Float_value 1.5;"octaves",Int_value octaves] quat_source;
      let selection = if selected then Option.bind group_owner (fun owner -> Rdk.Geometry.find_group ~owner "selected" quat_geometry) else None in
      let native = Rdk.Attribute_ops.noise ~grain:97 ?selection ~seed ~owner ~name:"orient" ~kind:Rdk.Attribute_ops.Noise_quaternion
        ~location:native_location ~range:native_range ~operation:Rdk.Attribute_ops.Noise_set ~blend:1. ~frequency ~offset:Vec3.zero
        ~octaves ~lacunarity:2. ~roughness:0.5 quat_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "quaternion noise flat encodings match native"
    ) [1;3]) [0;17])
      ["positive",Rdk.Attribute_ops.Noise_positive;"zero-centered",Rdk.Attribute_ops.Noise_zero_centered;
       "min-max;vec4,-0.5,-0.4,-0.3,-0.2;vec4,0.5,0.6,0.7,0.8",
       Rdk.Attribute_ops.Noise_min_max (Rdk.Attribute_ops.Vec4 (-0.5,-0.4,-0.3,-0.2),Rdk.Attribute_ops.Vec4 (0.5,0.6,0.7,0.8))])
      ["position",Rdk.Attribute_ops.Noise_position;"element-number",Rdk.Attribute_ops.Noise_element_number;
       "attribute:loc",Rdk.Attribute_ops.Noise_attribute "loc"])
      (if owner = Rdk.Attribute.Detail then [false] else [false;true]))
    [Rdk.Attribute.Point,"Point",Some Rdk.Group.Point;Rdk.Attribute.Vertex,"Vertex",Some Rdk.Group.Vertex;
     Rdk.Attribute.Primitive,"Primitive",Some Rdk.Group.Primitive;Rdk.Attribute.Detail,"Detail",None];
  same_cook "quaternion noise blank group" ~typed:(Sop.attribute_noise_quaternion ~group:" " quat_source)
    ~factory:Nodes.Attribute_noise_quaternion.factory ["group",Parameter.Text_value " "] quat_source;
  check (Node.dependencies quat = Context.Dependencies.static) "quaternion noise explicit seed is static";
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
    "quaternion noise refuses invalid construction")
    [(fun () -> Sop.attribute_noise_quaternion ~name:" " quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~name:"P" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~owner:Rdk.Attribute.Detail ~group:"selected" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~location:"unknown" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~location:"attribute: " quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~range:"unknown" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~range:"min-max;scalar,0;scalar,1" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~range:"min-max;vec4,nan,0,0,0;vec4,1,1,1,1" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~range:"min-max;vec4,2,0,0,0;vec4,1,1,1,1" quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~frequency:(Vec3.create Float.nan 0. 0.) quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~frequency:(Vec3.create (-1.) 0. 0.) quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~octaves:0 quat_source);
     (fun () -> Sop.attribute_noise_quaternion ~octaves:65 quat_source)];
  check (Result.is_error (Node.apply_parameters quat ["range",Parameter.Text_value "invalid"])) "quaternion noise inspector rejects malformed range";
  let wire_geometry = Test_polywire_sop.source () in
  let wire_source = Sop.snapshot wire_geometry in
  List.iter (fun is_sweep ->
    let construct,factory,operation = if is_sweep then Sop.sweep_circle,Nodes.Sweep_circle.factory,"sweep_circle" else Sop.polywire,Nodes.Polywire.factory,"polywire" in
    let wire = construct wire_source in
    check (Node.operation wire = operation) "circular wire retains its runtime identity";
    check (Node.label wire = operation) "circular wire retains its default label";
    same_cook (operation ^ " defaults") ~typed:wire ~factory [] wire_source;
    cache_identity ~companions:["maximum_joint_scale_attribute",["prevent_joint_buckling",Parameter.Bool_value true]]
      (operation ^ " all fields") wire;
    for flags = 0 to 511 do
      let flag bit = flags land (1 lsl bit) <> 0 in
      let use_sides = flag 0 and use_segment_scales = flag 1 and prevent_joint_buckling = flag 2
      and smooth_point = flag 3 and use_max_valence = flag 4 and generate_uv = flag 5 and caps = flag 6
      and use_u_range = flag 7 and use_v_range = flag 8 in
      let typed = construct ~radius:0.2 ~use_sides ~sides:6 ~segments:1 ~use_segment_scales
        ~first_segment_scale:0.2 ~last_segment_scale:0.8 ~prevent_joint_buckling ~maximum_joint_scale:2.
        ~smooth_point ~use_max_valence ~max_valence:3 ~seam_offset:(-1) ~generate_uv ~use_u_range ~u_min:(-1.) ~u_max:2.
        ~use_v_range ~v_min:2. ~v_max:4. ~caps ~cap_group:"ends" wire_source in
      same_cook (operation ^ " controls") ~typed ~factory
        ["radius",Parameter.Float_value 0.2;"use_sides",Bool_value use_sides;"sides",Int_value 6;"segments",Int_value 1;
         "use_segment_scales",Bool_value use_segment_scales;"first_segment_scale",Float_value 0.2;"last_segment_scale",Float_value 0.8;
         "prevent_joint_buckling",Bool_value prevent_joint_buckling;"maximum_joint_scale",Float_value 2.;"smooth_point",Bool_value smooth_point;
         "use_max_valence",Bool_value use_max_valence;"max_valence",Int_value 3;"seam_offset",Int_value (-1);"generate_uv",Bool_value generate_uv;
         "use_u_range",Bool_value use_u_range;"u_min",Float_value (-1.);"u_max",Float_value 2.;"use_v_range",Bool_value use_v_range;
         "v_min",Float_value 2.;"v_max",Float_value 4.;"caps",Bool_value caps;"cap_group",Text_value "ends"] wire_source;
      let sides = if use_sides then Some 6 else None and segment_scales = if use_segment_scales then Some (0.2,0.8) else None
      and max_valence = if use_max_valence then Some 3 else None and u_range = if use_u_range then Some (-1.,2.) else None
      and v_range = if use_v_range then Some (2.,4.) else None and cap_group = if caps then Some "ends" else None in
      let native = Rdk.Sweep_circle.run ~grain:97 ~radius:0.2 ?sides ~segments:1 ?segment_scales ~prevent_joint_buckling
        ~maximum_joint_scale:2. ~smooth_point ?max_valence ~seam_offset:(-1) ~generate_uv ?u_range ?v_range ~caps ?cap_group wire_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "circular wire flat controls match native"
    done;
    same_cook (operation ^ " unset names") ~typed:(construct ~group:" " ~divisions_attribute:" " ~segments_attribute:" "
      ~segment_scales_attribute:" " ~maximum_joint_scale_attribute:" " ~smooth_attribute:" " ~scale_attribute:" "
      ~seam_attribute:" " ~segment_seam_attribute:" " ~v_attribute:" " ~up_attribute:" " ~uv_range_attribute:" " ~caps:true ~cap_group:" " wire_source)
      ~factory ["group",Parameter.Text_value " ";"divisions_attribute",Text_value " ";"segments_attribute",Text_value " ";
       "segment_scales_attribute",Text_value " ";"maximum_joint_scale_attribute",Text_value " ";"smooth_attribute",Text_value " ";
       "scale_attribute",Text_value " ";"seam_attribute",Text_value " ";"segment_seam_attribute",Text_value " ";"v_attribute",Text_value " ";
       "up_attribute",Text_value " ";"uv_range_attribute",Text_value " ";"caps",Bool_value true;"cap_group",Text_value " "] wire_source;
    List.iter (fun invalid -> check (match invalid () with _ -> false | exception Invalid_argument _ -> true) "circular wire refuses invalid construction")
      [(fun () -> construct ~radius:0. wire_source);(fun () -> construct ~radius:Float.nan wire_source);
       (fun () -> construct ~sides:2 wire_source);(fun () -> construct ~segments:0 wire_source);
       (fun () -> construct ~use_segment_scales:true ~first_segment_scale:0.9 ~last_segment_scale:0.1 wire_source);
       (fun () -> construct ~maximum_joint_scale:0.5 wire_source);(fun () -> construct ~max_valence:0 wire_source);
       (fun () -> construct ~maximum_joint_scale_attribute:"limit" wire_source);(fun () -> construct ~u_min:Float.nan wire_source)];
    check (Result.is_error (Node.apply_parameters wire ["radius",Parameter.Float_value Float.nan])) "circular wire inspector refuses invalid radius"
  ) [false;true];
  let with_wire_attribute owner name storage geometry =
    let attribute = Rdk.Attribute.create_owned ~owner ~name storage |> Result.get_ok in
    Rdk.Geometry.with_attribute attribute geometry |> Result.get_ok in
  let f2 = Rdk.Packed.Float2.of_owned ~x:(Array.make 4 0.1) ~y:(Array.make 4 0.9) |> Result.get_ok
  and f3 = Rdk.Packed.Float3.of_owned ~x:(Array.make 4 0.) ~y:(Array.make 4 1.) ~z:(Array.make 4 0.) |> Result.get_ok
  and f4 = Rdk.Packed.Float4.of_owned ~x:(Array.make 4 0.) ~y:(Array.make 4 1.) ~z:(Array.make 4 2.) ~w:(Array.make 4 3.) |> Result.get_ok in
  let override_geometry = wire_geometry
    |> with_wire_attribute Rdk.Attribute.Point "limit" (Rdk.Attribute.Float (Array.make 4 2.))
    |> with_wire_attribute Rdk.Attribute.Point "scale" (Rdk.Attribute.Float (Array.make 4 0.8))
    |> with_wire_attribute Rdk.Attribute.Point "smooth" (Rdk.Attribute.Float (Array.make 4 1.))
    |> with_wire_attribute Rdk.Attribute.Point "seam" (Rdk.Attribute.Int (Array.make 4 1))
    |> with_wire_attribute Rdk.Attribute.Point "v" (Rdk.Attribute.Float [|0.;1.;0.;1.|])
    |> with_wire_attribute Rdk.Attribute.Point "up" (Rdk.Attribute.Float3 f3)
    |> with_wire_attribute Rdk.Attribute.Vertex "scales" (Rdk.Attribute.Float2 f2)
    |> with_wire_attribute Rdk.Attribute.Vertex "segment_seam" (Rdk.Attribute.Int (Array.make 4 1))
    |> with_wire_attribute Rdk.Attribute.Vertex "ranges" (Rdk.Attribute.Float4 f4) in
  let override_source = Sop.snapshot override_geometry in
  List.iter (fun is_sweep ->
    let construct,factory = if is_sweep then Sop.sweep_circle,Nodes.Sweep_circle.factory else Sop.polywire,Nodes.Polywire.factory in
    List.iter (fun selected ->
    let group = if selected then "first" else "" in
    let typed = construct ~group ~divisions_attribute:"div" ~segments:2 ~segments_attribute:"seg" ~segment_scales_attribute:"scales"
      ~prevent_joint_buckling:true ~maximum_joint_scale_attribute:"limit" ~smooth_attribute:"smooth" ~scale_attribute:"scale"
      ~seam_attribute:"seam" ~segment_seam_attribute:"segment_seam" ~v_attribute:"v" ~up_attribute:"up" ~uv_range_attribute:"ranges"
      ~caps:true override_source in
    same_cook "circular wire attribute overrides" ~typed ~factory
      ["group",Parameter.Text_value group;"divisions_attribute",Text_value "div";"segments",Int_value 2;"segments_attribute",Text_value "seg";
       "segment_scales_attribute",Text_value "scales";"prevent_joint_buckling",Bool_value true;"maximum_joint_scale_attribute",Text_value "limit";
       "smooth_attribute",Text_value "smooth";"scale_attribute",Text_value "scale";"seam_attribute",Text_value "seam";"segment_seam_attribute",Text_value "segment_seam";
       "v_attribute",Text_value "v";"up_attribute",Text_value "up";"uv_range_attribute",Text_value "ranges";"caps",Bool_value true] override_source;
    let primitives = if selected then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "first" override_geometry else None in
    let native = Rdk.Sweep_circle.run ~grain:97 ?primitives ~sides:8 ~radius:0.1 ~divisions_attribute:"div" ~segments:2
      ~segments_attribute:"seg" ~segment_scales_attribute:"scales" ~prevent_joint_buckling:true ~maximum_joint_scale_attribute:"limit"
      ~smooth_attribute:"smooth" ~scale_attribute:"scale" ~seam_attribute:"seam" ~segment_seam_attribute:"segment_seam" ~v_attribute:"v"
      ~up_attribute:"up" ~u_range:(0.,1.) ~v_range:(0.,1.) ~uv_range_attribute:"ranges" ~caps:true ~cap_group:"caps" override_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "circular wire attribute overrides match native"
  ) [false;true]) [false;true];
  let tri2_node = Sop.polyline ~closed:true [|0.,0.,0.;1.,0.,1.;1.,1.,3.;0.,1.,2.|]
    |> Sop.group ~name:"selected" Select.all_points
    |> Sop.group ~name:"constraints" (Select.primitive_indices [|0|])
    |> Sop.group_edges ~name:"edges" in
  let tri2_geometry = cook 1 tri2_node in
  let uv = Rdk.Packed.Float2.of_owned ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] |> Result.get_ok in
  let uv = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"uv" (Rdk.Attribute.Float2 uv) |> Result.get_ok in
  let tri2_geometry = Rdk.Geometry.with_attribute uv tri2_geometry |> Result.get_ok in
  let tri2_source = Sop.snapshot tri2_geometry in
  let tri2 = Sop.triangulate_2d tri2_source in
  same_cook "triangulate 2d defaults" ~typed:tri2 ~factory:Nodes.Triangulate_2d.factory [] tri2_source;
  cache_identity "triangulate 2d all fields" tri2;
  List.iter (fun (projection,choice,native_projection) -> List.iter (fun refine ->
    List.iter (fun use_maximum_area -> List.iter (fun use_target_edge_length ->
    List.iter (fun preserve_point_payload -> List.iter (fun restore_original_point_positions ->
      let plane_origin = Vec3.create 0.2 0.3 0.4 and plane_normal = Vec3.create 1. 1. 1. in
      let typed = Sop.triangulate_2d ~projection ~plane_origin ~plane_normal ~point_attribute:"uv" ~seed:17
        ~refine ~minimum_angle:0.1 ~use_maximum_area ~maximum_area:0.5 ~use_target_edge_length ~target_edge_length:1.
        ~minimum_edge_length:0.01 ~maximum_new_points:256 ~regularization_steps:1
        ~preserve_point_payload ~restore_original_point_positions ~split_point_group:"split" ~refinement_point_group:"refined"
        ~triangle_group:"triangles" ~constraint_group:"output_constraints" tri2_source in
      same_cook "triangulate 2d projection refinement controls" ~typed ~factory:Nodes.Triangulate_2d.factory
        ["projection",Parameter.Choice_value choice;"plane_origin_x",Float_value 0.2;"plane_origin_y",Float_value 0.3;"plane_origin_z",Float_value 0.4;
         "plane_normal_x",Float_value 1.;"plane_normal_y",Float_value 1.;"plane_normal_z",Float_value 1.;"point_attribute",Text_value "uv";"seed",Int_value 17;
         "refine",Bool_value refine;"minimum_angle",Float_value 0.1;"use_maximum_area",Bool_value use_maximum_area;"maximum_area",Float_value 0.5;
         "use_target_edge_length",Bool_value use_target_edge_length;"target_edge_length",Float_value 1.;"minimum_edge_length",Float_value 0.01;
         "maximum_new_points",Int_value 256;"regularization_steps",Int_value 1;"preserve_point_payload",Bool_value preserve_point_payload;
         "restore_original_point_positions",Bool_value restore_original_point_positions;"split_point_group",Text_value "split";
         "refinement_point_group",Text_value "refined";"triangle_group",Text_value "triangles";"constraint_group",Text_value "output_constraints"] tri2_source;
      let maximum_area = if use_maximum_area then Some 0.5 else None and target_edge_length = if use_target_edge_length then Some 1. else None in
      let native = Rdk.Triangulate2d.run ~grain:97 ~projection:native_projection ~seed:17L ~refine ~minimum_angle:0.1 ?maximum_area ?target_edge_length
        ~minimum_edge_length:0.01 ~maximum_new_points:256 ~regularization_steps:1 ~preserve_point_payload ~restore_original_point_positions
        ~split_point_group:"split" ~refinement_point_group:"refined" ~triangle_group:"triangles" ~constraint_group:"output_constraints"
        tri2_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "triangulate 2d flat projection and refinement match native"
    ) [false;true]) [false;true]) [false;true]) [false;true]) [false;true])
    [Sop.Triangulate_best_fit,"Best fit",Rdk.Triangulate2d.Best_fit;
     Sop.Triangulate_xy,"XY",Rdk.Triangulate2d.Plane_xy;Sop.Triangulate_yz,"YZ",Rdk.Triangulate2d.Plane_yz;Sop.Triangulate_zx,"ZX",Rdk.Triangulate2d.Plane_zx;
     Sop.Triangulate_plane,"Custom plane",Rdk.Triangulate2d.Plane {origin=Vec3.create 0.2 0.3 0.4;normal=Vec3.create 1. 1. 1.};
     Sop.Triangulate_attribute,"Point attribute",Rdk.Triangulate2d.Point_attribute "uv"];
  for flags = 0 to 255 do
    let flag bit = flags land (1 lsl bit) <> 0 in
    let split_crossing_constraints = flag 0 and flood_from_hull_boundary = flag 1 and remove_outside_constraint_polygons = flag 2
    and silhouette_constraints = flag 3 and remove_outside_silhouette = flag 4 and ignore_non_constraint_points = flag 5
    and remove_duplicate_points = flag 6 and keep_primitives = flag 7 in
    let typed = Sop.triangulate_2d ~point_group:"selected" ~constraint_edge_group:"edges" ~constraint_primitive_group:"constraints"
      ~projection:Sop.Triangulate_xy ~split_crossing_constraints ~flood_from_hull_boundary ~remove_outside_constraint_polygons
      ~silhouette_constraints ~remove_outside_silhouette ~ignore_non_constraint_points ~remove_duplicate_points ~keep_primitives
      ~remove_unused_points:true ~recompute_point_normals:true ~allow_constraint_splitting:false ~allow_movement_of_interior_input_points:true tri2_source in
    same_cook "triangulate 2d constraint cleanup controls" ~typed ~factory:Nodes.Triangulate_2d.factory
      ["point_group",Parameter.Text_value "selected";"constraint_edge_group",Text_value "edges";"constraint_primitive_group",Text_value "constraints";
       "projection",Choice_value "XY";"split_crossing_constraints",Bool_value split_crossing_constraints;"flood_from_hull_boundary",Bool_value flood_from_hull_boundary;
       "remove_outside_constraint_polygons",Bool_value remove_outside_constraint_polygons;"silhouette_constraints",Bool_value silhouette_constraints;
       "remove_outside_silhouette",Bool_value remove_outside_silhouette;"ignore_non_constraint_points",Bool_value ignore_non_constraint_points;
       "remove_duplicate_points",Bool_value remove_duplicate_points;"keep_primitives",Bool_value keep_primitives;"remove_unused_points",Bool_value true;
       "recompute_point_normals",Bool_value true;"allow_constraint_splitting",Bool_value false;"allow_movement_of_interior_input_points",Bool_value true] tri2_source;
    let selection = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" tri2_geometry |> Option.get |> fun g -> Rdk.Transform_ops.Selected_points g in
    let constraint_edges = Rdk.Geometry.find_edge_group "edges" tri2_geometry |> Option.get
    and constraint_primitives = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "constraints" tri2_geometry |> Option.get in
    let native = Rdk.Triangulate2d.run ~grain:97 ~selection ~constraint_edges ~constraint_primitives ~projection:Rdk.Triangulate2d.Plane_xy
      ~split_crossing_constraints ~flood_from_hull_boundary ~remove_outside_constraint_polygons ~silhouette_constraints ~remove_outside_silhouette
      ~ignore_non_constraint_points ~remove_duplicate_points ~keep_primitives ~remove_unused_points:true ~recompute_point_normals:true
      ~allow_constraint_splitting:false ~allow_movement_of_interior_input_points:true tri2_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "triangulate 2d constraint controls match native"
  done;
  same_cook "triangulate 2d blank names" ~typed:(Sop.triangulate_2d ~point_group:" " ~constraint_edge_group:" " ~constraint_primitive_group:" "
    ~split_point_group:" " ~refinement_point_group:" " ~triangle_group:" " ~constraint_group:" " tri2_source)
    ~factory:Nodes.Triangulate_2d.factory ["point_group",Parameter.Text_value " ";"constraint_edge_group",Text_value " ";"constraint_primitive_group",Text_value " ";
      "split_point_group",Text_value " ";"refinement_point_group",Text_value " ";"triangle_group",Text_value " ";"constraint_group",Text_value " "] tri2_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true) "triangulate 2d refuses invalid construction")
    [(fun () -> Sop.triangulate_2d ~plane_origin:(Vec3.create Float.nan 0. 0.) tri2_source);
     (fun () -> Sop.triangulate_2d ~projection:Sop.Triangulate_plane ~plane_normal:Vec3.zero tri2_source);
     (fun () -> Sop.triangulate_2d ~projection:Sop.Triangulate_attribute ~point_attribute:" " tri2_source);
     (fun () -> Sop.triangulate_2d ~refine:true ~minimum_angle:0. tri2_source);
     (fun () -> Sop.triangulate_2d ~refine:true ~minimum_angle:(Float.pi /. 3.) tri2_source);
     (fun () -> Sop.triangulate_2d ~use_maximum_area:true ~maximum_area:0. tri2_source);
     (fun () -> Sop.triangulate_2d ~use_target_edge_length:true ~target_edge_length:0. tri2_source);
     (fun () -> Sop.triangulate_2d ~maximum_new_points:(-1) tri2_source);
     (fun () -> Sop.triangulate_2d ~regularization_steps:(-1) tri2_source)];
  check (Result.is_error (Node.apply_parameters tri2 ["minimum_angle",Parameter.Float_value Float.nan])) "triangulate 2d inspector refuses nonfinite angles";
  let duplicate_geometry = Test_duplicate_sop.source () in
  let duplicate_source = Sop.snapshot duplicate_geometry in
  let duplicate = Sop.duplicate duplicate_source in
  same_cook "duplicate defaults" ~typed:duplicate ~factory:Nodes.Duplicate.factory [] duplicate_source;
  cache_identity "duplicate all fields" duplicate;
  let matrices = [Mat4.identity;Mat4.translation (Vec3.create 2. 3. 4.);Mat4.rotation_z 0.7;
    Mat4.of_rows (2.,0.3,0.,1.) (0.,0.5,0.2,2.) (0.1,0.,1.5,3.) (0.01,0.02,0.03,1.);
    Mat4.of_rows (-1.,0.,0.,0.) (0.,1.,0.,0.) (0.,0.,1.,0.) (0.,0.,0.,2.)] in
  List.iter (fun matrix -> List.iter (fun copies -> List.iter (fun cumulative ->
    List.iter (fun selected -> List.iter (fun preserve_groups -> List.iter (fun named ->
      let m row column = Mat4.get matrix ~row ~column in
      let group = if selected then "right" else "" and copy_group_prefix = if named then "copy_" else "" in
      let typed = Sop.duplicate ~copies ~cumulative ~group ~copy_group_prefix ~preserve_groups
        ~m00:(m 0 0) ~m01:(m 0 1) ~m02:(m 0 2) ~m03:(m 0 3)
        ~m10:(m 1 0) ~m11:(m 1 1) ~m12:(m 1 2) ~m13:(m 1 3)
        ~m20:(m 2 0) ~m21:(m 2 1) ~m22:(m 2 2) ~m23:(m 2 3)
        ~m30:(m 3 0) ~m31:(m 3 1) ~m32:(m 3 2) ~m33:(m 3 3) duplicate_source in
      let values = List.init 16 (fun i -> Printf.sprintf "m%d%d" (i/4) (i mod 4),Parameter.Float_value (m (i/4) (i mod 4))) in
      same_cook "duplicate controls" ~typed ~factory:Nodes.Duplicate.factory
        (["copies",Parameter.Int_value copies;"cumulative",Bool_value cumulative;"group",Text_value group;
          "copy_group_prefix",Text_value copy_group_prefix;"preserve_groups",Bool_value preserve_groups] @ values) duplicate_source;
      let primitives = if selected then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "right" duplicate_geometry else None in
      let copy_group_prefix = if named then Some copy_group_prefix else None in
      let native = Rdk.Instance_copy.duplicate ~grain:97 ~copies ~cumulative ~transform:matrix
        ?primitives ?copy_group_prefix ~preserve_groups duplicate_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "duplicate flat matrix controls match native"
    ) [false;true]) [false;true]) [false;true]) [false;true]) [0;1;3]) matrices;
  same_cook "duplicate blank names" ~typed:(Sop.duplicate ~group:" " ~copy_group_prefix:" " duplicate_source)
    ~factory:Nodes.Duplicate.factory ["group",Parameter.Text_value " ";"copy_group_prefix",Text_value " "] duplicate_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "duplicate refuses invalid construction")
    [(fun () -> Sop.duplicate ~copies:(-1) duplicate_source);
     (fun () -> Sop.duplicate ~copies:Sys.max_array_length duplicate_source);
     (fun () -> Sop.duplicate ~m00:Float.nan duplicate_source);
     (fun () -> Sop.duplicate ~m33:Float.infinity duplicate_source)];
  for index = 0 to 15 do
    check (Result.is_error (Node.apply_parameters duplicate
      [Printf.sprintf "m%d%d" (index/4) (index mod 4),Parameter.Float_value Float.nan]))
      "duplicate inspector refuses nonfinite matrix entries"
  done;
  let detect_source_node = Sop.grid ~columns:3 ~rows:3 ()
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0;1|]) in
  let detect_collision_node = (let migration_matrix = Mat4.rotation_x (Float.pi /. 2.) in
Sop.transform ~mode:Sop.Transform_matrix
  ~m11:(Mat4.get migration_matrix ~row:1 ~column:1)
  ~m12:(Mat4.get migration_matrix ~row:1 ~column:2)
  ~m21:(Mat4.get migration_matrix ~row:2 ~column:1)
  ~m22:(Mat4.get migration_matrix ~row:2 ~column:2) detect_source_node) in
  let detect_source_geometry = cook 1 detect_source_node and detect_collision_geometry = cook 1 detect_collision_node in
  let detect_source = Sop.snapshot detect_source_geometry and detect_collision = Sop.snapshot detect_collision_geometry in
  let detect = Sop.boolean_detect detect_source (Some detect_collision) in
  same_cook "boolean detect defaults" ~optional_inputs:[Some detect_source;Some detect_collision]
    ~typed:detect ~factory:Nodes.Boolean_detect.factory [] detect_source;
  same_cook "boolean detect disconnected defaults" ~optional_inputs:[Some detect_source;None]
    ~typed:(Sop.boolean_detect detect_source None) ~factory:Nodes.Boolean_detect.factory [] detect_source;
  cache_identity "boolean detect all fields" detect;
  cache_identity "boolean detect inactive collision fields" (Sop.boolean_detect detect_source None);
  List.iter (fun use_collision -> List.iter (fun include_coplanar -> List.iter (fun use_groups ->
    for outputs = 1 to 63 do
      if use_collision || outputs land 56 <> 0 then (
        let name bit value = if outputs land (1 lsl bit) <> 0 then value else "" in
        let intersecting_group = name 0 "cross" and intersections_attribute = name 1 "cross_rows"
        and count_attribute = name 2 "cross_count" and self_intersecting_group = name 3 "self"
        and self_intersections_attribute = name 4 "self_rows" and self_count_attribute = name 5 "self_count" in
        let source_group = if use_groups then "selected" else ""
        and collision_group = if use_groups then "selected" else "" in
        let collision = if use_collision then Some detect_collision else None in
        let typed = Sop.boolean_detect ~source_group ~collision_group ~tolerance:1e-9 ~include_coplanar
          ~intersecting_group ~intersections_attribute ~count_attribute ~self_intersecting_group
          ~self_intersections_attribute ~self_count_attribute detect_source collision in
        same_cook "boolean detect controls" ~optional_inputs:[Some detect_source;collision] ~typed
          ~factory:Nodes.Boolean_detect.factory
          ["source_group",Parameter.Text_value source_group;"collision_group",Text_value collision_group;
           "tolerance",Float_value 1e-9;"include_coplanar",Bool_value include_coplanar;
           "intersecting_group",Text_value intersecting_group;"intersections_attribute",Text_value intersections_attribute;
           "count_attribute",Text_value count_attribute;"self_intersecting_group",Text_value self_intersecting_group;
           "self_intersections_attribute",Text_value self_intersections_attribute;"self_count_attribute",Text_value self_count_attribute] detect_source;
        let optional name = if name = "" then None else Some name in
        let cross name = if use_collision then optional name else None in
        let source_primitives = if use_groups then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" detect_source_geometry else None
        and collision_primitives = if use_groups && use_collision then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" detect_collision_geometry else None in
        let collision_geometry = if use_collision then detect_collision_geometry else detect_source_geometry in
        let native = Rdk.Boolean_detect.run_checked ~grain:97 ?source_primitives ?collision_primitives
          ~tolerance:1e-9 ~include_coplanar ~intersecting_group:(cross intersecting_group)
          ?intersections_attribute:(cross intersections_attribute) ?count_attribute:(cross count_attribute)
          ?self_intersecting_group:(optional self_intersecting_group)
          ?self_intersections_attribute:(optional self_intersections_attribute) ?self_count_attribute:(optional self_count_attribute)
          ~collision:collision_geometry detect_source_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "boolean detect flat controls match native")
    done) [false;true]) [false;true]) [false;true];
  let inactive = Sop.boolean_detect ~collision_group:"missing" ~intersecting_group:"same"
      ~intersections_attribute:"duplicate" ~count_attribute:"duplicate" ~self_intersecting_group:"same" detect_source None in
  check (equal_geometry (cook 1 inactive) (cook 1 (Sop.boolean_detect ~self_intersecting_group:"same" detect_source None)))
    "boolean detect ignores disconnected collision fields";
  same_cook "boolean detect unset names" ~optional_inputs:[Some detect_source;Some detect_collision]
    ~typed:(Sop.boolean_detect ~source_group:" " ~collision_group:" " ~intersecting_group:" "
      ~intersections_attribute:" " ~count_attribute:" " ~self_intersections_attribute:" " ~self_count_attribute:" " detect_source (Some detect_collision))
    ~factory:Nodes.Boolean_detect.factory ["source_group",Parameter.Text_value " ";"collision_group",Text_value " ";
      "intersecting_group",Text_value " ";"intersections_attribute",Text_value " ";"count_attribute",Text_value " ";
      "self_intersections_attribute",Text_value " ";"self_count_attribute",Text_value " "] detect_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "boolean detect refuses invalid construction")
    [ (fun () -> Sop.boolean_detect ~tolerance:Float.nan detect_source None);
      (fun () -> Sop.boolean_detect ~tolerance:(-0.1) detect_source None);
      (fun () -> Sop.boolean_detect ~self_intersecting_group:"" detect_source None);
      (fun () -> Sop.boolean_detect ~intersecting_group:"same" ~self_intersecting_group:"same" detect_source (Some detect_collision));
      (fun () -> Sop.boolean_detect ~intersections_attribute:"same" ~self_count_attribute:"same" detect_source (Some detect_collision)) ];
  check (Result.is_error (Node.apply_parameters detect ["tolerance",Parameter.Float_value Float.nan]))
    "boolean detect inspector refuses invalid tolerance";
  let boolean_left_geometry = cook 1 (Sop.box ~normals:None ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Rdk.Box_generator.Box_triangles ~consolidate_points:true ())
      |> Rdk.Geometry.without_attribute ~owner:Rdk.Attribute.Point "N"
  and boolean_right_geometry = cook 1 (Sop.box ~normals:None ~size:(Vec3.create 2. 2. 2.) ~center:(Vec3.create 0.5 0.5 0.5)
      ~connectivity:Rdk.Box_generator.Box_triangles ~consolidate_points:true ())
      |> Rdk.Geometry.without_attribute ~owner:Rdk.Attribute.Point "N" in
  let boolean_left = Sop.snapshot boolean_left_geometry and boolean_right = Sop.snapshot boolean_right_geometry in
  let boolean = Sop.boolean boolean_left boolean_right in
  same_cook "boolean defaults" ~inputs:[boolean_right] ~typed:boolean ~factory:Nodes.Boolean.factory [] boolean_left;
  cache_identity "boolean all fields" boolean;
  List.iter (fun (operation,operation_choice) -> List.iter (fun (left_treatment,left_choice) ->
    List.iter (fun (right_treatment,right_choice) -> List.iter (fun (seam_points,seam_choice) ->
      List.iter (fun (detriangulation,polygon_choice) -> List.iter (fun (point_conflict,conflict_choice) ->
        if operation <> Rdk.Boolean.Shatter || left_treatment = Rdk.Boolean.Solid && right_treatment = Rdk.Boolean.Solid then (
        let typed = Sop.boolean ~operation ~left_treatment ~right_treatment ~seam_points ~detriangulation ~point_conflict
            ~require_closed:Sop.Closed_not_required ~piece_attribute:"cell" ~left_piece_group:"a" ~overlap_piece_group:"overlap"
            ~right_piece_group:"b" ~point_tolerance:1e-9 ~tiny_seam_threshold:1e-12 boolean_left boolean_right in
        same_cook "boolean operation and products" ~inputs:[boolean_right] ~typed ~factory:Nodes.Boolean.factory
          ["operation",Parameter.Choice_value operation_choice;"left_treatment",Choice_value left_choice;"right_treatment",Choice_value right_choice;
           "seam_points",Choice_value seam_choice;"detriangulation",Choice_value polygon_choice;"point_conflict",Choice_value conflict_choice;
           "require_closed",Choice_value "Allow open";"piece_attribute",Text_value "cell";"left_piece_group",Text_value "a";
           "overlap_piece_group",Text_value "overlap";"right_piece_group",Text_value "b";
           "point_tolerance",Float_value 1e-9;"tiny_seam_threshold",Float_value 1e-12] boolean_left;
        let native = Rdk.Boolean.run ~operation ~left_treatment ~right_treatment ~seam_points ~detriangulation ~point_conflict
            ~require_closed:false ~piece_attribute:"cell" ~left_piece_group:(Some "a") ~overlap_piece_group:(Some "overlap")
            ~right_piece_group:(Some "b") ~point_tolerance:1e-9 ~tiny_seam_threshold:1e-12 ~right:boolean_right_geometry
            boolean_left_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "boolean flat operation and product controls match native"))
      [Rdk.Boolean.Reject,"Reject conflict";Promote_to_vertex,"Promote to vertex"])
      [Rdk.Boolean.Triangles,"Triangles";Unchanged_polygons,"Unchanged polygons";All_polygons,"All polygons"])
      [Rdk.Boolean.Shared_seam_points,"Shared";Split_seam_points,"Split"])
      [Rdk.Boolean.Solid,"Solid";Surface,"Surface"])
      [Rdk.Boolean.Solid,"Solid";Surface,"Surface"])
      [Rdk.Boolean.Union,"Union";Intersection,"Intersection";Difference,"Subtract B from A";Reverse_difference,"Subtract A from B";
       Xor,"Exclusive or";Shatter,"Shatter"];
  List.iter (fun (require_closed,closed_choice,native_closed) -> List.iter (fun resolve_left_self_intersections ->
    List.iter (fun resolve_right_self_intersections -> List.iter (fun strict_cleanup -> List.iter (fun assume_flat ->
      List.iter (fun cleanup_max_batches ->
        let typed = Sop.boolean ~require_closed ~resolve_left_self_intersections ~resolve_right_self_intersections ~strict_cleanup
            ~assume_flat ~cleanup_max_batches boolean_left boolean_right in
        same_cook "boolean closed and cleanup" ~inputs:[boolean_right] ~typed ~factory:Nodes.Boolean.factory
          ["require_closed",Parameter.Choice_value closed_choice;"resolve_left_self_intersections",Bool_value resolve_left_self_intersections;
           "resolve_right_self_intersections",Bool_value resolve_right_self_intersections;"strict_cleanup",Bool_value strict_cleanup;
           "assume_flat",Bool_value assume_flat;"cleanup_max_batches",Int_value cleanup_max_batches] boolean_left;
        let native = Rdk.Boolean.run ?require_closed:native_closed ~resolve_left_self_intersections ~resolve_right_self_intersections
            ~strict_cleanup ~assume_flat ~cleanup_max_batches ~right:boolean_right_geometry boolean_left_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "boolean flat closed and cleanup controls match native") [4;8])
      [false;true]) [false;true]) [false;true]) [false;true])
      [Sop.Closed_default,"Operation default",None;Closed_required,"Require closed",Some true;Closed_not_required,"Allow open",Some false];
  same_cook "boolean unset shatter groups" ~inputs:[boolean_right]
    ~typed:(Sop.boolean ~operation:Rdk.Boolean.Shatter ~piece_attribute:" " ~left_piece_group:" " ~overlap_piece_group:" "
      ~right_piece_group:" " boolean_left boolean_right) ~factory:Nodes.Boolean.factory
    ["operation",Parameter.Choice_value "Shatter";"piece_attribute",Text_value " ";"left_piece_group",Text_value " ";
      "overlap_piece_group",Text_value " ";"right_piece_group",Text_value " "] boolean_left;
  same_cook "boolean inactive duplicate groups" ~inputs:[boolean_right]
    ~typed:(Sop.boolean ~left_piece_group:"same" ~overlap_piece_group:"same" ~right_piece_group:"same" boolean_left boolean_right)
    ~factory:Nodes.Boolean.factory ["left_piece_group",Parameter.Text_value "same";"overlap_piece_group",Text_value "same";
      "right_piece_group",Text_value "same"] boolean_left;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "boolean refuses invalid construction")
    [ (fun () -> Sop.boolean ~point_tolerance:Float.nan boolean_left boolean_right);
      (fun () -> Sop.boolean ~point_tolerance:(-0.1) boolean_left boolean_right);
      (fun () -> Sop.boolean ~tiny_seam_threshold:Float.infinity boolean_left boolean_right);
      (fun () -> Sop.boolean ~tiny_seam_threshold:(-0.1) boolean_left boolean_right);
      (fun () -> Sop.boolean ~cleanup_max_batches:0 boolean_left boolean_right);
      (fun () -> Sop.boolean ~operation:Rdk.Boolean.Shatter ~left_treatment:Rdk.Boolean.Surface boolean_left boolean_right);
      (fun () -> Sop.boolean ~operation:Rdk.Boolean.Shatter ~left_piece_group:"same" ~right_piece_group:"same" boolean_left boolean_right) ];
  check (Result.is_error (Node.apply_parameters boolean ["point_tolerance",Parameter.Float_value Float.nan]))
    "boolean inspector refuses invalid tolerance";
  let subdivision_source_node = Sop.grid ~counts:Rdk.Plane_generators.Grid_divisions ~columns:2 ~rows:2
      ~connectivity:Rdk.Plane_generators.Grid_triangles ~size:2. ()
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0;1;2;3|])
      |> Sop.group ~name:"subdivision_hole" (Select.primitive_indices [||])
      |> Sop.group ~name:"holes" (Select.primitive_indices [|7|]) in
  let subdivision_geometry = cook 1 subdivision_source_node in
  let uv = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Vertex ~name:"uv"
      (Rdk.Attribute.Float2 (Rdk.Packed.Float2.of_owned
        ~x:(Array.init (Rdk.Geometry.vertex_count subdivision_geometry) (fun vertex -> float_of_int vertex /. 10.))
        ~y:(Array.init (Rdk.Geometry.vertex_count subdivision_geometry) (fun vertex -> float_of_int (vertex mod 3))) |> Result.get_ok)) |> Result.get_ok in
  let subdivision_geometry = Rdk.Geometry.with_attribute uv subdivision_geometry |> Result.get_ok in
  let subdivision_source = Sop.snapshot subdivision_geometry in
  let subdivision_crease_node = Sop.snapshot subdivision_geometry
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"creaseweight" ~value:2.
      |> Sop.group ~name:"creases" Select.all_primitives in
  let subdivision_crease_geometry = cook 1 subdivision_crease_node in
  let subdivision_crease = Sop.snapshot subdivision_crease_geometry in
  same_cook "subdivide defaults" ~optional_inputs:[Some subdivision_source;None]
    ~typed:(Sop.subdivide subdivision_source None) ~factory:Nodes.Subdivide.factory [] subdivision_source;
  cache_identity ~companions:["resulting_crease_group",["generate_resulting_creases",Parameter.Bool_value true]]
    "subdivide all fields" (Sop.subdivide subdivision_source (Some subdivision_crease));
  let subdivision_selection = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" subdivision_geometry |> Option.get
  and subdivision_holes = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "subdivision_hole" subdivision_geometry |> Option.get
  and subdivision_crease_selection = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "creases" subdivision_crease_geometry |> Option.get in
  let subdivision_cracks = [Sop.Cracks_do_not_close,"Do not close",Rdk.Subdivide.Subdivide_do_not_close;
    Cracks_pull_no_division,"Pull, no edge division",Subdivide_pull_no_edge_division;
    Cracks_pull_divide,"Pull, divide edges",Subdivide_pull_divide_edges 0.75;
    Cracks_pull_triangulate,"Pull, triangulate",Subdivide_pull_triangulate 0.75;
    Cracks_stitch_no_division,"Stitch, no edge division",Subdivide_stitch_no_edge_division;
    Cracks_stitch_divide,"Stitch, divide edges",Subdivide_stitch_divide_edges;
    Cracks_stitch_triangulate,"Stitch, triangulate",Subdivide_stitch_triangulate] in
  List.iter (fun (scheme,scheme_choice) -> List.iter (fun (cracks,cracks_choice,native_cracks) ->
    List.iter (fun (crease_weight_mode,weight_choice) -> List.iter (fun use_creases ->
      List.iter (fun generate_resulting_creases -> List.iter (fun consistent_topology ->
        let creases = if use_creases then Some subdivision_crease else None in
        let crease_group = if use_creases then "creases" else "" in
        let resulting_crease_group = if generate_resulting_creases then "resulting" else "" in
        let typed = Sop.subdivide ~group:"selected" ~scheme ~cracks ~crack_bias:0.75 ~crease_weight_mode ~crease_weight:2.5
            ~crease_group ~generate_resulting_creases ~resulting_crease_group ~consistent_topology subdivision_source creases in
        same_cook "subdivide cracks and creases" ~optional_inputs:[Some subdivision_source;creases] ~typed ~factory:Nodes.Subdivide.factory
          ["group",Parameter.Text_value "selected";"scheme",Choice_value scheme_choice;"cracks",Choice_value cracks_choice;
           "crack_bias",Float_value 0.75;"crease_weight_mode",Choice_value weight_choice;"crease_weight",Float_value 2.5;
           "crease_group",Text_value crease_group;"generate_resulting_creases",Bool_value generate_resulting_creases;
           "resulting_crease_group",Text_value resulting_crease_group;"consistent_topology",Bool_value consistent_topology] subdivision_source;
        let creases = Option.map (fun _ -> subdivision_crease_geometry) creases in
        let crease_primitives = if use_creases then Some subdivision_crease_selection else None
        and crease_weight = if crease_weight_mode = Sop.Kernel_explicit then Some 2.5 else None
        and resulting_crease_group = if generate_resulting_creases then Some "resulting" else None in
        let native = Rdk.Subdivide.subdivide ~scheme ~primitives:subdivision_selection ~cracks:native_cracks
            ~consistent_topology ?creases ?crease_primitives ?crease_weight ~generate_resulting_creases ?resulting_crease_group
            ~hole_primitives:subdivision_holes ~remove_holes:false ~boundary_interpolation:Rdk.Subdivide.Subdivide_boundary_edge_and_corner
            ~face_varying_interpolation:Rdk.Subdivide.Subdivide_fvar_boundaries subdivision_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "subdivide flat crack and crease controls match native") [false;true]) [false;true])
      [false;true]) [Sop.Kernel_explicit,"Explicit";Kernel_auto,"Auto"]) subdivision_cracks)
      [Rdk.Subdivide.Catmull_clark,"Catmull-Clark";Loop,"Loop";Bilinear,"Bilinear"];
  let holes = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "holes" subdivision_geometry |> Option.get in
  List.iter (fun (boundary_interpolation,boundary_choice) -> List.iter (fun (face_varying_interpolation,fvar_choice) ->
    List.iter (fun (triangle_policy,triangle_choice) -> List.iter (fun (creasing_method,creasing_choice) ->
      List.iter (fun remove_holes -> List.iter (fun treat_curves_as_independent -> List.iter (fun recompute_point_normals ->
        let typed = Sop.subdivide ~boundary_interpolation ~face_varying_interpolation ~triangle_policy ~creasing_method
            ~hole_group:"holes" ~remove_holes ~treat_curves_as_independent ~recompute_point_normals subdivision_source None in
        same_cook "subdivide interpolation" ~optional_inputs:[Some subdivision_source;None] ~typed ~factory:Nodes.Subdivide.factory
          ["boundary_interpolation",Parameter.Choice_value boundary_choice;"face_varying_interpolation",Choice_value fvar_choice;
           "triangle_policy",Choice_value triangle_choice;"creasing_method",Choice_value creasing_choice;
           "hole_group",Text_value "holes";"remove_holes",Bool_value remove_holes;
           "treat_curves_as_independent",Bool_value treat_curves_as_independent;"recompute_point_normals",Bool_value recompute_point_normals] subdivision_source;
        let native = Rdk.Subdivide.subdivide ~boundary_interpolation ~face_varying_interpolation ~triangle_policy ~creasing_method
            ~hole_primitives:holes ~remove_holes ~treat_curves_as_independent ~recompute_point_normals
            ~crease_weight:1. ~generate_resulting_creases:false subdivision_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "subdivide interpolation controls match native") [false;true]) [false;true])
        [false;true]) [Rdk.Subdivide.Subdivide_creasing_uniform,"Uniform";Subdivide_creasing_chaikin,"Chaikin"])
        [Rdk.Subdivide.Subdivide_triangles_catmull_clark,"Catmull-Clark";Subdivide_triangles_smooth,"Smooth"])
        [Rdk.Subdivide.Subdivide_fvar_none,"None";Subdivide_fvar_corners_only,"Corners only";Subdivide_fvar_corners_plus1,"Corners plus 1";
         Subdivide_fvar_corners_plus2,"Corners plus 2";Subdivide_fvar_boundaries,"Boundaries";Subdivide_fvar_all,"All"])
        [Rdk.Subdivide.Subdivide_boundary_none,"None";Subdivide_boundary_edge_only,"Edge only";Subdivide_boundary_edge_and_corner,"Edge and corner"];
  same_cook "subdivide unset names" ~optional_inputs:[Some subdivision_source;None]
    ~typed:(Sop.subdivide ~group:" " ~crease_group:" " ~resulting_crease_group:" " ~hole_group:" " subdivision_source None)
    ~factory:Nodes.Subdivide.factory ["group",Parameter.Text_value " ";"crease_group",Text_value " ";
      "resulting_crease_group",Text_value " ";"hole_group",Text_value " "] subdivision_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "subdivide refuses invalid construction")
    [ (fun () -> Sop.subdivide ~iterations:0 subdivision_source None);
      (fun () -> Sop.subdivide ~crack_bias:Float.nan subdivision_source None);
      (fun () -> Sop.subdivide ~crack_bias:1.1 subdivision_source None);
      (fun () -> Sop.subdivide ~crease_weight:Float.nan subdivision_source None);
      (fun () -> Sop.subdivide ~crease_weight:(-1.) subdivision_source None);
      (fun () -> Sop.subdivide ~resulting_crease_group:"creases" subdivision_source None);
      (fun () -> Sop.subdivide ~crease_group:"creases" subdivision_source None) ];
  check (Result.is_error (Node.apply_parameters (Sop.subdivide subdivision_source None)
      ["crease_weight",Parameter.Float_value Float.nan])) "subdivide inspector refuses invalid crease weight";
  let fuse_source_node = Sop.points [|(0.,0.,0.);(0.1,0.,0.);(1.,0.,0.);(1.1,0.,0.)|]
      |> Sop.set_vector ~name:"Cd" ~value:Vec3.unit_x |> Sop.set_float ~name:"weight" ~value:2.
      |> Sop.set_float ~name:"radius" ~value:1. |> Sop.set_float ~name:"match" ~value:1.
      |> Sop.set_int ~name:"targetpoint" ~value:0
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1;2;3|]) in
  let fuse_target_node = Sop.points [|(0.,0.,0.);(1.,0.,0.)|]
      |> Sop.set_vector ~name:"Cd" ~value:Vec3.unit_x |> Sop.set_float ~name:"weight" ~value:2.
      |> Sop.set_float ~name:"radius" ~value:1. |> Sop.set_float ~name:"match" ~value:1.
      |> Sop.set_int ~name:"targetpoint" ~value:0
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1|]) in
  let fuse_source_geometry = cook 1 fuse_source_node and fuse_target_geometry = cook 1 fuse_target_node in
  let fuse_source = Sop.snapshot fuse_source_geometry and fuse_target = Sop.snapshot fuse_target_geometry in
  let fuse = Sop.fuse fuse_source None in
  same_cook "fuse defaults" ~optional_inputs:[Some fuse_source;None] ~typed:fuse ~factory:Nodes.Fuse.factory [] fuse_source;
  cache_identity ~changes:["attribute_rules",Parameter.Text_value "Cd\taverage\t";"group_rules",Text_value "selected*\tunion"]
    ~companions:["match_condition",["match_attribute",Parameter.Text_value "match"];
      "match_tolerance",["match_attribute",Parameter.Text_value "match"]]
    "fuse all fields" fuse;
  let fuse_rule_source = Sop.points [|(0.,0.,0.);(0.,0.,0.)|]
      |> Sop.set_float ~name:"value" ~value:2.
      |> Sop.group ~name:"selected_subset" (Select.point_indices [|0|]) in
  let fuse_rule_geometry = cook 1 fuse_rule_source in
  let fuse_rule_source = Sop.snapshot fuse_rule_geometry in
  let fuse_rule_node = Sop.fuse ~attribute_rules:"value\tsum\t" ~group_rules:"selected*\tintersection" fuse_rule_source None in
  same_cook "fuse rule table payload" ~optional_inputs:[Some fuse_rule_source;None] ~typed:fuse_rule_node ~factory:Nodes.Fuse.factory
    ["attribute_rules",Parameter.Text_value "value\tsum\t";"group_rules",Text_value "selected*\tintersection"] fuse_rule_source;
  let fuse_rule_result = cook 1 fuse_rule_node in
  check (match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "value" fuse_rule_result with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with Rdk.Attribute.Float values -> values = [|4.|] | _ -> false)
    | None -> false) "fuse attribute table changes reduced payload";
  check (match Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected_subset" fuse_rule_result with
    | Some group -> Rdk.Group.cardinality group = 0 | None -> false) "fuse group table changes reduced membership";
  let cleanup_geometry = cook 1 (Sop.polyline [|(0.,0.,0.);(0.,0.,0.)|]) in
  let cleanup_source = Sop.snapshot cleanup_geometry in
  List.iter (fun remove_degenerate_primitives -> List.iter (fun remove_unused_points_from_degenerate_primitives ->
    let typed = Sop.fuse ~remove_degenerate_primitives ~remove_unused_points_from_degenerate_primitives cleanup_source None in
    same_cook "fuse degenerate cleanup" ~optional_inputs:[Some cleanup_source;None] ~typed ~factory:Nodes.Fuse.factory
      ["remove_degenerate_primitives",Parameter.Bool_value remove_degenerate_primitives;
       "remove_unused_points_from_degenerate_primitives",Bool_value remove_unused_points_from_degenerate_primitives] cleanup_source;
    let native = Rdk.Fuse_grid.fuse ~tolerance:0.001 ~remove_degenerate_primitives
        ~remove_unused_points_from_degenerate_primitives cleanup_geometry |> Result.get_ok in
    let result = cook 1 typed in
    check (equal_geometry native result) "fuse cleanup preserves native geometry";
    check (Rdk.Geometry.primitive_count result = (if remove_degenerate_primitives then 0 else 1)
      && Rdk.Geometry.point_count result = (if remove_degenerate_primitives && remove_unused_points_from_degenerate_primitives then 0 else 1))
      "fuse cleanup changes degenerate cardinality") [false;true]) [false;true];
  let attribute_rules = "Cd\taverage\t" and group_rules = "selected*\tunion" in
  let native_attribute_rules = [Rdk.Fuse_grid.fuse_attribute_rule ~pattern:"Cd" Rdk.Fuse_reduce.Attribute_average]
  and native_group_rules = [Rdk.Fuse_grid.fuse_group_rule ~pattern:"selected*" Rdk.Fuse_reduce.Group_union] in
  let source_selection = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" fuse_source_geometry |> Option.get in
  let positions = [Rdk.Fuse_reduce.First_position,"First";Least_point_position,"Least point";Greatest_point_position,"Greatest point";
    Average_position,"Average";Minimum_position,"Minimum";Maximum_position,"Maximum";Mode_position,"Mode";Median_position,"Median";
    Sum_position,"Sum";Sum_squares_position,"Sum squares";Root_mean_square_position,"Root mean square";
    Weighted_average_position,"Weighted average";Weighted_sum_position,"Weighted sum";Minimum_weight_position,"Minimum weight";
    Maximum_weight_position,"Maximum weight"] in
  List.iter (fun use_target -> List.iter (fun (targeting,targeting_choice) -> List.iter (fun (using,using_choice) ->
    List.iter (fun (metric,metric_choice) -> List.iter (fun (position,position_choice) ->
      let target = if use_target then Some fuse_target else None in
      let radius_attribute,match_attribute,match_tolerance = if targeting = Sop.Fuse_near_points
        then "radius","match",0.1 else "","",0. in
      let typed = Sop.fuse ~group:"selected" ~target_group:"selected" ~targeting ~target_attribute:"targetpoint" ~using
          ~metric ~tolerance:0.3 ~position ~weight_attribute:"weight" ~attributes:Rdk.Fuse_reduce.Average_numeric
          ~attribute_rules ~group_rules ~radius_attribute ~match_attribute ~match_tolerance
          ~snapped_group:"snapped" ~snapped_destination_attribute:"destination" fuse_source target in
      same_cook "fuse targeting and reducers" ~optional_inputs:[Some fuse_source;target] ~typed ~factory:Nodes.Fuse.factory
        ["group",Parameter.Text_value "selected";"target_group",Text_value "selected";"targeting",Choice_value targeting_choice;
         "target_attribute",Text_value "targetpoint";"using",Choice_value using_choice;"metric",Choice_value metric_choice;
         "tolerance",Float_value 0.3;"position",Choice_value position_choice;"weight_attribute",Text_value "weight";
         "attributes",Choice_value "Average numeric";"attribute_rules",Text_value attribute_rules;"group_rules",Text_value group_rules;
         "radius_attribute",Text_value radius_attribute;"match_attribute",Text_value match_attribute;"match_tolerance",Float_value match_tolerance;
         "snapped_group",Text_value "snapped";"snapped_destination_attribute",Text_value "destination"] fuse_source;
      let targeting = match targeting with Sop.Fuse_near_points -> Rdk.Fuse_grid.Near_points
        | Fuse_specified_points -> Rdk.Fuse_grid.Specified_points "targetpoint" in
      let target_geometry = if use_target then fuse_target_geometry else fuse_source_geometry in
      let target_selection = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" target_geometry |> Option.get in
      let target = Option.map (fun _ -> target_geometry) target in
      let optional name = if name = "" then None else Some name in
      let radius_attribute = optional radius_attribute and match_attribute = optional match_attribute in
      let native = Rdk.Fuse_grid.fuse ~selection:source_selection ~target_selection ~targeting ~using ~metric ~tolerance:0.3
          ~position ~weight_attribute:"weight" ~attributes:Rdk.Fuse_reduce.Average_numeric ~attribute_rules:native_attribute_rules
          ~group_rules:native_group_rules ?radius_attribute ?match_attribute ~match_tolerance
          ~snapped_group:"snapped" ~snapped_destination_attribute:"destination" ~remove_degenerate_primitives:true
          ~remove_unused_points_from_degenerate_primitives:true ?target fuse_source_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "fuse flat controls match native") positions)
      [Rdk.Fuse_grid.Euclidean,"Euclidean";Componentwise,"Componentwise"])
      [Rdk.Fuse_grid.Least_target_point,"Least target point";Closest_target_point,"Closest target point"])
      [Sop.Fuse_near_points,"Near points";Fuse_specified_points,"Specified points"]) [false;true];
  List.iter (fun inclusive -> List.iter (fun match_attributes -> List.iter (fun (match_condition,condition_choice) ->
    List.iter (fun modify_target -> List.iter (fun fuse_points -> List.iter (fun keep_fused_points ->
      List.iter (fun remove_degenerate_primitives -> List.iter (fun remove_unused_points_from_degenerate_primitives ->
        List.iter (fun remove_all_unused_points ->
          if fuse_points || not keep_fused_points then (
          let target = if modify_target then None else Some fuse_target in
          let typed = Sop.fuse ~inclusive ~match_attributes ~match_condition ~modify_target ~fuse_points ~keep_fused_points
              ~remove_degenerate_primitives ~remove_unused_points_from_degenerate_primitives ~remove_all_unused_points
              ~tolerance:0.3 ~match_attribute:"match" ~match_tolerance:0.1 fuse_source target in
          same_cook "fuse matching and cleanup" ~optional_inputs:[Some fuse_source;target] ~typed ~factory:Nodes.Fuse.factory
            ["inclusive",Parameter.Bool_value inclusive;"match_attributes",Bool_value match_attributes;
             "match_condition",Choice_value condition_choice;"modify_target",Bool_value modify_target;"fuse_points",Bool_value fuse_points;
             "keep_fused_points",Bool_value keep_fused_points;"remove_degenerate_primitives",Bool_value remove_degenerate_primitives;
             "remove_unused_points_from_degenerate_primitives",Bool_value remove_unused_points_from_degenerate_primitives;
             "remove_all_unused_points",Bool_value remove_all_unused_points;"tolerance",Float_value 0.3;
             "match_attribute",Text_value "match";"match_tolerance",Float_value 0.1] fuse_source;
          let target = Option.map (fun _ -> fuse_target_geometry) target in
          let native = Rdk.Fuse_grid.fuse ~inclusive ~match_attributes ~match_condition ~modify_target ~fuse_points ~keep_fused_points
              ~remove_degenerate_primitives ~remove_unused_points_from_degenerate_primitives ~remove_all_unused_points
              ~tolerance:0.3 ~match_attribute:"match" ~match_tolerance:0.1 ?target fuse_source_geometry |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "fuse matching and cleanup match native")) [false;true]) [false;true])
        [false;true]) [false;true]) [false;true]) [false;true])
        [Rdk.Fuse_grid.Equal_attribute_values,"Equal";Unequal_attribute_values,"Unequal"]) [false;true]) [false;true];
  same_cook "fuse unset names" ~optional_inputs:[Some fuse_source;None]
    ~typed:(Sop.fuse ~group:" " ~target_group:" " ~weight_attribute:" " ~radius_attribute:" " ~match_attribute:" "
      ~snapped_group:" " ~snapped_destination_attribute:" " fuse_source None) ~factory:Nodes.Fuse.factory
    ["group",Parameter.Text_value " ";"target_group",Text_value " ";"weight_attribute",Text_value " ";"radius_attribute",Text_value " ";
     "match_attribute",Text_value " ";"snapped_group",Text_value " ";"snapped_destination_attribute",Text_value " "] fuse_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "fuse refuses invalid construction")
    [ (fun () -> Sop.fuse ~tolerance:Float.nan fuse_source None);
      (fun () -> Sop.fuse ~tolerance:(-0.1) fuse_source None);
      (fun () -> Sop.fuse ~match_tolerance:Float.infinity fuse_source None);
      (fun () -> Sop.fuse ~targeting:Sop.Fuse_specified_points ~target_attribute:" " fuse_source None);
      (fun () -> Sop.fuse ~targeting:Sop.Fuse_specified_points ~radius_attribute:"radius" fuse_source None);
      (fun () -> Sop.fuse ~match_tolerance:0.1 fuse_source None);
      (fun () -> Sop.fuse ~match_condition:Rdk.Fuse_grid.Unequal_attribute_values fuse_source None);
      (fun () -> Sop.fuse ~fuse_points:false ~keep_fused_points:true fuse_source None);
      (fun () -> Sop.fuse ~modify_target:true fuse_source (Some fuse_target));
      (fun () -> Sop.fuse ~position:Rdk.Fuse_reduce.Weighted_average_position fuse_source None);
      (fun () -> Sop.fuse ~attribute_rules:"Cd\tunknown\t" fuse_source None);
      (fun () -> Sop.fuse ~attribute_rules:"Cd\tweighted_average\t" fuse_source None);
      (fun () -> Sop.fuse ~group_rules:"selected*\tunknown" fuse_source None) ];
  check (Result.is_error (Node.apply_parameters fuse ["match_tolerance",Parameter.Float_value Float.nan]))
    "fuse inspector refuses invalid tolerance";
  let analysis_source_node = Sop.merge [Sop.polyline [|(-1.,0.,0.);(1.,0.,0.)|];
      Sop.polyline [|(0.,0.,-1.);(0.,0.,1.)|]]
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0;1|]) in
  let analysis_collision_node = Sop.polyline [|(0.,-1.,0.);(0.,1.,0.)|]
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|]) in
  let analysis_source_geometry = cook 1 analysis_source_node and analysis_collision_geometry = cook 1 analysis_collision_node in
  let analysis_source = Sop.snapshot analysis_source_geometry and analysis_collision = Sop.snapshot analysis_collision_geometry in
  let analysis = Sop.intersection_analysis analysis_source None in
  same_cook "intersection analysis defaults" ~optional_inputs:[Some analysis_source;None]
    ~typed:analysis ~factory:Nodes.Intersection_analysis.factory [] analysis_source;
  cache_identity "intersection analysis all fields" analysis;
  List.iter (fun use_collision -> List.iter (fun include_coplanar -> List.iter (fun use_groups ->
    for outputs = 0 to 15 do
      let name bit value = if outputs land (1 lsl bit) <> 0 then value else "" in
      let input_attribute = name 0 "input" and primitive_attribute = name 1 "primitive"
      and primitive_uvw_attribute = name 2 "uvw" and point_attribute = name 3 "point" in
      let source_group = if use_groups then "selected" else "" in
      let collision_group = if use_groups then "selected" else "" in
      let collision = if use_collision then Some analysis_collision else None in
      let typed = Sop.intersection_analysis ~source_group ~collision_group ~tolerance:1e-9 ~include_coplanar
          ~input_attribute ~primitive_attribute ~primitive_uvw_attribute ~point_attribute analysis_source collision in
      same_cook "intersection analysis controls" ~optional_inputs:[Some analysis_source;collision]
        ~typed ~factory:Nodes.Intersection_analysis.factory
        ["source_group",Parameter.Text_value source_group;"collision_group",Text_value collision_group;
         "tolerance",Float_value 1e-9;"include_coplanar",Bool_value include_coplanar;
         "input_attribute",Text_value input_attribute;"primitive_attribute",Text_value primitive_attribute;
         "primitive_uvw_attribute",Text_value primitive_uvw_attribute;"point_attribute",Text_value point_attribute] analysis_source;
      let optional name = if name = "" then None else Some name in
      let source_primitives = if use_groups then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" analysis_source_geometry else None
      and collision_primitives = if use_groups && use_collision then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" analysis_collision_geometry else None in
      let collision = Option.map (fun _ -> analysis_collision_geometry) collision in
      let native = Rdk.Intersection_analysis.run ?source_primitives ?collision_primitives ~tolerance:1e-9 ~include_coplanar
          ~input_attribute:(optional input_attribute) ~primitive_attribute:(optional primitive_attribute)
          ~primitive_uvw_attribute:(optional primitive_uvw_attribute) ~point_attribute:(optional point_attribute)
          ?collision analysis_source_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "intersection analysis flat controls match native"
    done) [false;true]) [false;true]) [false;true];
  same_cook "intersection analysis unset names" ~optional_inputs:[Some analysis_source;Some analysis_collision]
    ~typed:(Sop.intersection_analysis ~source_group:" " ~collision_group:" " ~input_attribute:" "
      ~primitive_attribute:" " ~primitive_uvw_attribute:" " ~point_attribute:" " analysis_source (Some analysis_collision))
    ~factory:Nodes.Intersection_analysis.factory ["source_group",Parameter.Text_value " ";"collision_group",Text_value " ";
      "input_attribute",Text_value " ";"primitive_attribute",Text_value " ";"primitive_uvw_attribute",Text_value " ";"point_attribute",Text_value " "] analysis_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "intersection analysis refuses invalid construction")
    [ (fun () -> Sop.intersection_analysis ~tolerance:Float.nan analysis_source None);
      (fun () -> Sop.intersection_analysis ~tolerance:(-0.1) analysis_source None);
      (fun () -> Sop.intersection_analysis ~input_attribute:"P" analysis_source None);
      (fun () -> Sop.intersection_analysis ~input_attribute:"sourceprim" analysis_source None) ];
  check (Result.is_error (Node.apply_parameters analysis ["tolerance",Parameter.Float_value Float.nan]))
    "intersection analysis inspector refuses invalid tolerance";
  let fracture_source_node = Sop.box ~size:(Vec3.create 2. 2. 2.) ~connectivity:Rdk.Box_generator.Box_quads
      ~consolidate_points:true ~normals:None () in
  let fracture_cutter_node = Sop.grid ~counts:Rdk.Plane_generators.Grid_divisions ~columns:1 ~rows:1
      ~connectivity:Rdk.Plane_generators.Grid_triangles ~size:3. () in
  let fracture_source_geometry = cook 1 fracture_source_node |> Rdk.Geometry.without_attribute ~owner:Rdk.Attribute.Point "N"
  and fracture_cutter_geometry = cook 1 fracture_cutter_node |> Rdk.Geometry.without_attribute ~owner:Rdk.Attribute.Point "N" in
  let fracture_source = Sop.snapshot fracture_source_geometry and fracture_cutter = Sop.snapshot fracture_cutter_geometry in
  let fracture = Sop.boolean_fracture fracture_source fracture_cutter in
  same_cook "boolean fracture defaults" ~inputs:[fracture_cutter] ~typed:fracture ~factory:Nodes.Boolean_fracture.factory [] fracture_source;
  cache_identity "boolean fracture all fields" fracture;
  List.iter (fun resolve_cutter_self_intersections -> List.iter (fun (detriangulation,polygon_choice) ->
    List.iter (fun require_closed -> List.iter (fun (point_conflict,conflict_choice) ->
      List.iter (fun assume_flat -> List.iter (fun strict_cleanup -> List.iter (fun cleanup_max_batches ->
        let typed = Sop.boolean_fracture ~resolve_cutter_self_intersections ~detriangulation ~require_closed
            ~point_conflict ~assume_flat ~strict_cleanup ~cleanup_max_batches ~piece_attribute:"cell"
            ~point_tolerance:1e-9 ~tiny_seam_threshold:1e-12 fracture_source fracture_cutter in
        same_cook "boolean fracture controls" ~inputs:[fracture_cutter] ~typed ~factory:Nodes.Boolean_fracture.factory
          ["resolve_cutter_self_intersections",Parameter.Bool_value resolve_cutter_self_intersections;
           "detriangulation",Choice_value polygon_choice;"require_closed",Bool_value require_closed;
           "point_conflict",Choice_value conflict_choice;"assume_flat",Bool_value assume_flat;
           "strict_cleanup",Bool_value strict_cleanup;"cleanup_max_batches",Int_value cleanup_max_batches;
           "piece_attribute",Text_value "cell";"point_tolerance",Float_value 1e-9;"tiny_seam_threshold",Float_value 1e-12] fracture_source;
        let native = Rdk.Boolean.run ~operation:Rdk.Boolean.Difference ~left_treatment:Rdk.Boolean.Solid ~right_treatment:Rdk.Boolean.Surface
            ~resolve_right_self_intersections:resolve_cutter_self_intersections ~detriangulation ~require_closed
            ~point_conflict ~assume_flat ~strict_cleanup ~cleanup_max_batches ~piece_attribute:"cell"
            ~point_tolerance:1e-9 ~tiny_seam_threshold:1e-12 ~seam_points:Rdk.Boolean.Shared_seam_points
            ~right:fracture_cutter_geometry fracture_source_geometry |> Result.get_ok in
        let geometry = cook 1 typed in
        check (equal_geometry native geometry) "boolean fracture flat controls match native";
        check (Node.operation typed = "boolean" && Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "cell" geometry <> None)
          "boolean fracture retains operation identity and piece payload") [4;8]) [false;true]) [false;true])
      [Rdk.Boolean.Reject,"Reject conflict";Promote_to_vertex,"Promote to vertex"])
      [false;true]) [Rdk.Boolean.Triangles,"Triangles";Unchanged_polygons,"Unchanged polygons";All_polygons,"All polygons"]) [false;true];
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "boolean fracture refuses invalid construction")
    [ (fun () -> Sop.boolean_fracture ~point_tolerance:Float.nan fracture_source fracture_cutter);
      (fun () -> Sop.boolean_fracture ~point_tolerance:(-0.1) fracture_source fracture_cutter);
      (fun () -> Sop.boolean_fracture ~tiny_seam_threshold:Float.infinity fracture_source fracture_cutter);
      (fun () -> Sop.boolean_fracture ~tiny_seam_threshold:(-0.1) fracture_source fracture_cutter);
      (fun () -> Sop.boolean_fracture ~cleanup_max_batches:0 fracture_source fracture_cutter);
      (fun () -> Sop.boolean_fracture ~piece_attribute:" " fracture_source fracture_cutter) ];
  check (Result.is_error (Node.apply_parameters fracture ["tiny_seam_threshold",Parameter.Float_value Float.nan]))
    "boolean fracture inspector refuses invalid tolerance";
  let replication_geometry = Test_point_replicate_sop.source () in
  let replication_source = Sop.snapshot replication_geometry |> Sop.set_vector ~name:"v" ~value:(Vec3.create 0.2 0.3 0.4) in
  let replication_geometry = cook 1 replication_source in
  let replication_custom = Sop.points [|(0.,0.,0.);(0.,0.,1.)|] in
  let replication_custom_geometry = cook 1 replication_custom in
  same_cook "point replicate defaults" ~optional_inputs:[Some replication_source;None] ~typed:(Sop.point_replicate replication_source None)
    ~factory:Nodes.Point_replicate.factory [] replication_source;
  cache_identity "point replicate all fields" (Sop.point_replicate replication_source None);
  let replication_points = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "emit" replication_geometry |> Option.get in
  List.iter (fun (shape,shape_choice) -> List.iter (fun (velocity_stretch,velocity_choice) ->
    List.iter (fun use_noise -> List.iter (fun quasi_stratified -> List.iter (fun keep_input ->
      List.iter (fun context_seed -> List.iter (fun noise_context_seed ->
        let custom_shape = if shape = Rdk.Point_replication.Replicate_custom then Some replication_custom else None in
        let typed = Sop.point_replicate ~group:"emit" ~points_per_point:2. ~scale_attribute:"density"
            ~context_seed ~seed:7 ~shape ~velocity_stretch ~use_noise ~noise_context_seed ~noise_seed:9
            ~quasi_stratified ~keep_input ~keep_source_attributes:true ~generated_group:"cloud"
            ~center:(Vec3.create 0.1 0.2 0.3) ~size:(Vec3.create 0.8 0.9 1.) ~orientation:(Vec3.create 0.2 0.1 0.3)
            ~uniform_scale:0.7 ~velocity_scale:0.4 ~inherit_velocity:0.6 ~radial_velocity:0.2
            ~transform_attributes:"flow" replication_source custom_shape in
        same_cook "point replicate controls" ~optional_inputs:[Some replication_source;custom_shape] ~typed
          ~factory:Nodes.Point_replicate.factory
          ["group",Parameter.Text_value "emit";"points_per_point",Float_value 2.;"scale_attribute",Text_value "density";
           "context_seed",Bool_value context_seed;"seed",Int_value 7;"shape",Choice_value shape_choice;
           "velocity_stretch",Choice_value velocity_choice;"use_noise",Bool_value use_noise;
           "noise_context_seed",Bool_value noise_context_seed;"noise_seed",Int_value 9;
           "quasi_stratified",Bool_value quasi_stratified;"keep_input",Bool_value keep_input;
           "keep_source_attributes",Bool_value true;"generated_group",Text_value "cloud";
           "center_x",Float_value 0.1;"center_y",Float_value 0.2;"center_z",Float_value 0.3;
           "size_x",Float_value 0.8;"size_y",Float_value 0.9;"size_z",Float_value 1.;
           "orientation_x",Float_value 0.2;"orientation_y",Float_value 0.1;"orientation_z",Float_value 0.3;
           "uniform_scale",Float_value 0.7;"velocity_scale",Float_value 0.4;"inherit_velocity",Float_value 0.6;
           "radial_velocity",Float_value 0.2;"transform_attributes",Text_value "flow"] replication_source;
        check (Context.Dependencies.mem Context.Dependencies.Seed (Node.dependencies typed)
          = (context_seed || use_noise && noise_context_seed)) "point replicate context seed dependency";
        if not context_seed && not (use_noise && noise_context_seed) then (
          let custom_shape = Option.map (fun _ -> replication_custom_geometry) custom_shape in
          let noise_amplitude = if use_noise then Some (Vec3.create 0.1 0.1 0.1) else None in
          let native = Rdk.Point_replication.run ~points:replication_points ~points_per_point:2. ~scale_attribute:"density"
              ~seed:(Rand.seed 7) ~shape ~velocity_stretch ?noise_amplitude ~noise_seed:9
              ~quasi_stratified ~keep_input ~keep_source_attributes:true ~generated_group:"cloud"
              ~center:(Vec3.create 0.1 0.2 0.3) ~size:(Vec3.create 0.8 0.9 1.) ~orientation:(Vec3.create 0.2 0.1 0.3)
              ~uniform_scale:0.7 ~velocity_scale:0.4 ~inherit_velocity:0.6 ~radial_velocity:0.2
              ~transform_attributes:"flow" ?custom_shape replication_geometry |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "point replicate flat controls match native")) [false;true]) [false;true])
      [false;true]) [false;true]) [false;true])
      [Rdk.Point_replication.Replicate_no_velocity_stretch,"None";Replicate_scaled_velocity,"Scaled velocity";Replicate_velocity_only,"Velocity only"])
      [Rdk.Point_replication.Replicate_point,"Point";Replicate_box,"Box";Replicate_sphere,"Sphere";Replicate_disk,"Disk";Replicate_line,"Line";Replicate_custom,"Custom"];
  let inactive_custom = Sop.point_replicate replication_source (Some replication_custom) in
  check (List.length (Node.inputs inactive_custom) = 2) "point replicate retains inactive optional connection";
  same_cook "point replicate inactive custom input" ~optional_inputs:[Some replication_source;Some replication_custom]
    ~typed:inactive_custom ~factory:Nodes.Point_replicate.factory [] replication_source;
  same_cook "point replicate zero count and unset names" ~optional_inputs:[Some replication_source;None] ~typed:(Sop.point_replicate ~points_per_point:0. ~group:" "
      ~scale_attribute:" " ~generated_group:" " replication_source None) ~factory:Nodes.Point_replicate.factory
    ["points_per_point",Parameter.Float_value 0.;"group",Text_value " ";"scale_attribute",Text_value " ";"generated_group",Text_value " "] replication_source;
  List.iter (fun construct -> check (match construct () with _ -> false | exception Invalid_argument _ -> true)
      "point replicate refuses invalid construction")
    [ (fun () -> Sop.point_replicate ~points_per_point:Float.nan replication_source None);
      (fun () -> Sop.point_replicate ~points_per_point:(-1.) replication_source None);
      (fun () -> Sop.point_replicate ~size:(Vec3.create (-1.) 1. 1.) replication_source None);
      (fun () -> Sop.point_replicate ~noise_roughness:1.1 replication_source None);
      (fun () -> Sop.point_replicate ~noise_attenuation:0. replication_source None);
      (fun () -> Sop.point_replicate ~noise_turbulence:0 replication_source None);
      (fun () -> Sop.point_replicate ~id_attribute:" " replication_source None);
      (fun () -> Sop.point_replicate ~shape:Rdk.Point_replication.Replicate_custom replication_source None);
      (fun () -> Sop.point_replicate ~keep_source_attributes:true ~source_point_attribute:"P" replication_source None);
      (fun () -> Sop.point_replicate ~keep_source_attributes:true ~source_index_attribute:"sourcepoint" replication_source None) ];
  check (Result.is_error (Node.apply_parameters (Sop.point_replicate replication_source None)
      ["noise_frequency_x",Parameter.Float_value Float.nan])) "point replicate inspector refuses nonfinite vector";
  let bevel_geometry = Test_poly_bevel_sop.source () |> Test_poly_bevel_sop.with_edges in
  let bevel_source = Sop.snapshot bevel_geometry |> Sop.set_float ~name:"pscale" ~value:0.8 in
  let bevel_geometry = cook 1 bevel_source in
  same_cook "poly bevel defaults" ~typed:(Sop.poly_bevel bevel_source) ~factory:Nodes.Poly_bevel.factory [] bevel_source;
  cache_identity "poly bevel all fields" (Sop.poly_bevel bevel_source);
  let bevel_edges = Rdk.Geometry.find_edge_group "bevel_edges" bevel_geometry |> Option.get in
  List.iter (fun (shape,choice) -> List.iter (fun divisions -> List.iter (fun clamp_overlap ->
    List.iter (fun ignore_flat_angle -> List.iter (fun recompute_point_normals -> List.iter (fun use_scale ->
      let point_scale_attribute = if use_scale then "pscale" else "" in
      let typed = Sop.poly_bevel ~group:"bevel_edges" ~shape ~convexity:0.75 ~distance:0.2 ~divisions ~clamp_overlap
          ~ignore_flat_angle ~recompute_point_normals ~point_scale_attribute ~edge_group:"edge_fillets"
          ~corner_group:"corner_fillets" ~offset_group:"offset_edges" bevel_source in
      same_cook "poly bevel controls" ~typed ~factory:Nodes.Poly_bevel.factory
        ["group",Parameter.Text_value "bevel_edges";"shape",Choice_value choice;"convexity",Float_value 0.75;
         "distance",Float_value 0.2;"divisions",Int_value divisions;"clamp_overlap",Bool_value clamp_overlap;
         "ignore_flat_angle",Float_value ignore_flat_angle;"recompute_point_normals",Bool_value recompute_point_normals;
         "point_scale_attribute",Text_value point_scale_attribute;"edge_group",Text_value "edge_fillets";
         "corner_group",Text_value "corner_fillets";"offset_group",Text_value "offset_edges"] bevel_source;
      let shape = match shape with Sop.Poly_chamfer -> Rdk.Poly_bevel.Bevel_chamfer
        | Poly_round -> Rdk.Poly_bevel.Bevel_round {convexity=0.75} in
      let ignore_flat_angle = if ignore_flat_angle > 0. then Some ignore_flat_angle else None in
      let point_scale_attribute = if use_scale then Some "pscale" else None in
      let native = Rdk.Poly_bevel.run ~edges:bevel_edges ~shape ~distance:0.2 ~divisions ~clamp_overlap
          ?ignore_flat_angle ~recompute_point_normals ?point_scale_attribute ~edge_group:"edge_fillets"
          ~corner_group:"corner_fillets" ~offset_group:"offset_edges" bevel_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "poly bevel flat controls match native") [false;true])
      [false;true]) [0.;0.1]) [false;true]) [1;3]) [Sop.Poly_chamfer,"Chamfer";Poly_round,"Round"];
  same_cook "poly bevel unset names" ~typed:(Sop.poly_bevel ~group:"" ~point_scale_attribute:"" ~edge_group:""
      ~corner_group:"" ~offset_group:"" bevel_source) ~factory:Nodes.Poly_bevel.factory [] bevel_source;
  List.iter (fun construct ->
    check (match construct () with _ -> false | exception Invalid_argument _ -> true) "poly bevel refuses invalid construction")
    [ (fun () -> Sop.poly_bevel ~distance:Float.nan bevel_source);
      (fun () -> Sop.poly_bevel ~distance:(-0.1) bevel_source);
      (fun () -> Sop.poly_bevel ~divisions:0 bevel_source);
      (fun () -> Sop.poly_bevel ~convexity:Float.infinity bevel_source);
      (fun () -> Sop.poly_bevel ~convexity:1.1 bevel_source);
      (fun () -> Sop.poly_bevel ~ignore_flat_angle:(Float.pi +. 0.1) bevel_source);
      (fun () -> Sop.poly_bevel ~ignore_flat_angle:(-0.1) bevel_source) ];
  check (Result.is_error (Node.apply_parameters (Sop.poly_bevel bevel_source)
      ["distance",Parameter.Float_value Float.nan])) "poly bevel inspector refuses invalid distance";
  let ray_source_node = Sop.grid ~columns:3 ~rows:2 () |> (let migration_translation = Vec3.unit_y in
fun migration_input ->
  Sop.transform ~mode:Sop.Transform_matrix ~m03:migration_translation.Vec3.x
    ~m13:migration_translation.Vec3.y ~m23:migration_translation.Vec3.z
    migration_input)
      |> Sop.set_vector ~name:"N" ~value:(Vec3.neg Vec3.unit_y)
      |> Sop.set_vector ~name:"dir" ~value:(Vec3.neg Vec3.unit_y)
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1|])
      |> Sop.group ~name:"selected" (Select.vertex_indices [|0;1|])
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selected" ~incidence:Rdk.Group_mesh.Boundary_edge in
  let ray_collision_node = Sop.grid ~columns:4 ~rows:3 () |> Sop.color_by_height
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"corner" ~value:3.
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"material" ~value:4
      |> Sop.set_int ~owner:Rdk.Attribute.Detail ~name:"revision" ~value:5
      |> Sop.group ~name:"collision" Select.all_primitives
      |> Sop.group ~name:"collision_points" (Select.point_indices [|0;1;2;3;4;5|]) in
  let ray_source_geometry = cook 1 ray_source_node and ray_collision_geometry = cook 1 ray_collision_node in
  let ray_source = Sop.snapshot ray_source_geometry and ray_collision = Sop.snapshot ray_collision_geometry in
  let ray = Sop.ray ray_source ray_collision in
  same_cook "ray defaults" ~inputs:[ray_collision] ~typed:ray ~factory:Nodes.Ray.factory [] ray_source;
  cache_identity ~companions:["match_groups",["point_pattern",Parameter.Text_value "Cd"];
    "source_vertex_numbers_attribute",["source_vertex_weights_attribute",Parameter.Text_value "weights"];
    "source_vertex_weights_attribute",["source_vertex_numbers_attribute",Parameter.Text_value "numbers"]] "ray all fields" ray;
  let direction_vector = Vec3.create 0. (-1.) 0. in
  let selection = Rdk.Transform_ops.Selected_points (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" ray_source_geometry |> Option.get)
  and collision_primitives = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "collision" ray_collision_geometry |> Option.get in
  List.iter (fun (method_,method_choice,sample_counts) -> List.iter (fun (direction,direction_choice,native_direction) ->
    List.iter (fun (direction_mode,mode_choice) -> List.iter (fun (surface_hit,hit_choice) ->
      List.iter (fun (combine,combine_choice) -> List.iter (fun samples -> List.iter (fun limit_max_distance ->
        let typed = Sop.ray ~method_ ~direction ~direction_vector ~direction_attribute:"dir" ~direction_mode ~surface_hit ~combine
            ~samples ~jitter_scale:0.03 ~seed:7 ~min_distance:0.1 ~limit_max_distance ~max_distance:2. ~tolerance:1e-9 ~scale:0.8 ~lift:0.01
            ~group:"selected" ~collision_group:"collision" ~distance_attribute:"distance" ~primitive_attribute:"primitive"
            ~source_vertex_numbers_attribute:"numbers" ~source_vertex_weights_attribute:"weights" ~hit_group:"hits" ~normal_attribute:"hit_normal"
            ~point_pattern:"Cd collision_points" ~vertex_pattern:"corner" ~primitive_pattern:"material collision" ~detail_pattern:"revision"
            ray_source ray_collision in
        same_cook ("ray " ^ method_choice ^ direction_choice ^ mode_choice ^ hit_choice ^ combine_choice) ~inputs:[ray_collision]
          ~typed ~factory:Nodes.Ray.factory ["method_",Parameter.Choice_value method_choice;"direction",Choice_value direction_choice;
            "direction_y",Float_value (-1.);"direction_attribute",Text_value "dir";"direction_mode",Choice_value mode_choice;
            "surface_hit",Choice_value hit_choice;"combine",Choice_value combine_choice;"samples",Int_value samples;
            "jitter_scale",Float_value 0.03;"seed",Int_value 7;"min_distance",Float_value 0.1;"limit_max_distance",Bool_value limit_max_distance;
            "max_distance",Float_value 2.;"tolerance",Float_value 1e-9;"scale",Float_value 0.8;"lift",Float_value 0.01;
            "group",Text_value "selected";"collision_group",Text_value "collision";"distance_attribute",Text_value "distance";
            "primitive_attribute",Text_value "primitive";"source_vertex_numbers_attribute",Text_value "numbers";
            "source_vertex_weights_attribute",Text_value "weights";"hit_group",Text_value "hits";"normal_attribute",Text_value "hit_normal";
            "point_pattern",Text_value "Cd collision_points";"vertex_pattern",Text_value "corner";
            "primitive_pattern",Text_value "material collision";"detail_pattern",Text_value "revision"] ray_source;
        let max_distance = if limit_max_distance then Some 2. else None in
        let native = Rdk.Ray.run ~method_ ~direction:native_direction ~direction_mode ~surface_hit ~combine ~samples
            ~jitter_scale:0.03 ~seed:7 ~min_distance:0.1 ?max_distance ~tolerance:1e-9 ~scale:0.8 ~lift:0.01 ~selection ~collision_primitives
            ~distance_attribute:"distance" ~primitive_attribute:"primitive" ~source_vertex_numbers_attribute:"numbers"
            ~source_vertex_weights_attribute:"weights" ~hit_group:"hits" ~normal_attribute:"hit_normal"
            ~point_pattern:"Cd collision_points" ~vertex_pattern:"corner" ~primitive_pattern:"material collision" ~detail_pattern:"revision"
            ~source:ray_source_geometry ~collision:ray_collision_geometry () |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "ray flat controls match native") [false;true]) sample_counts)
      [Rdk.Ray.Ray_average,"Average";Ray_median,"Median";Ray_shortest,"Shortest";Ray_longest,"Longest"])
      [Rdk.Ray.Ray_first_surface,"First surface";Ray_last_surface,"Last surface"])
      [Rdk.Ray.Ray_forward,"Forward";Ray_reverse,"Reverse";Ray_bidirectional_closest,"Bidirectional closest";Ray_bidirectional_farthest,"Bidirectional farthest"])
    [Sop.Direction_vector,"Vector",Rdk.Ray.Ray_vector direction_vector;Direction_normal,"Normal",Ray_normal;
     Direction_attribute,"Attribute",Ray_attribute "dir"])
    [Rdk.Ray.Ray_project,"Project rays",[1;3];Ray_minimum_distance,"Minimum distance",[1]];
  List.iter (fun (group_owner,owner_choice,selection) ->
    let typed = Sop.ray ~group_owner ~group:"selected" ~point_pattern:"Cd collision_points" ~match_groups:true ray_source ray_collision in
    same_cook "ray selection owners and group matching" ~inputs:[ray_collision] ~typed ~factory:Nodes.Ray.factory
      ["group_owner",Parameter.Choice_value owner_choice;"group",Text_value "selected";
       "point_pattern",Text_value "Cd collision_points";"match_groups",Bool_value true] ray_source;
    let native = Rdk.Ray.run ~selection ~point_pattern:"Cd collision_points" ~match_groups:true
        ~source:ray_source_geometry ~collision:ray_collision_geometry () |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "ray selection owners match native")
    [Sop.Element_point,"Point",Rdk.Transform_ops.Selected_points (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" ray_source_geometry |> Option.get);
     Element_vertex,"Vertex",Selected_vertices (Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "selected" ray_source_geometry |> Option.get);
     Element_primitive,"Primitive",Selected_primitives (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" ray_source_geometry |> Option.get);
     Element_edge,"Edge",Selected_edges (Rdk.Geometry.find_edge_group "selected" ray_source_geometry |> Option.get)];
  same_cook "ray inactive zero direction" ~inputs:[ray_collision]
    ~typed:(Sop.ray ~method_:Rdk.Ray.Ray_minimum_distance ~direction:Sop.Direction_vector ~direction_vector:Vec3.zero ray_source ray_collision)
    ~factory:Nodes.Ray.factory ["method_",Parameter.Choice_value "Minimum distance";"direction",Choice_value "Vector";"direction_y",Float_value 0.] ray_source;
  same_cook "ray unset names" ~inputs:[ray_collision]
    ~typed:(Sop.ray ~group:" " ~collision_group:" " ~distance_attribute:" " ~source_vertex_numbers_attribute:" "
      ~source_vertex_weights_attribute:" " ~point_pattern:" " ray_source ray_collision) ~factory:Nodes.Ray.factory
    ["group",Parameter.Text_value " ";"collision_group",Text_value " ";"distance_attribute",Text_value " ";
     "source_vertex_numbers_attribute",Text_value " ";"source_vertex_weights_attribute",Text_value " ";"point_pattern",Text_value " "] ray_source;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true) "ray refuses invalid controls at construction")
    [(fun () -> Sop.ray ~samples:1025 ray_source ray_collision);
     (fun () -> Sop.ray ~method_:Rdk.Ray.Ray_minimum_distance ~samples:2 ray_source ray_collision);
     (fun () -> Sop.ray ~direction:Sop.Direction_vector ~direction_vector:Vec3.zero ray_source ray_collision);
     (fun () -> Sop.ray ~direction:Sop.Direction_attribute ~direction_attribute:" " ray_source ray_collision);
     (fun () -> Sop.ray ~jitter_scale:nan ray_source ray_collision);
     (fun () -> Sop.ray ~limit_max_distance:true ~min_distance:2. ~max_distance:1. ray_source ray_collision);
     (fun () -> Sop.ray ~tolerance:Float.max_float ray_source ray_collision);
     (fun () -> Sop.ray ~source_vertex_numbers_attribute:"numbers" ray_source ray_collision);
     (fun () -> Sop.ray ~normal_attribute:"P" ray_source ray_collision);
     (fun () -> Sop.ray ~normal_attribute:"same" ~distance_attribute:"same" ray_source ray_collision);
     (fun () -> Sop.ray ~match_groups:true ray_source ray_collision);
     (fun () -> Sop.ray ~point_pattern:"broken[" ray_source ray_collision)];
  check (Result.is_error (Node.apply_parameters ray ["tolerance",Parameter.Float_value nan])) "ray refuses invalid inspector edit";
  let copy_fields input = input
      |> Sop.enumerate ~name:"id" |> Sop.enumerate ~owner:Rdk.Attribute.Vertex ~name:"id"
      |> Sop.enumerate ~owner:Rdk.Attribute.Primitive ~name:"id"
      |> Sop.enumerate ~name:"source" |> Sop.enumerate ~owner:Rdk.Attribute.Vertex ~name:"source"
      |> Sop.enumerate ~owner:Rdk.Attribute.Primitive ~name:"source"
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1;2|])
      |> Sop.group ~name:"selected" (Select.vertex_indices [|0;1;2|])
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0;1|]) in
  let copy_source = Sop.grid ~columns:4 ~rows:3 () |> copy_fields
      |> Sop.set_float ~name:"value" ~value:2.
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"value" ~value:3.
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"value" ~value:4
      |> Sop.set_int ~owner:Rdk.Attribute.Detail ~name:"value" ~value:5 in
  let copy_target = Sop.grid ~columns:3 ~rows:2 () |> copy_fields in
  let copy_source_geometry = cook 1 copy_source and copy_target_geometry = cook 1 copy_target in
  let copy_source = Sop.snapshot copy_source_geometry and copy_target = Sop.snapshot copy_target_geometry in
  let copied = Sop.attribute_copy copy_source copy_target in
  same_cook "attribute copy defaults" ~inputs:[copy_target] ~typed:copied ~factory:Nodes.Attribute_copy.factory [] copy_source;
  cache_identity ~changes:["rules",Parameter.Text_value "point\tid\tid_copy"] "attribute copy all fields" copied;
  let rules = "point\tvalue\tvalue_copy\nvertex\tvalue\tvalue_copy\nprimitive\tvalue\tvalue_copy\ndetail\tvalue\tvalue_copy\npoint\tP\t" in
  let native_rules = List.map (fun owner -> Rdk.Attribute_ops.copy_rule ~owner ~into:"value_copy" "value")
      [Rdk.Attribute.Point;Vertex;Primitive;Detail] @ [Rdk.Attribute_ops.copy_rule ~owner:Rdk.Attribute.Point "P"] in
  List.iter (fun (group_owner,owner_choice) -> List.iter (fun (match_,match_choice,native_match) ->
    List.iter (fun allow_position ->
      if group_owner <> Rdk.Group.Vertex || match_ <> Sop.Copy_by_values then begin
      let typed = Sop.attribute_copy ~group_owner ~match_ ~allow_position ~rules ~source_group:"selected" ~target_group:"selected"
          copy_source copy_target in
      same_cook ("attribute copy " ^ owner_choice ^ match_choice) ~inputs:[copy_target] ~typed ~factory:Nodes.Attribute_copy.factory
        ["group_owner",Parameter.Choice_value owner_choice;"match_",Choice_value match_choice;"allow_position",Bool_value allow_position;
         "rules",Text_value rules;"source_group",Text_value "selected";"target_group",Text_value "selected"] copy_source;
      let source_group = Rdk.Geometry.find_group ~owner:group_owner "selected" copy_source_geometry |> Option.get
      and target_group = Rdk.Geometry.find_group ~owner:group_owner "selected" copy_target_geometry |> Option.get in
      let native = Rdk.Attribute_ops.copy ~group_owner ~match_:native_match ~allow_position ~rules:native_rules ~source_group ~target_group
          ~source:copy_source_geometry ~target:copy_target_geometry () |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "attribute copy flat controls match native"
      end) [false;true])
    [Sop.Copy_cyclic,"Cyclic",Rdk.Attribute_ops.Cyclic;
     Copy_by_values,"By attribute values",By_values {source_attribute="id";target_attribute="id"};
     Copy_to_element,"To source element",To_element {target_attribute="source"}])
    [Rdk.Group.Point,"Points";Vertex,"Vertices";Primitive,"Primitives"];
  same_cook "attribute copy group pattern precedence" ~inputs:[copy_target]
    ~typed:(Sop.attribute_copy ~source_group:"ignored" ~source_group_pattern:"sel*" ~target_group:"ignored" ~target_group_pattern:"sel*"
      copy_source copy_target) ~factory:Nodes.Attribute_copy.factory ["source_group",Parameter.Text_value "ignored";
      "source_group_pattern",Text_value "sel*";"target_group",Text_value "ignored";"target_group_pattern",Text_value "sel*"] copy_source;
  same_cook "attribute copy unset groups" ~inputs:[copy_target]
    ~typed:(Sop.attribute_copy ~source_group:" " ~source_group_pattern:" " ~target_group:" " ~target_group_pattern:" " copy_source copy_target)
    ~factory:Nodes.Attribute_copy.factory ["source_group",Parameter.Text_value " ";"source_group_pattern",Text_value " ";
      "target_group",Text_value " ";"target_group_pattern",Text_value " "] copy_source;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "attribute copy refuses invalid controls at construction")
    [(fun () -> Sop.attribute_copy ~rules:"" copy_source copy_target);
     (fun () -> Sop.attribute_copy ~rules:"broken" copy_source copy_target);
     (fun () -> Sop.attribute_copy ~rules:"unknown\tvalue\t" copy_source copy_target);
     (fun () -> Sop.attribute_copy ~rules:"point\tbroken[\t" copy_source copy_target);
     (fun () -> Sop.attribute_copy ~match_:Sop.Copy_by_values ~source_match_attribute:" " copy_source copy_target);
     (fun () -> Sop.attribute_copy ~group_owner:Rdk.Group.Vertex ~match_:Sop.Copy_by_values copy_source copy_target);
     (fun () -> Sop.attribute_copy ~match_:Sop.Copy_to_element ~target_element_attribute:"P" copy_source copy_target);
     (fun () -> Sop.attribute_copy ~source_group_pattern:"broken[" copy_source copy_target)];
  check (Result.is_error (Node.apply_parameters copied ["rules",Parameter.Text_value "broken"]))
    "attribute copy refuses invalid inspector edit";
  let surface_source = Sop.grid ~columns:4 ~rows:3 () |> Sop.color_by_height
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"corner" ~value:3.
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"material" ~value:4
      |> Sop.group ~name:"source" (Select.primitive_indices [|0;1|])
      |> Sop.group ~name:"corners" (Select.vertex_indices [|0;1;2;3;4|]) in
  let surface_target = Sop.grid ~columns:3 ~rows:2 ()
      |> Sop.group ~name:"target" (Select.point_indices [|0;1|])
      |> Sop.group ~name:"target" (Select.vertex_indices [|0;1|])
      |> Sop.group ~name:"target" (Select.primitive_indices [|0|]) in
  let surface_geometry = cook 1 surface_source and target_geometry = cook 1 surface_target in
  let surface_source = Sop.snapshot surface_geometry and surface_target = Sop.snapshot target_geometry in
  let surface_transfer = Sop.attribute_transfer_surface surface_source surface_target in
  same_cook "surface transfer defaults" ~inputs:[surface_target] ~typed:surface_transfer
    ~factory:Nodes.Attribute_transfer_surface.factory [] surface_source;
  cache_identity "surface transfer all fields" surface_transfer;
  let attributes = "point\tCd\tcolor\nvertex\tcorner\tcorner_copy\nprimitive\tmaterial\tmaterial_copy" in
  let native_attributes = [Rdk.Attribute_ops.surface_attribute ~owner:Rdk.Attribute.Point ~into:"color" "Cd";
    Rdk.Attribute_ops.surface_attribute ~owner:Rdk.Attribute.Vertex ~into:"corner_copy" "corner";
    Rdk.Attribute_ops.surface_attribute ~owner:Rdk.Attribute.Primitive ~into:"material_copy" "material"] in
  List.iter (fun (target_owner,owner_choice,group_owner) -> List.iter (fun (falloff,falloff_choice,native_falloff) ->
    List.iter (fun (distance_mode,distance_choice,max_distance,blend_width) ->
      List.iter (fun (unmatched,unmatched_choice) -> List.iter (fun (source_vertex_selection,selection_choice) ->
        let typed = Sop.attribute_transfer_surface ~target_owner ~attributes ~distance_mode ~max_distance:1. ~blend_width
            ~falloff ~uniform_bias:0.7 ~unmatched ~distance_attribute:"distance" ~source_group:"source"
            ~source_vertex_group:"corners" ~source_vertex_selection ~target_group:"target" surface_source surface_target in
        same_cook ("surface transfer " ^ owner_choice ^ falloff_choice ^ distance_choice) ~inputs:[surface_target]
          ~typed ~factory:Nodes.Attribute_transfer_surface.factory ["target_owner",Parameter.Choice_value owner_choice;
            "attributes",Text_value attributes;"distance_mode",Choice_value distance_choice;"max_distance",Float_value 1.;
            "blend_width",Float_value blend_width;"falloff",Choice_value falloff_choice;"uniform_bias",Float_value 0.7;
            "unmatched",Choice_value unmatched_choice;"distance_attribute",Text_value "distance";
            "source_group",Text_value "source";"source_vertex_group",Text_value "corners";
            "source_vertex_selection",Choice_value selection_choice;"target_group",Text_value "target"] surface_source;
        let source_primitives = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "source" surface_geometry |> Option.get
        and source_vertices = Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "corners" surface_geometry |> Option.get
        and target_elements = Rdk.Geometry.find_group ~owner:group_owner "target" target_geometry |> Option.get in
        let native = Rdk.Attribute_ops.transfer_surface ~target_owner ~attributes:native_attributes ?max_distance ~blend_width
            ~falloff:native_falloff ~unmatched ~distance_attribute:"distance" ~source_primitives ~source_vertices
            ~source_vertex_selection ~target_elements ~source:surface_geometry ~target:target_geometry () |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "surface transfer flat controls match native")
        [Rdk.Attribute_ops.All_triangle_vertices,"All triangle vertices";Any_triangle_vertex,"Any triangle vertex"])
      [Rdk.Attribute_ops.Keep_target,"Keep target";Default_value,"Default value"])
      [Sop.Kernel_explicit,"Explicit",Some 1.,0.2;Kernel_auto,"Auto",None,0.])
    [Sop.Transfer_linear,"Linear",Rdk.Attribute_ops.Linear;Transfer_smoothstep,"Smoothstep",Smoothstep;Transfer_uniform,"Uniform",Uniform 0.7])
    [Rdk.Attribute.Point,"Point",Rdk.Group.Point;Vertex,"Vertex",Vertex;Primitive,"Primitive",Primitive];
  same_cook "surface transfer group patterns" ~inputs:[surface_target]
    ~typed:(Sop.attribute_transfer_surface ~source_group:"ignored" ~source_group_pattern:"sour*"
      ~source_vertex_group:"ignored" ~source_vertex_group_pattern:"corn*" ~target_group:"ignored" ~target_group_pattern:"targ*"
      surface_source surface_target) ~factory:Nodes.Attribute_transfer_surface.factory
    ["source_group",Parameter.Text_value "ignored";"source_group_pattern",Text_value "sour*";
     "source_vertex_group",Text_value "ignored";"source_vertex_group_pattern",Text_value "corn*";
     "target_group",Text_value "ignored";"target_group_pattern",Text_value "targ*"] surface_source;
  same_cook "surface transfer unset and empty rules" ~inputs:[surface_target]
    ~typed:(Sop.attribute_transfer_surface ~attributes:" " ~source_group:" " ~source_vertex_group:" " ~target_group:" "
      ~distance_attribute:" " surface_source surface_target) ~factory:Nodes.Attribute_transfer_surface.factory
    ["attributes",Parameter.Text_value " ";"source_group",Text_value " ";"source_vertex_group",Text_value " ";
     "target_group",Text_value " ";"distance_attribute",Text_value " "] surface_source;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "surface transfer refuses invalid controls at construction")
    [(fun () -> Sop.attribute_transfer_surface ~attributes:"broken" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~attributes:"detail\tx\tx" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~target_owner:Rdk.Attribute.Detail surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~attributes:"point\tP\tcopy" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~attributes:"point\tCd\tP" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~attributes:"point\tCd\tx\nvertex\tcorner\tx" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~distance_attribute:"Cd" surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~max_distance:nan surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~distance_mode:Sop.Kernel_auto ~blend_width:1. surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~uniform_bias:1.1 surface_source surface_target);
     (fun () -> Sop.attribute_transfer_surface ~target_group_pattern:"broken[" surface_source surface_target)];
  check (Result.is_error (Node.apply_parameters surface_transfer ["attributes",Parameter.Text_value "broken"]))
    "surface transfer refuses invalid inspector edit";
  let seam_left = Sop.box ~normals:None ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Rdk.Box_generator.Box_triangles ~consolidate_points:true () in
  let seam_right = Sop.box ~normals:None ~size:(Vec3.create 2. 2. 2.) ~center:(Vec3.create 0.5 0.5 0.5)
      ~connectivity:Rdk.Box_generator.Box_triangles ~consolidate_points:true () in
  let seam_left_geometry = cook 1 seam_left and seam_right_geometry = cook 1 seam_right in
  let seam_left = Sop.snapshot seam_left_geometry and seam_right = Sop.snapshot seam_right_geometry in
  let seam = Sop.boolean_seam seam_left seam_right in
  same_cook "boolean seam defaults" ~inputs:[seam_right] ~typed:seam ~factory:Nodes.Boolean_seam.factory [] seam_left;
  cache_identity "boolean seam all fields" seam;
  List.iter (fun (output,output_choice) -> List.iter (fun (left_treatment,left_choice) ->
    List.iter (fun (right_treatment,right_choice) -> List.iter (fun resolve_left_self_intersections ->
      List.iter (fun resolve_right_self_intersections ->
        let typed = Sop.boolean_seam ~output ~left_treatment ~right_treatment ~resolve_left_self_intersections
            ~resolve_right_self_intersections ~left_self_group:"left" ~between_group:"between" ~right_self_group:"right"
            ~coincident_group:"coincident" seam_left seam_right in
        same_cook ("boolean seam " ^ output_choice ^ left_choice ^ right_choice) ~inputs:[seam_right] ~typed ~factory:Nodes.Boolean_seam.factory
          ["output",Parameter.Choice_value output_choice;"left_treatment",Choice_value left_choice;"right_treatment",Choice_value right_choice;
           "resolve_left_self_intersections",Bool_value resolve_left_self_intersections;
           "resolve_right_self_intersections",Bool_value resolve_right_self_intersections;
           "left_self_group",Text_value "left";"between_group",Text_value "between";"right_self_group",Text_value "right";
           "coincident_group",Text_value "coincident"] seam_left;
        let native = Rdk.Boolean.seam ~output ~left_treatment ~right_treatment ~resolve_left_self_intersections
            ~resolve_right_self_intersections ~left_self_group:(Some "left") ~between_group:(Some "between")
            ~right_self_group:(Some "right") ~coincident_group:(Some "coincident") ~right:seam_right_geometry seam_left_geometry
            |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "boolean seam flat controls match native") [false;true]) [false;true])
      [Rdk.Boolean.Solid,"Solid";Surface,"Surface"]) [Rdk.Boolean.Solid,"Solid";Surface,"Surface"])
    [Rdk.Boolean.Seam_curves,"Seam curves";Coincident_patches,"Coincident patches"];
  let coincident_right_geometry = cook 1 (Sop.box ~normals:None ~size:(Vec3.create 2. 2. 2.) ~center:(Vec3.create 0.5 0. 0.)
      ~connectivity:Rdk.Box_generator.Box_triangles ~consolidate_points:true ()) in
  let coincident_right = Sop.snapshot coincident_right_geometry in
  let coincident = Sop.boolean_seam ~output:Rdk.Boolean.Coincident_patches ~coincident_group:"patches" seam_left coincident_right in
  same_cook "boolean seam coincident area" ~inputs:[coincident_right] ~typed:coincident ~factory:Nodes.Boolean_seam.factory
    ["output",Parameter.Choice_value "Coincident patches";"coincident_group",Text_value "patches"] seam_left;
  let native_coincident = Rdk.Boolean.seam ~output:Rdk.Boolean.Coincident_patches ~coincident_group:(Some "patches")
      ~right:coincident_right_geometry seam_left_geometry |> Result.get_ok in
  let cooked_coincident = cook 1 coincident in
  check (equal_geometry native_coincident cooked_coincident) "boolean seam coincident area matches native";
  check (Rdk.Geometry.primitive_count cooked_coincident > 0) "boolean seam coincident fixture has area";
  same_cook "boolean seam unset groups" ~inputs:[seam_right]
    ~typed:(Sop.boolean_seam ~left_self_group:" " ~between_group:" " ~right_self_group:" " ~coincident_group:" " seam_left seam_right)
    ~factory:Nodes.Boolean_seam.factory ["left_self_group",Parameter.Text_value " ";"between_group",Text_value " ";
      "right_self_group",Text_value " ";"coincident_group",Text_value " "] seam_left;
  same_cook "boolean seam inactive group names" ~inputs:[coincident_right]
    ~typed:(Sop.boolean_seam ~output:Rdk.Boolean.Coincident_patches ~left_self_group:"same" ~between_group:"same" ~right_self_group:"same"
      seam_left coincident_right) ~factory:Nodes.Boolean_seam.factory ["output",Parameter.Choice_value "Coincident patches";
      "left_self_group",Text_value "same";"between_group",Text_value "same";"right_self_group",Text_value "same"] seam_left;
  check (try ignore (Sop.boolean_seam ~left_self_group:"same" ~between_group:"same" seam_left seam_right);
      false with Invalid_argument _ -> true) "boolean seam refuses duplicate active group names";
  check (Result.is_error (Node.apply_parameters seam ["between_group",Parameter.Text_value "boolean_left_self_seam"]))
    "boolean seam refuses invalid inspector edit";
  let sweep_backbone_source = Sop.merge [Sop.polyline [|(0.,0.,0.);(0.3,0.,1.);(0.,0.,2.)|];
      Sop.polyline ~closed:true [|(3.,0.,0.);(4.,0.,1.);(3.,1.,2.)|]]
      |> Sop.set_float ~name:"payload" ~value:2.
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|]) in
  let sweep_profile_source = Sop.polyline ~closed:true [|(-0.2,-0.2,0.);(0.2,-0.2,0.);(0.2,0.2,0.);(-0.2,0.2,0.)|]
      |> Sop.set_vector ~name:"v" ~value:Vec3.unit_x
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"material" ~value:3
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|]) in
  let sweep_backbone_geometry = cook 1 sweep_backbone_source and sweep_profile_geometry = cook 1 sweep_profile_source in
  let sweep_backbone = Sop.snapshot sweep_backbone_geometry and sweep_profile = Sop.snapshot sweep_profile_geometry in
  let swept = Sop.sweep sweep_backbone sweep_profile in
  same_cook "sweep defaults" ~inputs:[sweep_profile] ~typed:swept ~factory:Nodes.Sweep.factory [] sweep_backbone;
  cache_identity "sweep all fields" swept;
  List.iter (fun (connectivity,connectivity_choice,surface) ->
    List.iter (fun (tangent,tangent_choice) -> List.iter (fun continuous_closed ->
      List.iter (fun transform_attributes -> List.iter (fun reverse_cross_sections ->
        List.iter (fun caps ->
          let typed = Sop.sweep ~connectivity ~tangent ~continuous_closed ~transform_attributes ~reverse_cross_sections
              ~scale:0.8 ~roll:0.2 ~twist:0.3 ~caps ~cap_group:"ends" ~uv_attribute:"st" ~cross_section_prefix:"profile_"
              sweep_backbone sweep_profile in
          same_cook ("sweep " ^ connectivity_choice ^ tangent_choice) ~inputs:[sweep_profile] ~typed ~factory:Nodes.Sweep.factory
            ["connectivity",Parameter.Choice_value connectivity_choice;"tangent",Choice_value tangent_choice;
             "continuous_closed",Bool_value continuous_closed;"transform_attributes",Bool_value transform_attributes;
             "reverse_cross_sections",Bool_value reverse_cross_sections;"scale",Float_value 0.8;"roll",Float_value 0.2;
             "twist",Float_value 0.3;"caps",Bool_value caps;"cap_group",Text_value "ends";"uv_attribute",Text_value "st";
             "cross_section_prefix",Text_value "profile_"] sweep_backbone;
          let cap_group = if caps then Some "ends" else None in
          let native = Rdk.Sweep_modeling.sweep ~connectivity ~tangent ~continuous_closed ~transform_attributes ~reverse_cross_sections
              ~scale:0.8 ~roll:0.2 ~twist:0.3 ~caps ?cap_group ~uv_attribute:(Some "st") ~cross_section_prefix:"profile_"
              ~backbone:sweep_backbone_geometry ~cross_section:sweep_profile_geometry () |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "sweep flat controls match native") (if surface then [false;true] else [false]))
        [false;true]) [false;true]) [false;true])
      [Rdk.Sweep_modeling.Sweep_average_edges,"Average edges";Sweep_central_difference,"Central difference";
       Sweep_previous_edge,"Previous edge";Sweep_next_edge,"Next edge";Sweep_z_axis,"Z axis"])
    [Rdk.Plane_generators.Grid_points,"Points",false;Grid_rows,"Rows",false;Grid_columns,"Columns",false;
     Grid_rows_and_columns,"Rows and columns",false;Grid_quads,"Quads",true;Grid_triangles,"Triangles",true;
     Grid_alternating_triangles,"Alternating triangles",true;Grid_reverse_triangles,"Reverse triangles",true];
  List.iter (fun backbone_selected -> List.iter (fun profile_selected ->
    let backbone_group = if backbone_selected then "selected" else " "
    and cross_section_group = if profile_selected then "selected" else " " in
    let typed = Sop.sweep ~backbone_group ~cross_section_group ~caps:true sweep_backbone sweep_profile in
    same_cook "sweep selections" ~inputs:[sweep_profile] ~typed ~factory:Nodes.Sweep.factory
      ["backbone_group",Parameter.Text_value backbone_group;"cross_section_group",Text_value cross_section_group;"caps",Bool_value true]
      sweep_backbone;
    let backbones = if backbone_selected then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" sweep_backbone_geometry else None
    and cross_sections = if profile_selected then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "selected" sweep_profile_geometry else None in
    let native = Rdk.Sweep_modeling.sweep ?backbones ?cross_sections ~caps:true ~cap_group:"caps"
        ~backbone:sweep_backbone_geometry ~cross_section:sweep_profile_geometry () |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "sweep selections match native") [false;true]) [false;true];
  same_cook "sweep unset outputs" ~inputs:[sweep_profile]
    ~typed:(Sop.sweep ~caps:true ~cap_group:" " ~uv_attribute:" " sweep_backbone sweep_profile)
    ~factory:Nodes.Sweep.factory ["caps",Parameter.Bool_value true;"cap_group",Text_value " ";"uv_attribute",Text_value " "] sweep_backbone;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "sweep refuses invalid controls at construction")
    [(fun () -> Sop.sweep ~scale:nan sweep_backbone sweep_profile);
     (fun () -> Sop.sweep ~roll:infinity sweep_backbone sweep_profile);
     (fun () -> Sop.sweep ~twist:nan sweep_backbone sweep_profile);
     (fun () -> Sop.sweep ~caps:true ~connectivity:Rdk.Plane_generators.Grid_points sweep_backbone sweep_profile);
     (fun () -> Sop.sweep ~cross_section_prefix:(String.make 1 '\000') sweep_backbone sweep_profile);
     (fun () -> Sop.sweep ~uv_attribute:"P" sweep_backbone sweep_profile)];
  check (Result.is_error (Node.apply_parameters swept ["twist",Parameter.Float_value nan])) "sweep refuses invalid inspector edit";
  let scatter_source = Sop.grid ~columns:4 ~rows:3 ()
      |> Sop.set_float ~name:"density" ~value:0.5
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"density" ~value:0.6
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"density" ~value:0.7
      |> Sop.set_float ~owner:Rdk.Attribute.Detail ~name:"density" ~value:0.8
      |> Sop.set_float ~name:"point_value" ~value:2.
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"vertex_value" ~value:3.
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"primitive_value" ~value:4.
      |> Sop.set_float ~owner:Rdk.Attribute.Detail ~name:"detail_value" ~value:5.
      |> Sop.group ~name:"points" (Select.point_indices [|0;1;2|])
      |> Sop.group ~name:"vertices" (Select.vertex_indices [|0;1;2|])
      |> Sop.group ~name:"surface" (Select.primitive_indices [|0;1|]) in
  let scatter_geometry = cook 1 scatter_source in
  let scatter_input = Sop.snapshot scatter_geometry in
  let scattered = Sop.scatter scatter_input in
  same_cook "scatter defaults" ~typed:scattered ~factory:Nodes.Scatter.factory [] scatter_input;
  cache_identity ~companions:["match_groups",["point_pattern",Parameter.Text_value "point_value"];
    "source_vertex_numbers_attribute",["source_vertex_weights_attribute",Parameter.Text_value "weights"];
    "source_vertex_weights_attribute",["source_vertex_numbers_attribute",Parameter.Text_value "numbers"]]
    "scatter all fields" scattered;
  List.iter (fun (density_owner,owner_choice) -> List.iter (fun use_density ->
    List.iter (fun context_seed -> List.iter (fun match_groups ->
      let typed = Sop.scatter ~count:9 ~seed:7 ~context_seed ~group:"surface" ~use_density ~density_owner
          ~density_attribute:"density" ~point_pattern:"point_value points" ~vertex_pattern:"vertex_value vertices"
          ~primitive_pattern:"primitive_value surface" ~detail_pattern:"detail_value" ~match_groups
          ~source_primitive_attribute:"primitive" ~source_vertex_numbers_attribute:"numbers" ~source_vertex_weights_attribute:"weights"
          scatter_input in
      same_cook ("scatter " ^ owner_choice) ~typed ~factory:Nodes.Scatter.factory
        ["count",Parameter.Int_value 9;"seed",Int_value 7;"context_seed",Bool_value context_seed;"group",Text_value "surface";
         "use_density",Bool_value use_density;"density_owner",Choice_value owner_choice;"density_attribute",Text_value "density";
         "point_pattern",Text_value "point_value points";"vertex_pattern",Text_value "vertex_value vertices";
         "primitive_pattern",Text_value "primitive_value surface";"detail_pattern",Text_value "detail_value";
         "match_groups",Bool_value match_groups;"source_primitive_attribute",Text_value "primitive";
         "source_vertex_numbers_attribute",Text_value "numbers";"source_vertex_weights_attribute",Text_value "weights"] scatter_input;
      check (Context.Dependencies.mem Context.Dependencies.Seed (Node.dependencies typed) = context_seed)
        "scatter context seed owns its dependency";
      if not context_seed then begin
        let density = if use_density then Some (Rdk.Scatter.density ~owner:density_owner "density") else None in
        let primitives = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "surface" scatter_geometry |> Option.get in
        let native = Rdk.Scatter.run ~count:9 ~seed:7 ~primitives ?density ~point_pattern:"point_value points"
            ~vertex_pattern:"vertex_value vertices" ~primitive_pattern:"primitive_value surface" ~detail_pattern:"detail_value"
            ~match_groups ~source_primitive_attribute:"primitive" ~source_vertex_numbers_attribute:"numbers"
            ~source_vertex_weights_attribute:"weights" scatter_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "scatter flat controls match native"
      end) [false;true]) [false;true]) [false;true])
    [Rdk.Attribute.Point,"Point";Vertex,"Vertex";Primitive,"Primitive";Detail,"Detail"];
  same_cook "scatter zero count" ~typed:(Sop.scatter ~count:0 scatter_input)
    ~factory:Nodes.Scatter.factory ["count",Parameter.Int_value 0] scatter_input;
  same_cook "scatter unset names" ~typed:(Sop.scatter ~group:" " ~point_pattern:" " ~vertex_pattern:" "
      ~primitive_pattern:" " ~detail_pattern:" " ~source_primitive_attribute:" " ~source_vertex_numbers_attribute:" "
      ~source_vertex_weights_attribute:" " scatter_input) ~factory:Nodes.Scatter.factory
    ["group",Parameter.Text_value " ";"point_pattern",Text_value " ";"vertex_pattern",Text_value " ";
     "primitive_pattern",Text_value " ";"detail_pattern",Text_value " ";"source_primitive_attribute",Text_value " ";
     "source_vertex_numbers_attribute",Text_value " ";"source_vertex_weights_attribute",Text_value " "] scatter_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "scatter refuses invalid controls at construction")
    [(fun () -> Sop.scatter ~count:(-1) scatter_input);
     (fun () -> Sop.scatter ~count:max_int scatter_input);
     (fun () -> Sop.scatter ~count:(Sys.max_array_length / 3 + 1) ~point_pattern:"point_value" scatter_input);
     (fun () -> Sop.scatter ~use_density:true ~density_attribute:" " scatter_input);
     (fun () -> Sop.scatter ~use_density:true ~density_attribute:"P" scatter_input);
     (fun () -> Sop.scatter ~point_pattern:"broken[" scatter_input);
     (fun () -> Sop.scatter ~match_groups:true scatter_input);
     (fun () -> Sop.scatter ~source_primitive_attribute:"P" scatter_input);
     (fun () -> Sop.scatter ~source_vertex_numbers_attribute:"numbers" scatter_input);
     (fun () -> Sop.scatter ~source_vertex_numbers_attribute:"same" ~source_vertex_weights_attribute:"same" scatter_input)];
  check (Result.is_error (Node.apply_parameters scattered ["source_vertex_numbers_attribute",Parameter.Text_value "numbers"]))
    "scatter refuses invalid inspector edit";
  let soft_source = Sop.grid ~columns:4 ~rows:3 ()
      |> Sop.set_float ~name:"mask" ~value:0.4
      |> Sop.group ~name:"seed" (Select.point_indices [|0|])
      |> Sop.group ~name:"seed" (Select.vertex_indices [|0|])
      |> Sop.group ~name:"seed" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"seed" ~incidence:Rdk.Group_mesh.Boundary_edge in
  let soft_geometry = cook 1 soft_source in
  let soft_input = Sop.snapshot soft_geometry in
  let soft = Sop.soft_transform_trs soft_input in
  same_cook "soft transform defaults" ~typed:soft ~factory:Nodes.Soft_transform.factory [] soft_input;
  cache_identity "soft transform all fields" soft;
  let translate = Vec3.create 0.2 0.3 (-0.1) and rotate = Vec3.create 0.1 0.2 0.3
  and scale = Vec3.create 1.1 0.9 1.2 and pivot = Vec3.create 0.1 (-0.1) 0.2
  and pivot_rotation = Vec3.create 0.2 0.1 (-0.1) in
  let transform_values = ["translate_x",Parameter.Float_value translate.x;"translate_y",Float_value translate.y;
    "translate_z",Float_value translate.z;"rotate_x",Float_value rotate.x;"rotate_y",Float_value rotate.y;
    "rotate_z",Float_value rotate.z;"scale_x",Float_value scale.x;"scale_y",Float_value scale.y;
    "scale_z",Float_value scale.z;"shear_xy",Float_value 0.1;"shear_xz",Float_value 0.2;"shear_yz",Float_value (-0.1);
    "uniform_scale",Float_value 0.8;"pivot_x",Float_value pivot.x;"pivot_y",Float_value pivot.y;
    "pivot_z",Float_value pivot.z;"pivot_rotation_x",Float_value pivot_rotation.x;
    "pivot_rotation_y",Float_value pivot_rotation.y;"pivot_rotation_z",Float_value pivot_rotation.z] in
  let matrix ?order ?rotation_order ~invert () = Rdk.Transform_ops.compose_transform ?order ?rotation_order
      ~translate ~rotate ~scale ~shear:(Vec3.create 0.1 0.2 (-0.1)) ~uniform_scale:0.8 ~pivot ~pivot_rotation ~invert ()
      |> Result.get_ok in
  List.iter (fun (group_owner,owner_choice,selection) ->
    List.iter (fun (metric,metric_choice) -> List.iter (fun apply_rolloff ->
      List.iter (fun (falloff,falloff_choice) -> List.iter (fun invert ->
        let typed = Sop.soft_transform_trs ~translate ~rotate ~scale ~shear_xy:0.1 ~shear_xz:0.2 ~shear_yz:(-0.1)
            ~uniform_scale:0.8 ~pivot ~pivot_rotation ~invert ~group_owner ~group:"seed" ~metric ~metric_attribute:"mask"
            ~apply_rolloff ~falloff ~radius:2. ~falloff_attribute:"weight" ~recompute_normals:false soft_input in
        same_cook ("soft transform " ^ owner_choice ^ metric_choice ^ falloff_choice) ~typed ~factory:Nodes.Soft_transform.factory
          (transform_values @ ["group_owner",Parameter.Choice_value owner_choice;"group",Text_value "seed";
            "metric",Choice_value metric_choice;"metric_attribute",Text_value "mask";"apply_rolloff",Bool_value apply_rolloff;
            "falloff",Choice_value falloff_choice;"radius",Float_value 2.;"falloff_attribute",Text_value "weight";
            "recompute_normals",Bool_value false;"invert",Bool_value invert]) soft_input;
        let metric = match metric with Sop.Soft_radius -> Rdk.Transform_ops.Soft_radius
          | Soft_edge -> Soft_edge | Soft_attribute -> Soft_attribute {attribute="mask";apply_rolloff} in
        let native = Rdk.Transform_ops.soft_transform ~selection ~metric ~falloff ~radius:2.
            ~falloff_attribute:"weight" ~recompute_normals:false (matrix ~invert ()) soft_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "soft transform flat controls match native") [false;true])
        [Rdk.Transform_ops.Soft_linear,"Linear";Soft_quadratic,"Quadratic";Soft_cubic,"Cubic"])
        [false;true]) [Sop.Soft_radius,"Radius";Soft_edge,"Edge distance";Soft_attribute,"Attribute"])
    [Sop.Element_point,"Point",Rdk.Transform_ops.Selected_points (Rdk.Geometry.find_group ~owner:Rdk.Group.Point "seed" soft_geometry |> Option.get);
     Element_vertex,"Vertex",Selected_vertices (Rdk.Geometry.find_group ~owner:Rdk.Group.Vertex "seed" soft_geometry |> Option.get);
     Element_primitive,"Primitive",Selected_primitives (Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "seed" soft_geometry |> Option.get);
     Element_edge,"Edge",Selected_edges (Rdk.Geometry.find_edge_group "seed" soft_geometry |> Option.get)];
  List.iter (fun (order,order_choice) -> List.iter (fun (rotation_order,rotation_choice) ->
    let typed = Sop.soft_transform_trs ~order ~rotation_order ~translate ~rotate ~scale ~shear_xy:0.1 ~shear_xz:0.2 ~shear_yz:(-0.1)
        ~uniform_scale:0.8 ~pivot ~pivot_rotation soft_input in
    same_cook "soft transform orders" ~typed ~factory:Nodes.Soft_transform.factory
      (transform_values @ ["order",Parameter.Choice_value order_choice;"rotation_order",Choice_value rotation_choice]) soft_input;
    let native = Rdk.Transform_ops.soft_transform (matrix ~order ~rotation_order ~invert:false ()) soft_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "soft transform orders match native")
      [Rdk.Transform_ops.Transform_xyz,"XYZ";Transform_xzy,"XZY";Transform_yxz,"YXZ";Transform_yzx,"YZX";Transform_zxy,"ZXY";Transform_zyx,"ZYX"])
    [Rdk.Transform_ops.Transform_srt,"SRT";Transform_str,"STR";Transform_rst,"RST";Transform_rts,"RTS";Transform_tsr,"TSR";Transform_trs,"TRS"];
  same_cook "soft transform raw mask zero radius"
    ~typed:(Sop.soft_transform_trs ~metric:Sop.Soft_attribute ~apply_rolloff:false ~radius:0. soft_input)
    ~factory:Nodes.Soft_transform.factory ["metric",Parameter.Choice_value "Attribute";"apply_rolloff",Bool_value false;"radius",Float_value 0.] soft_input;
  same_cook "soft transform unset names" ~typed:(Sop.soft_transform_trs ~group:" " ~falloff_attribute:" " soft_input)
    ~factory:Nodes.Soft_transform.factory ["group",Parameter.Text_value " ";"falloff_attribute",Text_value " "] soft_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "soft transform refuses invalid controls at construction")
    [(fun () -> Sop.soft_transform_trs ~translate:(Vec3.create nan 0. 0.) soft_input);
     (fun () -> Sop.soft_transform_trs ~scale:Vec3.zero ~invert:true soft_input);
     (fun () -> Sop.soft_transform_trs ~scale:(Vec3.create Float.max_float 1. 1.) ~uniform_scale:Float.max_float soft_input);
     (fun () -> Sop.soft_transform_trs ~radius:0. soft_input);
     (fun () -> Sop.soft_transform_trs ~radius:nan soft_input);
     (fun () -> Sop.soft_transform_trs ~metric:Sop.Soft_attribute ~metric_attribute:" " soft_input);
     (fun () -> Sop.soft_transform_trs ~metric:Sop.Soft_attribute ~metric_attribute:"P" soft_input);
     (fun () -> Sop.soft_transform_trs ~falloff_attribute:"P" soft_input)];
  check (Result.is_error (Node.apply_parameters soft ["translate_x",Parameter.Float_value nan]))
    "soft transform refuses invalid inspector edit";
  let reduce_source = Sop.grid ~columns:6 ~rows:5 ~connectivity:Rdk.Plane_generators.Grid_triangles ()
      |> Sop.group ~name:"selected" (Select.primitive_indices (Array.init 30 Fun.id))
      |> Sop.group ~name:"hard_points" (Select.point_indices [|0;5|])
      |> Sop.group_edges ~name:"hard_edges" ~incidence:Rdk.Group_mesh.Boundary_edge in
  let reduce_geometry = cook 1 reduce_source in
  let reduce_input = Sop.snapshot reduce_geometry in
  let reduced = Sop.poly_reduce reduce_input in
  same_cook "poly reduce defaults" ~typed:reduced ~factory:Nodes.Poly_reduce.factory [] reduce_input;
  cache_identity "poly reduce all fields" reduced;
  List.iter (fun (target_mode,choice,native_target) ->
    List.iter (fun preserve_boundary -> List.iter (fun only_original_positions ->
      List.iter (fun limit_normal_deviation ->
        let typed = Sop.poly_reduce ~target_mode ~ratio:0.6 ~primitive_count:24 ~preserve_boundary
            ~only_original_positions ~equalize_lengths:1e-8 ~limit_normal_deviation ~max_normal_deviation:0.7
            ~output_group:"reduced" ~recompute_point_normals:false reduce_input in
        same_cook ("poly reduce " ^ choice) ~typed ~factory:Nodes.Poly_reduce.factory
          ["target_mode",Parameter.Choice_value choice;"ratio",Float_value 0.6;"primitive_count",Int_value 24;
           "preserve_boundary",Bool_value preserve_boundary;"only_original_positions",Bool_value only_original_positions;
           "equalize_lengths",Float_value 1e-8;"limit_normal_deviation",Bool_value limit_normal_deviation;
           "max_normal_deviation",Float_value 0.7;"output_group",Text_value "reduced";"recompute_point_normals",Bool_value false] reduce_input;
        let max_normal_deviation = if limit_normal_deviation then Some 0.7 else None in
        let native = Rdk.Poly_reduce.run ~target:native_target ~preserve_boundary ~only_original_positions
            ~equalize_lengths:1e-8 ?max_normal_deviation ~output_group:"reduced" ~recompute_point_normals:false
            reduce_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "poly reduce flat target matches native") [false;true]) [false;true]) [false;true])
    [Sop.Reduce_ratio,"Percentage",Rdk.Poly_reduce.Reduce_ratio 0.6;
     Reduce_primitive_count,"Primitive count",Reduce_primitive_count 24];
  List.iter (fun (group,hard_point_group,hard_edge_group) ->
    let typed = Sop.poly_reduce ~group ~hard_point_group ~hard_edge_group ~ratio:0.5 reduce_input in
    same_cook "poly reduce constraints" ~typed ~factory:Nodes.Poly_reduce.factory
      ["group",Parameter.Text_value group;"hard_point_group",Text_value hard_point_group;"hard_edge_group",Text_value hard_edge_group]
      reduce_input;
    let find owner name = if name = "" then None else Rdk.Geometry.find_group ~owner name reduce_geometry in
    let primitives = find Rdk.Group.Primitive group and hard_points = find Rdk.Group.Point hard_point_group
    and hard_edges = if hard_edge_group = "" then None else Rdk.Geometry.find_edge_group hard_edge_group reduce_geometry in
    let native = Rdk.Poly_reduce.run ~target:(Rdk.Poly_reduce.Reduce_ratio 0.5) ?primitives ?hard_points ?hard_edges
        reduce_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "poly reduce constraints match native")
    ["selected","","";"","hard_points","";"","","hard_edges";"selected","hard_points","hard_edges"];
  List.iter (fun ratio -> same_cook "poly reduce ratio endpoints" ~typed:(Sop.poly_reduce ~ratio reduce_input)
      ~factory:Nodes.Poly_reduce.factory ["ratio",Parameter.Float_value ratio] reduce_input) [0.;1.];
  List.iter (fun primitive_count -> same_cook "poly reduce count endpoints"
      ~typed:(Sop.poly_reduce ~target_mode:Sop.Reduce_primitive_count ~primitive_count reduce_input)
      ~factory:Nodes.Poly_reduce.factory ["target_mode",Parameter.Choice_value "Primitive count";"primitive_count",Int_value primitive_count]
      reduce_input) [0;100];
  same_cook "poly reduce unset groups" ~typed:(Sop.poly_reduce ~group:" " ~hard_point_group:" " ~hard_edge_group:" " ~output_group:" " reduce_input)
    ~factory:Nodes.Poly_reduce.factory ["group",Parameter.Text_value " ";"hard_point_group",Text_value " ";
      "hard_edge_group",Text_value " ";"output_group",Text_value " "] reduce_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "poly reduce refuses invalid controls at construction")
    [(fun () -> Sop.poly_reduce ~ratio:nan reduce_input);
     (fun () -> Sop.poly_reduce ~ratio:1.1 reduce_input);
     (fun () -> Sop.poly_reduce ~primitive_count:(-1) reduce_input);
     (fun () -> Sop.poly_reduce ~equalize_lengths:(-1.) reduce_input);
     (fun () -> Sop.poly_reduce ~equalize_lengths:infinity reduce_input);
     (fun () -> Sop.poly_reduce ~max_normal_deviation:4. reduce_input)];
  check (Result.is_error (Node.apply_parameters reduced ["max_normal_deviation",Parameter.Float_value nan]))
    "poly reduce refuses invalid inspector edit";
  let cut_geometry = Test_extract_point_curve_sop.source_geometry () in
  let cut_points = Rdk.Group.init ~owner:Rdk.Group.Point ~name:"selected" 4 (fun i -> i mod 2 = 0) in
  let topology = Rdk.Geometry.topology cut_geometry in
  let cut_edges = Rdk.Edge_group.init ~topology ~index:(Rdk.Topology_index.create topology)
      ~name:"selected" (fun i -> i mod 2 = 0) in
  let cut_geometry = Rdk.Geometry.with_group cut_points cut_geometry |> get |> Rdk.Geometry.with_edge_group cut_edges |> get in
  let cut_input = Sop.snapshot cut_geometry in
  let poly_cut = Sop.poly_cut cut_input in
  same_cook "poly cut defaults" ~typed:poly_cut ~factory:Nodes.Poly_cut.factory [] cut_input;
  cache_identity "poly cut all fields" poly_cut;
  List.iter (fun (element,element_choice,cut_points,cut_edges) ->
    List.iter (fun (strategy,strategy_choice) ->
      List.iter (fun (detection,detection_choice,native_detection) ->
        List.iter (fun keep_closed ->
          let typed = Sop.poly_cut ~element ~strategy ~detection ~attribute:"distance" ~value:0. ~threshold:0.5
              ~keep_closed ~group:"first" ~cut_group:"selected" cut_input in
          same_cook ("poly cut " ^ element_choice ^ strategy_choice ^ detection_choice) ~typed ~factory:Nodes.Poly_cut.factory
            ["element",Parameter.Choice_value element_choice;"strategy",Choice_value strategy_choice;
             "detection",Choice_value detection_choice;"attribute",Text_value "distance";"value",Float_value 0.;"threshold",Float_value 0.5;
             "keep_closed",Bool_value keep_closed;"group",Text_value "first";"cut_group",Text_value "selected"] cut_input;
          let primitives = Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "first" cut_geometry |> Option.get in
          let native = Rdk.Poly_cut.cut ~element ~strategy ~detection:native_detection ~keep_closed ~primitives
              ?cut_points ?cut_edges cut_geometry |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "poly cut flat detection matches native") [false;true])
        [Sop.Cut_all,"All selected",Rdk.Poly_cut.Poly_cut_all;
         Cut_crossing,"Attribute crossing",Poly_cut_crossing {attribute="distance";value=0.};
         Cut_change,"Attribute change",Poly_cut_change {attribute="distance";threshold=0.5}])
      [Rdk.Poly_cut.Poly_cut_remove,"Remove";Poly_cut_cut,"Cut"])
    [Rdk.Poly_cut.Poly_cut_points,"Points",Some cut_points,None;Poly_cut_edges,"Edges",None,Some cut_edges];
  same_cook "poly cut unset groups" ~typed:(Sop.poly_cut ~group:" " ~cut_group:" " cut_input)
    ~factory:Nodes.Poly_cut.factory ["group",Parameter.Text_value " ";"cut_group",Text_value " "] cut_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "poly cut refuses invalid controls at construction")
    [(fun () -> Sop.poly_cut ~value:nan cut_input);
     (fun () -> Sop.poly_cut ~threshold:(-1.) cut_input);
     (fun () -> Sop.poly_cut ~detection:Sop.Cut_crossing ~attribute:" " cut_input);
     (fun () -> Sop.poly_cut ~detection:Sop.Cut_crossing ~attribute:"P" cut_input);
     (fun () -> Sop.poly_cut ~detection:Sop.Cut_change ~strategy:Rdk.Poly_cut.Poly_cut_cut ~threshold:0. cut_input)];
  check (Result.is_error (Node.apply_parameters poly_cut ["threshold",Parameter.Float_value nan]))
    "poly cut refuses invalid inspector edit";
  let generation_geometry = Test_point_generate_sop.source () in
  let probability = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"probability"
      (Rdk.Attribute.Float [|0.25;0.75;1.|]) |> get in
  let generation_geometry = Rdk.Geometry.with_attribute probability generation_geometry |> get in
  let generation_input = Sop.snapshot generation_geometry in
  let generated = Sop.point_generate generation_input in
  same_cook "point generate defaults" ~typed:generated ~factory:Nodes.Point_generate_from_input.factory [] generation_input;
  cache_identity "point generate all fields" generated;
  List.iter (fun (mode,choice,native_mode) ->
    List.iter (fun keep_input -> List.iter (fun context_seed ->
      let typed = Sop.point_generate ~mode ~total:7 ~points_per_point:1.5 ~scale_attribute:"density"
          ~probability_attribute:"probability" ~keep_input ~context_seed ~seed:7 ~group:"emit"
          ~generated_group:"made" ~source_point_attribute:"from" ~source_index_attribute:"index"
          ~copy_point_attributes:"id" generation_input in
      same_cook ("point generate " ^ choice) ~typed ~factory:Nodes.Point_generate_from_input.factory
        ["mode",Parameter.Choice_value choice;"total",Int_value 7;"points_per_point",Float_value 1.5;
         "scale_attribute",Text_value "density";"probability_attribute",Text_value "probability";
         "keep_input",Bool_value keep_input;"context_seed",Bool_value context_seed;"seed",Int_value 7;
         "group",Text_value "emit";"generated_group",Text_value "made";"source_point_attribute",Text_value "from";
         "source_index_attribute",Text_value "index";"copy_point_attributes",Text_value "id"] generation_input;
      if not context_seed then begin
        let points = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "emit" generation_geometry |> Option.get in
        let native = Rdk.Point_generate.run ~mode:native_mode ~points ~keep_input ~seed:(Rand.seed 7)
            ~generated_group:"made" ~source_point_attribute:"from" ~source_index_attribute:"index"
            ~copy_point_attributes:"id" generation_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "point generate flat modes match native"
      end) [false;true]) [false;true])
    [Sop.Point_generate_total,"Total count",Rdk.Point_generate.Generate_total 7;
     Point_generate_per_point,"Per point",Generate_per_point {points_per_point=1.5;scale_attribute=Some "density"};
     Point_generate_probability,"Probability attribute",Generate_probability {attribute="probability"}];
  same_cook "point generate unset names" ~typed:(Sop.point_generate ~group:" " ~scale_attribute:" "
      ~generated_group:" " ~copy_point_attributes:" " ~copy_detail_attributes:" " generation_input)
    ~factory:Nodes.Point_generate_from_input.factory ["group",Parameter.Text_value " ";"scale_attribute",Text_value " ";
      "generated_group",Text_value " ";"copy_point_attributes",Text_value " ";"copy_detail_attributes",Text_value " "] generation_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "point generate refuses invalid controls at construction")
    [(fun () -> Sop.point_generate ~total:(-1) generation_input);
     (fun () -> Sop.point_generate ~points_per_point:nan generation_input);
     (fun () -> Sop.point_generate ~points_per_point:Float.max_float generation_input);
     (fun () -> Sop.point_generate ~source_point_attribute:"P" generation_input);
     (fun () -> Sop.point_generate ~source_point_attribute:"same" ~source_index_attribute:"same" generation_input);
     (fun () -> Sop.point_generate ~mode:Sop.Point_generate_probability ~probability_attribute:" " generation_input);
     (fun () -> Sop.point_generate ~copy_detail_attributes:"broken[" generation_input)];
  check (Result.is_error (Node.apply_parameters generated ["points_per_point",Parameter.Float_value nan]))
    "point generate refuses invalid inspector edit";
  let extract_geometry = Test_extract_point_curve_sop.source_geometry () in
  let extract_input = Sop.snapshot extract_geometry in
  let extracted = Sop.extract_point_from_curve extract_input in
  same_cook "extract point curve defaults" ~typed:extracted ~factory:Nodes.Extract_point_from_curve.factory [] extract_input;
  cache_identity "extract point curve all fields" extracted;
  List.iter (fun (cut,cut_choice,native_cut) ->
    List.iter (fun copy_primitive_attributes -> List.iter (fun selected ->
      let group = if selected then "first" else " " in
      let typed = Sop.extract_point_from_curve ~cut ~constant:0.25 ~primitive_attribute:"cut" ~group
          ~point_attributes:"weight" ~copy_primitive_attributes ~primitive_attributes:"material"
          ~curve_u_attribute:"u" ~number_cuts_attribute:"cuts" ~curve_number_attribute:"curve" extract_input in
      same_cook ("extract point curve " ^ cut_choice) ~typed ~factory:Nodes.Extract_point_from_curve.factory
        ["cut",Parameter.Choice_value cut_choice;"constant",Float_value 0.25;"primitive_attribute",Text_value "cut";
         "group",Text_value group;"point_attributes",Text_value "weight";"copy_primitive_attributes",Bool_value copy_primitive_attributes;
         "primitive_attributes",Text_value "material";"curve_u_attribute",Text_value "u";
         "number_cuts_attribute",Text_value "cuts";"curve_number_attribute",Text_value "curve"] extract_input;
      let primitives = if selected then Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive "first" extract_geometry else None in
      let native = Rdk.Curve_topology.extract_point_from_curve ?primitives ~cut:native_cut ~point_attributes:"weight"
          ~copy_primitive_attributes ~primitive_attributes:"material" ~curve_u_attribute:"u" ~number_cuts_attribute:"cuts"
          ~curve_number_attribute:"curve" ~distance_attribute:"distance" extract_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "extract point curve flat cut matches native") [false;true]) [false;true])
    [Sop.Extract_point_constant,"Constant",Rdk.Curve_topology.Extract_cut_constant 0.25;
     Extract_point_primitive_attribute,"Primitive attribute",Extract_cut_primitive_attribute "cut";
     Extract_point_current_time,"Current time",Extract_cut_constant 0.];
  same_cook "extract point curve unset diagnostics" ~typed:(Sop.extract_point_from_curve ~group:" "
      ~curve_u_attribute:" " ~number_cuts_attribute:" " ~curve_number_attribute:" " extract_input)
    ~factory:Nodes.Extract_point_from_curve.factory ["group",Parameter.Text_value " ";
      "curve_u_attribute",Text_value " ";"number_cuts_attribute",Text_value " ";"curve_number_attribute",Text_value " "] extract_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "extract point curve refuses invalid controls at construction")
    [(fun () -> Sop.extract_point_from_curve ~constant:nan extract_input);
     (fun () -> Sop.extract_point_from_curve ~cut:Sop.Extract_point_primitive_attribute ~primitive_attribute:" " extract_input);
     (fun () -> Sop.extract_point_from_curve ~distance_attribute:" " extract_input);
     (fun () -> Sop.extract_point_from_curve ~curve_u_attribute:"P" extract_input);
     (fun () -> Sop.extract_point_from_curve ~curve_u_attribute:"same" ~curve_number_attribute:"same" extract_input);
     (fun () -> Sop.extract_point_from_curve ~point_attributes:"broken[" extract_input);
     (fun () -> Sop.extract_point_from_curve ~primitive_attributes:"broken[" extract_input)];
  check (Result.is_error (Node.apply_parameters extracted ["constant",Parameter.Float_value nan]))
    "extract point curve refuses invalid inspector edit";

  let mountain_source = Sop.grid ~columns:4 ~rows:3 ()
      |> Sop.set_vector ~name:"direction" ~value:(Vec3.create 1. 2. 3.)
      |> Sop.set_float ~name:"mask" ~value:0.5
      |> Sop.group ~name:"selected" (Select.point_indices [|0;1;2|]) in
  let mountain = Sop.mountain mountain_source in
  same_cook "mountain defaults" ~typed:mountain ~factory:Nodes.Mountain.factory [] mountain_source;
  cache_identity "mountain all fields" mountain;
  let mountain_geometry = cook 1 mountain_source in
  List.iter (fun (seed_mode,seed_choice) ->
    List.iter (fun normalize_direction -> List.iter (fun recompute_normals ->
      let typed = Sop.mountain ~seed_mode ~seed:23 ~group:"selected" ~direction_attribute:"direction" ~mask_attribute:"mask"
          ~normalize_direction ~height:0.7 ~frequency:(Vec3.create 0.4 0.8 0.55) ~offset:(Vec3.create 2. 3. 5.)
          ~octaves:5 ~lacunarity:2.05 ~roughness:0.48 ~height_attribute:"height" ~recompute_normals mountain_source in
      same_cook ("mountain " ^ seed_choice) ~typed ~factory:Nodes.Mountain.factory
        ["seed_mode",Parameter.Choice_value seed_choice;"seed",Int_value 23;"group",Text_value "selected";
         "direction_attribute",Text_value "direction";"mask_attribute",Text_value "mask";
         "normalize_direction",Bool_value normalize_direction;"height",Float_value 0.7;
         "frequency_x",Float_value 0.4;"frequency_y",Float_value 0.8;"frequency_z",Float_value 0.55;
         "offset_x",Float_value 2.;"offset_y",Float_value 3.;"offset_z",Float_value 5.;"octaves",Int_value 5;
         "lacunarity",Float_value 2.05;"roughness",Float_value 0.48;"height_attribute",Text_value "height";
         "recompute_normals",Bool_value recompute_normals] mountain_source;
      if seed_mode = Sop.Kernel_explicit then begin
        let selected = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" mountain_geometry |> Option.get in
        let native = Rdk.Deform.mountain ~seed:23 ~selection:(Rdk.Transform_ops.Selected_points selected)
            ~direction_attribute:"direction" ~mask_attribute:"mask" ~normalize_direction ~height:0.7
            ~frequency:(Vec3.create 0.4 0.8 0.55) ~offset:(Vec3.create 2. 3. 5.) ~octaves:5 ~lacunarity:2.05
            ~roughness:0.48 ~height_attribute:"height" ~recompute_normals mountain_geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "mountain flat controls match native"
      end) [false;true]) [false;true])
    [Sop.Kernel_explicit,"Explicit";Kernel_auto,"Auto"];
  same_cook "mountain unset names" ~typed:(Sop.mountain ~group:" " ~direction_attribute:" "
      ~mask_attribute:" " ~height_attribute:" " ~height:0. mountain_source)
    ~factory:Nodes.Mountain.factory ["group",Parameter.Text_value " ";"direction_attribute",Text_value " ";
      "mask_attribute",Text_value " ";"height_attribute",Text_value " ";"height",Float_value 0.] mountain_source;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "mountain refuses invalid controls at construction")
    [(fun () -> Sop.mountain ~height:nan mountain_source);
     (fun () -> Sop.mountain ~height:(-1.) mountain_source);
     (fun () -> Sop.mountain ~frequency:(Vec3.create (-1.) 1. 1.) mountain_source);
     (fun () -> Sop.mountain ~offset:(Vec3.create infinity 0. 0.) mountain_source);
     (fun () -> Sop.mountain ~octaves:0 mountain_source);
     (fun () -> Sop.mountain ~octaves:65 mountain_source);
     (fun () -> Sop.mountain ~lacunarity:0. mountain_source);
     (fun () -> Sop.mountain ~roughness:1.1 mountain_source);
     (fun () -> Sop.mountain ~height_attribute:"P" mountain_source)];
  check (Result.is_error (Node.apply_parameters mountain ["roughness",Parameter.Float_value nan]))
    "mountain refuses invalid inspector edit";

  let tube = Sop.tube () in
  same_generator "tube defaults" ~typed:tube ~factory:Nodes.Tube.factory [];
  cache_identity ~companions:["end_caps",["cap_group",Parameter.Text_value ""]] "tube all fields" tube;
  List.iter (fun (connectivity,connectivity_choice,polygon) ->
    List.iter (fun (normals,normals_choice) ->
      List.iter (fun (normals_mode,normals_mode_choice,native_normals) ->
        if connectivity <> Rdk.Parametric_generators.Tube_points || native_normals <> Some Rdk.Parametric_generators.Tube_vertex_normals then
          List.iter (fun end_caps -> List.iter (fun consolidate_cap_points ->
            List.iter (fun (top_radius,bottom_radius) ->
              let cap_group = if end_caps then "caps" else " " in
              let typed = Sop.tube ~connectivity ~normals ~normals_mode ~end_caps ~consolidate_cap_points ~cap_group
                  ~rows:3 ~columns:5 ~top_radius ~bottom_radius ~height:2. ~radius_scale:1.25 () in
              same_generator ("tube " ^ connectivity_choice ^ normals_choice ^ normals_mode_choice)
                ~typed ~factory:Nodes.Tube.factory ["connectivity",Parameter.Choice_value connectivity_choice;
                  "normals",Choice_value normals_choice;"normals_mode",Choice_value normals_mode_choice;
                  "end_caps",Bool_value end_caps;"consolidate_cap_points",Bool_value consolidate_cap_points;
                  "cap_group",Text_value cap_group;"rows",Int_value 3;"columns",Int_value 5;
                  "top_radius",Float_value top_radius;"bottom_radius",Float_value bottom_radius;"height",Float_value 2.;"radius_scale",Float_value 1.25];
              let native = Rdk.Parametric_generators.tube ~connectivity ?normals:native_normals ~end_caps ~consolidate_cap_points
                  ?cap_group:(if end_caps then Some "caps" else None) ~rows:3 ~columns:5 ~top_radius ~bottom_radius
                  ~height:2. ~radius_scale:1.25 ~uv_attribute:"uv" () |> Result.get_ok in
              check (equal_geometry native (cook 1 typed)) "tube flat caps and tips match native")
              [1.,1.;0.,1.;1.,0.]) [false;true]) (if polygon then [false;true] else [false]))
        [Sop.Kernel_explicit,"Explicit",Some normals;Kernel_auto,"Auto",None])
      [Rdk.Parametric_generators.Tube_no_normals,"None";Tube_point_normals,"Point";Tube_vertex_normals,"Vertex"])
    [Rdk.Parametric_generators.Tube_triangles,"Triangles",true;Tube_alternating_triangles,"Alternating triangles",true;
     Tube_quads,"Quads",true;Tube_rows,"Rows",false;Tube_columns,"Columns",false;
     Tube_rows_and_columns,"Rows and columns",false;Tube_points,"Points",false];
  let tube_axis = Vec3.create 1. 2. 3. and tube_center = Vec3.create 2. (-1.) 3.
  and tube_rotation = Vec3.create 0.2 0.3 0.4 in
  List.iter (fun (orientation,orientation_choice,native_orientation) ->
    List.iter (fun (rotation_order,rotation_choice) ->
      let typed = Sop.tube ~orientation ~axis:tube_axis ~rotation_order ~center:tube_center ~rotation:tube_rotation
          ~rows:3 ~columns:5 ~uv_attribute:" " ~cap_group:" " () in
      same_generator ("tube orientation " ^ orientation_choice ^ rotation_choice)
        ~typed ~factory:Nodes.Tube.factory ["orientation",Parameter.Choice_value orientation_choice;
          "axis_x",Float_value 1.;"axis_y",Float_value 2.;"axis_z",Float_value 3.;
          "rotation_order",Choice_value rotation_choice;"center_x",Float_value 2.;"center_y",Float_value (-1.);"center_z",Float_value 3.;
          "rotation_x",Float_value 0.2;"rotation_y",Float_value 0.3;"rotation_z",Float_value 0.4;
          "rows",Int_value 3;"columns",Int_value 5;"uv_attribute",Text_value " ";"cap_group",Text_value " "];
      let native = Rdk.Parametric_generators.tube ~orientation:native_orientation ~rotation_order ~center:tube_center ~rotation:tube_rotation
          ~connectivity:Rdk.Parametric_generators.Tube_triangles ~end_caps:true ~consolidate_cap_points:false
          ~rows:3 ~columns:5 ~top_radius:1. ~bottom_radius:1. ~height:2. () |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "tube flat orientation and unset names match native")
      [Rdk.Parametric_generators.Tube_xyz,"XYZ";Tube_xzy,"XZY";Tube_yxz,"YXZ";Tube_yzx,"YZX";Tube_zxy,"ZXY";Tube_zyx,"ZYX"])
    [Sop.Axis_x,"X axis",Rdk.Parametric_generators.Tube_x;Axis_y,"Y axis",Tube_y;Axis_z,"Z axis",Tube_z;
     Axis_custom,"Custom axis",Tube_axis tube_axis];
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "tube refuses invalid controls at construction")
    [(fun () -> Sop.tube ~top_radius:0. ~bottom_radius:0. ());
     (fun () -> Sop.tube ~top_radius:(-1.) ());
     (fun () -> Sop.tube ~bottom_radius:nan ());
     (fun () -> Sop.tube ~radius_scale:Float.max_float ~top_radius:2. ());
     (fun () -> Sop.tube ~height:0. ());
     (fun () -> Sop.tube ~orientation:Sop.Axis_custom ~axis:Vec3.zero ());
     (fun () -> Sop.tube ~center:(Vec3.create infinity 0. 0.) ());
     (fun () -> Sop.tube ~rows:1 ());
     (fun () -> Sop.tube ~columns:2 ());
     (fun () -> Sop.tube ~rows:Sys.max_array_length ());
     (fun () -> Sop.tube ~uv_attribute:"N" ());
     (fun () -> Sop.tube ~connectivity:Rdk.Parametric_generators.Tube_points ~end_caps:false ~cap_group:""
         ~normals:Rdk.Parametric_generators.Tube_vertex_normals ());
     (fun () -> Sop.tube ~connectivity:Rdk.Parametric_generators.Tube_rows ());
     (fun () -> Sop.tube ~end_caps:false ())];
  check (Result.is_error (Node.apply_parameters tube ["end_caps",Parameter.Bool_value false]))
    "tube refuses invalid cap inspector edit";

  let torus = Sop.torus () in
  same_generator "torus defaults" ~typed:torus ~factory:Nodes.Torus.factory [];
  cache_identity ~companions:["u_end_caps",["u_wrap",Parameter.Bool_value false];
    "v_end_cap",["v_wrap",Parameter.Bool_value false;"v_end",Parameter.Float_value Float.pi]]
    "torus all fields" torus;
  List.iter (fun (connectivity,connectivity_choice,polygon) ->
    List.iter (fun (normals,normals_choice) ->
      List.iter (fun (normals_mode,normals_mode_choice,native_normals) ->
        if connectivity <> Rdk.Parametric_generators.Torus_points || native_normals <> Some Rdk.Parametric_generators.Torus_vertex_normals then
          List.iter (fun u_wrap -> List.iter (fun v_wrap ->
            List.iter (fun u_end_caps -> List.iter (fun v_end_cap ->
              let typed = Sop.torus ~connectivity ~normals ~normals_mode ~u_wrap ~v_wrap ~u_end_caps ~v_end_cap
                  ~u_start:0.1 ~u_end:2.4 ~v_start:(-0.8) ~v_end:1.8 ~rows:4 ~columns:5 ~major_radius:3. ~minor_radius:1. () in
              same_generator ("torus " ^ connectivity_choice ^ normals_choice ^ normals_mode_choice)
                ~typed ~factory:Nodes.Torus.factory ["connectivity",Parameter.Choice_value connectivity_choice;
                  "normals",Choice_value normals_choice;"normals_mode",Choice_value normals_mode_choice;
                  "u_wrap",Bool_value u_wrap;"v_wrap",Bool_value v_wrap;"u_end_caps",Bool_value u_end_caps;"v_end_cap",Bool_value v_end_cap;
                  "u_start",Float_value 0.1;"u_end",Float_value 2.4;"v_start",Float_value (-0.8);"v_end",Float_value 1.8;
                  "rows",Int_value 4;"columns",Int_value 5;"major_radius",Float_value 3.;"minor_radius",Float_value 1.];
              let native = Rdk.Parametric_generators.torus ~connectivity ?normals:native_normals ~u_wrap ~v_wrap ~u_end_caps ~v_end_cap
                  ~u_start:0.1 ~u_end:2.4 ~v_start:(-0.8) ~v_end:1.8 ~rows:4 ~columns:5 ~major_radius:3. ~minor_radius:1.
                  ~uv_attribute:"uv" () |> Result.get_ok in
              check (equal_geometry native (cook 1 typed)) "torus flat controls match native")
              (if polygon && not v_wrap then [false;true] else [false]))
              (if polygon && not u_wrap then [false;true] else [false])) [false;true]) [false;true])
        [Sop.Kernel_explicit,"Explicit",Some normals;Kernel_auto,"Auto",None])
      [Rdk.Parametric_generators.Torus_no_normals,"None";Torus_point_normals,"Point";Torus_vertex_normals,"Vertex"])
    [Rdk.Parametric_generators.Torus_triangles,"Triangles",true;Torus_alternating_triangles,"Alternating triangles",true;
     Torus_quads,"Quads",true;Torus_rows,"Rows",false;Torus_columns,"Columns",false;
     Torus_rows_and_columns,"Rows and columns",false;Torus_points,"Points",false];
  let torus_axis = Vec3.create 1. 2. 3. and torus_center = Vec3.create 2. (-1.) 3.
  and torus_rotation = Vec3.create 0.2 0.3 0.4 in
  List.iter (fun (orientation,orientation_choice,native_orientation) ->
    List.iter (fun (rotation_order,rotation_choice) ->
      let typed = Sop.torus ~orientation ~axis:torus_axis ~rotation_order ~center:torus_center ~rotation:torus_rotation
          ~uniform_scale:1.25 ~rows:4 ~columns:5 ~uv_attribute:" " () in
      same_generator ("torus orientation " ^ orientation_choice ^ rotation_choice)
        ~typed ~factory:Nodes.Torus.factory ["orientation",Parameter.Choice_value orientation_choice;
          "axis_x",Float_value 1.;"axis_y",Float_value 2.;"axis_z",Float_value 3.;
          "rotation_order",Choice_value rotation_choice;"center_x",Float_value 2.;"center_y",Float_value (-1.);"center_z",Float_value 3.;
          "rotation_x",Float_value 0.2;"rotation_y",Float_value 0.3;"rotation_z",Float_value 0.4;
          "uniform_scale",Float_value 1.25;"rows",Int_value 4;"columns",Int_value 5;"uv_attribute",Text_value " "];
      let native = Rdk.Parametric_generators.torus ~orientation:native_orientation ~rotation_order ~center:torus_center ~rotation:torus_rotation
          ~uniform_scale:1.25 ~rows:4 ~columns:5 ~major_radius:1. ~minor_radius:0.25 () |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "torus flat orientation and unset UV match native")
      [Rdk.Parametric_generators.Torus_xyz,"XYZ";Torus_xzy,"XZY";Torus_yxz,"YXZ";Torus_yzx,"YZX";Torus_zxy,"ZXY";Torus_zyx,"ZYX"])
    [Sop.Axis_x,"X axis",Rdk.Parametric_generators.Torus_x;Axis_y,"Y axis",Torus_y;Axis_z,"Z axis",Torus_z;
     Axis_custom,"Custom axis",Torus_axis torus_axis];
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "torus refuses invalid controls at construction")
    [(fun () -> Sop.torus ~major_radius:0. ());
     (fun () -> Sop.torus ~minor_radius:nan ());
     (fun () -> Sop.torus ~uniform_scale:Float.max_float ~major_radius:2. ());
     (fun () -> Sop.torus ~orientation:Sop.Axis_custom ~axis:Vec3.zero ());
     (fun () -> Sop.torus ~u_start:(-.Float.max_float) ~u_end:Float.max_float ());
     (fun () -> Sop.torus ~u_start:1. ~u_end:1. ());
     (fun () -> Sop.torus ~rows:2 ());
     (fun () -> Sop.torus ~u_wrap:false ~v_wrap:false ~columns:2 ~u_end_caps:true ());
     (fun () -> Sop.torus ~rows:Sys.max_array_length ());
     (fun () -> Sop.torus ~uv_attribute:"P" ());
     (fun () -> Sop.torus ~connectivity:Rdk.Parametric_generators.Torus_points ~normals:Rdk.Parametric_generators.Torus_vertex_normals ());
     (fun () -> Sop.torus ~connectivity:Rdk.Parametric_generators.Torus_rows ~u_wrap:false ~u_end_caps:true ());
     (fun () -> Sop.torus ~u_end_caps:true ());
     (fun () -> Sop.torus ~v_wrap:false ~v_end_cap:true ())];
  check (Result.is_error (Node.apply_parameters torus ["u_end_caps",Parameter.Bool_value true]))
    "torus refuses invalid cap inspector edit";

  let uv_sphere = Sop.uv_sphere () in
  same_generator "UV sphere defaults" ~typed:uv_sphere ~factory:Nodes.Uv_sphere.factory [];
  cache_identity "UV sphere all fields" uv_sphere;
  List.iter (fun (connectivity,connectivity_choice) ->
    List.iter (fun (normals,normals_choice) ->
      List.iter (fun (normals_mode,normals_mode_choice,native_normals) ->
        if connectivity <> Rdk.Uv_sphere.Sphere_points || native_normals <> Some Rdk.Uv_sphere.Sphere_vertex_normals then
          List.iter (fun unique_points_per_pole ->
            List.iter (fun triangular_poles ->
              let typed = Sop.uv_sphere ~radius:(Rays_math.Vec3.create (1.5) (2.) (0.75)) ~connectivity ~normals ~normals_mode ~unique_points_per_pole ~triangular_poles
                  ~segments:8 ~rings:4    () in
              same_generator ("UV sphere " ^ connectivity_choice ^ normals_choice ^ normals_mode_choice)
                ~typed ~factory:Nodes.Uv_sphere.factory ["connectivity",Parameter.Choice_value connectivity_choice;
                  "normals",Choice_value normals_choice;"normals_mode",Choice_value normals_mode_choice;
                  "unique_points_per_pole",Bool_value unique_points_per_pole;"triangular_poles",Bool_value triangular_poles;
                  "segments",Int_value 8;"rings",Int_value 4;"radius_x",Float_value 1.5;"radius_y",Float_value 2.;"radius_z",Float_value 0.75];
              let native = Rdk.Uv_sphere.run ~connectivity ?normals:native_normals ~unique_points_per_pole ~triangular_poles
                  ~segments:8 ~rings:4 ~radius_x:1.5 ~radius_y:2. ~radius_z:0.75 ~uv_attribute:"uv" ~radius:1. () |> Result.get_ok in
              check (equal_geometry native (cook 1 typed)) "UV sphere flattened normals match native") [false;true]) [false;true])
        [Sop.Kernel_explicit,"Explicit",Some normals;Kernel_auto,"Auto",None])
      [Rdk.Uv_sphere.Sphere_no_normals,"None";Sphere_point_normals,"Point";Sphere_vertex_normals,"Vertex"])
    [Rdk.Uv_sphere.Sphere_triangles,"Triangles";Sphere_alternating_triangles,"Alternating triangles";
     Sphere_quads,"Quads";Sphere_rows,"Rows";Sphere_columns,"Columns";Sphere_rows_and_columns,"Rows and columns";Sphere_points,"Points"];
  let sphere_axis = Vec3.create 1. 2. 3. and sphere_center = Vec3.create 2. (-1.) 3.
  and sphere_rotation = Vec3.create 0.2 0.3 0.4 in
  List.iter (fun (orientation,orientation_choice,native_orientation) ->
    List.iter (fun (rotation_order,rotation_choice) ->
      let typed = Sop.uv_sphere ~orientation ~axis:sphere_axis ~rotation_order ~center:sphere_center ~rotation:sphere_rotation
          ~uniform_scale:1.25 ~segments:8 ~rings:4 () in
      same_generator ("UV sphere orientation " ^ orientation_choice ^ rotation_choice)
        ~typed ~factory:Nodes.Uv_sphere.factory ["orientation",Parameter.Choice_value orientation_choice;
          "axis_x",Float_value 1.;"axis_y",Float_value 2.;"axis_z",Float_value 3.;
          "rotation_order",Choice_value rotation_choice;"center_x",Float_value 2.;"center_y",Float_value (-1.);"center_z",Float_value 3.;
          "rotation_x",Float_value 0.2;"rotation_y",Float_value 0.3;"rotation_z",Float_value 0.4;
          "uniform_scale",Float_value 1.25;"segments",Int_value 8;"rings",Int_value 4];
      let native = Rdk.Uv_sphere.run ~orientation:native_orientation ~rotation_order ~center:sphere_center ~rotation:sphere_rotation
          ~uniform_scale:1.25 ~segments:8 ~rings:4 ~uv_attribute:"uv" ~radius:1. () |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "UV sphere flat orientation matches native")
      [Rdk.Uv_sphere.Sphere_xyz,"XYZ";Sphere_xzy,"XZY";Sphere_yxz,"YXZ";Sphere_yzx,"YZX";Sphere_zxy,"ZXY";Sphere_zyx,"ZYX"])
    [Sop.Axis_x,"X axis",Rdk.Uv_sphere.Sphere_x;Axis_y,"Y axis",Sphere_y;Axis_z,"Z axis",Sphere_z;
     Axis_custom,"Custom axis",Sphere_axis sphere_axis];
  List.iter (fun (radius_x_mode,x_choice,x) ->
    List.iter (fun (radius_y_mode,y_choice,y) ->
      List.iter (fun (radius_z_mode,z_choice,z) ->
        let typed = Sop.uv_sphere ~radius:(Rays_math.Vec3.create (1.5) (2.) (0.75)) ~radius_x_mode ~radius_y_mode ~radius_z_mode
            ~base_radius:3. ~segments:8 ~rings:4 ~uv_attribute:" " () in
        same_generator "UV sphere per-axis fallback" ~typed ~factory:Nodes.Uv_sphere.factory
          ["radius_x_mode",Parameter.Choice_value x_choice;"radius_y_mode",Choice_value y_choice;"radius_z_mode",Choice_value z_choice;
           "radius_x",Float_value 1.5;"radius_y",Float_value 2.;"radius_z",Float_value 0.75;"base_radius",Float_value 3.;
           "segments",Int_value 8;"rings",Int_value 4;"uv_attribute",Text_value " "];
        let native = Rdk.Uv_sphere.run ?radius_x:x ?radius_y:y ?radius_z:z ~radius:3. ~segments:8 ~rings:4 () |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "UV sphere fallback radii and unset UV match native")
        [Sop.Kernel_explicit,"Explicit",Some 0.75;Kernel_auto,"Auto",None])
      [Sop.Kernel_explicit,"Explicit",Some 2.;Kernel_auto,"Auto",None])
    [Sop.Kernel_explicit,"Explicit",Some 1.5;Kernel_auto,"Auto",None];
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "UV sphere refuses invalid controls at construction")
    [(fun () -> Sop.uv_sphere ~base_radius:0. ());
     (fun () -> Sop.uv_sphere ~radius:(Rays_math.Vec3.create (nan) (1.) (1.))  ());
     (fun () -> Sop.uv_sphere ~radius:(Rays_math.Vec3.create (1.) (2.) (1.)) ~uniform_scale:Float.max_float  ());
     (fun () -> Sop.uv_sphere ~orientation:Sop.Axis_custom ~axis:Vec3.zero ());
     (fun () -> Sop.uv_sphere ~center:(Vec3.create infinity 0. 0.) ());
     (fun () -> Sop.uv_sphere ~segments:2 ());
     (fun () -> Sop.uv_sphere ~rings:max_int ());
     (fun () -> Sop.uv_sphere ~segments:Sys.max_array_length ~rings:2 ());
     (fun () -> Sop.uv_sphere ~uv_attribute:"N" ());
     (fun () -> Sop.uv_sphere ~connectivity:Rdk.Uv_sphere.Sphere_points ~normals:Rdk.Uv_sphere.Sphere_vertex_normals ())];
  check (Result.is_error (Node.apply_parameters uv_sphere ["radius_x",Parameter.Float_value nan]))
    "UV sphere refuses invalid inspector edit";

  let transfer_geometry = cook 1 (Sop.box ()) in
  let transfer_source = List.fold_left (fun geometry (owner,name,value) ->
      let count = match owner with Rdk.Attribute.Point -> Rdk.Geometry.point_count geometry
        | Vertex -> Rdk.Geometry.vertex_count geometry | Primitive -> Rdk.Geometry.primitive_count geometry | Detail -> 1 in
      Rdk.Attribute.create_owned ~owner ~name (Rdk.Attribute.Float (Array.make count value)) |> get
      |> fun attribute -> Rdk.Geometry.with_attribute attribute geometry |> get) transfer_geometry
      [Rdk.Attribute.Point,"point_value",2.;Vertex,"vertex_value",3.;Primitive,"primitive_value",4.;Detail,"detail_value",5.] in
  let transfer_source_input = Sop.snapshot transfer_source and transfer_target_input = Sop.snapshot transfer_geometry in
  let transferred_all = Sop.attribute_transfer_all transfer_source_input transfer_target_input in
  same_cook ~inputs:[transfer_target_input] "transfer all defaults" ~typed:transferred_all
    ~factory:Nodes.Attribute_transfer_all.factory [] transfer_source_input;
  cache_identity "transfer all all fields" transferred_all;
  List.iter (fun (mode,mode_choice,native_mode) ->
    List.iter (fun (falloff,falloff_choice,native_falloff) ->
      List.iter (fun (distance_mode,distance_choice,distance,blend_width) ->
        List.iter (fun (unmatched,unmatched_choice) ->
          let typed = Sop.attribute_transfer_all ~point_pattern:"point_*" ~vertex_pattern:"vertex_*"
              ~primitive_pattern:"primitive_*" ~detail_pattern:"detail_*" ~mode ~neighbors:3 ~power:1.5
              ~kernel_radius:2. ~distance_mode ~max_distance:2. ~blend_width ~falloff ~uniform_bias:0.7 ~unmatched
              transfer_source_input transfer_target_input in
          same_cook ~inputs:[transfer_target_input] ("transfer all " ^ mode_choice ^ falloff_choice ^ distance_choice ^ unmatched_choice)
            ~typed ~factory:Nodes.Attribute_transfer_all.factory
            ["point_pattern",Parameter.Text_value "point_*";"vertex_pattern",Text_value "vertex_*";
             "primitive_pattern",Text_value "primitive_*";"detail_pattern",Text_value "detail_*";
             "mode",Choice_value mode_choice;"neighbors",Int_value 3;"power",Float_value 1.5;
             "kernel_radius",Float_value 2.;"distance_mode",Choice_value distance_choice;"max_distance",Float_value 2.;
             "blend_width",Float_value blend_width;"falloff",Choice_value falloff_choice;
             "uniform_bias",Float_value 0.7;"unmatched",Choice_value unmatched_choice] transfer_source_input;
          let native = Rdk.Attribute_ops.transfer_all ~point_pattern:"point_*" ~vertex_pattern:"vertex_*"
              ~primitive_pattern:"primitive_*" ~detail_pattern:"detail_*" ~mode:native_mode ?max_distance:distance
              ~blend_width ~falloff:native_falloff ~unmatched ~source:transfer_source ~target:transfer_geometry () |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "transfer all flattened controls match native")
        [Rdk.Attribute_ops.Keep_target,"Keep target";Default_value,"Default value"])
      [Sop.Kernel_explicit,"Explicit",Some 2.,0.25;Kernel_auto,"Auto",None,0.])
    [Sop.Transfer_linear,"Linear",Rdk.Attribute_ops.Linear;Transfer_smoothstep,"Smoothstep",Smoothstep;
     Transfer_uniform,"Uniform",Uniform 0.7])
    [Sop.Transfer_nearest,"Nearest",Rdk.Attribute_ops.Nearest;
     Transfer_inverse,"Inverse distance",Inverse_distance {neighbors=3;power=1.5};
     Transfer_links,"Links kernel",Kernel {neighbors=3;radius=2.;kernel=Links};
     Transfer_renderman,"RenderMan kernel",Kernel {neighbors=3;radius=2.;kernel=RenderMan};
     Transfer_hart,"Hart kernel",Kernel {neighbors=3;radius=2.;kernel=Hart}];
  List.iter (fun pattern ->
    let values = List.map (fun name -> name,Parameter.Text_value (if name=pattern then "*" else " "))
        ["point_pattern";"vertex_pattern";"primitive_pattern";"detail_pattern"] in
    let owner_pattern name = if name = pattern then "*" else " " in
    let typed = Sop.attribute_transfer_all ~point_pattern:(owner_pattern "point_pattern")
        ~vertex_pattern:(owner_pattern "vertex_pattern") ~primitive_pattern:(owner_pattern "primitive_pattern")
        ~detail_pattern:(owner_pattern "detail_pattern") transfer_source_input transfer_target_input in
    let patterns = List.map (fun name -> if name=pattern then Some "*" else None)
        ["point_pattern";"vertex_pattern";"primitive_pattern";"detail_pattern"] in
    match patterns with
    | [point_pattern;vertex_pattern;primitive_pattern;detail_pattern] ->
        let native = Rdk.Attribute_ops.transfer_all ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
            ~max_distance:1. ~falloff:Rdk.Attribute_ops.Linear ~source:transfer_source ~target:transfer_geometry () |> Result.get_ok in
        same_cook ~inputs:[transfer_target_input] ("transfer all owner " ^ pattern)
          ~typed ~factory:Nodes.Attribute_transfer_all.factory values transfer_source_input;
        check (equal_geometry native (cook 1 typed)) "transfer all blank owner patterns are unset"
    | _ -> assert false) ["point_pattern";"vertex_pattern";"primitive_pattern";"detail_pattern"];
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "transfer all refuses invalid controls at construction")
    [(fun () -> Sop.attribute_transfer_all ~point_pattern:" " transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~vertex_pattern:"broken[" transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~neighbors:0 transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~mode:Sop.Transfer_inverse ~power:0. transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~kernel_radius:Float.max_float transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~max_distance:nan transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~distance_mode:Sop.Kernel_auto ~blend_width:0.1 transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~uniform_bias:1.1 transfer_source_input transfer_target_input);
     (fun () -> Sop.attribute_transfer_all ~max_distance:(sqrt Float.max_float) ~blend_width:(sqrt Float.max_float)
         transfer_source_input transfer_target_input)];
  check (Result.is_error (Node.apply_parameters transferred_all ["power",Parameter.Float_value nan]))
    "transfer all refuses invalid inspector edit";

  let facet_geometry = cook 1 (Sop.box ()) in
  let facet_input = Sop.snapshot facet_geometry in
  let faceted = Sop.facet facet_input in
  same_cook "facet defaults" ~typed:faceted ~factory:Nodes.Facet.factory [] facet_input;
  cache_identity "facet all fields" faceted;
  check (equal_geometry (Rdk.Facet.run ~cusp_angle:Float.pi facet_geometry |> Result.get_ok) (cook 1 faceted))
    "facet valid Lisp default matches native";
  List.iter (fun (group_owner,owner_choice,geometry,selection) ->
    let input = Sop.snapshot geometry in
    List.iter (fun (consolidation,consolidation_choice,point_distance,normal_distance) ->
      List.iter (fun (cusp_mode,cusp_choice,cusp) ->
        List.iter (fun unique_points ->
          let typed = Sop.facet ~group_owner ~group:"selection" ~consolidation ~consolidate_distance:0.01
              ~consolidate_normals_distance:0.02 ~cusp_mode ~cusp_angle:0.8 ~unique_points
              ~pre_compute_normals:true ~make_normals_unit_length:true ~post_compute_normals:true
              ~reverse_normals:true ~orient_polygons:true ~remove_degenerate:true ~make_planar:true input in
          same_cook ("facet " ^ owner_choice ^ consolidation_choice ^ cusp_choice)
            ~typed ~factory:Nodes.Facet.factory ["group_owner",Parameter.Choice_value owner_choice;
              "group",Text_value "selection";"consolidation",Choice_value consolidation_choice;
              "consolidate_distance",Float_value 0.01;"consolidate_normals_distance",Float_value 0.02;
              "cusp_mode",Choice_value cusp_choice;"cusp_angle",Float_value 0.8;"unique_points",Bool_value unique_points;
              "pre_compute_normals",Bool_value true;"make_normals_unit_length",Bool_value true;
              "post_compute_normals",Bool_value true;"reverse_normals",Bool_value true;
              "orient_polygons",Bool_value true;"remove_degenerate",Bool_value true;"make_planar",Bool_value true] input;
          let native = Rdk.Facet.run ~selection ?consolidate_distance:point_distance
              ?consolidate_normals_distance:normal_distance ?cusp_angle:cusp ~unique_points
              ~pre_compute_normals:true ~make_normals_unit_length:true ~post_compute_normals:true
              ~reverse_normals:true ~orient_polygons:true ~remove_degenerate:true ~make_planar:true geometry |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "facet flattened controls match native") [false;true])
        [Sop.Kernel_explicit,"Explicit",Some 0.8;Kernel_auto,"Auto",None])
      [Sop.Consolidation_none,"None",None,None;Consolidation_points,"Points",Some 0.01,None;
       Consolidation_normals,"Normals",None,Some 0.02])
    (let ordinary owner count = Rdk.Group.init ~owner ~name:"selection" count (fun i -> i mod 2 = 0) in
     let point = ordinary Rdk.Group.Point (Rdk.Geometry.point_count facet_geometry)
     and vertex = ordinary Rdk.Group.Vertex (Rdk.Geometry.vertex_count facet_geometry)
     and primitive = ordinary Rdk.Group.Primitive (Rdk.Geometry.primitive_count facet_geometry) in
     let topology = Rdk.Geometry.topology facet_geometry in
     let edge = Rdk.Edge_group.init ~topology ~index:(Rdk.Topology_index.create topology)
         ~name:"selection" (fun i -> i mod 2 = 0) in
     [Sop.Element_point,"Point",Rdk.Geometry.with_group point facet_geometry |> get,Rdk.Transform_ops.Selected_points point;
      Element_vertex,"Vertex",Rdk.Geometry.with_group vertex facet_geometry |> get,Selected_vertices vertex;
      Element_primitive,"Primitive",Rdk.Geometry.with_group primitive facet_geometry |> get,Selected_primitives primitive;
      Element_edge,"Edge",Rdk.Geometry.with_edge_group edge facet_geometry |> get,Selected_edges edge]);
  same_cook "facet inline removal" ~typed:(Sop.facet ~remove_inline_points:true ~inline_distance:0.1 facet_input)
    ~factory:Nodes.Facet.factory ["remove_inline_points",Parameter.Bool_value true;"inline_distance",Float_value 0.1] facet_input;
  check (equal_geometry (Rdk.Facet.run ~remove_inline_points:true ~inline_distance:0.1 ~cusp_angle:Float.pi facet_geometry
      |> Result.get_ok) (cook 1 (Sop.facet ~remove_inline_points:true ~inline_distance:0.1 facet_input)))
    "facet inline control matches native";
  same_cook "facet unset group" ~typed:(Sop.facet ~group:" " facet_input)
    ~factory:Nodes.Facet.factory ["group",Parameter.Text_value " "] facet_input;
  List.iter (fun make -> check (try ignore (make ());false with Invalid_argument _ -> true)
      "facet refuses invalid controls at construction")
    [(fun () -> Sop.facet ~consolidate_distance:nan facet_input);
     (fun () -> Sop.facet ~consolidate_normals_distance:(-1.) facet_input);
     (fun () -> Sop.facet ~inline_distance:infinity facet_input);
     (fun () -> Sop.facet ~cusp_mode:Sop.Kernel_auto ~cusp_angle:(Float.pi +. 1.) facet_input)];
  check (Result.is_error (Node.apply_parameters faceted ["consolidate_distance",Parameter.Float_value nan]))
    "facet refuses invalid inspector edit";

  let blast_geometry = cook 1 (Sop.box ()) in
  let blast_source attribute_owner group_owner =
    let count = match attribute_owner with Rdk.Attribute.Point -> Rdk.Geometry.point_count blast_geometry
      | Primitive -> Rdk.Geometry.primitive_count blast_geometry | _ -> assert false in
    let storage = match attribute_owner with
      | Rdk.Attribute.Point -> Rdk.Attribute.Float (Array.init count (fun i -> float_of_int (i mod 3) -. 1.))
      | _ -> Rdk.Attribute.Int (Array.init count (fun i -> i mod 3 - 1)) in
    let attribute = Rdk.Attribute.create_owned ~owner:attribute_owner ~name:"mask" storage |> get in
    let base = Rdk.Group.init ~owner:group_owner ~name:"base" count (fun i -> i < count - 1) in
    Rdk.Geometry.with_attribute attribute blast_geometry |> get |> Rdk.Geometry.with_group base |> get in
  let blast_input = Sop.snapshot (blast_source Rdk.Attribute.Point Rdk.Group.Point) in
  let attribute_blast = Sop.blast_by_attribute blast_input in
  same_cook "blast by attribute defaults" ~typed:attribute_blast ~factory:Nodes.Blast_by_attribute.factory [] blast_input;
  cache_identity ~companions:["remove_unused_points",["owner",Parameter.Choice_value "Primitives"]]
    "blast by attribute all fields" attribute_blast;
  List.iter (fun (owner,attribute_owner,group_owner,owner_choice) ->
    let geometry = blast_source attribute_owner group_owner in
    let input = Sop.snapshot geometry in
    List.iter (fun (mode,mode_choice,native_mode) ->
      List.iter (fun (output,output_choice,native_output) ->
        List.iter (fun invert -> List.iter (fun remove_unused_points ->
          let typed = Sop.blast_by_attribute ~owner ~mode ~threshold:0.25 ~minimum:(-0.5) ~maximum:0.5
              ~center:0. ~width:1. ~group:"base" ~invert ~output ~output_group:"picked" ~remove_unused_points input in
          same_cook ("blast attribute " ^ owner_choice ^ mode_choice ^ output_choice)
            ~typed ~factory:Nodes.Blast_by_attribute.factory ["owner",Parameter.Choice_value owner_choice;
              "mode",Choice_value mode_choice;"threshold",Float_value 0.25;"minimum",Float_value (-0.5);
              "maximum",Float_value 0.5;"center",Float_value 0.;"width",Float_value 1.;
              "group",Text_value "base";"invert",Bool_value invert;"output",Choice_value output_choice;
              "output_group",Text_value "picked";"remove_unused_points",Bool_value remove_unused_points] input;
          let native = Rdk.Blast_by_attribute.blast ~owner ~attribute:"mask" ~mode:native_mode ~output:native_output
              ~base:(Rdk.Geometry.find_group ~owner:group_owner "base" geometry |> Option.get)
              ~invert ~remove_unused_points geometry |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "blast attribute flattened fields match native")
          (if owner = Rdk.Blast_by_attribute.Blast_primitives && output = Sop.Blast_delete then [false;true] else [false])) [false;true])
        [Sop.Blast_delete,"Delete elements",Rdk.Blast_by_attribute.Blast_delete;
         Blast_group,"Create group",Blast_group "picked"])
      [Sop.Blast_below,"Below threshold",Rdk.Blast_by_attribute.Blast_below 0.25;
       Blast_range,"Range",Blast_range {minimum=(-0.5);maximum=0.5};
       Blast_width,"Center and width",Blast_width {center=0.;width=1.}])
    [Rdk.Blast_by_attribute.Blast_points,Rdk.Attribute.Point,Rdk.Group.Point,"Points";
     Blast_primitives,Primitive,Primitive,"Primitives"];
  same_cook "blast attribute unset base and inactive output name"
    ~typed:(Sop.blast_by_attribute ~group:" " ~output_group:" " blast_input)
    ~factory:Nodes.Blast_by_attribute.factory ["group",Parameter.Text_value " ";"output_group",Text_value " "] blast_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "blast attribute refuses invalid controls at construction")
    [(fun () -> Sop.blast_by_attribute ~attribute:" " blast_input);
     (fun () -> Sop.blast_by_attribute ~remove_unused_points:true blast_input);
     (fun () -> Sop.blast_by_attribute ~owner:Rdk.Blast_by_attribute.Blast_primitives
         ~output:Sop.Blast_group ~remove_unused_points:true blast_input);
     (fun () -> Sop.blast_by_attribute ~output:Sop.Blast_group ~output_group:" " blast_input);
     (fun () -> Sop.blast_by_attribute ~threshold:nan blast_input);
     (fun () -> Sop.blast_by_attribute ~maximum:infinity blast_input);
     (fun () -> Sop.blast_by_attribute ~mode:Sop.Blast_range ~minimum:2. ~maximum:1. blast_input);
     (fun () -> Sop.blast_by_attribute ~width:(-1.) blast_input);
     (fun () -> Sop.blast_by_attribute ~mode:Sop.Blast_width ~center:Float.max_float ~width:Float.max_float blast_input)];
  check (Result.is_error (Node.apply_parameters attribute_blast ["threshold",Parameter.Float_value nan]))
    "blast attribute refuses non-finite inspector edit";
  let gridded = Sop.grid () in
  same_generator "grid defaults" ~typed:gridded ~factory:Nodes.Grid.factory [];
  cache_identity "grid all fields" gridded;
  List.iter (fun (counts, count_choice) ->
    List.iter (fun (connectivity, connectivity_choice) ->
      List.iter (fun (orientation, plane_choice, native_orientation) ->
        List.iter (fun (width_mode, width_choice) -> List.iter (fun (height_mode, height_choice) ->
          let typed = Sop.grid ~counts ~connectivity ~orientation
              ~horizontal:(Vec3.create 1. 2. 0.5) ~vertical:(Vec3.create (-0.25) 0.75 2.)
              ~width_mode ~height_mode ~width:6. ~height:2. ~size:3. ~columns:4 ~rows:3
              ~center:(Vec3.create 2. 3. 4.) ~rotation:0.25 ~uv_attribute:"st" () in
          same_generator ("grid " ^ count_choice ^ connectivity_choice ^ plane_choice ^ width_choice ^ height_choice)
            ~typed ~factory:Nodes.Grid.factory ["counts", Parameter.Choice_value count_choice;
              "connectivity", Choice_value connectivity_choice; "orientation", Choice_value plane_choice;
              "horizontal_x", Float_value 1.; "horizontal_y", Float_value 2.; "horizontal_z", Float_value 0.5;
              "vertical_x", Float_value (-0.25); "vertical_y", Float_value 0.75; "vertical_z", Float_value 2.;
              "width_mode", Choice_value width_choice; "height_mode", Choice_value height_choice;
              "width", Float_value 6.; "height", Float_value 2.; "size", Float_value 3.; "columns", Int_value 4; "rows", Int_value 3;
              "center_x", Float_value 2.; "center_y", Float_value 3.; "center_z", Float_value 4.;
              "rotation", Float_value 0.25; "uv_attribute", Text_value "st"];
          let native = Rdk.Plane_generators.grid ~counts ~connectivity ~orientation:native_orientation
              ?width:(if width_mode = Sop.Kernel_auto then None else Some 6.)
              ?height:(if height_mode = Sop.Kernel_auto then None else Some 2.) ~size:3. ~columns:4 ~rows:3
              ~center:(Vec3.create 2. 3. 4.) ~rotation:0.25 ~uv_attribute:"st" () |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "grid flattened fields and Auto dimensions match native")
          [Sop.Kernel_explicit,"Explicit"; Kernel_auto,"Auto"])
        [Sop.Kernel_explicit,"Explicit"; Kernel_auto,"Auto"])
      [Sop.Plane_xy,"XY",Rdk.Plane_generators.Grid_xy; Plane_xz,"XZ",Grid_xz; Plane_yz,"YZ",Grid_yz;
       Plane_axes,"Custom axes",Grid_axes {horizontal=Vec3.create 1. 2. 0.5;vertical=Vec3.create (-0.25) 0.75 2.}])
    [Rdk.Plane_generators.Grid_points,"Points";Grid_rows,"Rows";Grid_columns,"Columns";
     Grid_rows_and_columns,"Rows and columns";Grid_quads,"Quads";Grid_triangles,"Triangles";
     Grid_alternating_triangles,"Alternating triangles";Grid_reverse_triangles,"Reverse triangles"])
    [Rdk.Plane_generators.Grid_divisions,"Divisions";Grid_point_counts,"Point counts"];
  same_generator "grid singleton point counts and unset UV"
    ~typed:(Sop.grid ~counts:Rdk.Plane_generators.Grid_point_counts ~connectivity:Rdk.Plane_generators.Grid_points
      ~columns:1 ~rows:1 ~uv_attribute:" " ()) ~factory:Nodes.Grid.factory
    ["counts",Parameter.Choice_value "Point counts";"connectivity",Choice_value "Points";
     "columns",Int_value 1;"rows",Int_value 1;"uv_attribute",Text_value " "];
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "grid refuses invalid controls at construction")
    [(fun () -> Sop.grid ~columns:0 ()); (fun () -> Sop.grid ~rows:0 ());
     (fun () -> Sop.grid ~counts:Rdk.Plane_generators.Grid_point_counts ~columns:1 ());
     (fun () -> Sop.grid ~counts:Rdk.Plane_generators.Grid_point_counts ~connectivity:Rdk.Plane_generators.Grid_rows ~columns:1 ());
     (fun () -> Sop.grid ~counts:Rdk.Plane_generators.Grid_point_counts ~connectivity:Rdk.Plane_generators.Grid_columns ~rows:1 ());
     (fun () -> Sop.grid ~size:0. ()); (fun () -> Sop.grid ~width:0. ()); (fun () -> Sop.grid ~height:0. ());
     (fun () -> Sop.grid ~center:(Vec3.create nan 0. 0.) ());
     (fun () -> Sop.grid ~orientation:Sop.Plane_axes ~horizontal:Vec3.unit_x ~vertical:Vec3.unit_x ());
     (fun () -> Sop.grid ~columns:max_int ());
     (fun () -> Sop.grid ~columns:Sys.max_array_length ~rows:10 ());
     (fun () -> Sop.grid ~counts:Rdk.Plane_generators.Grid_point_counts ~columns:Sys.max_array_length ~rows:2 ());
     (fun () -> Sop.grid ~uv_attribute:"P" ()); (fun () -> Sop.grid ~uv_attribute:"N" ())];
  check (Result.is_error (Node.apply_parameters gridded ["size",Parameter.Float_value 0.]))
    "grid refuses zero size inspector edit";
  let circled = Sop.circle () in
  same_generator "circle defaults" ~typed:circled ~factory:Nodes.Circle.factory [];
  cache_identity "circle all fields" circled;
  List.iter (fun (arc, arc_choice, native_arc) ->
    List.iter (fun (orientation, orientation_choice, native_orientation) ->
      List.iter (fun (radius_x_mode, x_choice) -> List.iter (fun (radius_y_mode, y_choice) ->
        List.iter (fun reverse ->
          let typed = Sop.circle ~arc ~start_angle:(-0.4) ~end_angle:2.2 ~orientation
              ~horizontal:(Vec3.create 1. 2. 0.5) ~vertical:(Vec3.create (-0.25) 0.75 2.)
              ~reverse ~center:(Vec3.create 2. 3. 4.) ~radius:2. ~radius_x_mode ~radius_x:3.
              ~radius_y_mode ~radius_y:1.5 ~rotation:0.25 ~uniform_scale:1.2 ~segments:12 () in
          same_generator ("circle " ^ arc_choice ^ orientation_choice ^ x_choice ^ y_choice)
            ~typed ~factory:Nodes.Circle.factory ["arc", Parameter.Choice_value arc_choice;
              "start_angle", Float_value (-0.4); "end_angle", Float_value 2.2;
              "orientation", Choice_value orientation_choice; "horizontal_x", Float_value 1.;
              "horizontal_y", Float_value 2.; "horizontal_z", Float_value 0.5;
              "vertical_x", Float_value (-0.25); "vertical_y", Float_value 0.75; "vertical_z", Float_value 2.;
              "reverse", Bool_value reverse; "center_x", Float_value 2.; "center_y", Float_value 3.; "center_z", Float_value 4.;
              "radius", Float_value 2.; "radius_x_mode", Choice_value x_choice; "radius_x", Float_value 3.;
              "radius_y_mode", Choice_value y_choice; "radius_y", Float_value 1.5;
              "rotation", Float_value 0.25; "uniform_scale", Float_value 1.2; "segments", Int_value 12];
          let native = Rdk.Plane_generators.circle ~arc:native_arc ~orientation:native_orientation
              ~reverse ~center:(Vec3.create 2. 3. 4.) ~radius:2.
              ?radius_x:(if radius_x_mode = Sop.Kernel_auto then None else Some 3.)
              ?radius_y:(if radius_y_mode = Sop.Kernel_auto then None else Some 1.5)
              ~rotation:0.25 ~uniform_scale:1.2 ~segments:12 () |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "circle flattened fields and Auto radii match native") [false;true])
        [Sop.Kernel_explicit,"Explicit"; Kernel_auto,"Auto"])
      [Sop.Kernel_explicit,"Explicit"; Kernel_auto,"Auto"])
    [Sop.Plane_xy,"XY",Rdk.Plane_generators.Circle_xy; Plane_xz,"XZ",Circle_xz;
     Plane_yz,"YZ",Circle_yz; Plane_axes,"Custom axes",Circle_axes {
       horizontal=Vec3.create 1. 2. 0.5; vertical=Vec3.create (-0.25) 0.75 2.}])
    [Sop.Circle_closed,"Closed",Rdk.Plane_generators.Circle_closed;
     Circle_open,"Open arc",Circle_open_arc {start_angle=(-0.4);end_angle=2.2};
     Circle_chord,"Chord closed",Circle_closed_arc {start_angle=(-0.4);end_angle=2.2};
     Circle_sliced,"Sliced",Circle_sliced_arc {start_angle=(-0.4);end_angle=2.2}];
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "circle refuses invalid controls at construction")
    [(fun () -> Sop.circle ~radius:0. ()); (fun () -> Sop.circle ~radius_x:0. ());
     (fun () -> Sop.circle ~radius_x:Float.max_float ~uniform_scale:2. ());
     (fun () -> Sop.circle ~radius_x:Float.min_float ~uniform_scale:Float.min_float ());
     (fun () -> Sop.circle ~radius_y:0. ()); (fun () -> Sop.circle ~uniform_scale:0. ());
     (fun () -> Sop.circle ~segments:2 ()); (fun () -> Sop.circle ~segments:max_int ());
     (fun () -> Sop.circle ~arc:Sop.Circle_sliced ~start_angle:1. ~end_angle:1. ());
     (fun () -> Sop.circle ~arc:Sop.Circle_open ~start_angle:(-.Float.max_float) ~end_angle:Float.max_float ());
     (fun () -> Sop.circle ~center:(Vec3.create nan 0. 0.) ());
     (fun () -> Sop.circle ~horizontal:(Vec3.create infinity 0. 0.) ());
     (fun () -> Sop.circle ~orientation:Sop.Plane_axes ~horizontal:Vec3.zero ());
     (fun () -> Sop.circle ~orientation:Sop.Plane_axes ~horizontal:Vec3.unit_x ~vertical:Vec3.unit_x ())];
  check (Result.is_error (Node.apply_parameters circled ["radius_x", Parameter.Float_value 0.]))
    "circle refuses zero-radius inspector edit";
  let spiraled = Sop.spiral () in
  same_generator "spiral defaults" ~typed:spiraled ~factory:Nodes.Spiral.factory [];
  cache_identity ~changes:["height_ramp", Parameter.Text_value "0:1,1:0.8";
      "radius_ramp", Text_value "0:1,1:1.2"] "spiral all fields" spiraled;
  List.iter (fun (extent_mode, extent_choice, extent) ->
    List.iter (fun (radius_mode, radius_choice, radius) ->
      List.iter (fun (divisions_mode, divisions_choice, divisions) ->
        List.iter (fun uniform_angle -> List.iter (fun (direction, direction_choice) ->
          let typed = Sop.spiral ~extent_mode ~turns:2. ~height:(-2.) ~pitch:(-1.)
              ~radius_mode ~start_radius:0.5 ~end_radius:2. ~radius_change:0.2 ~logarithmic_scale:1.2
              ~height_ramp:"0:0.8,0.5:1.2,1:1" ~radius_ramp:"0:1,0.4:0.7,1:1.1"
              ~radius_scale:1.3 ~direction ~start_angle:0.3 ~divisions_mode ~divisions:12 ~uniform_angle
              ~spiral_count:2 ~orientation:Sop.Axis_custom ~axis:(Vec3.create 1. 2. 3.)
              ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
              ~rotation_order:Rdk.Spiral.Spiral_zxy ~uniform_scale:1.2
              ~angle_attribute:"angle" ~x_axis_attribute:"xaxis" ~y_axis_attribute:"yaxis"
              ~tangent_attribute:"tangent" ~orient_attribute:"orient" ~distance_attribute:"distance" () in
          same_generator ("spiral " ^ extent_choice ^ radius_choice ^ divisions_choice ^ direction_choice)
            ~typed ~factory:Nodes.Spiral.factory ["extent_mode", Parameter.Choice_value extent_choice;
              "turns", Float_value 2.; "height", Float_value (-2.); "pitch", Float_value (-1.);
              "radius_mode", Choice_value radius_choice; "start_radius", Float_value 0.5;
              "end_radius", Float_value 2.; "radius_change", Float_value 0.2; "logarithmic_scale", Float_value 1.2;
              "height_ramp", Text_value "0:0.8,0.5:1.2,1:1"; "radius_ramp", Text_value "0:1,0.4:0.7,1:1.1";
              "radius_scale", Float_value 1.3; "direction", Choice_value direction_choice;
              "start_angle", Float_value 0.3; "divisions_mode", Choice_value divisions_choice; "divisions", Int_value 12;
              "uniform_angle", Bool_value uniform_angle; "spiral_count", Int_value 2;
              "orientation", Choice_value "Custom axis"; "axis_x", Float_value 1.; "axis_y", Float_value 2.; "axis_z", Float_value 3.;
              "center_x", Float_value 2.; "center_y", Float_value 3.; "center_z", Float_value 4.;
              "rotation_x", Float_value 0.2; "rotation_y", Float_value 0.3; "rotation_z", Float_value 0.4;
              "rotation_order", Choice_value "ZXY"; "uniform_scale", Float_value 1.2;
              "angle_attribute", Text_value "angle"; "x_axis_attribute", Text_value "xaxis"; "y_axis_attribute", Text_value "yaxis";
              "tangent_attribute", Text_value "tangent"; "orient_attribute", Text_value "orient"; "distance_attribute", Text_value "distance"];
          let native = Rdk.Spiral.run ~extent ~radius ~height_ramp:[0.,0.8;0.5,1.2;1.,1.]
              ~radius_ramp:[0.,1.;0.4,0.7;1.,1.1] ~radius_scale:1.3 ~direction ~start_angle:0.3
              ~divisions ~uniform_angle ~spiral_count:2 ~orientation:(Rdk.Spiral.Spiral_axis (Vec3.create 1. 2. 3.))
              ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.2 0.3 0.4)
              ~rotation_order:Rdk.Spiral.Spiral_zxy ~uniform_scale:1.2 ~angle_attribute:"angle"
              ~x_axis_attribute:"xaxis" ~y_axis_attribute:"yaxis" ~tangent_attribute:"tangent"
              ~orient_attribute:"orient" ~distance_attribute:"distance" () |> Result.get_ok in
          check (equal_geometry native (cook 1 typed)) "spiral flattened fields match native")
          [Rdk.Spiral.Spiral_counterclockwise, "Counterclockwise"; Spiral_clockwise, "Clockwise"])
          [false; true])
        [Sop.Spiral_per_curve, "Per curve", Rdk.Spiral.Spiral_divisions_per_curve 12;
         Spiral_per_turn, "Per turn", Spiral_divisions_per_turn 12])
      [Sop.Spiral_archimedean_change, "Archimedean change", Rdk.Spiral.Spiral_archimedean_change {start_radius=0.5; increase_per_turn=0.2};
       Spiral_archimedean_end, "Archimedean end", Spiral_archimedean_end {start_radius=0.5; end_radius=2.};
       Spiral_logarithmic_change, "Logarithmic change", Spiral_logarithmic_change {start_radius=0.5; scale_per_turn=1.2};
       Spiral_logarithmic_end, "Logarithmic end", Spiral_logarithmic_end {start_radius=0.5; end_radius=2.}])
    [Sop.Spiral_turns_height, "Turns and height", Rdk.Spiral.Spiral_turns {turns=2.; height=(-2.)};
     Spiral_height_pitch, "Height and pitch", Spiral_height_pitch {height=(-2.); pitch=(-1.)}];
  List.iter (fun (orientation, choice) -> List.iter (fun (rotation_order, order_choice) ->
    same_generator ("spiral orientation " ^ choice ^ order_choice)
      ~typed:(Sop.spiral ~orientation ~rotation_order ~rotation:(Vec3.create 0.2 0.3 0.4) ())
      ~factory:Nodes.Spiral.factory ["orientation", Parameter.Choice_value choice;
        "rotation_order", Choice_value order_choice; "rotation_x", Float_value 0.2;
        "rotation_y", Float_value 0.3; "rotation_z", Float_value 0.4])
    [Rdk.Spiral.Spiral_xyz,"XYZ"; Spiral_xzy,"XZY"; Spiral_yxz,"YXZ";
     Spiral_yzx,"YZX"; Spiral_zxy,"ZXY"; Spiral_zyx,"ZYX"])
    [Sop.Axis_x,"X axis"; Axis_y,"Y axis"; Axis_z,"Z axis"; Axis_custom,"Custom axis"];
  let constant_ramps = Sop.spiral ~height_ramp:"0.4:0.8" ~radius_ramp:"0.2:1.2" () in
  same_generator "spiral constant ramps" ~typed:constant_ramps ~factory:Nodes.Spiral.factory
    ["height_ramp", Parameter.Text_value "0.4:0.8"; "radius_ramp", Text_value "0.2:1.2"];
  check (equal_geometry (cook 1 constant_ramps)
      (Rdk.Spiral.run ~height_ramp:[0.4,0.8] ~radius_ramp:[0.2,1.2] () |> Result.get_ok))
    "spiral single-knot ramps retain native constant behavior";
  same_generator "spiral unset names and ramps" ~typed:(Sop.spiral ~height_ramp:" " ~radius_ramp:" "
      ~angle_attribute:" " ~x_axis_attribute:" " ~y_axis_attribute:" " ~tangent_attribute:" "
      ~orient_attribute:" " ~distance_attribute:" " ()) ~factory:Nodes.Spiral.factory
    (List.map (fun name -> name, Parameter.Text_value " ") ["height_ramp";"radius_ramp";
      "angle_attribute";"x_axis_attribute";"y_axis_attribute";"tangent_attribute";"orient_attribute";"distance_attribute"]);
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "spiral refuses invalid controls at construction")
    [(fun () -> Sop.spiral ~turns:0. ());
     (fun () -> Sop.spiral ~extent_mode:Sop.Spiral_height_pitch ~pitch:0. ());
     (fun () -> Sop.spiral ~extent_mode:Sop.Spiral_height_pitch ~pitch:(-1.) ());
     (fun () -> Sop.spiral ~radius_change:(-1.) ());
     (fun () -> Sop.spiral ~radius_mode:Sop.Spiral_logarithmic_change ~logarithmic_scale:0. ());
     (fun () -> Sop.spiral ~radius_mode:Sop.Spiral_logarithmic_change ~logarithmic_scale:Float.max_float ());
     (fun () -> Sop.spiral ~radius_mode:Sop.Spiral_logarithmic_end ~end_radius:0. ());
     (fun () -> Sop.spiral ~radius_scale:0. ()); (fun () -> Sop.spiral ~uniform_scale:0. ());
     (fun () -> Sop.spiral ~center:(Vec3.create nan 0. 0.) ());
     (fun () -> Sop.spiral ~orientation:Sop.Axis_custom ~axis:Vec3.zero ());
     (fun () -> Sop.spiral ~divisions:0 ());
     (fun () -> Sop.spiral ~divisions:max_int ()); (fun () -> Sop.spiral ~spiral_count:max_int ());
     (fun () -> Sop.spiral ~height_ramp:"0:1,0.5:1,0.5:2,1:1" ());
     (fun () -> Sop.spiral ~radius_ramp:"0:1,0.8:1" ());
     (fun () -> Sop.spiral ~radius_ramp:"0.2:nan" ());
     (fun () -> Sop.spiral ~angle_attribute:"P" ());
     (fun () -> Sop.spiral ~angle_attribute:"same" ~orient_attribute:"same" ())];
  check (Result.is_error (Node.apply_parameters spiraled ["turns", Parameter.Float_value 0.]))
    "spiral rejects zero-turn inspector edit";
  let velocity_sample offset = Sop.points [|(offset, 0., 0.); (offset +. 1., 2., 3.); (offset +. 2., 4., 6.)|]
      |> Sop.set_vector ~name:"v" ~value:(Vec3.create 1. 2. 3.)
      |> Sop.set_vector ~name:"incoming" ~value:(Vec3.create 2. 3. 4.)
      |> Sop.enumerate ~name:"id"
      |> Sop.group ~name:"selected" (Select.point_indices [|0; 2|]) in
  let current_velocity = velocity_sample 1. and previous_velocity = velocity_sample 0.
  and next_velocity = velocity_sample 3. in
  let velocity = Sop.point_velocity current_velocity (Some previous_velocity) None in
  same_cook ~optional_inputs:[Some current_velocity; Some previous_velocity; None]
    "point velocity defaults" ~typed:velocity ~factory:Nodes.Point_velocity.factory [] current_velocity;
  cache_identity ~companions:["compute_acceleration", ["approximation", Parameter.Choice_value "Central difference"]]
    "point velocity all fields" velocity;
  List.iter (fun (approximation, choice) ->
    List.iter (fun (unmatched, unmatched_choice) -> List.iter (fun acceleration ->
      let typed = Sop.point_velocity ~approximation ~dt:0.5 ~match_attribute:"id" ~unmatched
          ~group:"selected" ~add:(Vec3.create 1. 2. 3.) ~compute_acceleration:acceleration
          ~velocity_attribute:"computed" ~acceleration_attribute:"computed_accel"
          current_velocity (Some previous_velocity) (Some next_velocity) in
      same_cook ~optional_inputs:[Some current_velocity; Some previous_velocity; Some next_velocity]
        ("velocity deformation " ^ choice ^ unmatched_choice) ~typed ~factory:Nodes.Point_velocity.factory
        ["approximation", Parameter.Choice_value choice; "dt", Float_value 0.5;
         "match_attribute", Text_value "id"; "unmatched", Choice_value unmatched_choice;
         "group", Text_value "selected"; "add_x", Float_value 1.; "add_y", Float_value 2.; "add_z", Float_value 3.;
         "compute_acceleration", Bool_value acceleration; "velocity_attribute", Text_value "computed";
         "acceleration_attribute", Text_value "computed_accel"] current_velocity;
      let geometry = cook 1 current_velocity in
      let native = Rdk.Motion.point_velocity ~approximation ~dt:0.5 ~match_attribute:"id" ~unmatched
          ~points:(Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" geometry |> Option.get)
          ~add_velocity:(Vec3.create 1. 2. 3.) ~compute_acceleration:acceleration
          ~velocity_attribute:"computed" ~acceleration_attribute:"computed_accel"
          ~previous:(cook 1 previous_velocity) ~next:(cook 1 next_velocity) geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "velocity deformation matches native")
      (if approximation = Rdk.Motion.Central_difference then [false; true] else [false]))
      [Rdk.Motion.Velocity_unmatched_error, "Error"; Velocity_unmatched_zero, "Zero"])
    [Rdk.Motion.Backward_difference, "Backward difference"; Central_difference, "Central difference";
     Forward_difference, "Forward difference"];
  List.iter (fun (initialization, choice, native_initialization) ->
    List.iter (fun previous -> List.iter (fun next ->
      let typed = Sop.point_velocity ~initialization ~set:(Vec3.create 4. 5. 6.)
          ~source_attribute:"incoming" ~source_scale:0.5 ~add:Vec3.unit_y
          current_velocity previous next in
      same_cook ~optional_inputs:[Some current_velocity; previous; next]
        ("velocity initialization " ^ choice) ~typed ~factory:Nodes.Point_velocity.factory
        ["initialization", Parameter.Choice_value choice; "set_x", Float_value 4.; "set_y", Float_value 5.;
         "set_z", Float_value 6.; "source_attribute", Text_value "incoming"; "source_scale", Float_value 0.5;
         "add_y", Float_value 1.] current_velocity;
      let native = Rdk.Motion.point_velocity ~initialization:native_initialization
          ~add_velocity:Vec3.unit_y ?previous:(Option.map (cook 1) previous)
          ?next:(Option.map (cook 1) next) (cook 1 current_velocity) |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "velocity initialization matches native")
      [None; Some next_velocity]) [None; Some previous_velocity])
    [Sop.Velocity_keep, "Keep incoming", Rdk.Motion.Keep_incoming;
     Velocity_set, "Set value", Set_value (Vec3.create 4. 5. 6.);
     Velocity_from_attribute, "From attribute", From_attribute {name="incoming"; scale=0.5}];
  same_cook ~optional_inputs:[Some current_velocity; None; Some next_velocity]
    "velocity forward-only unset selection/match" ~typed:(Sop.point_velocity
      ~approximation:Rdk.Motion.Forward_difference ~group:" " ~match_attribute:" " current_velocity None (Some next_velocity))
    ~factory:Nodes.Point_velocity.factory ["approximation", Parameter.Choice_value "Forward difference";
      "group", Text_value " "; "match_attribute", Text_value " "] current_velocity;
  let partial_previous = Sop.points [|(0., 0., 0.)|] |> Sop.enumerate ~name:"id" in
  let zero_unmatched = Sop.point_velocity ~match_attribute:"id" ~unmatched:Rdk.Motion.Velocity_unmatched_zero
      current_velocity (Some partial_previous) None in
  same_cook ~optional_inputs:[Some current_velocity; Some partial_previous; None] "velocity unmatched zero"
    ~typed:zero_unmatched ~factory:Nodes.Point_velocity.factory
    ["match_attribute", Parameter.Text_value "id"; "unmatched", Choice_value "Zero"] current_velocity;
  let native_zero = Rdk.Motion.point_velocity ~match_attribute:"id" ~unmatched:Rdk.Motion.Velocity_unmatched_zero
      ~previous:(cook 1 partial_previous) (cook 1 current_velocity) |> Result.get_ok in
  check (equal_geometry native_zero (cook 1 zero_unmatched)) "velocity unmatched policy matches native";
  let unmatched_error = Sop.point_velocity ~match_attribute:"id" current_velocity (Some partial_previous) None in
  let session = Session.create ~max_entries:8 ~max_payload_bytes:200_000_000 |> get in
  let context = Context.create ~domains:1 () |> get in
  check (match Session.cook session ~context unmatched_error with
    | Error error -> error.code = "invalid_deformation" | Ok _ -> false)
    "velocity missing matches retain structured cook error";
  Session.close session;
  let velocity_leaf = Sop.snapshot (cook 1 current_velocity)
  and previous_leaf = Sop.snapshot (cook 1 previous_velocity)
  and next_leaf = Sop.snapshot (cook 1 next_velocity) in
  let dynamic_velocity = Sop.point_velocity ~label:"sample roles" velocity_leaf (Some previous_leaf) None in
  let document = List.fold_left (fun document node -> Edit_graph.add_node node document |> get)
      Edit_graph.empty [velocity_leaf; previous_leaf; next_leaf]
      |> Edit_graph.add_node ~factory:Nodes.Point_velocity.factory
          ~inputs:[|Some (Node.id velocity_leaf); Some (Node.id previous_leaf); None|] dynamic_velocity |> get
      |> Edit_graph.disconnect ~consumer:(Node.id dynamic_velocity) ~input_index:1 |> get
      |> Edit_graph.connect ~source:(Node.id next_leaf) ~consumer:(Node.id dynamic_velocity) ~input_index:2 |> get in
  let rebuilt = Edit_graph.compile_node document ~node_id:(Node.id dynamic_velocity) |> get in
  let edited = fst (Node.apply_parameters rebuilt ["approximation", Parameter.Choice_value "Forward difference"] |> get) in
  same_node "velocity rewiring and parameter edit retain next role"
    ~typed:(Sop.point_velocity ~approximation:Rdk.Motion.Forward_difference velocity_leaf None (Some next_leaf)) ~catalog:edited;
  check (Node.id edited = Node.id dynamic_velocity && Node.label edited = "sample roles")
    "velocity rewiring retains node identity and label";
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "point velocity refuses invalid controls at construction")
    [(fun () -> Sop.point_velocity ~dt:0. current_velocity None None);
     (fun () -> Sop.point_velocity ~dt:nan current_velocity None None);
     (fun () -> Sop.point_velocity ~set:(Vec3.create infinity 0. 0.) current_velocity None None);
     (fun () -> Sop.point_velocity ~source_scale:nan current_velocity None None);
     (fun () -> Sop.point_velocity ~add:(Vec3.create 0. nan 0.) current_velocity None None);
     (fun () -> Sop.point_velocity ~velocity_attribute:"P" current_velocity None None);
     (fun () -> Sop.point_velocity ~velocity_attribute:" " current_velocity None None);
     (fun () -> Sop.point_velocity ~compute_acceleration:true ~acceleration_attribute:"v" current_velocity None None);
     (fun () -> Sop.point_velocity ~compute_acceleration:true ~acceleration_attribute:"P" current_velocity None None);
     (fun () -> Sop.point_velocity ~compute_acceleration:true current_velocity None None);
     (fun () -> Sop.point_velocity ~compute_acceleration:true ~approximation:Rdk.Motion.Central_difference
         ~initialization:Sop.Velocity_keep current_velocity None None);
     (fun () -> Sop.point_velocity ~initialization:Sop.Velocity_from_attribute ~source_attribute:" " current_velocity None None)];
  check (Result.is_error (Node.apply_parameters velocity ["dt", Parameter.Float_value 0.]))
    "velocity refuses zero time step inspector edit";
  let fade_input = Sop.points [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|]
      |> Sop.set_float ~name:"start" ~value:2. |> Sop.set_float ~name:"hold" ~value:3.
      |> Sop.set_float ~name:"fade" ~value:0.8 |> Sop.set_color ~color:Vec3.unit_x
      |> Sop.group ~name:"selected" Select.all_points in
  let faded = Sop.attribute_fade fade_input None None in
  same_cook ~optional_inputs:[Some fade_input; None; None] "attribute fade defaults"
    ~typed:faded ~factory:Nodes.Attribute_fade.factory [] fade_input;
  cache_identity ~changes:["fade_in_ramp", Parameter.Text_value "0:0,0.5:0.3,1:1";
      "fade_out_ramp", Text_value "0:1,0.5:0.7,1:0"] "attribute fade all fields" faded;
  let fade_start = fade_input |> Sop.set_float ~name:"start" ~value:1.
  and fade_hold = fade_input |> Sop.set_float ~name:"hold" ~value:0.5 in
  List.iter (fun start_source -> List.iter (fun hold_source ->
    let typed = Sop.attribute_fade ~group:"selected" ~start_attribute:"start"
        ~start_retime_offset:1. ~start_retime_scale:0.75 ~hold_scale_attribute:"hold"
        ~frame_offset:(-10.) ~fade_in:8. ~fade_hold:6. ~fade_out:16.
        ~fade_in_ramp:"0:0,0.3:0.08,0.72:0.9,1:1"
        ~fade_out_ramp:"0:1,0.25:0.96,0.65:0.18,1:0" ~visualize:true
        fade_input start_source hold_source in
    same_cook ~optional_inputs:[Some fade_input; start_source; hold_source] "fade optional inputs and ramps"
      ~typed ~factory:Nodes.Attribute_fade.factory ["group", Parameter.Text_value "selected";
        "start_attribute", Text_value "start"; "start_retime_offset", Float_value 1.;
        "start_retime_scale", Float_value 0.75; "hold_scale_attribute", Text_value "hold";
        "frame_offset", Float_value (-10.); "fade_in", Float_value 8.; "fade_hold", Float_value 6.;
        "fade_out", Float_value 16.; "fade_in_ramp", Text_value "0:0,0.3:0.08,0.72:0.9,1:1";
        "fade_out_ramp", Text_value "0:1,0.25:0.96,0.65:0.18,1:0"; "visualize", Bool_value true] fade_input;
    let geometry = cook 1 fade_input in
    let native = Rdk.Attribute_fade.fade ~points:(Rdk.Geometry.find_group ~owner:Rdk.Group.Point "selected" geometry |> Option.get)
        ?start_source:(Option.map (cook 1) start_source) ?hold_source:(Option.map (cook 1) hold_source)
        ~start_attribute:"start" ~start_retime:(1., 0.75) ~hold_scale_attribute:"hold"
        ~frame:0. ~frame_offset:(-10.) ~fade_in:8. ~fade_hold:6. ~fade_out:16.
        ~fade_in_ramp:[0.,0.;0.3,0.08;0.72,0.9;1.,1.]
        ~fade_out_ramp:[0.,1.;0.25,0.96;0.65,0.18;1.,0.] ~visualize:true geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "fade matches native timing, inputs and ramps")
    [None; Some fade_hold]) [None; Some fade_start];
  same_cook ~optional_inputs:[Some fade_input; None; None] "fade unset names and ramps"
    ~typed:(Sop.attribute_fade ~group:" " ~start_attribute:" " ~hold_scale_attribute:" "
      ~fade_in_ramp:" " ~fade_out_ramp:" " fade_input None None)
    ~factory:Nodes.Attribute_fade.factory ["group", Parameter.Text_value " ";
      "start_attribute", Text_value " "; "hold_scale_attribute", Text_value " ";
      "fade_in_ramp", Text_value " "; "fade_out_ramp", Text_value " "] fade_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "fade refuses invalid controls at construction")
    [(fun () -> Sop.attribute_fade ~fade_attribute:" " fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_attribute:"P" fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_attribute:"Cd" ~visualize:true fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_in:(-1.) fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_hold:(-1.) fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_out:(-1.) fade_input None None);
     (fun () -> Sop.attribute_fade ~start_retime_scale:nan fade_input None None);
     (fun () -> Sop.attribute_fade ~frame_offset:infinity fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_in_ramp:"0:0,0.5:1,0.5:0,1:1" fade_input None None);
     (fun () -> Sop.attribute_fade ~fade_out_ramp:"0:1,0.8:0" fade_input None None)];
  check (Result.is_error (Node.apply_parameters faded ["fade_in_ramp", Parameter.Text_value "bad"]))
    "fade refuses malformed inspector ramp";
  let fade_leaf = Sop.snapshot (cook 1 fade_input)
  and start_leaf = Sop.snapshot (cook 1 fade_start)
  and hold_leaf = Sop.snapshot (cook 1 fade_hold) in
  let dynamic_fade = Sop.attribute_fade ~label:"optional fade" ~start_attribute:"start"
      ~hold_scale_attribute:"hold" ~fade_hold:3. fade_leaf (Some start_leaf) None in
  let document = List.fold_left (fun document node -> Edit_graph.add_node node document |> get)
      Edit_graph.empty [fade_leaf; start_leaf; hold_leaf]
      |> Edit_graph.add_node ~inputs:[|Some (Node.id fade_leaf); Some (Node.id start_leaf); None|]
          ~factory:Nodes.Attribute_fade.factory dynamic_fade |> get
      |> Edit_graph.disconnect ~consumer:(Node.id dynamic_fade) ~input_index:1 |> get
      |> Edit_graph.connect ~source:(Node.id hold_leaf) ~consumer:(Node.id dynamic_fade) ~input_index:2 |> get in
  let rebuilt = Edit_graph.compile_node document ~node_id:(Node.id dynamic_fade) |> get in
  same_node "fade optional rewiring retains hold role" ~typed:(Sop.attribute_fade ~start_attribute:"start"
      ~hold_scale_attribute:"hold" ~fade_hold:3. fade_leaf None (Some hold_leaf)) ~catalog:rebuilt;
  check (Node.id rebuilt = Node.id dynamic_fade && Node.label rebuilt = "optional fade")
    "fade rewiring retains node identity and label";
  let edited = fst (Node.apply_parameters rebuilt ["fade_hold", Parameter.Float_value 5.] |> get) in
  same_node "fade parameter edit retains optional roles" ~typed:(Sop.attribute_fade ~start_attribute:"start"
      ~hold_scale_attribute:"hold" ~fade_hold:5. fade_leaf None (Some hold_leaf)) ~catalog:edited;
  let mirror_geometry = cook 1 (Sop.box ()) in
  let mirror_source owner group_owner =
    let count = match owner with
      | Rdk.Attribute.Point -> Rdk.Geometry.point_count mirror_geometry
      | Vertex -> Rdk.Geometry.vertex_count mirror_geometry
      | Primitive -> Rdk.Geometry.primitive_count mirror_geometry | Detail -> assert false in
    let values offset = Array.init count (fun index -> float_of_int index +. offset) in
    let attributes = ["value", Rdk.Attribute.Float4 (Rdk.Packed.Float4.of_owned
        ~x:(values 1.) ~y:(values 2.) ~z:(values 3.) ~w:(values 4.) |> get);
      "text", Rdk.Attribute.Text (Array.init count (fun index -> "L" ^ string_of_int index));
      "map", Rdk.Attribute.Int (Array.init count (fun index -> if index < count / 2 then -1 else count - index - 1))] in
    let geometry = List.fold_left (fun geometry (name, storage) ->
      Rdk.Geometry.with_attribute (Rdk.Attribute.create_owned ~owner ~name storage |> get) geometry |> get)
      mirror_geometry attributes in
    let destination = Rdk.Group.init ~owner:group_owner ~name:"destination" count (fun index -> index >= count / 2) in
    let selection = Rdk.Group.init ~owner:group_owner ~name:"selection" count (fun _ -> true) in
    Rdk.Geometry.with_group destination geometry |> get |> Rdk.Geometry.with_group selection |> get in
  let mirror_input = Sop.snapshot (mirror_source Rdk.Attribute.Point Rdk.Group.Point) in
  let mirrored = Sop.attribute_mirror mirror_input in
  same_cook "attribute mirror defaults" ~typed:mirrored ~factory:Nodes.Attribute_mirror.factory [] mirror_input;
  cache_identity ~companions:["owner", ["method_", Parameter.Choice_value "Mapping attribute"]]
    "attribute mirror all fields" mirrored;
  List.iter (fun (owner, attribute_owner, group_owner, owner_choice) ->
    let geometry = mirror_source attribute_owner group_owner in
    let input = Sop.snapshot geometry in
    List.iter (fun (group_use, group_choice) ->
      List.iter (fun (transform, transform_choice, native_transform) ->
        let typed = Sop.attribute_mirror ~owner ~method_:Sop.Mirror_mapping
            ~mapping_attribute:"map" ~mapping_destination_group:"destination" ~attributes:"value text"
            ~group:"selection" ~group_use ~transform ~uv_origin_u:0.2 ~uv_origin_v:0.3
            ~uv_direction_u:2. ~uv_direction_v:3. ~replace_strings:true ~string_search:"L"
            ~string_replacement:"Right" ~output_mapping:"pair" ~source_group:"sources"
            ~destination_group:"destinations" input in
        same_cook ("mirror mapping " ^ owner_choice ^ group_choice ^ transform_choice) ~typed
          ~factory:Nodes.Attribute_mirror.factory ["owner", Parameter.Choice_value owner_choice;
            "method_", Choice_value "Mapping attribute"; "mapping_attribute", Text_value "map";
            "mapping_destination_group", Text_value "destination"; "attributes", Text_value "value text";
            "group", Text_value "selection"; "group_use", Choice_value group_choice;
            "transform", Choice_value transform_choice; "uv_origin_u", Float_value 0.2; "uv_origin_v", Float_value 0.3;
            "uv_direction_u", Float_value 2.; "uv_direction_v", Float_value 3.; "replace_strings", Bool_value true;
            "string_search", Text_value "L"; "string_replacement", Text_value "Right";
            "output_mapping", Text_value "pair"; "source_group", Text_value "sources";
            "destination_group", Text_value "destinations"] input;
        let find name = Rdk.Geometry.find_group ~owner:group_owner name geometry |> Option.get in
        let native = Rdk.Attribute_mirror.run ~owner ~group:(find "selection") ~group_use
            ~attributes:"value text" ~transform:native_transform ~string_replace:("L", "Right")
            ~output_mapping:"pair" ~source_group:"sources" ~destination_group:"destinations"
            ~method_:(Rdk.Attribute_mirror.Mirror_by_mapping {mapping_attribute="map"; destination_group=find "destination"})
            geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "mirror mapping matches native fields")
        [Sop.Mirror_copy, "Copy", Rdk.Attribute_mirror.Mirror_copy;
         Mirror_uv, "UV", Mirror_uv {origin_u=0.2; origin_v=0.3; direction_u=2.; direction_v=3.}])
      [Rdk.Attribute_mirror.Mirror_group_as_source, "Group is source";
       Mirror_group_as_destination, "Group is destination"];
    if owner <> Rdk.Attribute_mirror.Mirror_vertex_attributes then
      List.iter (fun (transform, choice, native_transform) ->
        let typed = Sop.attribute_mirror ~owner ~attributes:"value" ~transform ~distance:0.
            ~normal:(Vec3.create 2. 0. 0.) ~tolerance:0.01 input in
        same_cook ("mirror plane " ^ owner_choice ^ choice) ~typed ~factory:Nodes.Attribute_mirror.factory
          ["owner", Parameter.Choice_value owner_choice; "attributes", Text_value "value";
           "transform", Choice_value choice; "distance", Float_value 0.; "normal_x", Float_value 2.;
           "tolerance", Float_value 0.01] input;
        let native = Rdk.Attribute_mirror.run ~owner ~attributes:"value" ~transform:native_transform
            ~method_:(Rdk.Attribute_mirror.Mirror_by_plane {origin=Vec3.zero; normal=Vec3.create 2. 0. 0.;
              distance=0.; tolerance=0.01}) geometry |> Result.get_ok in
        check (equal_geometry native (cook 1 typed)) "mirror plane matches native fields")
        [Sop.Mirror_copy, "Copy", Rdk.Attribute_mirror.Mirror_copy;
         Mirror_uv, "UV", Mirror_uv {origin_u=0.; origin_v=0.; direction_u=1.; direction_v=0.};
         Mirror_vector, "Vector", Mirror_vector; Mirror_point, "Point", Mirror_point])
    [Rdk.Attribute_mirror.Mirror_point_attributes, Rdk.Attribute.Point, Rdk.Group.Point, "Point";
     Mirror_vertex_attributes, Vertex, Vertex, "Vertex"; Mirror_primitive_attributes, Primitive, Primitive, "Primitive"];
  same_cook "mirror unset names" ~typed:(Sop.attribute_mirror ~group:" " ~output_mapping:" "
      ~source_group:" " ~destination_group:" " mirror_input) ~factory:Nodes.Attribute_mirror.factory
    ["group", Parameter.Text_value " "; "output_mapping", Text_value " ";
     "source_group", Text_value " "; "destination_group", Text_value " "] mirror_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "mirror refuses invalid controls at construction")
    [(fun () -> Sop.attribute_mirror ~distance:(-1.) mirror_input);
     (fun () -> Sop.attribute_mirror ~tolerance:infinity mirror_input);
     (fun () -> Sop.attribute_mirror ~tolerance:Float.max_float mirror_input);
     (fun () -> Sop.attribute_mirror ~normal:Vec3.zero mirror_input);
     (fun () -> Sop.attribute_mirror ~origin:(Vec3.create nan 0. 0.) mirror_input);
     (fun () -> Sop.attribute_mirror ~origin:(Vec3.create Float.max_float 0. 0.) ~distance:Float.max_float mirror_input);
     (fun () -> Sop.attribute_mirror ~owner:Rdk.Attribute_mirror.Mirror_vertex_attributes mirror_input);
     (fun () -> Sop.attribute_mirror ~method_:Sop.Mirror_mapping ~mapping_attribute:" " mirror_input);
     (fun () -> Sop.attribute_mirror ~method_:Sop.Mirror_mapping ~mapping_destination_group:" " mirror_input);
     (fun () -> Sop.attribute_mirror ~method_:Sop.Mirror_mapping ~transform:Sop.Mirror_vector mirror_input);
     (fun () -> Sop.attribute_mirror ~transform:Sop.Mirror_uv ~uv_direction_u:0. mirror_input);
     (fun () -> Sop.attribute_mirror ~uv_origin_v:nan mirror_input);
     (fun () -> Sop.attribute_mirror ~replace_strings:true ~string_search:"" mirror_input);
     (fun () -> Sop.attribute_mirror ~source_group:"same" ~destination_group:"same" mirror_input);
     (fun () -> Sop.attribute_mirror ~attributes:"[" mirror_input)];
  check (Result.is_error (Node.apply_parameters mirrored ["normal_x", Parameter.Float_value 0.]))
    "mirror refuses zero normal inspector edit";
  let remap_geometry = cook 1 (Sop.box ()) in
  let remap_source owner kind =
    let count = match owner with
      | Rdk.Attribute.Point -> Rdk.Geometry.point_count remap_geometry
      | Vertex -> Rdk.Geometry.vertex_count remap_geometry
      | Primitive -> Rdk.Geometry.primitive_count remap_geometry | Detail -> 1 in
    let values () = Array.init count (fun index -> float_of_int (index mod 4) -. 1.) in
    let storage = match kind with
      | Sop.Numeric_scalar -> Rdk.Attribute.Float (values ())
      | Numeric_vec2 -> Float2 (Rdk.Packed.Float2.of_owned ~x:(values ()) ~y:(values ()) |> get)
      | Numeric_vec3 -> Float3 (Rdk.Packed.Float3.of_owned ~x:(values ()) ~y:(values ()) ~z:(values ()) |> get)
      | Numeric_vec4 -> Float4 (Rdk.Packed.Float4.of_owned ~x:(values ()) ~y:(values ()) ~z:(values ()) ~w:(values ()) |> get) in
    let attribute = Rdk.Attribute.create_owned ~owner ~name:"value" storage |> get in
    Rdk.Geometry.with_attribute attribute remap_geometry |> get in
  let remap_input = Sop.snapshot (remap_source Rdk.Attribute.Point Sop.Numeric_scalar) in
  let remapped = Sop.attribute_remap remap_input in
  same_cook "attribute remap defaults" ~typed:remapped ~factory:Nodes.Attribute_remap.factory [] remap_input;
  cache_identity ~changes:["ramp", Parameter.Text_value "0:0,0.5:0.2,1:1"]
    "attribute remap all fields" remapped;
  List.iter (fun (owner, owner_choice) ->
    List.iter (fun (kind, kind_choice, output_min, output_max) ->
      let geometry = remap_source owner kind in
      let input_node = Sop.snapshot geometry in
      List.iter (fun (policy, policy_choice) ->
        List.iter (fun (input_range, range_choice, input) ->
          let typed = Sop.attribute_remap ~owner ~kind ~into:"mapped" ~policy ~input_range
              ~output_min:(Vec3.create (-2.) (-3.) (-4.)) ~output_min_w:(-5.)
              ~output_max:(Vec3.create 2. 3. 4.) ~output_max_w:5.
              ~ramp:"0:0,0.5:0.2,1:1" input_node in
          same_cook ("remap " ^ owner_choice ^ " " ^ kind_choice ^ " " ^ policy_choice ^ " " ^ range_choice)
            ~typed ~factory:Nodes.Attribute_remap.factory ["owner", Parameter.Choice_value owner_choice;
              "kind", Choice_value kind_choice; "into", Text_value "mapped"; "policy", Choice_value policy_choice;
              "input_range", Choice_value range_choice; "output_min_x", Float_value (-2.);
              "output_min_y", Float_value (-3.); "output_min_z", Float_value (-4.); "output_min_w", Float_value (-5.);
              "output_max_x", Float_value 2.; "output_max_y", Float_value 3.; "output_max_z", Float_value 4.;
              "output_max_w", Float_value 5.; "ramp", Text_value "0:0,0.5:0.2,1:1"] input_node;
          let native = Rdk.Attribute_ops.remap ~owner ~name:"value" ~into:"mapped" ~input
              ~output_min ~output_max ~policy ~ramp:[0., 0.; 0.5, 0.2; 1., 1.] geometry
              |> Rdk.Error.unguard |> get in
          check (equal_geometry native (cook 1 typed)) "remap flat ranges/ramp preserve native channels")
          [Sop.Remap_automatic, "Automatic", Rdk.Attribute_ops.Remap_auto;
           Remap_explicit, "Explicit", Rdk.Attribute_ops.Remap_explicit {
             min = (match kind with Numeric_scalar -> Scalar 0. | Numeric_vec2 -> Vec2 Vec2.zero
               | Numeric_vec3 -> Vec3 Vec3.zero | Numeric_vec4 -> Vec4 (0., 0., 0., 0.));
             max = (match kind with Numeric_scalar -> Scalar 1. | Numeric_vec2 -> Vec2 (Vec2.create 1. 1.)
               | Numeric_vec3 -> Vec3 (Vec3.create 1. 1. 1.) | Numeric_vec4 -> Vec4 (1., 1., 1., 1.)) }])
        [Rdk.Attribute_ops.Remap_clamp, "Clamp"; Remap_cycle, "Cycle"; Remap_extrapolate, "Extrapolate"])
      [Sop.Numeric_scalar, "Scalar", Rdk.Attribute_ops.Scalar (-2.), Scalar 2.;
       Numeric_vec2, "Vector 2", Vec2 (Vec2.create (-2.) (-3.)), Vec2 (Vec2.create 2. 3.);
       Numeric_vec3, "Vector 3", Vec3 (Vec3.create (-2.) (-3.) (-4.)), Vec3 (Vec3.create 2. 3. 4.);
       Numeric_vec4, "Vector 4", Vec4 (-2., -3., -4., -5.), Vec4 (2., 3., 4., 5.)])
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"; Detail, "Detail"];
  let selected_remap = Sop.group ~name:"selected" (Select.point_indices [|0; 1|]) remap_input in
  same_cook "remap selection and unset destination"
    ~typed:(Sop.attribute_remap ~group:"selected" ~into:" " ~ramp:" " selected_remap)
    ~factory:Nodes.Attribute_remap.factory ["group", Parameter.Text_value "selected";
      "into", Text_value " "; "ramp", Text_value " "] selected_remap;
  same_cook "remap unset group" ~typed:(Sop.attribute_remap ~group:" " remap_input)
    ~factory:Nodes.Attribute_remap.factory ["group", Parameter.Text_value " "] remap_input;
  let remap_positions = Sop.box () in
  same_cook "remap canonical P" ~typed:(Sop.attribute_remap ~name:"P" ~kind:Sop.Numeric_vec3 remap_positions)
    ~factory:Nodes.Attribute_remap.factory ["name", Parameter.Text_value "P";
      "kind", Choice_value "Vector 3"] remap_positions;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "remap refuses invalid fields at construction")
    [ (fun () -> Sop.attribute_remap ~name:" " remap_input);
      (fun () -> Sop.attribute_remap ~owner:Rdk.Attribute.Detail ~group:"selected" remap_input);
      (fun () -> Sop.attribute_remap ~into:"P" remap_input);
      (fun () -> Sop.attribute_remap ~input_min:(Vec3.create nan 0. 0.) remap_input);
      (fun () -> Sop.attribute_remap ~output_max_w:infinity remap_input);
      (fun () -> Sop.attribute_remap ~input_range:Sop.Remap_explicit ~input_max:Vec3.zero remap_input);
      (fun () -> Sop.attribute_remap ~ramp:"0:0,0.5:0.2,0.5:0.7,1:1" remap_input);
      (fun () -> Sop.attribute_remap ~ramp:"0.2:0,1:1" remap_input);
      (fun () -> Sop.attribute_remap ~ramp:"0:0,0.8:1" remap_input);
      (fun () -> Sop.attribute_remap ~ramp:"0:nan,1:1" remap_input);
      (fun () -> Sop.attribute_remap ~ramp:"bad" remap_input) ];
  let copy_source = List.fold_left (fun input owner ->
      Sop.set_float ~owner ~name:"weight" ~value:10. input) (Sop.box ())
      [Rdk.Attribute.Point; Vertex; Primitive]
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"variant" ~value:10
      |> Sop.group ~name:"source" (Select.primitive_indices [|0|]) in
  let copy_targets = Sop.points [|(0., 0., 0.); (2., 0., 0.); (4., 0., 0.)|]
      |> Sop.set_float ~name:"weight" ~value:3.
      |> Sop.set_int ~name:"variant" ~value:10
      |> Sop.group ~name:"targets" (Select.point_indices [|0; 2|]) in
  let copied = Sop.copy_to_points copy_source copy_targets in
  same_cook ~inputs:[copy_targets] "copy to points defaults" ~typed:copied
    ~factory:Nodes.Copy_to_points.factory [] copy_source;
  cache_identity ~changes:["target_attributes", Parameter.Text_value "weight\tpoints\tcopy"]
    "copy to points all fields" copied;
  same_cook ~inputs:[copy_targets] "copy to points group restrictions"
    ~typed:(Sop.copy_to_points ~source_group:"source" ~target_group:"targets" copy_source copy_targets)
    ~factory:Nodes.Copy_to_points.factory ["source_group", Parameter.Text_value "source";
      "target_group", Text_value "targets"] copy_source;
  same_cook ~inputs:[copy_targets] "copy to points piece matching"
    ~typed:(Sop.copy_to_points ~piece_attribute:"variant" copy_source copy_targets)
    ~factory:Nodes.Copy_to_points.factory ["piece_attribute", Parameter.Text_value "variant"] copy_source;
  same_cook ~inputs:[copy_targets] "copy to points unset names"
    ~typed:(Sop.copy_to_points ~source_group:" " ~target_group:" " ~piece_attribute:" "
      ~target_attributes:" " copy_source copy_targets)
    ~factory:Nodes.Copy_to_points.factory ["source_group", Parameter.Text_value " ";
      "target_group", Text_value " "; "piece_attribute", Text_value " "; "target_attributes", Text_value " "] copy_source;
  let source_geometry = cook 1 copy_source and target_geometry = cook 1 copy_targets in
  List.iter (fun (owner_token, copy_target_owner) ->
    List.iter (fun (operation_token, copy_target_operation) ->
      let target_attributes = "weight\t" ^ owner_token ^ "\t" ^ operation_token in
      let typed = Sop.copy_to_points ~target_attributes copy_source copy_targets in
      same_cook ~inputs:[copy_targets] ("copy transfer " ^ owner_token ^ " " ^ operation_token)
        ~typed ~factory:Nodes.Copy_to_points.factory
        ["target_attributes", Parameter.Text_value target_attributes] copy_source;
      let native = Rdk.Instance_copy.copy_to_points
          ~target_attributes:[{ Rdk.Instance_copy.copy_target_pattern = "weight";
            copy_target_owner; copy_target_operation }]
          ~source:source_geometry ~targets:target_geometry () |> Rdk.Error.unguard |> get in
      check (equal_geometry native (cook 1 typed)) "copy target table preserves native operations")
      ["nothing", Rdk.Instance_copy.Copy_target_nothing; "copy", Copy_target_copy;
       "add", Copy_target_add; "subtract", Copy_target_subtract; "multiply", Copy_target_multiply])
    ["points", Rdk.Instance_copy.Copy_target_points; "vertices", Copy_target_vertices;
     "primitives", Copy_target_primitives];
  let packed = Sop.copy_to_points ~pack:true ~target_group:"targets" copy_source copy_targets in
  let packed_factory = from_factory Nodes.Copy_to_points.factory
      ["pack", Parameter.Bool_value true; "target_group", Text_value "targets"] [copy_source; copy_targets] in
  same_node "copy packed geometry" ~typed:packed ~catalog:packed_factory;
  let transforms domains graph =
    let context = Context.create ~domains ~grain:97 ~seed:42L () |> get in
    let session = Session.create ~max_entries:8 ~max_payload_bytes:200_000_000 |> get in
    let output = Session.cook session ~context graph |> Result.get_ok in
    Session.close session;
    Option.get output.instances in
  let expected = transforms 1 packed in
  List.iter (fun actual -> check (Marshal.to_string actual [Marshal.No_sharing]
      = Marshal.to_string expected [Marshal.No_sharing] && Array.length actual = 2)
      "copy packed transforms are byte-identical at both doors and domain counts")
    [transforms 4 packed; transforms 1 packed_factory; transforms 4 packed_factory];
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "copy to points refuses invalid fields at construction")
    [ (fun () -> Sop.copy_to_points ~target_attributes:"weight" copy_source copy_targets);
      (fun () -> Sop.copy_to_points ~target_attributes:"weight\tdetail\tcopy" copy_source copy_targets);
      (fun () -> Sop.copy_to_points ~target_attributes:"weight\tpoints\tbogus" copy_source copy_targets);
      (fun () -> Sop.copy_to_points ~target_attributes:"[\tpoints\tcopy" copy_source copy_targets);
      (fun () -> Sop.copy_to_points ~pack:true ~source_group:"source" copy_source copy_targets);
      (fun () -> Sop.copy_to_points ~pack:true ~piece_attribute:"variant" copy_source copy_targets) ];
  let exploded_input = Sop.box () in
  let exploded = Sop.exploded_view exploded_input in
  same_cook "exploded view defaults" ~typed:exploded ~factory:Nodes.Exploded_view.factory [] exploded_input;
  same_cook "exploded view advanced controls"
    ~typed:(Sop.exploded_view ~amount:(-0.2) ~scale:(Vec3.create 0. 2. (-1.))
      ~piece_attribute:"shard" ~noise_amount:0.5 ~noise_frequency:0. ~noise_seed:7 exploded_input)
    ~factory:Nodes.Exploded_view.factory ["amount", Parameter.Float_value (-0.2);
      "scale_x", Float_value 0.; "scale_y", Float_value 2.; "scale_z", Float_value (-1.);
      "piece_attribute", Text_value "shard"; "noise_amount", Float_value 0.5;
      "noise_frequency", Float_value 0.; "noise_seed", Int_value 7] exploded_input;
  check (equal_geometry (cook 1 exploded_input) (cook 1 exploded))
    "exploded view preserves source geometry";
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "exploded view refuses invalid controls at construction")
    [ (fun () -> Sop.exploded_view ~amount:nan exploded_input);
      (fun () -> Sop.exploded_view ~scale:(Vec3.create infinity 1. 1.) exploded_input);
      (fun () -> Sop.exploded_view ~noise_amount:nan exploded_input);
      (fun () -> Sop.exploded_view ~noise_frequency:(-1.) exploded_input);
      (fun () -> Sop.exploded_view ~piece_attribute:" " exploded_input) ];
  let join_input = Sop.merge [
      Sop.polyline [|(0., 0., 0.); (1., 0., 0.)|];
      Sop.polyline [|(2., 0., 0.); (1., 0., 0.)|];
      Sop.polyline [|(2., 0., 0.); (3., 0., 0.)|] ]
      |> Sop.group ~name:"selected" (Select.primitive_indices [|2; 0|]) in
  let joined = Sop.join_curves join_input in
  same_cook "join curves defaults" ~typed:joined ~factory:Nodes.Join_curves.factory [] join_input;
  cache_identity ~changes:["picked_ends", Parameter.Text_value "0:start"]
    "join curves all fields" joined;
  List.iter (fun orient_closest -> List.iter (fun connect_closest_ends ->
    List.iter (fun wrap ->
      same_cook "join curves orientation, ordering and wrapping"
        ~typed:(Sop.join_curves ~orient_closest ~connect_closest_ends ~wrap join_input)
        ~factory:Nodes.Join_curves.factory ["orient_closest", Parameter.Bool_value orient_closest;
          "connect_closest_ends", Bool_value connect_closest_ends; "wrap", Bool_value wrap] join_input)
      [false; true]) [false; true]) [false; true];
  List.iter (fun group_size ->
    same_cook "join curves grouped limits and retained originals"
      ~typed:(Sop.join_curves ~group:"selected" ~use_group_size:true ~group_size
        ~keep_originals:true ~only_connected:true ~tolerance:0.1 join_input)
      ~factory:Nodes.Join_curves.factory ["group", Parameter.Text_value "selected";
        "use_group_size", Bool_value true; "group_size", Int_value group_size;
        "keep_originals", Bool_value true; "only_connected", Bool_value true;
        "tolerance", Float_value 0.1] join_input) [1; 2; 5];
  let join_geometry = cook 1 join_input in
  List.iter (fun (picked_ends, picks) ->
    let typed = Sop.join_curves ~picked_ends join_input in
    same_cook "join curves explicit picked traversal" ~typed ~factory:Nodes.Join_curves.factory
      ["picked_ends", Parameter.Text_value picked_ends] join_input;
    let native = Rdk.Curve_topology.join_curves ~picked_ends:picks join_geometry
        |> Rdk.Error.unguard |> get in
    check (equal_geometry native (cook 1 typed)) "picked text preserves native traversal")
    ["2:end,0:start,1:end", [|
        { Rdk.Curve_topology.primitive = 2; end_ = Join_curve_end };
        { Rdk.Curve_topology.primitive = 0; end_ = Join_curve_start };
        { Rdk.Curve_topology.primitive = 1; end_ = Join_curve_end }|];
     "[]", [||]];
  same_cook "join curves unset selection" ~typed:(Sop.join_curves ~group:" " ~picked_ends:" " join_input)
    ~factory:Nodes.Join_curves.factory ["group", Parameter.Text_value " "; "picked_ends", Text_value " "] join_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "join curves refuses invalid fields at construction")
    [ (fun () -> Sop.join_curves ~group_size:0 join_input);
      (fun () -> Sop.join_curves ~tolerance:nan join_input);
      (fun () -> Sop.join_curves ~tolerance:(-1.) join_input);
      (fun () -> Sop.join_curves ~picked_ends:"0:start,0:end" join_input);
      (fun () -> Sop.join_curves ~picked_ends:"-1:start" join_input);
      (fun () -> Sop.join_curves ~picked_ends:"0:middle" join_input);
      (fun () -> Sop.join_curves ~picked_ends:"bad" join_input);
      (fun () -> Sop.join_curves ~picked_ends:"0:start" ~group:"selected" join_input);
      (fun () -> Sop.join_curves ~picked_ends:"0:start" ~connect_closest_ends:true join_input) ];
  check (Result.is_error (Node.apply_parameters joined
      ["picked_ends", Parameter.Text_value "0:start,0:end"]))
    "join curves inspector refuses duplicate picks";
  let jitter_input = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:3 ~rows:2 ~size:2. ()
      |> Sop.set_float ~name:"mask" ~value:0.5
      |> Sop.set_float ~name:"pscale" ~value:2.
      |> Sop.set_int ~name:"id" ~value:17
      |> Sop.group ~name:"selected" (Select.point_indices [|0; 1|]) in
  let jittered = Sop.point_jitter jitter_input in
  same_cook "point jitter defaults" ~typed:jittered ~factory:Nodes.Point_jitter.factory [] jitter_input;
  cache_identity "point jitter all fields" jittered;
  List.iter (fun (seed_mode, choice) ->
    List.iter (fun use_point_scale ->
      same_cook ("point jitter " ^ choice ^ " point scale " ^ string_of_bool use_point_scale)
        ~typed:(Sop.point_jitter ~seed_mode ~seed:23 ~use_point_scale ~group:"selected"
          ~mask_attribute:"mask" ~id_attribute:"id" ~scale:0.4
          ~axis:(Vec3.create 1. 0.5 0.25) jitter_input)
        ~factory:Nodes.Point_jitter.factory ["seed_mode", Parameter.Choice_value choice;
          "seed", Int_value 23; "use_point_scale", Bool_value use_point_scale;
          "group", Text_value "selected"; "mask_attribute", Text_value "mask";
          "id_attribute", Text_value "id"; "scale", Float_value 0.4;
          "axis_y", Float_value 0.5; "axis_z", Float_value 0.25] jitter_input) [false; true])
    [Sop.Kernel_explicit, "Explicit"; Kernel_auto, "Auto"];
  same_cook "point jitter unset names" ~typed:(Sop.point_jitter ~group:" " ~mask_attribute:" "
      ~id_attribute:" " ~scale:0. ~axis:Vec3.zero jitter_input)
    ~factory:Nodes.Point_jitter.factory ["group", Parameter.Text_value " "; "mask_attribute", Text_value " ";
      "id_attribute", Text_value " "; "scale", Float_value 0.; "axis_x", Float_value 0.;
      "axis_y", Float_value 0.; "axis_z", Float_value 0.] jitter_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "point jitter refuses invalid fields at construction")
    [ (fun () -> Sop.point_jitter ~scale:nan jitter_input);
      (fun () -> Sop.point_jitter ~scale:(-1.) jitter_input);
      (fun () -> Sop.point_jitter ~axis:(Vec3.create 1. infinity 1.) jitter_input);
      (fun () -> Sop.point_jitter ~axis:(Vec3.create (-1.) 1. 1.) jitter_input) ];
  let snap_input = Sop.points [|(0.2, 0., 0.); (0.3, 0., 0.); (1.2, 0., 0.)|]
      |> Sop.set_float ~name:"value" ~value:2.
      |> Sop.set_float ~name:"w" ~value:1.
      |> Sop.group ~name:"selected" (Select.point_indices [|0; 1; 2|]) in
  let snapped = Sop.snap_to_grid snap_input in
  same_cook "snap to grid defaults" ~typed:snapped ~factory:Nodes.Snap_to_grid.factory [] snap_input;
  cache_identity ~changes:["attribute_rules", Parameter.Text_value "value\tmaximum\t";
      "group_rules", Text_value "selected\tunion"] "snap to grid all fields" snapped;
  List.iter (fun (rounding, choice) ->
    List.iter (fun limit_distance ->
      same_cook ("snap to grid " ^ choice ^ " limited " ^ string_of_bool limit_distance)
        ~typed:(Sop.snap_to_grid ~group:"selected" ~rounding ~limit_distance ~max_distance:0.25
          ~spacing:(Vec3.create 1. 2. 3.) ~offset:(Vec3.create 0.25 0.5 0.75)
          ~snapped_group:"snapped" snap_input)
        ~factory:Nodes.Snap_to_grid.factory ["group", Parameter.Text_value "selected";
          "rounding", Choice_value choice; "limit_distance", Bool_value limit_distance;
          "max_distance", Float_value 0.25; "spacing_y", Float_value 2.; "spacing_z", Float_value 3.;
          "offset_x", Float_value 0.25; "offset_y", Float_value 0.5; "offset_z", Float_value 0.75;
          "snapped_group", Text_value "snapped"] snap_input) [false; true])
    [Rdk.Fuse_grid.Grid_nearest, "Nearest"; Grid_down, "Down"; Grid_up, "Up"];
  List.iter (fun (position, choice) ->
    same_cook ("snap to grid position " ^ choice)
      ~typed:(Sop.snap_to_grid ~fuse_points:true ~position ~weight_attribute:"w" snap_input)
      ~factory:Nodes.Snap_to_grid.factory ["fuse_points", Parameter.Bool_value true;
        "position", Choice_value choice; "weight_attribute", Text_value "w"] snap_input)
    [Rdk.Fuse_reduce.First_position, "First"; Least_point_position, "Least point";
     Greatest_point_position, "Greatest point"; Average_position, "Average";
     Minimum_position, "Minimum"; Maximum_position, "Maximum"; Mode_position, "Mode";
     Median_position, "Median"; Sum_position, "Sum"; Sum_squares_position, "Sum squares";
     Root_mean_square_position, "Root mean square"; Weighted_average_position, "Weighted average";
     Weighted_sum_position, "Weighted sum"; Minimum_weight_position, "Minimum weight";
     Maximum_weight_position, "Maximum weight"];
  let snap_geometry = cook 1 snap_input in
  List.iter (fun (token, method_) ->
    let attribute_rules = "value\t" ^ token ^ "\tw" in
    let typed = Sop.snap_to_grid ~fuse_points:true ~attribute_rules snap_input in
    same_cook ("snap to grid attribute rule " ^ token) ~typed
      ~factory:Nodes.Snap_to_grid.factory ["fuse_points", Parameter.Bool_value true;
        "attribute_rules", Text_value attribute_rules] snap_input;
    let native = Rdk.Fuse_grid.snap_to_grid ~fuse_points:true
        ~attribute_rules:[{ Rdk.Fuse_reduce.pattern = "value"; method_; weight_attribute = Some "w" }]
        snap_geometry |> Rdk.Error.unguard |> get in
    check (equal_geometry native (cook 1 typed)) ("snap attribute table preserves native " ^ token))
    [ "average", Rdk.Fuse_reduce.Attribute_average; "least", Attribute_least_point;
      "greatest", Attribute_greatest_point; "maximum", Attribute_maximum; "minimum", Attribute_minimum;
      "mode", Attribute_mode; "median", Attribute_median; "sum", Attribute_sum;
      "sum_squares", Attribute_sum_squares; "root_mean_square", Attribute_root_mean_square;
      "concatenate", Attribute_concatenate; "weighted_average", Attribute_weighted_average;
      "weighted_sum", Attribute_weighted_sum; "minimum_weight", Attribute_minimum_weight;
      "maximum_weight", Attribute_maximum_weight; "concatenate_weight_order", Attribute_concatenate_weight_order ];
  List.iter (fun (token, group_method) ->
    let group_rules = "selected\t" ^ token in
    let typed = Sop.snap_to_grid ~fuse_points:true ~group_rules snap_input in
    same_cook ("snap to grid group rule " ^ token) ~typed
      ~factory:Nodes.Snap_to_grid.factory ["fuse_points", Parameter.Bool_value true;
        "group_rules", Text_value group_rules] snap_input;
    let native = Rdk.Fuse_grid.snap_to_grid ~fuse_points:true
        ~group_rules:[{ Rdk.Fuse_reduce.group_pattern = "selected"; group_method }]
        snap_geometry |> Rdk.Error.unguard |> get in
    check (equal_geometry native (cook 1 typed)) ("snap group table preserves native " ^ token))
    ["least", Rdk.Fuse_reduce.Group_least_point; "greatest", Group_greatest_point;
     "union", Group_union; "intersection", Group_intersection; "most_common", Group_most_common];
  same_cook "snap to grid average attributes and unset names"
    ~typed:(Sop.snap_to_grid ~fuse_points:true ~attributes:Rdk.Fuse_reduce.Average_numeric
      ~group:" " ~weight_attribute:" " ~snapped_group:" " ~attribute_rules:" " ~group_rules:" " snap_input)
    ~factory:Nodes.Snap_to_grid.factory ["fuse_points", Parameter.Bool_value true;
      "attributes", Choice_value "Average numeric"; "group", Text_value " "; "weight_attribute", Text_value " ";
      "snapped_group", Text_value " "; "attribute_rules", Text_value " "; "group_rules", Text_value " "] snap_input;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "snap to grid refuses invalid values at construction")
    [ (fun () -> Sop.snap_to_grid ~spacing:Vec3.zero snap_input);
      (fun () -> Sop.snap_to_grid ~spacing:(Vec3.create nan 1. 1.) snap_input);
      (fun () -> Sop.snap_to_grid ~offset:(Vec3.create (-0.1) 0. 0.) snap_input);
      (fun () -> Sop.snap_to_grid ~offset:(Vec3.create 0. 1.1 0.) snap_input);
      (fun () -> Sop.snap_to_grid ~offset:(Vec3.create 0. 0. infinity) snap_input);
      (fun () -> Sop.snap_to_grid ~max_distance:(-1.) snap_input);
      (fun () -> Sop.snap_to_grid ~max_distance:nan snap_input);
      (fun () -> Sop.snap_to_grid ~attribute_rules:"value" snap_input);
      (fun () -> Sop.snap_to_grid ~attribute_rules:"value\tbogus\t" snap_input);
      (fun () -> Sop.snap_to_grid ~attribute_rules:"value\tweighted_average\t" snap_input);
      (fun () -> Sop.snap_to_grid ~attribute_rules:"[\taverage\t" snap_input);
      (fun () -> Sop.snap_to_grid ~group_rules:"selected\tbogus" snap_input) ];
  let clean_input = Sop.box () in
  let cleaned = Sop.clean clean_input in
  same_cook "clean Lisp defaults" ~typed:cleaned ~factory:Nodes.Clean.factory [] clean_input;
  cache_identity "clean all fields" cleaned;
  List.iter (fun (epsilon_mode, epsilon_choice) ->
    List.iter (fun (consolidate_mode, consolidate_choice) ->
      List.iter (fun (overlaps, overlap_choice) ->
        same_cook ("clean " ^ epsilon_choice ^ " " ^ consolidate_choice ^ " " ^ overlap_choice)
          ~typed:(Sop.clean ~epsilon_mode ~consolidate_mode ~overlaps ~epsilon:0.
            ~consolidate_distance:0.01 ~reverse_winding:true ~remove_nan_points:false
            ~remove_unused_points:false ~delete_unused_groups:false clean_input)
          ~factory:Nodes.Clean.factory ["epsilon_mode", Parameter.Choice_value epsilon_choice;
            "consolidate_mode", Choice_value consolidate_choice; "overlaps", Choice_value overlap_choice;
            "epsilon", Float_value 0.; "consolidate_distance", Float_value 0.01;
            "reverse_winding", Bool_value true; "remove_nan_points", Bool_value false;
            "remove_unused_points", Bool_value false; "delete_unused_groups", Bool_value false] clean_input)
        [Sop.Clean_keep_first, "Keep first"; Clean_delete_pairs, "Delete pairs"; Clean_overlap_auto, "Auto"])
      [Sop.Kernel_explicit, "Explicit"; Kernel_auto, "Auto"])
    [Sop.Kernel_explicit, "Explicit"; Kernel_auto, "Auto"];
  let clean_attributes = List.fold_left (fun input owner ->
      Sop.set_float ~owner ~name:"unused" ~value:2. input) clean_input
      [Rdk.Attribute.Point; Vertex; Primitive; Detail] in
  let deleted_attributes = Sop.clean ~point_attributes:"unused*" ~vertex_attributes:"unused*"
      ~primitive_attributes:"unused*" ~detail_attributes:"unused*" clean_attributes in
  List.iter (fun owner -> check
      (Rdk.Geometry.find_attribute ~owner "unused" (cook 1 deleted_attributes) = None)
      "clean deletes selected attributes on every owner")
    [Rdk.Attribute.Point; Vertex; Primitive; Detail];
  same_cook "clean deletion patterns and unset names"
    ~typed:(Sop.clean ~point_attributes:"unused*" ~vertex_attributes:"unused*"
      ~primitive_attributes:"unused*" ~detail_attributes:"unused*"
      ~point_groups:" " ~vertex_groups:" " ~primitive_groups:" " ~edge_groups:" " clean_attributes)
    ~factory:Nodes.Clean.factory ["point_attributes", Parameter.Text_value "unused*";
      "vertex_attributes", Text_value "unused*"; "primitive_attributes", Text_value "unused*";
      "detail_attributes", Text_value "unused*"; "point_groups", Text_value " ";
      "vertex_groups", Text_value " "; "primitive_groups", Text_value " "; "edge_groups", Text_value " "] clean_attributes;
  List.iter (fun make -> check (try ignore (make ()); false with Invalid_argument _ -> true)
      "clean refuses invalid values at construction")
    [ (fun () -> Sop.clean ~epsilon:nan clean_input);
      (fun () -> Sop.clean ~epsilon:(-1.) clean_input);
      (fun () -> Sop.clean ~consolidate_distance:infinity clean_input);
      (fun () -> Sop.clean ~consolidate_distance:(-1.) clean_input);
      (fun () -> Sop.clean ~point_attributes:"[" clean_input);
      (fun () -> Sop.clean ~edge_groups:"[" clean_input) ];
  List.iter (fun field -> check
      (Result.is_error (Node.apply_parameters cleaned [field, Parameter.Text_value "["]))
      ("clean refuses invalid " ^ field ^ " patterns during inspector rebuild"))
    ["point_attributes"; "vertex_attributes"; "primitive_attributes"; "detail_attributes";
     "point_groups"; "vertex_groups"; "primitive_groups"; "edge_groups"];
  let merge_inputs = List.init 5 (fun index -> Sop.line ~points:(index + 2)
      ~origin:(Vec3.create (float_of_int index) 0. 0.) ()) in
  List.iter (fun count ->
    let inputs = List.filteri (fun index _ -> index < count) merge_inputs in
    same_node (Printf.sprintf "merge %d inputs" count)
      ~typed:(Sop.merge inputs)
      ~catalog:(from_factory Nodes.Merge.factory [] inputs);
    same_node (Printf.sprintf "merge %d tagged inputs" count)
      ~typed:(Sop.merge ~source_attribute:"source" ~source_base:(-3) inputs)
      ~catalog:(from_factory Nodes.Merge.factory ["source_attribute", Parameter.Text_value "source";
        "source_base", Int_value (-3)] inputs)) [1; 3; 5];
  let merged = Sop.merge ~label:"ordered merge" ~source_attribute:"source" ~source_base:7 merge_inputs in
  cache_identity "merge all fields" merged;
  same_node "merge unset source name" ~typed:(Sop.merge ~source_attribute:" " merge_inputs)
    ~catalog:(from_factory Nodes.Merge.factory ["source_attribute", Parameter.Text_value " "] merge_inputs);
  check (try ignore (Sop.merge []); false with Invalid_argument _ -> true)
    "merge requires its first rest input at construction";
  let initial_inputs = List.filteri (fun index _ -> index < 3) merge_inputs in
  let dynamic_merge = Sop.merge ~label:"ordered merge" ~source_attribute:"source" ~source_base:7 initial_inputs in
  let document = List.fold_left (fun document node -> Edit_graph.add_node node document |> get)
      Edit_graph.empty merge_inputs
      |> Edit_graph.add_node ~factory:Nodes.Merge.factory dynamic_merge |> get in
  let extra = List.nth merge_inputs 3 in
  let document = document
      |> Edit_graph.connect ~source:(Node.id extra) ~consumer:(Node.id dynamic_merge) ~input_index:3 |> get
      |> Edit_graph.disconnect ~consumer:(Node.id dynamic_merge) ~input_index:1 |> get in
  let rebuilt = Edit_graph.compile_node document ~node_id:(Node.id dynamic_merge) |> get in
  let retained_inputs = List.filteri (fun index _ -> index = 0 || index = 2 || index = 3) merge_inputs in
  same_node "merge rest append and sparse disconnection"
    ~typed:(Sop.merge ~source_attribute:"source" ~source_base:7 retained_inputs) ~catalog:rebuilt;
  check (Node.id rebuilt = Node.id dynamic_merge && Node.label rebuilt = "ordered merge")
    "merge rest rewiring preserves node identity and label";
  let edited = fst (Node.apply_parameters rebuilt
      ["source_base", Parameter.Int_value 11] |> get) in
  same_node "merge parameter rebuild retains rewired inputs"
    ~typed:(Sop.merge ~source_attribute:"source" ~source_base:11 retained_inputs) ~catalog:edited;
  let disconnected = Edit_graph.disconnect ~consumer:(Node.id dynamic_merge)
      ~input_index:0 document |> get in
  check (Result.is_error (Edit_graph.compile_node disconnected ~node_id:(Node.id dynamic_merge)))
    "merge refuses a disconnected required rest input";
  let platonic = Sop.platonic () in
  same_generator "platonic Lisp defaults" ~typed:platonic ~factory:Nodes.Platonic.factory [];
  cache_identity "platonic all fields" platonic;
  List.iter (fun (kind, choice) ->
    List.iter (fun (normals, normal_choice) ->
      same_generator ("platonic " ^ choice ^ " " ^ normal_choice)
        ~typed:(Sop.platonic ~kind ~normals ~radius:2. ()) ~factory:Nodes.Platonic.factory
        ["kind", Parameter.Choice_value choice; "normals", Choice_value normal_choice; "radius", Float_value 2.])
      [Rdk.Parametric_generators.Platonic_no_normals, "None"; Platonic_point_normals, "Point";
        Platonic_vertex_normals, "Vertex"])
    [Rdk.Parametric_generators.Platonic_tetrahedron, "Tetrahedron"; Platonic_cube, "Cube";
      Platonic_octahedron, "Octahedron"; Platonic_icosahedron, "Icosahedron";
      Platonic_dodecahedron, "Dodecahedron"; Platonic_soccer_ball, "Soccer ball"];
  List.iter (fun (orientation, choice) ->
    List.iter (fun (rotation_order, order_choice) ->
      same_generator ("platonic " ^ choice ^ " " ^ order_choice)
        ~typed:(Sop.platonic ~orientation ~axis:(Vec3.create 1. 2. 3.)
          ~center:(Vec3.create 2. 3. 4.) ~rotation:(Vec3.create 0.1 0.2 0.3)
          ~rotation_order ~face_groups:"faces" ()) ~factory:Nodes.Platonic.factory
        ["orientation", Parameter.Choice_value choice; "axis_x", Float_value 1.; "axis_y", Float_value 2.;
          "axis_z", Float_value 3.; "center_x", Float_value 2.; "center_y", Float_value 3.; "center_z", Float_value 4.;
          "rotation_x", Float_value 0.1; "rotation_y", Float_value 0.2; "rotation_z", Float_value 0.3;
          "rotation_order", Choice_value order_choice; "face_groups", Text_value "faces"])
      [Rdk.Parametric_generators.Platonic_xyz, "XYZ"; Platonic_xzy, "XZY"; Platonic_yxz, "YXZ";
        Platonic_yzx, "YZX"; Platonic_zxy, "ZXY"; Platonic_zyx, "ZYX"])
    [Sop.Axis_x, "X axis"; Axis_y, "Y axis"; Axis_z, "Z axis"; Axis_custom, "Custom axis"];
  same_generator "platonic unset prefix" ~typed:(Sop.platonic ~face_groups:" " ())
    ~factory:Nodes.Platonic.factory ["face_groups", Parameter.Text_value " "];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "platonic refuses invalid values at construction")
    [ (fun () -> Sop.platonic ~radius:0. ()); (fun () -> Sop.platonic ~radius:nan ());
      (fun () -> Sop.platonic ~orientation:Sop.Axis_custom ~axis:Vec3.zero ());
      (fun () -> Sop.platonic ~center:(Vec3.create nan 0. 0.) ());
      (fun () -> Sop.platonic ~rotation:(Vec3.create 0. infinity 0.) ()) ];
  let origins = Sop.point_generate_origin () in
  same_generator "origin point generate defaults" ~typed:origins ~factory:Nodes.Point_generate.factory [];
  cache_identity "origin point generate all fields" origins;
  same_generator "origin point generate metadata" ~typed:(Sop.point_generate_origin ~points:7
      ~generated_group:"made" ~source_point_attribute:"from_point" ~source_index_attribute:"from_index" ())
    ~factory:Nodes.Point_generate.factory ["points", Parameter.Int_value 7;
      "generated_group", Text_value "made"; "source_point_attribute", Text_value "from_point";
      "source_index_attribute", Text_value "from_index"];
  same_generator "origin point generate unset group" ~typed:(Sop.point_generate_origin ~generated_group:" " ())
    ~factory:Nodes.Point_generate.factory ["generated_group", Parameter.Text_value " "];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "origin point generate refuses invalid fields at construction")
    [ (fun () -> Sop.point_generate_origin ~points:0 ());
      (fun () -> Sop.point_generate_origin ~points:51 ());
      (fun () -> Sop.point_generate_origin ~source_point_attribute:" " ());
      (fun () -> Sop.point_generate_origin ~source_index_attribute:"P" ());
      (fun () -> Sop.point_generate_origin ~source_point_attribute:"same" ~source_index_attribute:"same" ()) ];
  let color_input = Sop.line ~origin:Vec3.zero ~direction:Vec3.unit_y ~length:2. () in
  let profile = Sop.polyline [|(1., -1., 0.); (2., 0., 0.); (1., 1., 0.)|]
      |> Sop.group ~name:"profile" Select.all_primitives in
  let edge_input = Sop.polyline [|(0., 0., 0.); (1., 0., 0.); (3., 0., 0.)|]
      |> Sop.set_float ~name:"value" ~value:2.
      |> Sop.group ~name:"tip" (Select.point_indices [|2|])
      |> Sop.group ~name:"all" Select.all_points in
  let edge_transport = Sop.edge_transport edge_input in
  same_cook "edge transport defaults" ~typed:edge_transport ~factory:Nodes.Edge_transport.factory [] edge_input;
  cache_identity ~companions:transport_cache_companions
    "edge transport all fields" edge_transport;
  List.iter (fun (roots, root_choice) ->
    List.iter (fun (direction, direction_choice) ->
      List.iter (fun (operation, choice) ->
        same_cook ("edge transport " ^ root_choice ^ " " ^ direction_choice ^ " " ^ choice)
          ~typed:(Sop.edge_transport ~roots ~root_group:"tip" ~point_group:"all" ~direction ~operation
            ~root_value:Rdk.Edge_transport.Transport_root_hold
            ~scale_by_edge_length:(operation = Rdk.Edge_transport.Transport_total) edge_input)
          ~factory:Nodes.Edge_transport.factory ["roots", Parameter.Choice_value root_choice;
            "root_group", Text_value "tip"; "point_group", Text_value "all";
            "direction", Choice_value direction_choice; "operation", Choice_value choice;
            "root_value", Choice_value "Hold";
            "scale_by_edge_length", Bool_value (operation = Rdk.Edge_transport.Transport_total)] edge_input)
        [Rdk.Edge_transport.Transport, "Transport"; Transport_from_root, "From root"; Transport_total, "Total";
          Transport_maximum, "Maximum"; Transport_minimum, "Minimum"])
      [Rdk.Edge_transport.Transport_forward, "Forward"; Transport_backward, "Backward"])
    [Sop.Transport_first, "First point"; Transport_last, "Last point"; Transport_group, "Root group"];
  List.iter (fun (split, split_choice) ->
    List.iter (fun (merge, merge_choice) ->
      List.iter (fun (normalization, choice) ->
        same_cook ("edge transport " ^ split_choice ^ " " ^ merge_choice ^ " " ^ choice)
          ~typed:(Sop.edge_transport ~operation:Rdk.Edge_transport.Transport_total ~integrate_constant:true
            ~split ~merge ~normalization ~attribute:"distance" edge_input)
          ~factory:Nodes.Edge_transport.factory ["operation", Parameter.Choice_value "Total";
            "integrate_constant", Bool_value true; "split", Choice_value split_choice;
            "merge", Choice_value merge_choice; "normalization", Choice_value choice;
            "attribute", Text_value "distance"] edge_input)
        [Rdk.Edge_transport.Transport_no_normalization, "None"; Transport_normalize_components, "Per component";
          Transport_normalize_global, "Global"])
      [Rdk.Edge_transport.Transport_merge_add, "Add"; Transport_merge_maximum, "Maximum"; Transport_merge_minimum, "Minimum"])
    [Rdk.Edge_transport.Transport_copy, "Copy"; Transport_split, "Split"];
  same_cook "edge transport unset point group" ~typed:(Sop.edge_transport ~point_group:" " edge_input)
    ~factory:Nodes.Edge_transport.factory ["point_group", Parameter.Text_value " "] edge_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "edge transport refuses invalid attributes at construction")
    [ (fun () -> Sop.edge_transport ~attribute:"" edge_input);
      (fun () -> Sop.edge_transport ~attribute:"P" edge_input);
      (fun () -> Sop.edge_transport ~integrate_constant:true edge_input);
      (fun () -> Sop.edge_transport ~scale_by_edge_length:true edge_input);
      (fun () -> Sop.edge_transport_curves ~integrate_constant:true edge_input);
      (fun () -> Sop.edge_transport_curves ~scale_by_edge_length:true edge_input);
      (fun () -> Sop.edge_transport_parent ~integrate_constant:true edge_input);
      (fun () -> Sop.edge_transport_parent ~scale_by_edge_length:true edge_input) ];
  let revolved = Sop.revolve profile in
  same_cook "revolve defaults" ~typed:revolved ~factory:Nodes.Revolve.factory [] profile;
  cache_identity "revolve all fields" revolved;
  List.iter (fun (revolve_type, type_choice) ->
    List.iter (fun (connectivity, choice) ->
      same_cook ("revolve " ^ type_choice ^ " " ^ choice) ~typed:(Sop.revolve ~revolve_type ~connectivity
          ~group:"profile" ~divisions:8 ~start_angle:0.2 ~end_angle:2.5 ~reverse_cross_sections:true
          ~origin:(Vec3.create 0.1 0.2 0.3) ~axis:(Vec3.create 1. 2. 3.) ~uv_attribute:"st" profile)
        ~factory:Nodes.Revolve.factory ["revolve_type", Parameter.Choice_value type_choice;
          "connectivity", Choice_value choice; "group", Text_value "profile"; "divisions", Int_value 8;
          "start_angle", Float_value 0.2; "end_angle", Float_value 2.5; "reverse_cross_sections", Bool_value true;
          "origin_x", Float_value 0.1; "origin_y", Float_value 0.2; "origin_z", Float_value 0.3;
          "axis_x", Float_value 1.; "axis_y", Float_value 2.; "axis_z", Float_value 3.; "uv_attribute", Text_value "st"] profile)
      [Rdk.Plane_generators.Grid_points, "Points"; Grid_rows, "Rows"; Grid_columns, "Columns";
        Grid_rows_and_columns, "Rows and columns"; Grid_quads, "Quads"; Grid_triangles, "Triangles";
        Grid_alternating_triangles, "Alternating triangles"; Grid_reverse_triangles, "Reverse triangles"])
    [Rdk.Sweep_modeling.Revolve_closed, "Closed"; Revolve_open_arc, "Open arc"];
  same_cook "revolve caps" ~typed:(Sop.revolve ~caps:true ~cap_group:"endcaps" profile)
    ~factory:Nodes.Revolve.factory ["caps", Parameter.Bool_value true; "cap_group", Text_value "endcaps"] profile;
  same_cook "revolve unset names" ~typed:(Sop.revolve ~group:" " ~cap_group:" " ~uv_attribute:" " profile)
    ~factory:Nodes.Revolve.factory ["group", Parameter.Text_value " "; "cap_group", Text_value " "; "uv_attribute", Text_value " "] profile;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "revolve refuses invalid fields at construction")
    [ (fun () -> Sop.revolve ~divisions:2 profile);
      (fun () -> Sop.revolve ~revolve_type:Rdk.Sweep_modeling.Revolve_open_arc ~start_angle:0. ~end_angle:0. profile);
      (fun () -> Sop.revolve ~axis:Vec3.zero profile);
      (fun () -> Sop.revolve ~origin:(Vec3.create nan 0. 0.) profile);
      (fun () -> Sop.revolve ~start_angle:infinity profile);
      (fun () -> Sop.revolve ~caps:true ~connectivity:Rdk.Plane_generators.Grid_points profile);
      (fun () -> Sop.revolve ~caps:true ~revolve_type:Rdk.Sweep_modeling.Revolve_open_arc profile);
      (fun () -> Sop.revolve ~uv_attribute:"P" profile) ];
  let rewire_input = Sop.snapshot (Test_rewire_vertices_sop.source 24)
      |> Sop.set_int ~owner:Rdk.Attribute.Vertex ~name:"target" ~value:(-1)
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"target" ~value:(-1)
      |> Sop.group ~name:"selected" (Select.vertex_indices [|0; 1; 2|])
      |> Sop.group ~name:"selected" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selected" in
  let rewired = Sop.rewire_vertices rewire_input in
  same_cook "rewire vertices defaults" ~typed:rewired ~factory:Nodes.Rewire_vertices.factory [] rewire_input;
  cache_identity ~companions:["recursive", ["owner", Parameter.Choice_value "Point"]]
    "rewire vertices all fields" rewired;
  List.iter (fun (owner, owner_choice) ->
    List.iter (fun (selection_owner, choice) ->
      same_cook ("rewire vertices " ^ owner_choice ^ " " ^ choice)
        ~typed:(Sop.rewire_vertices ~owner ~selection_owner ~selection:"selected"
          ~delete_target_attribute:false ~keep_unused_points:true ~original_point_attribute:"original" rewire_input)
        ~factory:Nodes.Rewire_vertices.factory ["owner", Parameter.Choice_value owner_choice;
          "selection_owner", Choice_value choice; "selection", Text_value "selected";
          "delete_target_attribute", Bool_value false; "keep_unused_points", Bool_value true;
          "original_point_attribute", Text_value "original"] rewire_input)
      [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"])
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"];
  same_cook "rewire vertices recursive" ~typed:(Sop.rewire_vertices ~owner:Rdk.Attribute.Point ~recursive:true rewire_input)
    ~factory:Nodes.Rewire_vertices.factory ["owner", Parameter.Choice_value "Point"; "recursive", Bool_value true] rewire_input;
  same_cook "rewire vertices unset names" ~typed:(Sop.rewire_vertices ~selection:" " ~original_point_attribute:" " rewire_input)
    ~factory:Nodes.Rewire_vertices.factory ["selection", Parameter.Text_value " "; "original_point_attribute", Text_value " "] rewire_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "rewire vertices refuses invalid fields at construction")
    [ (fun () -> Sop.rewire_vertices ~target_attribute:" " rewire_input);
      (fun () -> Sop.rewire_vertices ~owner:Rdk.Attribute.Detail rewire_input);
      (fun () -> Sop.rewire_vertices ~recursive:true rewire_input);
      (fun () -> Sop.rewire_vertices ~original_point_attribute:"N" rewire_input) ];
  let rest = Sop.rest_position color_input None in
  same_cook ~optional_inputs:[Some color_input; None] "rest position defaults" ~typed:rest
    ~factory:Nodes.Rest_position.factory [] color_input;
  cache_identity "rest position all fields" rest;
  let rest_input = color_input
      |> Sop.set_vector ~name:"N" ~value:Vec3.unit_y
      |> Sop.set_vector ~name:"normal" ~value:Vec3.unit_z
      |> fun input -> Sop.rest_position ~normals:Rdk.Motion.Rest_normals_always input None in
  List.iter (fun (mode, choice) ->
    same_cook ~optional_inputs:[Some rest_input; None] ("rest position " ^ choice)
      ~typed:(Sop.rest_position ~mode rest_input None) ~factory:Nodes.Rest_position.factory
      ["mode", Parameter.Choice_value choice] rest_input)
    [Rdk.Motion.Store_rest, "Store"; Extract_rest, "Extract"; Swap_rest, "Swap"];
  let rest_reference = Sop.set_vector ~name:"normal" ~value:Vec3.unit_x color_input in
  List.iter (fun (normals, choice) ->
    same_cook ~optional_inputs:[Some rest_input; Some rest_reference] ("rest position normals " ^ choice)
      ~typed:(Sop.rest_position ~normals ~rest_attribute:"reference_rest"
        ~normal_attribute:"normal" ~rest_normal_attribute:"reference_normal" rest_input (Some rest_reference))
      ~factory:Nodes.Rest_position.factory ["normals", Parameter.Choice_value choice;
        "rest_attribute", Text_value "reference_rest"; "normal_attribute", Text_value "normal";
        "rest_normal_attribute", Text_value "reference_normal"] rest_input)
    [Rdk.Motion.No_rest_normals, "None"; Rest_normals_if_present, "If present"; Rest_normals_always, "Always"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "rest position refuses invalid attribute names at construction")
    [ (fun () -> Sop.rest_position ~rest_attribute:"P" color_input None);
      (fun () -> Sop.rest_position ~normals:Rdk.Motion.Rest_normals_always
        ~normal_attribute:" " color_input None) ];
  let float_set = Sop.set_float color_input and int_set = Sop.set_int color_input in
  same_cook "set float defaults" ~typed:float_set ~factory:Nodes.Set_float.factory [] color_input;
  same_cook "set int defaults" ~typed:int_set ~factory:Nodes.Set_int.factory [] color_input;
  cache_identity "set float all fields" float_set;
  cache_identity "set int all fields" int_set;
  let vector_set = Sop.set_vector color_input in
  same_cook "set vector defaults" ~typed:vector_set ~factory:Nodes.Set_vector.factory [] color_input;
  cache_identity "set vector all fields" vector_set;
  let oriented = Sop.set_orient color_input in
  let transformed = Sop.set_transform color_input in
  same_cook "set transform defaults" ~typed:transformed ~factory:Nodes.Set_transform.factory [] color_input;
  cache_identity ~changes:["m30", Parameter.Float_value 1e-13; "m31", Float_value 1e-13;
      "m32", Float_value 1e-13; "m33", Float_value (1. +. 1e-13)]
    "set transform all fields" transformed;
  same_cook "set transform matrix fields" ~typed:(Sop.set_transform
      ~m00:2. ~m01:0.1 ~m02:0.2 ~m03:3. ~m10:0.3 ~m11:4. ~m12:0.4 ~m13:5.
      ~m20:0.5 ~m21:0.6 ~m22:6. ~m23:7. ~m30:1e-13 ~m31:1e-13 ~m32:1e-13
      ~m33:(1. +. 1e-13) color_input) ~factory:Nodes.Set_transform.factory
    ["m00", Parameter.Float_value 2.; "m01", Float_value 0.1; "m02", Float_value 0.2;
      "m03", Float_value 3.; "m10", Float_value 0.3; "m11", Float_value 4.;
      "m12", Float_value 0.4; "m13", Float_value 5.; "m20", Float_value 0.5;
      "m21", Float_value 0.6; "m22", Float_value 6.; "m23", Float_value 7.;
      "m30", Float_value 1e-13; "m31", Float_value 1e-13; "m32", Float_value 1e-13;
      "m33", Float_value (1. +. 1e-13)] color_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "set transform refuses invalid matrices at construction")
    [ (fun () -> Sop.set_transform ~m00:nan color_input);
      (fun () -> Sop.set_transform ~m30:0.1 color_input);
      (fun () -> Sop.set_transform ~m33:0. color_input) ];
  same_cook "set orient defaults" ~typed:oriented ~factory:Nodes.Set_orient.factory [] color_input;
  cache_identity "set orient all fields" oriented;
  same_cook "set orient quaternion channels" ~typed:(Sop.set_orient ~x:0.2 ~y:0.3 ~z:0.4 ~w:0.5 color_input)
    ~factory:Nodes.Set_orient.factory ["x", Parameter.Float_value 0.2; "y", Float_value 0.3;
      "z", Float_value 0.4; "w", Float_value 0.5] color_input;
  same_cook "set orient zero normalization" ~typed:(Sop.set_orient ~w:0. color_input)
    ~factory:Nodes.Set_orient.factory ["w", Parameter.Float_value 0.] color_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "set orient refuses non-finite channels at construction")
    [ (fun () -> Sop.set_orient ~x:nan color_input);
      (fun () -> Sop.set_orient ~w:infinity color_input) ];
  List.iter (fun (owner, choice) ->
    same_cook ("set float " ^ choice) ~typed:(Sop.set_float ~owner ~name:"custom" ~value:0.75 color_input)
      ~factory:Nodes.Set_float.factory ["owner", Parameter.Choice_value choice;
        "name", Text_value "custom"; "value", Float_value 0.75] color_input;
    same_cook ("set int " ^ choice) ~typed:(Sop.set_int ~owner ~name:"custom" ~value:37 color_input)
      ~factory:Nodes.Set_int.factory ["owner", Parameter.Choice_value choice;
        "name", Text_value "custom"; "value", Int_value 37] color_input;
    same_cook ("set vector " ^ choice) ~typed:(Sop.set_vector ~owner ~name:"custom"
        ~value:(Vec3.create 0.2 0.3 0.4) color_input) ~factory:Nodes.Set_vector.factory
      ["owner", Parameter.Choice_value choice; "name", Text_value "custom";
        "x", Float_value 0.2; "y", Float_value 0.3; "z", Float_value 0.4] color_input)
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"; Detail, "Detail"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "attribute setters refuse invalid parameters at construction")
    [ (fun () -> Sop.set_float ~value:nan color_input);
      (fun () -> Sop.set_float ~name:" " color_input);
      (fun () -> Sop.set_float ~name:"P" color_input);
      (fun () -> Sop.set_int ~name:" " color_input);
      (fun () -> Sop.set_int ~name:"P" color_input);
      (fun () -> Sop.set_vector ~value:(Vec3.create nan 0. 0.) color_input);
      (fun () -> Sop.set_vector ~name:"P" color_input) ];
  let colored = Sop.color_by_height color_input in
  let constant_color = Sop.set_color color_input in
  same_cook "set color defaults" ~typed:constant_color ~factory:Nodes.Set_color.factory [] color_input;
  cache_identity "set color all fields" constant_color;
  let grouped_colors = color_input
      |> Sop.group ~name:"selection" (Select.point_indices [|0|])
      |> Sop.group ~name:"selection" (Select.vertex_indices [|0|])
      |> Sop.group ~name:"selection" (Select.primitive_indices [|0|]) in
  let enumerated = Sop.enumerate color_input in
  same_cook "enumerate defaults" ~typed:enumerated ~factory:Nodes.Enumerate.factory [] color_input;
  cache_identity "enumerate all fields" enumerated;
  let enumeration_input = grouped_colors
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"piece" ~value:1
      |> Sop.set_int ~owner:Rdk.Attribute.Vertex ~name:"piece" ~value:2
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"piece" ~value:3 in
  List.iter (fun (owner, choice) ->
    List.iter (fun (mode, mode_choice) ->
      same_cook ("enumerate " ^ choice ^ " " ^ mode_choice) ~typed:(Sop.enumerate ~owner
          ~name:"number" ~group:"selection" ~start:5 ~step:(-2) ~storage:Sop.Enumerate_text
          ~prefix:"part_" ~piece_attribute:"piece" ~mode enumeration_input)
        ~factory:Nodes.Enumerate.factory ["owner", Parameter.Choice_value choice;
          "name", Text_value "number"; "group", Text_value "selection";
          "start", Int_value 5; "step", Int_value (-2); "storage", Choice_value "Text";
          "prefix", Text_value "part_"; "piece_attribute", Text_value "piece";
          "mode", Choice_value mode_choice] enumeration_input)
      [Rdk.Attribute_ops.Enumerate_piece_elements, "Elements within pieces"; Enumerate_pieces, "Pieces"])
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"];
  same_cook "enumerate unset names" ~typed:(Sop.enumerate ~group:" " ~piece_attribute:" " color_input)
    ~factory:Nodes.Enumerate.factory ["group", Parameter.Text_value " ";
      "piece_attribute", Text_value " "] color_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "enumerate refuses invalid owners and names at construction")
    [ (fun () -> Sop.enumerate ~owner:Rdk.Attribute.Detail color_input);
      (fun () -> Sop.enumerate ~name:" " color_input);
      (fun () -> Sop.enumerate ~name:"P" color_input) ];
  List.iter (fun (owner, choice) ->
    let group = if owner = Rdk.Attribute.Detail then "" else "selection" in
    same_cook ("set color " ^ choice) ~typed:(Sop.set_color ~owner ~group
        ~color:(Vec3.create 0.2 0.3 0.4) ~alpha:0.5 grouped_colors)
      ~factory:Nodes.Set_color.factory ["owner", Parameter.Choice_value choice;
        "group", Text_value group; "color_r", Float_value 0.2;
        "color_g", Float_value 0.3; "color_b", Float_value 0.4; "alpha", Float_value 0.5] grouped_colors)
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"; Detail, "Detail"];
  same_cook "set color float alias" ~typed:(Sop.set_color_float ~color:Vec3.unit_y color_input)
    ~factory:Nodes.Set_color.factory ["color_r", Parameter.Float_value 0.; "color_b", Float_value 0.] color_input;
  same_cook "set color unset group" ~typed:(Sop.set_color ~group:" " color_input)
    ~factory:Nodes.Set_color.factory ["group", Parameter.Text_value " "] color_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "set color refuses invalid channels or detail selections at construction")
    [ (fun () -> Sop.set_color ~color:(Vec3.create nan 0. 0.) color_input);
      (fun () -> Sop.set_color ~alpha:1.1 color_input);
      (fun () -> Sop.set_color ~owner:Rdk.Attribute.Detail ~group:"selection" color_input) ];
  same_cook "color by height Lisp defaults" ~typed:colored
    ~factory:Nodes.Color_by_height.factory [] color_input;
  cache_identity "color by height all fields" colored;
  same_cook "color by height rgba" ~typed:(Sop.color_by_height
      ~low_red:10 ~low_green:20 ~low_blue:30 ~low_alpha:40
      ~high_red:50 ~high_green:60 ~high_blue:70 ~high_alpha:80 color_input)
    ~factory:Nodes.Color_by_height.factory ["low_red", Parameter.Int_value 10;
      "low_green", Int_value 20; "low_blue", Int_value 30; "low_alpha", Int_value 40;
      "high_red", Int_value 50; "high_green", Int_value 60;
      "high_blue", Int_value 70; "high_alpha", Int_value 80] color_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "color by height refuses invalid channels at construction")
    [ (fun () -> Sop.color_by_height ~low_red:(-1) color_input);
      (fun () -> Sop.color_by_height ~high_alpha:256 color_input) ];
  let uv_source = Test_point_split_sop.source () in
  let point_uv = Rdk.Packed.Float2.of_owned ~x:[|0.; 1.; 1.; 0.|]
      ~y:[|0.; 0.; 1.; 1.|] |> Result.get_ok in
  let point_uv = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"uv"
      (Rdk.Attribute.Float2 point_uv) |> Result.get_ok in
  let uv_input = Sop.snapshot (Rdk.Geometry.with_attribute point_uv uv_source |> Result.get_ok)
      |> Sop.group ~name:"selection" (Select.point_indices [|0; 2|])
      |> Sop.group ~name:"selection" (Select.vertex_indices [|0; 2|])
      |> Sop.group ~name:"selection" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selection" in
  let polyframed = Sop.polyframe uv_input in
  same_cook "polyframe defaults" ~typed:polyframed ~factory:Nodes.Polyframe.factory [] uv_input;
  cache_identity "polyframe all fields" polyframed;
  List.iter (fun (style, choice) ->
    same_cook ("polyframe style " ^ choice) ~typed:(Sop.polyframe ~style uv_input)
      ~factory:Nodes.Polyframe.factory ["style", Parameter.Choice_value choice] uv_input)
    [Sop.Style_first_edge, "First edge"; Style_two_edges, "Two edges"; Style_centroid, "Primitive centroid";
      Style_texture_uv, "Texture UV"; Style_texture_uv_gradient, "Texture UV gradient";
      Style_attribute_gradient, "Attribute gradient"];
  List.iter (fun (group_owner, choice) ->
    same_cook ("polyframe selection " ^ choice) ~typed:(Sop.polyframe ~group_owner ~group:"selection"
        ~style:Sop.Style_texture_uv_gradient ~style_attribute:"uv" ~orthogonal:true ~left_handed:true
        ~normal_attribute:"frame_n" ~tangent_attribute:"frame_u" ~bitangent_attribute:"frame_v" uv_input)
      ~factory:Nodes.Polyframe.factory ["group_owner", Parameter.Choice_value choice;
        "group", Text_value "selection"; "style", Choice_value "Texture UV gradient";
        "style_attribute", Text_value "uv"; "orthogonal", Bool_value true; "left_handed", Bool_value true;
        "normal_attribute", Text_value "frame_n"; "tangent_attribute", Text_value "frame_u";
        "bitangent_attribute", Text_value "frame_v"] uv_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "polyframe disabled outputs and unset group" ~typed:(Sop.polyframe ~group:" "
      ~tangent_attribute:"" ~bitangent_attribute:"" uv_input) ~factory:Nodes.Polyframe.factory
    ["group", Parameter.Text_value " "; "tangent_attribute", Text_value "";
      "bitangent_attribute", Text_value ""] uv_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "polyframe refuses invalid output names at construction")
    [ (fun () -> Sop.polyframe ~normal_attribute:" " uv_input);
      (fun () -> Sop.polyframe ~tangent_attribute:"P" uv_input);
      (fun () -> Sop.polyframe ~tangent_attribute:"N" uv_input);
      (fun () -> Sop.polyframe ~style:Sop.Style_attribute_gradient ~style_attribute:" " uv_input) ];
  let uv_transformed = Sop.uv_transform uv_input in
  let connected = Sop.connectivity uv_input in
  same_cook "connectivity defaults" ~typed:connected ~factory:Nodes.Connectivity.factory [] uv_input;
  cache_identity ~companions:["point_group", ["owner", Parameter.Choice_value "Points"]]
    "connectivity all fields" connected;
  List.iter (fun (owner, choice) ->
    let point_group = if owner = Rdk.Analysis.Connectivity_points then "selection" else "" in
    same_cook ("connectivity text " ^ choice) ~typed:(Sop.connectivity ~owner
        ~primitive_group:"seam_face" ~point_group ~name:"island"
        ~output:Sop.Text ~text_prefix:"part_" uv_input) ~factory:Nodes.Connectivity.factory
      ["owner", Parameter.Choice_value choice; "primitive_group", Text_value "seam_face";
        "point_group", Text_value point_group; "name", Text_value "island";
        "output", Choice_value "Text"; "text_prefix", Text_value "part_"] uv_input)
    [Rdk.Analysis.Connectivity_points, "Points"; Connectivity_primitives, "Primitives"];
  let seam_input = uv_input |> Sop.group_edges ~name:"seams" in
  same_cook "connectivity edge seams" ~typed:(Sop.connectivity ~seam_group:"seams" seam_input)
    ~factory:Nodes.Connectivity.factory ["seam_group", Parameter.Text_value "seams"] seam_input;
  same_cook "connectivity uv seams" ~typed:(Sop.connectivity ~uv_attribute:"uv" seam_input)
    ~factory:Nodes.Connectivity.factory ["uv_attribute", Parameter.Text_value "uv"] seam_input;
  same_cook "connectivity unset names" ~typed:(Sop.connectivity ~primitive_group:" "
      ~point_group:" " ~seam_group:" " ~uv_attribute:" " ~name:" " uv_input)
    ~factory:Nodes.Connectivity.factory ["primitive_group", Parameter.Text_value " ";
      "point_group", Text_value " "; "seam_group", Text_value " ";
      "uv_attribute", Text_value " "; "name", Text_value " "] uv_input;
  check (try ignore (Sop.connectivity ~owner:Rdk.Analysis.Connectivity_points ~name:"P" uv_input);
      false with Invalid_argument _ -> true) "connectivity refuses canonical P at construction";
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "connectivity refuses incompatible selection modes at construction")
    [ (fun () -> Sop.connectivity ~point_group:"selection" uv_input);
      (fun () -> Sop.connectivity ~owner:Rdk.Analysis.Connectivity_points ~uv_attribute:"uv" uv_input);
      (fun () -> Sop.connectivity ~seam_group:"seams" ~uv_attribute:"uv" uv_input) ];
  let uv_projected = Sop.uv_project uv_input in
  same_cook "uv project Lisp defaults" ~typed:uv_projected
    ~factory:Nodes.Uv_project.factory [] uv_input;
  cache_identity "uv project all fields" uv_projected;
  List.iter (fun (projection, choice) ->
    same_cook ("uv project " ^ choice) ~typed:(Sop.uv_project ~projection ~name:"mapped"
        ~group:"seam_face" ~origin:(Vec3.create 0.1 0.2 0.3)
        ~axis:Vec3.unit_z ~seam:Vec3.unit_y ~planar_u:(Vec3.create 2. 0. 0.)
        ~planar_v:(Vec3.create 0. 2. 0.) ~height:2. ~u_min:0.1 ~u_max:0.9
        ~v_min:0.2 ~v_max:0.8 ~fix_seams:false ~fix_poles:false uv_input)
      ~factory:Nodes.Uv_project.factory ["projection", Parameter.Choice_value choice;
        "name", Text_value "mapped"; "group", Text_value "seam_face";
        "origin_x", Float_value 0.1; "origin_y", Float_value 0.2; "origin_z", Float_value 0.3;
        "axis_y", Float_value 0.; "axis_z", Float_value 1.;
        "seam_x", Float_value 0.; "seam_y", Float_value 1.;
        "planar_u_x", Float_value 2.; "planar_v_y", Float_value 2.; "planar_v_z", Float_value 0.;
        "height", Float_value 2.; "u_min", Float_value 0.1; "u_max", Float_value 0.9;
        "v_min", Float_value 0.2; "v_max", Float_value 0.8;
        "fix_seams", Bool_value false; "fix_poles", Bool_value false] uv_input)
    [Sop.Planar, "Planar"; Cylindrical, "Cylindrical"; Spherical, "Spherical"];
  same_cook "uv project unset group" ~typed:(Sop.uv_project ~group:" " uv_input)
    ~factory:Nodes.Uv_project.factory ["group", Parameter.Text_value " "] uv_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "uv project refuses invalid parameters at construction")
    [ (fun () -> Sop.uv_project ~origin:(Vec3.create nan 0. 0.) uv_input);
      (fun () -> Sop.uv_project ~planar_u:Vec3.zero uv_input);
      (fun () -> Sop.uv_project ~planar_v:Vec3.unit_x uv_input);
      (fun () -> Sop.uv_project ~projection:Sop.Cylindrical ~height:0. uv_input);
      (fun () -> Sop.uv_project ~projection:Sop.Spherical ~seam:Vec3.unit_y uv_input);
      (fun () -> Sop.uv_project ~u_max:infinity uv_input) ];
  same_cook "uv transform defaults" ~typed:uv_transformed
    ~factory:Nodes.Uv_transform.factory [] uv_input;
  cache_identity "uv transform all fields" uv_transformed;
  List.iter (fun (owner, choice) ->
    same_cook ("uv transform " ^ choice) ~typed:(Sop.uv_transform ~owner ~group:"selection"
        ~translate_u:0.2 ~translate_v:0.3 ~scale_u:2. ~scale_v:3.
        ~angle:0.4 ~pivot_u:0.1 ~pivot_v:0.6 uv_input)
      ~factory:Nodes.Uv_transform.factory ["owner", Parameter.Choice_value choice;
        "group", Text_value "selection"; "translate_u", Float_value 0.2;
        "translate_v", Float_value 0.3; "scale_u", Float_value 2.; "scale_v", Float_value 3.;
        "angle", Float_value 0.4; "pivot_u", Float_value 0.1; "pivot_v", Float_value 0.6] uv_input)
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"];
  same_cook "uv transform unset group" ~typed:(Sop.uv_transform ~group:" " uv_input)
    ~factory:Nodes.Uv_transform.factory ["group", Parameter.Text_value " "] uv_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "uv transform refuses invalid parameters at construction")
    [ (fun () -> Sop.uv_transform ~owner:Rdk.Attribute.Primitive uv_input);
      (fun () -> Sop.uv_transform ~translate_u:nan uv_input);
      (fun () -> Sop.uv_transform ~scale_v:infinity uv_input);
      (fun () -> Sop.uv_transform ~angle:nan uv_input);
      (fun () -> Sop.uv_transform ~pivot_v:nan uv_input) ];
  let normal_input = Sop.box ~normals:None ~consolidate_points:true ()
      |> Sop.group ~name:"selection" (Select.point_indices [|0; 1; 2; 3|])
      |> Sop.group ~name:"selection" (Select.vertex_indices [|0; 1; 2; 3|])
      |> Sop.group ~name:"selection" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selection" in
  let bounded = Sop.bound normal_input in
  let distance_input = normal_input
      |> Sop.group ~name:"start" (Select.point_indices [|0|])
      |> Sop.group ~name:"start" (Select.vertex_indices [|0|])
      |> Sop.group ~name:"start" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"start" in
  let along = Sop.distance_along_geometry distance_input in
  let distance_reference = (let migration_translation = Vec3.create 2. 3. 4. in
Sop.transform ~mode:Sop.Transform_matrix ~m03:migration_translation.Vec3.x
  ~m13:migration_translation.Vec3.y ~m23:migration_translation.Vec3.z
  normal_input) in
  let geometry_distance = Sop.distance_from_geometry normal_input distance_reference in
  same_cook ~inputs:[distance_reference] "distance from geometry defaults" ~typed:geometry_distance
    ~factory:Nodes.Distance_from_geometry.factory [] normal_input;
  cache_identity "distance from geometry all fields" geometry_distance;
  List.iter (fun (owner, choice) ->
    List.iter (fun (reference_kind, reference_choice) ->
      same_cook ~inputs:[distance_reference] ("distance from geometry " ^ choice ^ " " ^ reference_choice)
        ~typed:(Sop.distance_from_geometry ~affected_owner:owner ~affected_group:"selection"
          ~reference_owner:owner ~reference_group:"selection" ~reference_kind
          ~falloff:Rdk.Transform_ops.Soft_quadratic ~radius_mode:Sop.Radius_fixed ~radius:3.
          ~distance_attribute:"nearest" ~mask_attribute:"mask" normal_input distance_reference)
        ~factory:Nodes.Distance_from_geometry.factory ["affected_owner", Parameter.Choice_value choice;
          "affected_group", Text_value "selection"; "reference_owner", Choice_value choice;
          "reference_group", Text_value "selection"; "reference_kind", Choice_value reference_choice;
          "falloff", Choice_value "Quadratic"; "radius_mode", Choice_value "Fixed"; "radius", Float_value 3.;
          "distance_attribute", Text_value "nearest"; "mask_attribute", Text_value "mask"] normal_input)
      [Rdk.Transform_ops.Distance_reference_points, "Points"; Distance_reference_primitives, "Primitives"])
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook ~inputs:[distance_reference] "distance from geometry mask only and unset groups"
    ~typed:(Sop.distance_from_geometry ~affected_group:" " ~reference_group:" " ~distance_attribute:" "
      ~mask_attribute:"mask" ~falloff:Rdk.Transform_ops.Soft_cubic normal_input distance_reference)
    ~factory:Nodes.Distance_from_geometry.factory ["affected_group", Parameter.Text_value " ";
      "reference_group", Text_value " "; "distance_attribute", Text_value " ";
      "mask_attribute", Text_value "mask"; "falloff", Choice_value "Cubic"] normal_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "distance from geometry refuses invalid fields at construction")
    [ (fun () -> Sop.distance_from_geometry ~radius:nan normal_input distance_reference);
      (fun () -> Sop.distance_from_geometry ~radius_mode:Sop.Radius_fixed ~radius:0. normal_input distance_reference);
      (fun () -> Sop.distance_from_geometry ~distance_attribute:"P" normal_input distance_reference);
      (fun () -> Sop.distance_from_geometry ~distance_attribute:"" normal_input distance_reference);
      (fun () -> Sop.distance_from_geometry ~mask_attribute:"distance" normal_input distance_reference) ];
  let target_distance = Sop.distance_from_target normal_input in
  same_cook "distance from target defaults" ~typed:target_distance ~factory:Nodes.Distance_from_target.factory [] normal_input;
  cache_identity ~companions:["metric", ["projection", Parameter.Choice_value "Planar"]]
    "distance from target all fields" target_distance;
  List.iter (fun (affected_owner, owner_choice) ->
    List.iter (fun (projection, projection_choice) ->
      same_cook ("distance from target " ^ owner_choice ^ " " ^ projection_choice)
        ~typed:(Sop.distance_from_target ~affected_owner ~affected_group:"selection" ~projection
          ~origin:(Vec3.create 0.1 0.2 0.3) ~direction:(Vec3.create 1. 2. 3.)
          ~radius_mode:Sop.Radius_fixed ~radius:3. ~falloff:Rdk.Transform_ops.Soft_cubic
          ~distance_attribute:"analytic" ~mask_attribute:"mask" normal_input)
        ~factory:Nodes.Distance_from_target.factory ["affected_owner", Parameter.Choice_value owner_choice;
          "affected_group", Text_value "selection"; "projection", Choice_value projection_choice;
          "origin_x", Float_value 0.1; "origin_y", Float_value 0.2; "origin_z", Float_value 0.3;
          "direction_x", Float_value 1.; "direction_y", Float_value 2.; "direction_z", Float_value 3.;
          "radius_mode", Choice_value "Fixed"; "radius", Float_value 3.; "falloff", Choice_value "Cubic";
          "distance_attribute", Text_value "analytic"; "mask_attribute", Text_value "mask"] normal_input)
      [Rdk.Transform_ops.Distance_target_spherical, "Spherical"; Distance_target_cylindrical, "Cylindrical";
        Distance_target_planar, "Planar"])
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "distance from target signed plane" ~typed:(Sop.distance_from_target
      ~projection:Rdk.Transform_ops.Distance_target_planar ~metric:Rdk.Transform_ops.Distance_target_signed
      ~falloff:Rdk.Transform_ops.Soft_quadratic ~mask_attribute:"mask" normal_input)
    ~factory:Nodes.Distance_from_target.factory ["projection", Parameter.Choice_value "Planar";
      "metric", Choice_value "Signed"; "falloff", Choice_value "Quadratic"; "mask_attribute", Text_value "mask"] normal_input;
  same_cook "distance from target mask only and unset group" ~typed:(Sop.distance_from_target
      ~affected_group:" " ~distance_attribute:" " ~mask_attribute:"mask" normal_input)
    ~factory:Nodes.Distance_from_target.factory ["affected_group", Parameter.Text_value " ";
      "distance_attribute", Text_value " "; "mask_attribute", Text_value "mask"] normal_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "distance from target refuses invalid fields at construction")
    [ (fun () -> Sop.distance_from_target ~radius:nan normal_input);
      (fun () -> Sop.distance_from_target ~radius_mode:Sop.Radius_fixed ~radius:0. normal_input);
      (fun () -> Sop.distance_from_target ~distance_attribute:"P" normal_input);
      (fun () -> Sop.distance_from_target ~distance_attribute:"" normal_input);
      (fun () -> Sop.distance_from_target ~mask_attribute:"distance" normal_input);
      (fun () -> Sop.distance_from_target ~origin:(Vec3.create nan 0. 0.) normal_input);
      (fun () -> Sop.distance_from_target ~projection:Rdk.Transform_ops.Distance_target_planar ~direction:Vec3.zero normal_input);
      (fun () -> Sop.distance_from_target ~metric:Rdk.Transform_ops.Distance_target_signed normal_input) ];
  same_cook "distance along defaults" ~typed:along ~factory:Nodes.Distance_along_geometry.factory [] distance_input;
  cache_identity "distance along all fields" along;
  List.iter (fun (start_owner, owner_choice) ->
    List.iter (fun (falloff, falloff_choice) ->
      List.iter (fun (radius_mode, radius_choice) ->
        same_cook ("distance along " ^ owner_choice ^ " " ^ falloff_choice ^ " " ^ radius_choice)
          ~typed:(Sop.distance_along_geometry ~start_owner ~affected_owner:start_owner ~affected_group:"selection"
            ~falloff ~radius_mode ~radius:3. ~distance_attribute:"along" ~mask_attribute:"mask" distance_input)
          ~factory:Nodes.Distance_along_geometry.factory ["start_owner", Parameter.Choice_value owner_choice;
            "affected_owner", Choice_value owner_choice; "affected_group", Text_value "selection";
            "falloff", Choice_value falloff_choice; "radius_mode", Choice_value radius_choice;
            "radius", Float_value 3.; "distance_attribute", Text_value "along"; "mask_attribute", Text_value "mask"] distance_input)
        [Sop.Radius_fixed, "Fixed"; Radius_maximum, "Maximum distance"])
      [Rdk.Transform_ops.Soft_linear, "Linear"; Soft_quadratic, "Quadratic"; Soft_cubic, "Cubic"])
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "distance along mask only and unset groups" ~typed:(Sop.distance_along_geometry ~start_group:" "
      ~affected_group:" " ~distance_attribute:" " ~mask_attribute:"mask" distance_input)
    ~factory:Nodes.Distance_along_geometry.factory ["start_group", Parameter.Text_value " ";
      "affected_group", Text_value " "; "distance_attribute", Text_value " "; "mask_attribute", Text_value "mask"] distance_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "distance along refuses invalid fields at construction")
    [ (fun () -> Sop.distance_along_geometry ~radius:nan distance_input);
      (fun () -> Sop.distance_along_geometry ~radius_mode:Sop.Radius_fixed ~radius:0. distance_input);
      (fun () -> Sop.distance_along_geometry ~radius:(-1.) distance_input);
      (fun () -> Sop.distance_along_geometry ~distance_attribute:"P" distance_input);
      (fun () -> Sop.distance_along_geometry ~distance_attribute:"" distance_input);
      (fun () -> Sop.distance_along_geometry ~mask_attribute:"distance" distance_input) ];
  let matched = Sop.match_size normal_input None in
  same_cook ~optional_inputs:[Some normal_input; None] "match size defaults" ~typed:matched
    ~factory:Nodes.Match_size.factory [] normal_input;
  cache_identity "match size all fields" matched;
  let fit_target = Sop.box ~size:(Vec3.create 3. 4. 5.) () in
  List.iter (fun (fit, choice) ->
    same_cook ~optional_inputs:[Some normal_input; Some fit_target] ("match size " ^ choice)
      ~typed:(Sop.match_size ~fit normal_input (Some fit_target))
      ~factory:Nodes.Match_size.factory ["fit", Parameter.Choice_value choice]
      normal_input)
    [Rdk.Match_size.Translate_only, "Translate only"; Stretch, "Stretch"; Contain, "Contain";
      Cover, "Cover"; Match_x, "Match X"; Match_y, "Match Y"; Match_z, "Match Z";
      Match_perimeter, "Match perimeter"; Match_area, "Match area"; Match_volume, "Match volume"];
  let match_target = (let migration_translation = Vec3.create 3. 4. 5. in
Sop.transform ~mode:Sop.Transform_matrix ~m03:migration_translation.Vec3.x
  ~m13:migration_translation.Vec3.y ~m23:migration_translation.Vec3.z
  normal_input) in
  List.iter (fun (owner, choice) ->
    same_cook ~optional_inputs:[Some normal_input; Some match_target]
      ("match size selections " ^ choice) ~typed:(Sop.match_size ~group_owner:owner ~group:"selection"
        ~source_group_owner:owner ~source_group:"selection" ~target_group_owner:owner ~target_group:"selection"
        ~fit:Rdk.Match_size.Translate_only ~translate_y:false ~translate_z:false
        ~scale_x:false ~scale_z:false ~justify:(Vec3.create (-1.) 0.5 1.)
        ~target_justify:(Vec3.create 1. 0. (-1.)) ~offset:(Vec3.create 0.1 0.2 0.3) ~scale:2.
        normal_input (Some match_target)) ~factory:Nodes.Match_size.factory
      ["group_owner", Parameter.Choice_value choice; "group", Text_value "selection";
        "source_group_owner", Choice_value choice; "source_group", Text_value "selection";
        "target_group_owner", Choice_value choice; "target_group", Text_value "selection";
        "fit", Choice_value "Translate only"; "translate_y", Bool_value false; "translate_z", Bool_value false;
        "scale_x", Bool_value false; "scale_z", Bool_value false;
        "justify_x", Float_value (-1.); "justify_y", Float_value 0.5; "justify_z", Float_value 1.;
        "target_justify_x", Float_value 1.; "target_justify_z", Float_value (-1.);
        "offset_x", Float_value 0.1; "offset_y", Float_value 0.2; "offset_z", Float_value 0.3;
        "scale", Float_value 2.] normal_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  let auto_match = Sop.match_size ~target_justify_mode:Sop.Justify_auto ~justify:Vec3.unit_x
      ~target_center:(Vec3.create 3. 4. 5.) ~target_size:(Vec3.create 2. 3. 4.) normal_input None in
  same_cook ~optional_inputs:[Some normal_input; None] "match size Auto" ~typed:auto_match
    ~factory:Nodes.Match_size.factory ["target_justify_mode", Parameter.Choice_value "Auto";
      "justify_x", Float_value 1.; "target_center_x", Float_value 3.; "target_center_y", Float_value 4.;
      "target_center_z", Float_value 5.; "target_size_x", Float_value 2.;
      "target_size_y", Float_value 3.; "target_size_z", Float_value 4.] normal_input;
  check (equal_geometry (cook 1 auto_match) (cook 1 (Sop.match_size ~justify:Vec3.unit_x
      ~target_justify:Vec3.unit_x ~target_center:(Vec3.create 3. 4. 5.)
      ~target_size:(Vec3.create 2. 3. 4.) normal_input None))) "match size Auto inherits source justification";
  let connected_match = Sop.match_size normal_input (Some match_target) in
  let match_document = Edit_graph.of_graph match_target
      |> Edit_graph.add_node ~factory:Nodes.Match_size.factory
           ~inputs:[|Some (Node.id normal_input); Some (Node.id match_target)|] connected_match |> get
      |> Edit_graph.disconnect ~consumer:(Node.id connected_match) ~input_index:1 |> get in
  let rewired_match = Edit_graph.compile_node match_document ~node_id:(Node.id connected_match) |> get in
  same_node "match size disconnect target" ~typed:matched ~catalog:rewired_match;
  check (Node.id rewired_match = Node.id connected_match) "match size retains identity after disconnection";
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "match size refuses invalid values at construction")
    [ (fun () -> Sop.match_size ~justify:(Vec3.create 2. 0. 0.) normal_input None);
      (fun () -> Sop.match_size ~target_justify:(Vec3.create nan 0. 0.) normal_input None);
      (fun () -> Sop.match_size ~offset:(Vec3.create infinity 0. 0.) normal_input None);
      (fun () -> Sop.match_size ~scale:(-1.) normal_input None);
      (fun () -> Sop.match_size ~target_center:(Vec3.create nan 0. 0.) normal_input None);
      (fun () -> Sop.match_size ~target_size:(Vec3.create 1. (-1.) 1.) normal_input None) ];
  same_cook "bound defaults" ~typed:bounded ~factory:Nodes.Bound.factory [] normal_input;
  cache_identity "bound all fields" bounded;
  List.iter (fun (group_owner, owner_choice) ->
    List.iter (fun (shape, shape_choice) ->
      same_cook ("bound " ^ owner_choice ^ " " ^ shape_choice) ~typed:(Sop.bound
          ~group_owner ~group:"selection" ~shape ~divisions_x:2 ~divisions_y:3 ~divisions_z:4
          ~segments:12 ~rings:6 ~minimum_radius:0.2 ~lower:(Vec3.create 0.1 0.2 0.3)
          ~upper:(Vec3.create 0.3 0.2 0.1) ~bounds_group:"bounds"
          ~center_attribute:"center" ~radii_attribute:"radii" normal_input)
        ~factory:Nodes.Bound.factory ["group_owner", Parameter.Choice_value owner_choice;
          "group", Text_value "selection"; "shape", Choice_value shape_choice;
          "divisions_x", Int_value 2; "divisions_y", Int_value 3; "divisions_z", Int_value 4;
          "segments", Int_value 12; "rings", Int_value 6; "minimum_radius", Float_value 0.2;
          "lower_x", Float_value 0.1; "lower_y", Float_value 0.2; "lower_z", Float_value 0.3;
          "upper_x", Float_value 0.3; "upper_y", Float_value 0.2; "upper_z", Float_value 0.1;
          "bounds_group", Text_value "bounds"; "center_attribute", Text_value "center";
          "radii_attribute", Text_value "radii"] normal_input)
      [Sop.Box, "Box"; Sphere, "Sphere"])
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "bound unset names" ~typed:(Sop.bound ~group:" " ~bounds_group:" "
      ~center_attribute:" " ~radii_attribute:" " normal_input) ~factory:Nodes.Bound.factory
    ["group", Parameter.Text_value " "; "bounds_group", Text_value " ";
      "center_attribute", Text_value " "; "radii_attribute", Text_value " "] normal_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "bound refuses invalid parameters at construction")
    [ (fun () -> Sop.bound ~divisions_x:0 normal_input);
      (fun () -> Sop.bound ~segments:2 normal_input);
      (fun () -> Sop.bound ~minimum_radius:nan normal_input);
      (fun () -> Sop.bound ~lower:(Vec3.create (-0.1) 0. 0.) normal_input);
      (fun () -> Sop.bound ~center_attribute:"P" normal_input);
      (fun () -> Sop.bound ~center_attribute:"same" ~radii_attribute:"same" normal_input) ];
  let filter_input = normal_input
      |> Sop.set_float ~name:"weight" ~value:0.7
      |> Sop.set_float ~name:"alpha" ~value:0.8 in
  let blurred = Sop.attribute_blur filter_input in
  let promoted = Sop.promote_attributes filter_input in
  same_cook "promote attributes Lisp defaults" ~typed:promoted
    ~factory:Nodes.Promote_attributes.factory [] filter_input;
  cache_identity "promote attributes all fields"
    (Sop.promote_attributes ~method_:Rdk.Attribute_ops.First ~pattern:"weight" filter_input);
  List.iter (fun (method_, choice) ->
    same_cook ("promote attributes " ^ choice) ~typed:(Sop.promote_attributes ~method_
        ~pattern:"weight" filter_input) ~factory:Nodes.Promote_attributes.factory
      ["method_", Parameter.Choice_value choice; "pattern", Text_value "weight"] filter_input)
    [Rdk.Attribute_ops.First, "First"; Last, "Last"; Average, "Average"; Minimum, "Minimum";
      Maximum, "Maximum"; Mode, "Mode"; Median, "Median"; Sum, "Sum";
      Sum_squares, "Sum of squares"; Root_mean_square, "Root mean square";
      Array_all, "Array of all"; Unique_values, "Unique values"];
  let promotion_input = Sop.set_int ~name:"piece" ~value:1 filter_input in
  same_cook "promote attributes piece and renamed index" ~typed:(Sop.promote_attributes
      ~method_:Rdk.Attribute_ops.First ~delete_source:true ~piece_attribute:"piece"
      ~source:Rdk.Attribute.Point ~destination:Rdk.Attribute.Point ~pattern:"weight"
      ~into_pattern:"reduced" ~index_pattern:"source" promotion_input)
    ~factory:Nodes.Promote_attributes.factory ["method_", Parameter.Choice_value "First";
      "delete_source", Bool_value true; "piece_attribute", Text_value "piece";
      "destination", Choice_value "Point"; "pattern", Text_value "weight";
      "into_pattern", Text_value "reduced"; "index_pattern", Text_value "source"] promotion_input;
  List.iter (fun (owner, choice) ->
    let input = Sop.set_float ~owner ~name:"payload" ~value:0.8 filter_input in
    same_cook ("promote attributes source " ^ choice) ~typed:(Sop.promote_attributes
        ~source:owner ~destination:Rdk.Attribute.Point ~pattern:"payload" input)
      ~factory:Nodes.Promote_attributes.factory ["source", Parameter.Choice_value choice;
        "destination", Choice_value "Point"; "pattern", Text_value "payload"] input;
    same_cook ("promote attributes destination " ^ choice) ~typed:(Sop.promote_attributes
        ~destination:owner ~pattern:"weight" filter_input) ~factory:Nodes.Promote_attributes.factory
      ["destination", Parameter.Choice_value choice; "pattern", Text_value "weight"] filter_input)
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"; Detail, "Detail"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "promote attributes refuses invalid patterns and source-index modes at construction")
    [ (fun () -> Sop.promote_attributes ~pattern:"broken[" filter_input);
      (fun () -> Sop.promote_attributes ~index_pattern:"source" filter_input);
      (fun () -> Sop.promote_attributes ~pattern:"weight" ~into_pattern:"out_*_*" filter_input) ];
  let smoothed = Sop.smooth filter_input in
  same_cook "smooth Lisp defaults" ~typed:smoothed ~factory:Nodes.Smooth.factory [] filter_input;
  cache_identity "smooth all fields" smoothed;
  List.iter (fun (boundary, choice) ->
    same_cook ("smooth boundary " ^ choice) ~typed:(Sop.smooth ~boundary
        ~group:"selection" ~constrained_points:"selection" ~iterations:3
        ~method_:Rdk.Attribute_ops.Edge_length ~mode:Sop.Custom ~step:0.2
        ~odd_step:0.3 ~even_step:(-0.4) ~weight_attribute:"weight" ~alpha_attribute:"alpha"
        ~attributes:"P weight" ~recompute_normals:true ~original_blend:0.2 ~smoothed_blend:0.8 filter_input)
      ~factory:Nodes.Smooth.factory ["boundary", Parameter.Choice_value choice;
        "group", Text_value "selection"; "constrained_points", Text_value "selection";
        "iterations", Int_value 3; "method_", Choice_value "Edge length";
        "mode", Choice_value "Custom steps"; "step", Float_value 0.2;
        "odd_step", Float_value 0.3; "even_step", Float_value (-0.4);
        "weight_attribute", Text_value "weight"; "alpha_attribute", Text_value "alpha";
        "attributes", Text_value "P weight"; "recompute_normals", Bool_value true;
        "original_blend", Float_value 0.2; "smoothed_blend", Float_value 0.8] filter_input)
    [Rdk.Smooth.Smooth_free, "Free"; Smooth_unshared, "Pin unshared"; Smooth_group_boundary, "Pin group boundary"];
  same_cook "smooth unset names" ~typed:(Sop.smooth ~group:" " ~constrained_points:" "
      ~weight_attribute:" " ~alpha_attribute:" " filter_input) ~factory:Nodes.Smooth.factory
    ["group", Parameter.Text_value " "; "constrained_points", Text_value " ";
      "weight_attribute", Text_value " "; "alpha_attribute", Text_value " "] filter_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "smooth refuses invalid parameters at construction")
    [ (fun () -> Sop.smooth ~iterations:0 filter_input);
      (fun () -> Sop.smooth ~step:nan filter_input);
      (fun () -> Sop.smooth ~smoothed_blend:infinity filter_input);
      (fun () -> Sop.smooth ~attributes:"broken[" filter_input) ];
  same_cook "attribute blur defaults" ~typed:blurred ~factory:Nodes.Attribute_blur.factory [] filter_input;
  cache_identity "attribute blur all fields" blurred;
  List.iter (fun (mode, mode_choice) ->
    List.iter (fun (method_, method_choice) ->
      same_cook ("attribute blur " ^ mode_choice ^ " " ^ method_choice)
        ~typed:(Sop.attribute_blur ~mode ~method_ ~attributes:"P weight" ~group:"selection"
          ~iterations:3 ~laplacian_step:0.2 ~odd_step:0.3 ~even_step:(-0.4)
          ~weight_attribute:"weight" ~alpha_attribute:"alpha" ~pin_borders:true
          ~original_blend:0.2 ~blurred_blend:0.8 filter_input)
        ~factory:Nodes.Attribute_blur.factory ["mode", Parameter.Choice_value mode_choice;
          "method_", Choice_value method_choice; "attributes", Text_value "P weight";
          "group", Text_value "selection"; "iterations", Int_value 3;
          "laplacian_step", Float_value 0.2; "odd_step", Float_value 0.3;
          "even_step", Float_value (-0.4); "weight_attribute", Text_value "weight";
          "alpha_attribute", Text_value "alpha"; "pin_borders", Bool_value true;
          "original_blend", Float_value 0.2; "blurred_blend", Float_value 0.8] filter_input)
      [Rdk.Attribute_ops.Uniform, "Uniform"; Edge_length, "Edge length"])
    [Sop.Laplacian, "Laplacian"; Custom, "Custom steps"];
  same_cook "attribute blur unset names" ~typed:(Sop.attribute_blur ~group:" "
      ~weight_attribute:" " ~alpha_attribute:" " filter_input)
    ~factory:Nodes.Attribute_blur.factory ["group", Parameter.Text_value " ";
      "weight_attribute", Text_value " "; "alpha_attribute", Text_value " "] filter_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "attribute blur refuses invalid parameters at construction")
    [ (fun () -> Sop.attribute_blur ~iterations:(-1) filter_input);
      (fun () -> Sop.attribute_blur ~laplacian_step:nan filter_input);
      (fun () -> Sop.attribute_blur ~original_blend:infinity filter_input);
      (fun () -> Sop.attribute_blur ~attributes:"broken[" filter_input) ];
  let graph_colored = Sop.graph_color normal_input in
  same_cook "graph color defaults" ~typed:graph_colored
    ~factory:Nodes.Graph_color.factory [] normal_input;
  cache_identity "graph color all fields" (Sop.graph_color ~sort_output:true normal_input);
  List.iter (fun (connectivity, choice) ->
    same_cook ("graph color connectivity " ^ choice)
      ~typed:(Sop.graph_color ~connectivity normal_input) ~factory:Nodes.Graph_color.factory
      ["connectivity", Parameter.Choice_value choice] normal_input)
    [Rdk.Graph_color.Graph_primitives_by_point, "Primitives by point";
     Graph_points_by_primitive, "Points by primitive"; Graph_primitives_by_edge, "Primitives by edge"];
  List.iter (fun (group_owner, choice) ->
    same_cook ("graph color selection " ^ choice) ~typed:(Sop.graph_color ~group_owner
        ~group:"selection" ~color_attribute:"schedule" ~sort_output:true ~output_worksets:true
        ~workset_begin_attribute:"begin" ~workset_length_attribute:"length" normal_input)
      ~factory:Nodes.Graph_color.factory ["group_owner", Parameter.Choice_value choice;
        "group", Text_value "selection"; "color_attribute", Text_value "schedule";
        "sort_output", Bool_value true; "output_worksets", Bool_value true;
        "workset_begin_attribute", Text_value "begin";
        "workset_length_attribute", Text_value "length"] normal_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "graph color refuses invalid output names at construction")
    [ (fun () -> Sop.graph_color ~color_attribute:"P" normal_input);
      (fun () -> Sop.graph_color ~output_worksets:true normal_input);
      (fun () -> Sop.graph_color ~sort_output:true ~output_worksets:true
        ~workset_begin_attribute:"same" ~workset_length_attribute:"same" normal_input) ];
  let normal = Sop.normals normal_input in
  same_cook "normal Lisp defaults" ~typed:normal ~factory:Nodes.Normal.factory [] normal_input;
  cache_identity "normal all fields" normal;
  List.iter (fun (owner, choice) ->
    same_cook ("normal output " ^ choice) ~typed:(Sop.normals ~owner normal_input)
      ~factory:Nodes.Normal.factory ["owner", Parameter.Choice_value choice] normal_input)
    [Rdk.Attribute.Point, "Point"; Vertex, "Vertex"; Primitive, "Primitive"; Detail, "Detail"];
  List.iter (fun (group_owner, choice) ->
    same_cook ("normal selection " ^ choice) ~typed:(Sop.normals ~group_owner ~group:"selection"
        ~weighting:Rdk.Normal_ops.Each_vertex ~cusp_angle:0.5 ~keep_original_zero:true
        ~reverse:true ~attribute:"normal" normal_input) ~factory:Nodes.Normal.factory
      ["group_owner", Parameter.Choice_value choice; "group", Text_value "selection";
       "weighting", Choice_value "Each vertex"; "cusp_angle", Float_value 0.5;
       "keep_original_zero", Bool_value true; "reverse", Bool_value true;
       "attribute", Text_value "normal"] normal_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "normal face-area weighting" ~typed:(Sop.normals ~weighting:Rdk.Normal_ops.Face_area normal_input)
    ~factory:Nodes.Normal.factory ["weighting", Parameter.Choice_value "Face area"] normal_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "normal refuses invalid cusp angles at construction")
    [ (fun () -> Sop.normals ~cusp_angle:nan normal_input);
      (fun () -> Sop.normals ~cusp_angle:(-1.) normal_input);
      (fun () -> Sop.normals ~cusp_angle:4. normal_input) ];
  let peak_input = normal_input
      |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"N" ~value:Vec3.unit_y
      |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"flow" ~value:(Vec3.create 2. 0. 0.)
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"mask" ~value:0.5 in
  let peaked = Sop.peak peak_input in
  same_cook "peak Lisp defaults" ~typed:peaked ~factory:Nodes.Peak.factory [] peak_input;
  cache_identity "peak all fields" peaked;
  List.iter (fun (group_owner, choice) ->
    same_cook ("peak selection " ^ choice) ~typed:(Sop.peak ~group_owner ~group:"selection"
        ~direction_attribute:"flow" ~normalize_direction:false ~mask_attribute:"mask"
        ~distance:0.2 ~recompute_normals:true peak_input) ~factory:Nodes.Peak.factory
      ["group_owner", Parameter.Choice_value choice; "group", Text_value "selection";
       "direction_attribute", Text_value "flow"; "normalize_direction", Bool_value false;
       "mask_attribute", Text_value "mask"; "distance", Float_value 0.2;
       "recompute_normals", Bool_value true] peak_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "peak generated direction" ~typed:(Sop.peak ~direction_attribute:"" peak_input)
    ~factory:Nodes.Peak.factory ["direction_attribute", Parameter.Text_value ""] peak_input;
  check (try ignore (Sop.peak ~distance:nan peak_input); false with Invalid_argument _ -> true)
    "peak refuses non-finite distance at construction";
  let bent = Sop.bend peak_input in
  same_cook "bend Lisp defaults" ~typed:bent ~factory:Nodes.Bend.factory [] peak_input;
  cache_identity "bend all fields" bent;
  List.iter (fun (group_owner, choice) ->
    same_cook ("bend selection " ^ choice) ~typed:(Sop.bend ~group_owner ~group:"selection"
        ~mask_attribute:"mask" ~origin:(Vec3.create 0.1 0.2 0.3)
        ~direction:(Vec3.create 1. 0. 1.) ~up:Vec3.unit_y ~length:2.
        ~bend_angle:0.4 ~twist_angle:0.6 ~limit:false ~both_directions:true
        ~continuous_twist:true ~capture_attribute:"capture" ~recompute_normals:true peak_input)
      ~factory:Nodes.Bend.factory ["group_owner", Parameter.Choice_value choice; "group", Text_value "selection";
        "mask_attribute", Text_value "mask"; "origin_x", Float_value 0.1; "origin_y", Float_value 0.2;
        "origin_z", Float_value 0.3; "direction_x", Float_value 1.; "direction_y", Float_value 0.;
        "direction_z", Float_value 1.; "up_y", Float_value 1.; "up_z", Float_value 0.;
        "length", Float_value 2.; "bend_angle", Float_value 0.4; "twist_angle", Float_value 0.6;
        "limit", Bool_value false; "both_directions", Bool_value true; "continuous_twist", Bool_value true;
        "capture_attribute", Text_value "capture"; "recompute_normals", Bool_value true] peak_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "bend refuses invalid capture fields at construction")
    [ (fun () -> Sop.bend ~length:0. peak_input);
      (fun () -> Sop.bend ~direction:Vec3.zero peak_input);
      (fun () -> Sop.bend ~direction:Vec3.unit_y ~up:Vec3.unit_y peak_input);
      (fun () -> Sop.bend ~bend_angle:nan peak_input);
      (fun () -> Sop.bend ~capture_attribute:"P" peak_input) ];
  check (Result.is_error (Node.apply_parameters bent ["length", Parameter.Float_value 0.]))
    "bend rejects zero-length edits";
  let clipped = Sop.clip normal_input in
  same_cook "clip defaults" ~typed:clipped ~factory:Nodes.Clip.factory [] normal_input;
  cache_identity "clip all fields" (Sop.clip ~keep:Rdk.Plane_clip.All normal_input);
  List.iter (fun (group_owner, choice) ->
    same_cook ("clip selection " ^ choice) ~typed:(Sop.clip ~group_owner ~group:"selection" normal_input)
      ~factory:Nodes.Clip.factory ["group_owner", Parameter.Choice_value choice;
        "group", Text_value "selection"] normal_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex"; Element_primitive, "Primitive"; Element_edge, "Edge"];
  same_cook "clip explicit fields" ~typed:(Sop.clip ~group_owner:Sop.Element_edge ~group:"selection"
      ~keep:Rdk.Plane_clip.All ~snapping_tolerance:0.001 ~fill:true ~split_connectivity:true
      ~distance:0.1 ~origin:(Vec3.create 0. 0.1 0.) ~replace_existing_groups:true
      ~clipped_edge_group:"edges" ~cap_group:"caps" ~clipped_group:"clipped"
      ~above_group:"above" ~below_group:"below" normal_input) ~factory:Nodes.Clip.factory
    ["group_owner", Parameter.Choice_value "Edge"; "group", Text_value "selection";
      "keep", Choice_value "All"; "snapping_tolerance", Float_value 0.001; "fill", Bool_value true;
      "split_connectivity", Bool_value true; "distance", Float_value 0.1; "origin_y", Float_value 0.1;
      "replace_existing_groups", Bool_value true; "clipped_edge_group", Text_value "edges";
      "cap_group", Text_value "caps"; "clipped_group", Text_value "clipped";
      "above_group", Text_value "above"; "below_group", Text_value "below"] normal_input;
  same_cook "clip unset attribute" ~typed:(Sop.clip ~clip_attribute:"" normal_input)
    ~factory:Nodes.Clip.factory ["clip_attribute", Parameter.Text_value ""] normal_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "clip refuses invalid plane fields at construction")
    [ (fun () -> Sop.clip ~normal:Vec3.zero normal_input);
      (fun () -> Sop.clip ~distance:nan normal_input);
      (fun () -> Sop.clip ~snapping_tolerance:(-1.) normal_input);
      (fun () -> Sop.clip ~split_connectivity:true normal_input);
      (fun () -> Sop.clip ~cap_group:"same" ~above_group:"same" normal_input) ];
  let expand_input = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:3 ~rows:2 ~size:2. ()
      |> Sop.group ~name:"group" (Select.point_indices [|0|])
      |> Sop.group ~name:"group" (Select.vertex_indices [|0|])
      |> Sop.group ~name:"group" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"group"
      |> Sop.group_edges ~name:"collision"
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"region" ~value:0
      |> (Sop.normals ~weighting:(Rdk.Normal_ops.Face_area) ~owner:(Rdk.Attribute.Point))
      |> Sop.set_vector ~owner:Rdk.Attribute.Primitive ~name:"N" ~value:Vec3.unit_y in
  let expanded = Sop.group_expand expand_input in
  same_cook "group expand defaults" ~typed:expanded ~factory:Nodes.Group_expand.factory [] expand_input;
  cache_identity ~changes:["connectivity_attributes", Parameter.Text_value "primitive\tregion"]
    "group expand all fields" expanded;
  List.iter (fun (owner, choice) ->
    same_cook ("group expand " ^ choice) ~typed:(Sop.group_expand ~owner expand_input)
      ~factory:Nodes.Group_expand.factory ["owner", Parameter.Choice_value choice] expand_input)
    [Rdk.Group_ops.Group_vertices, "Vertices"; Group_primitives, "Primitives"; Group_edges, "Edges"];
  same_cook "group expand constraints" ~typed:(Sop.group_expand ~owner:Rdk.Group_ops.Group_primitives
      ~name:"expanded" ~flood:true ~steps:2 ~step_attribute:"growth"
      ~primitive_connectivity:Rdk.Group_ops.Primitive_share_edges ~normal_spread:0.1
      ~use_normal_attribute:true ~normal_owner:Rdk.Attribute.Primitive ~normal_name:"N"
      ~connectivity_attributes:[{Rdk.Group_ops.boundary_attribute_owner=Rdk.Attribute.Primitive;
        boundary_attribute_pattern="region"}] ~connectivity_tolerance:0.001
      ~use_collision:true ~collision_owner:Rdk.Group_ops.Group_primitives ~collision_group:"group"
      ~collision_contain:true ~collision_allow_boundary:true expand_input)
    ~factory:Nodes.Group_expand.factory ["owner", Parameter.Choice_value "Primitives";
      "name", Text_value "expanded"; "flood", Bool_value true; "steps", Int_value 2;
      "step_attribute", Text_value "growth"; "primitive_connectivity", Choice_value "Share edges";
      "normal_spread", Float_value 0.1; "use_normal_attribute", Bool_value true;
      "connectivity_attributes", Text_value "primitive\tregion"; "connectivity_tolerance", Float_value 0.001;
      "use_collision", Bool_value true; "collision_owner", Choice_value "Primitives";
      "collision_group", Text_value "group"; "collision_contain", Bool_value true;
      "collision_allow_boundary", Bool_value true] expand_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "group expand refuses invalid fields at construction")
    [ (fun () -> Sop.group_expand ~normal_spread:nan expand_input);
      (fun () -> Sop.group_expand ~connectivity_tolerance:(-1.) expand_input);
      (fun () -> Sop.group_expand ~use_collision:true ~collision_contain:true expand_input);
      (fun () -> Sop.group_expand ~flood:true ~steps:(-1) expand_input) ];
  let curvature_input = Sop.snapshot (Test_measure_curvature_sop.source ()) in
  let curvature = Sop.measure_curvature curvature_input in
  same_cook "measure curvature defaults" ~typed:curvature
    ~factory:Nodes.Measure_curvature.factory [] curvature_input;
  cache_identity "measure curvature" curvature;
  same_cook "measure curvature explicit fields" ~typed:(Sop.measure_curvature ~point_group:"upper"
      ~boundary:Rdk.Curvature.Curvature_boundary_one_sided ~smoothing_iterations:2
      ~smoothing_strength:0.25 ~mean:"mean" ~gaussian:"gaussian" ~minimum:"minimum"
      ~maximum:"maximum" ~curvedness:"curvedness" ~shape_index:"shape_index" curvature_input)
    ~factory:Nodes.Measure_curvature.factory ["point_group", Parameter.Text_value "upper";
      "boundary", Choice_value "One-sided"; "smoothing_iterations", Int_value 2;
      "smoothing_strength", Float_value 0.25; "mean", Text_value "mean";
      "gaussian", Text_value "gaussian"; "minimum", Text_value "minimum";
      "maximum", Text_value "maximum"; "curvedness", Text_value "curvedness";
      "shape_index", Text_value "shape_index"] curvature_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "measure curvature refuses invalid fields at construction")
    [ (fun () -> Sop.measure_curvature ~mean:"" curvature_input);
      (fun () -> Sop.measure_curvature ~gaussian:"curvature" curvature_input);
      (fun () -> Sop.measure_curvature ~mean:"P" curvature_input);
      (fun () -> Sop.measure_curvature ~smoothing_iterations:(-1) curvature_input) ];
  check (Result.is_error (Node.apply_parameters curvature ["gaussian", Parameter.Text_value "curvature"]))
    "measure curvature rejects duplicate output edits";
  let laplacian_input = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:3 ~rows:3 ~size:2. ()
      |> Sop.group ~name:"selection" (Select.point_indices [|4; 5|])
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"height" ~value:0.5 in
  let laplacian = Sop.attribute_laplacian laplacian_input in
  same_cook "attribute Laplacian Lisp defaults" ~typed:laplacian
    ~factory:Nodes.Attribute_laplacian.factory [] laplacian_input;
  cache_identity "attribute Laplacian" laplacian;
  List.iter (fun (weighting, choice) ->
    same_cook ("attribute Laplacian " ^ choice) ~typed:(Sop.attribute_laplacian
        ~point_group:"selection" ~weighting ~normalize:false ~source:"height" ~output:"L" laplacian_input)
      ~factory:Nodes.Attribute_laplacian.factory ["point_group", Parameter.Text_value "selection";
        "weighting", Choice_value choice; "normalize", Bool_value false;
        "source", Text_value "height"; "output", Text_value "L"] laplacian_input)
    [Rdk.Laplacian.Laplacian_cotan, "Cotangent"; Laplacian_positive_cotan, "Positive cotangent";
     Laplacian_uniform, "Uniform"];
  check (Result.is_error (Node.apply_parameters laplacian ["output", Parameter.Text_value "P"]))
    "attribute Laplacian rejects canonical position edits";
  let seam_input = Sop.snapshot (Test_point_split_sop.source ())
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"piece" ~value:0 in
  let seamed = Sop.uv_auto_seam seam_input in
  same_cook "UV auto seam defaults" ~typed:seamed ~factory:Nodes.Uv_auto_seam.factory [] seam_input;
  cache_identity "UV auto seam" seamed;
  same_cook "UV auto seam explicit fields" ~typed:(Sop.uv_auto_seam ~name:"seams"
      ~group:"seam_face" ~angle:0.5 ~include_boundaries:false ~include_non_manifold:false
      ~partition_attribute:"piece" ~existing_uv:"uv" ~uv_tolerance:0.001
      ~island_attribute:"island" seam_input) ~factory:Nodes.Uv_auto_seam.factory
    ["name", Parameter.Text_value "seams"; "group", Text_value "seam_face";
     "angle", Float_value 0.5; "include_boundaries", Bool_value false;
     "include_non_manifold", Bool_value false; "partition_attribute", Text_value "piece";
     "existing_uv", Text_value "uv"; "uv_tolerance", Float_value 0.001;
     "island_attribute", Text_value "island"] seam_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "UV auto seam refuses invalid numeric fields at construction")
    [ (fun () -> Sop.uv_auto_seam ~angle:nan seam_input);
      (fun () -> Sop.uv_auto_seam ~angle:4. seam_input);
      (fun () -> Sop.uv_auto_seam ~uv_tolerance:(-1.) seam_input) ];
  let split_input = Sop.snapshot (Test_point_split_sop.source ())
      |> Sop.group ~name:"selected_vertices" (Select.vertex_indices [|0; 3|]) in
  let split = Sop.point_split split_input in
  same_cook "point split Lisp defaults" ~typed:split ~factory:Nodes.Point_split.factory [] split_input;
  cache_identity "point split" split;
  List.iter (fun (owner, choice, group) ->
    same_cook ("point split " ^ choice) ~typed:(Sop.point_split ~group_owner:owner ~group
        ~attributes:"uv" ~tolerance:1e-6 ~promote_attributes:true split_input)
      ~factory:Nodes.Point_split.factory ["group_owner", Parameter.Choice_value choice;
        "group", Text_value group; "attributes", Text_value "uv"; "tolerance", Float_value 1e-6;
        "promote_attributes", Bool_value true] split_input)
    [Sop.Element_point, "Point", "split_points"; Element_vertex, "Vertex", "selected_vertices";
     Element_primitive, "Primitive", "seam_face"];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "point split refuses invalid fields at construction")
    [ (fun () -> Sop.point_split ~group_owner:Sop.Element_edge ~group:"selection" split_input);
      (fun () -> Sop.point_split ~tolerance:(-1.) split_input);
      (fun () -> Sop.point_split ~tolerance:nan split_input) ];
  let relax_input = Sop.polyline [|0.,0.,0.; 1.,0.,0.; 3.,0.,0.; 6.,0.,0.|]
      |> Sop.group ~name:"selection" (Select.point_indices [|1; 2|])
      |> Sop.group ~name:"selection" (Select.primitive_indices [|0|])
      |> Sop.group ~name:"pins" (Select.point_indices [|0|]) in
  let relax_reference = Sop.polyline [|0.,0.,0.; 2.,0.,0.; 3.,0.,0.; 7.,0.,0.|] in
  let relaxed = Sop.edge_relax relax_input relax_reference in
  same_cook ~inputs:[relax_reference] "edge relax Lisp defaults" ~typed:relaxed
    ~factory:Nodes.Edge_relax.factory [] relax_input;
  List.iter (fun (owner, choice) ->
    same_cook ~inputs:[relax_reference] ("edge relax " ^ choice)
      ~typed:(Sop.edge_relax ~group_owner:owner ~group:"selection" ~pin_group:"pins"
        ~iterations:8 ~step_size:0.25 ~target_mode:Rdk.Edge_relax.Scale_independent_distribution
        ~only_shorten:true ~tolerance:0.001 relax_input relax_reference)
      ~factory:Nodes.Edge_relax.factory ["group_owner", Parameter.Choice_value choice;
        "group", Text_value "selection"; "pin_group", Text_value "pins"; "iterations", Int_value 8;
        "step_size", Float_value 0.25; "target_mode", Choice_value "Scale-independent distribution";
        "only_shorten", Bool_value true; "tolerance", Float_value 0.001] relax_input)
    [Sop.Element_point, "Point"; Element_primitive, "Primitive"];
  cache_identity ~changes:["group_owner", Parameter.Choice_value "Primitive"] "edge relax all fields"
    (Sop.edge_relax ~group_owner:Sop.Element_point ~group:"selection" relax_input relax_reference);
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "edge relax refuses invalid fields at construction")
    [ (fun () -> Sop.edge_relax ~group_owner:Sop.Element_vertex ~group:"selection" relax_input relax_reference);
      (fun () -> Sop.edge_relax ~iterations:0 relax_input relax_reference);
      (fun () -> Sop.edge_relax ~step_size:nan relax_input relax_reference);
      (fun () -> Sop.edge_relax ~step_size:1.1 relax_input relax_reference);
      (fun () -> Sop.edge_relax ~tolerance:0. relax_input relax_reference) ];
  check (Result.is_error (Node.apply_parameters relaxed ["step_size", Parameter.Float_value 0.]))
    "edge relax rejects zero step-size edits";
  let hull_input = Test_convex_hull_sop.source ()
      |> Sop.group ~name:"bottom" (Select.point_indices [|0; 1; 2; 3|]) in
  let hull = Sop.convex_hull hull_input in
  same_cook "convex hull Lisp defaults" ~typed:hull ~factory:Nodes.Convex_hull.factory [] hull_input;
  cache_identity "convex hull" hull;
  same_cook "convex hull selection" ~typed:(Sop.convex_hull ~group_owner:Sop.Element_point
      ~group:"bottom" ~preserve_point_payload:false ~source_point_attribute:"source"
      ~hull_group:"plane" hull_input) ~factory:Nodes.Convex_hull.factory
    ["group", Parameter.Text_value "bottom"; "preserve_point_payload", Bool_value false;
     "source_point_attribute", Text_value "source"; "hull_group", Text_value "plane"] hull_input;
  check (Result.is_error (Node.apply_parameters hull ["source_point_attribute", Parameter.Text_value "P"]))
    "convex hull rejects reserved ancestry edits";
  let grouped_hull_input = Sop.box ()
      |> Sop.group ~name:"selection" (Select.point_indices [|0; 1; 2; 3|])
      |> Sop.group ~name:"selection" (Select.vertex_indices [|0; 1; 2; 3|])
      |> Sop.group ~name:"selection" (Select.primitive_indices [|0|])
      |> Sop.group_edges ~name:"selection" in
  List.iter (fun (owner, choice) ->
    same_cook ("convex hull " ^ choice) ~typed:(Sop.convex_hull ~group_owner:owner
        ~group:"selection" grouped_hull_input) ~factory:Nodes.Convex_hull.factory
      ["group_owner", Parameter.Choice_value choice; "group", Text_value "selection"] grouped_hull_input)
    [Sop.Element_point, "Point"; Element_vertex, "Vertex";
     Element_primitive, "Primitive"; Element_edge, "Edge"];
  let bridge_input = Sop.snapshot (Test_poly_bridge_sop.bridge_source ()) in
  let bridged = Sop.poly_bridge bridge_input in
  same_cook "poly bridge Lisp defaults" ~typed:bridged ~factory:Nodes.Poly_bridge.factory [] bridge_input;
  cache_identity "poly bridge" bridged;
  same_cook "poly bridge explicit fields" ~typed:(Sop.poly_bridge
      ~pairing:Rdk.Poly_bridge.Bridge_by_centroid ~connect_closest_ends:false
      ~minimize:Rdk.Poly_loft.Three_point_distance ~reverse_source:true
      ~reverse_destination:true ~pairing_shift:1 ~divisions:2 ~keep_input:false
      ~output_group:"surface" ~collinearity_tolerance:0.1 ~recompute_normals:true bridge_input)
    ~factory:Nodes.Poly_bridge.factory ["pairing", Parameter.Choice_value "By centroid";
      "connect_closest_ends", Bool_value false; "minimize", Choice_value "Three point distance";
      "reverse_source", Bool_value true; "reverse_destination", Bool_value true;
      "pairing_shift", Int_value 1; "divisions", Int_value 2; "keep_input", Bool_value false;
      "output_group", Text_value "surface"; "collinearity_tolerance", Float_value 0.1;
      "recompute_normals", Bool_value true] bridge_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "poly bridge refuses invalid numeric fields at construction")
    [ (fun () -> Sop.poly_bridge ~divisions:0 bridge_input);
      (fun () -> Sop.poly_bridge ~collinearity_tolerance:1.1 bridge_input);
      (fun () -> Sop.poly_bridge ~collinearity_tolerance:nan bridge_input) ];
  let circle_input = Sop.snapshot (Test_circle_from_edges_sop.loop_geometry 2 16) in
  let fitted = Sop.circle_from_edges circle_input in
  same_cook "circle from edges defaults" ~typed:fitted
    ~factory:Nodes.Circle_from_edges.factory [] circle_input;
  cache_identity "circle from edges" fitted;
  same_cook "circle from edges explicit fields" ~typed:(Sop.circle_from_edges
      ~group:"loops" ~use_radius:true ~radius:1.5 ~scale:(Rays_math.Vec3.create 1. 0.75 0.5)
      ~output_group:"fitted" circle_input) ~factory:Nodes.Circle_from_edges.factory
    ["group", Parameter.Text_value "loops"; "use_radius", Bool_value true;
     "radius", Float_value 1.5; "scale_y", Float_value 0.75; "scale_z", Float_value 0.5;
     "output_group", Text_value "fitted"] circle_input;
  check (Result.is_error (Node.apply_parameters fitted ["use_radius", Parameter.Bool_value true;
      "radius", Float_value 0.])) "circle from edges rejects enabled zero-radius edits";
  let resample_input = Sop.merge [
      Sop.polyline [|(0., 0., 0.); (2., 0., 0.)|];
      Sop.polyline [|(10., 0., 0.); (11., 1., 0.); (12., 0., 0.)|] ]
      |> Sop.group ~name:"first_curve" (Select.primitive_indices [|0|])
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"counts" ~value:4
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"lengths" ~value:0.4 in
  let resampled = Sop.resample resample_input in
  same_cook "resample Lisp defaults" ~typed:resampled ~factory:Nodes.Resample.factory [] resample_input;
  List.iter (fun (name, typed, values) ->
    same_cook name ~typed ~factory:Nodes.Resample.factory values resample_input)
    [ "resample attribute sizing", Sop.resample ~use_segments:false ~segments_attribute:"counts" resample_input,
      ["use_segments", Parameter.Bool_value false; "segments_attribute", Text_value "counts"];
      "resample length sizing", Sop.resample ~use_segments:false
        ~use_maximum_segment_length:true ~maximum_segment_length:0.4 resample_input,
      ["use_segments", Bool_value false; "use_maximum_segment_length", Bool_value true;
       "maximum_segment_length", Float_value 0.4];
      "resample explicit fields", Sop.resample ~group:"first_curve" ~segments:4
        ~use_maximum_segment_length:true ~maximum_segment_length:0.4
        ~segment_length_attribute:"lengths" ~segments_attribute:"counts"
        ~even_last_segment:false ~curve_u_attribute:"u" ~curve_number_attribute:"curve"
        ~distance_attribute:"distance" ~tangent_attribute:"tangent" resample_input,
      ["group", Text_value "first_curve"; "segments", Int_value 4;
       "use_maximum_segment_length", Bool_value true; "maximum_segment_length", Float_value 0.4;
       "segment_length_attribute", Text_value "lengths"; "segments_attribute", Text_value "counts";
       "even_last_segment", Bool_value false; "curve_u_attribute", Text_value "u";
       "curve_number_attribute", Text_value "curve"; "distance_attribute", Text_value "distance";
       "tangent_attribute", Text_value "tangent"] ];
  cache_identity "resample all fields" (Sop.resample ~segments_attribute:"counts" resample_input);
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "resample refuses invalid numeric fields at construction")
    [ (fun () -> Sop.resample ~segments:0 resample_input);
      (fun () -> Sop.resample ~maximum_segment_length:nan resample_input);
      (fun () -> Sop.resample ~use_segments:false resample_input);
      (fun () -> Sop.resample ~curve_u_attribute:"P" resample_input);
      (fun () -> Sop.resample ~curve_u_attribute:"u" ~distance_attribute:"u" resample_input);
      (fun () -> Sop.resample ~use_maximum_segment_length:true ~maximum_segment_length:0. resample_input) ];
  check (Result.is_error (Node.apply_parameters resampled ["use_maximum_segment_length", Bool_value true;
      "maximum_segment_length", Float_value 0.])) "resample rejects enabled zero-length edits";
  let carve_input = resample_input
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"first_u" ~value:0.2
      |> Sop.set_float ~owner:Rdk.Attribute.Primitive ~name:"last_u" ~value:0.8 in
  let carved = Sop.carve carve_input in
  same_cook "carve defaults" ~typed:carved ~factory:Nodes.Carve.factory [] carve_input;
  cache_identity ~changes:["last", Float_value 0.75] "carve all fields" carved;
  List.iter (fun keep ->
    let choice = match keep with Rdk.Curve_ops.Inside -> "Inside"
      | Outside -> "Outside" | Inside_and_outside -> "Inside and outside" in
    same_cook ("carve " ^ choice) ~typed:(Sop.carve ~first:0.2 ~last:0.8 ~keep carve_input)
      ~factory:Nodes.Carve.factory ["first", Float_value 0.2; "last", Float_value 0.8;
        "keep", Choice_value choice] carve_input)
    [Rdk.Curve_ops.Inside; Outside; Inside_and_outside];
  same_cook "carve explicit fields" ~typed:(Sop.carve ~group:"first_curve"
      ~relative_arc_length:false ~first:0.2 ~last:0.8 ~first_attribute:"first_u"
      ~last_attribute:"last_u" ~attribute_mode:Rdk.Curve_ops.Scale
      ~only_at_breakpoints:true ~cut_at_all_internal_breakpoints:true
      ~keep:Rdk.Curve_ops.Inside_and_outside ~divisions:2 ~keep_original:true carve_input)
    ~factory:Nodes.Carve.factory ["group", Text_value "first_curve";
      "relative_arc_length", Bool_value false; "first", Float_value 0.2; "last", Float_value 0.8;
      "first_attribute", Text_value "first_u"; "last_attribute", Text_value "last_u";
      "attribute_mode", Choice_value "Scale"; "only_at_breakpoints", Bool_value true;
      "cut_at_all_internal_breakpoints", Bool_value true; "keep", Choice_value "Inside and outside";
      "divisions", Int_value 2; "keep_original", Bool_value true] carve_input;
  same_cook "carve equal extraction" ~typed:(Sop.carve ~first:0.5 ~last:0.5 ~extract_points:true carve_input)
    ~factory:Nodes.Carve.factory ["first", Float_value 0.5; "last", Float_value 0.5;
      "extract_points", Bool_value true] carve_input;
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "carve refuses invalid numeric fields at construction")
    [ (fun () -> Sop.carve ~first:nan carve_input);
      (fun () -> Sop.carve ~first:(-0.1) carve_input);
      (fun () -> Sop.carve ~first:0.8 ~last:0.2 carve_input);
      (fun () -> Sop.carve ~first:0.5 ~last:0.5 carve_input) ];
  check (Result.is_error (Node.apply_parameters carved ["last", Float_value 0.]))
    "carve rejects collapsed non-extraction edits";
  let loft_input = resample_input
      |> Sop.group ~name:"both_curves" (Select.primitive_indices [|0; 1|]) in
  List.iter (fun (name, factory, default, explicit) ->
    same_cook ~optional_inputs:[Some loft_input; None] (name ^ " Lisp defaults")
      ~typed:(default None) ~factory [] loft_input;
    same_cook ~optional_inputs:[Some loft_input; Some loft_input] (name ^ " rest input")
      ~typed:(default (Some loft_input)) ~factory [] loft_input;
    cache_identity name (default None);
    same_cook ~optional_inputs:[Some loft_input; Some loft_input] (name ^ " explicit fields")
      ~typed:(explicit ()) ~factory ["group", Text_value "both_curves";
        "connect_closest_ends", Bool_value false; "minimize", Choice_value "Three point distance";
        "u_wrap", Bool_value true; "v_wrap", Bool_value true; "keep_primitives", Bool_value true;
        "output_group", Text_value "surface"; "collinearity_tolerance", Float_value 0.1;
        "recompute_normals", Bool_value false] loft_input)
    [ "poly loft", Nodes.Poly_loft.factory, (fun rest -> Sop.poly_loft loft_input rest),
      (fun () -> Sop.poly_loft ~group:"both_curves" ~connect_closest_ends:false
        ~minimize:Rdk.Poly_loft.Three_point_distance ~u_wrap:true ~v_wrap:true
        ~keep_primitives:true ~output_group:"surface" ~collinearity_tolerance:0.1
        ~recompute_normals:false loft_input (Some loft_input));
      "skin", Nodes.Skin.factory, (fun rest -> Sop.skin loft_input rest),
      (fun () -> Sop.skin ~group:"both_curves" ~connect_closest_ends:false
        ~minimize:Rdk.Poly_loft.Three_point_distance ~u_wrap:true ~v_wrap:true
        ~keep_primitives:true ~output_group:"surface" ~collinearity_tolerance:0.1
        ~recompute_normals:false loft_input (Some loft_input)) ];
  List.iter (fun make ->
    check (try ignore (make ()); false with Invalid_argument _ -> true)
      "loft/skin refuse invalid collinearity tolerance at construction")
    [ (fun () -> Sop.poly_loft ~collinearity_tolerance:1.1 loft_input None);
      (fun () -> Sop.skin ~collinearity_tolerance:nan loft_input None) ];
  let warped = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:6 ~rows:6 ~size:2. ()
      |> Sop.point_jitter ~seed:7 ~scale:0.3 in
  let remesh_input = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:2 ~rows:2 ~size:0.5 ()
      |> Sop.group ~name:"fixed" (Select.point_indices [|0|])
      |> Sop.group_edges ~name:"rim" ~incidence:Rdk.Group_mesh.Boundary_edge
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"mesh_target" ~value:0.3 in
  let remeshed = Sop.remesh remesh_input in
  same_cook "remesh Lisp defaults" ~typed:remeshed ~factory:Nodes.Remesh.factory [] remesh_input;
  cache_identity "remesh" remeshed;
  let explicit_remesh = Sop.remesh ~iterations:1 ~smoothing:0.25 ~project:false
      ~use_input_points_only:true ~hard_point_group:"fixed" ~hard_edge_group:"rim"
      ~target_size_attribute:"mesh_target" ~preserve_uv_seams:false ~uv_attribute:"other_uv"
      ~output_hard_edges:"hard" ~output_mesh_size:"lengths" ~output_quality:"quality"
      ~recompute_point_normals:false ~target_length:0.3 remesh_input in
  same_cook "remesh explicit fields" ~typed:explicit_remesh ~factory:Nodes.Remesh.factory
    [ "iterations", Parameter.Int_value 1; "smoothing", Float_value 0.25;
      "project", Bool_value false; "use_input_points_only", Bool_value true;
      "hard_point_group", Text_value "fixed"; "hard_edge_group", Text_value "rim";
      "target_size_attribute", Text_value "mesh_target";
      "preserve_uv_seams", Bool_value false; "uv_attribute", Text_value "other_uv";
      "output_hard_edges", Text_value "hard"; "output_mesh_size", Text_value "lengths";
      "output_quality", Text_value "quality"; "recompute_point_normals", Bool_value false;
      "target_length", Float_value 0.3 ] remesh_input;
  cache_identity "remesh explicit" explicit_remesh;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "remesh refuses invalid numeric fields at construction")
    [ (fun () -> Sop.remesh ~target_length:0. remesh_input);
      (fun () -> Sop.remesh ~target_length:nan remesh_input);
      (fun () -> Sop.remesh ~iterations:(-1) remesh_input);
      (fun () -> Sop.remesh ~smoothing:1.1 remesh_input);
      (fun () -> Sop.remesh ~smoothing:infinity remesh_input) ];
  check (Result.is_error (Node.apply_parameters remeshed ["target_length", Parameter.Float_value 0.]))
    "remesh rejects zero target-length edits";
  let equalize_input = Sop.polyline [|0.,0.,0.; 1.,0.,0.; 4.,0.,0.; 6.,0.,0.|]
      |> Sop.group_edges ~name:"uneven" in
  let equalized = Sop.edge_equalize equalize_input in
  same_cook "edge_equalize Lisp defaults" ~typed:equalized
    ~factory:Nodes.Edge_equalize.factory [] equalize_input;
  cache_identity "edge_equalize" equalized;
  List.iter (fun (method_, choice) ->
    same_cook ("edge_equalize " ^ choice)
      ~typed:(Sop.edge_equalize ~group:"uneven" ~method_ ~iterations:80
        ~tolerance:1e-7 ~output_group:"equalized" equalize_input)
      ~factory:Nodes.Edge_equalize.factory
      [ "group", Parameter.Text_value "uneven"; "method_", Choice_value choice;
        "iterations", Int_value 80; "tolerance", Float_value 1e-7;
        "output_group", Text_value "equalized" ] equalize_input)
    [ Rdk.Edge_ops.Equalize_average, "Average"; Rdk.Edge_ops.Equalize_longest, "Longest";
      Rdk.Edge_ops.Equalize_shortest, "Shortest" ];
  List.iter (fun tolerance ->
    check (match Sop.edge_equalize ~tolerance equalize_input with
      | _ -> false | exception Invalid_argument _ -> true)
      "edge_equalize refuses invalid tolerance at construction") [0.; -1.; nan; infinity];
  check (Result.is_error (Node.apply_parameters equalized
      ["tolerance", Parameter.Float_value 0.]))
    "edge_equalize returns an error for zero-tolerance edits";
  let delete_input = warped
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"keep" ~value:1.
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"drop" ~value:2. in
  let deleted = Sop.delete_attributes delete_input None in
  same_cook "delete_attributes Lisp defaults" ~typed:deleted
    ~factory:Nodes.Delete_attributes.factory ~optional_inputs:[Some delete_input; None] [] delete_input;
  cache_identity "delete_attributes" deleted;
  let reference = Sop.points [|0., 0., 0.|]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"keep" ~value:1. in
  let delete_values = [ "delete_non_selected", Parameter.Bool_value true;
      "point_pattern", Text_value "keep"; "vertex_pattern", Text_value "N";
      "primitive_pattern", Text_value "material"; "detail_pattern", Text_value "metadata" ] in
  let referenced_delete = Sop.delete_attributes ~delete_non_selected:true
      ~point_pattern:"keep" ~vertex_pattern:"N" ~primitive_pattern:"material"
      ~detail_pattern:"metadata" delete_input (Some reference) in
  same_cook "delete_attributes reference and patterns" ~typed:referenced_delete
    ~factory:Nodes.Delete_attributes.factory delete_values delete_input ~inputs:[reference];
  cache_identity "delete_attributes reference" referenced_delete;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "delete_attributes refuses invalid patterns at construction")
    [ (fun () -> Sop.delete_attributes ~point_pattern:"broken[" delete_input None);
      (fun () -> Sop.delete_attributes ~vertex_pattern:"broken[" delete_input None);
      (fun () -> Sop.delete_attributes ~primitive_pattern:"broken[" delete_input None);
      (fun () -> Sop.delete_attributes ~detail_pattern:"broken[" delete_input None) ];
  check (Result.is_error (Node.apply_parameters deleted
      ["point_pattern", Parameter.Text_value "broken["]))
    "delete_attributes returns an error for invalid pattern edits";
  let transport_input = Sop.merge [
      Sop.polyline [|0.,0.,0.; 1.,0.,0.; 3.,0.,0.|];
      Sop.polyline [|0.,2.,0.; 2.,2.,0.; 5.,2.,0.|] ]
      |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"value" ~value:1.
      |> Sop.set_float ~owner:Rdk.Attribute.Vertex ~name:"value" ~value:2.
      |> Sop.group ~name:"first" (Select.primitive_indices [|0|]) in
  let curve_transport = Sop.edge_transport_curves transport_input in
  same_cook "edge_transport_curves Lisp defaults" ~typed:curve_transport
    ~factory:Nodes.Edge_transport_curves.factory [] transport_input;
  cache_identity ~companions:transport_cache_companions "edge_transport_curves" curve_transport;
  let explicit_curve = Sop.edge_transport_curves ~primitive_group:"first"
      ~owner:Rdk.Attribute.Vertex ~direction:Rdk.Edge_transport.Transport_backward
      ~operation:Rdk.Edge_transport.Transport_total ~root_value:Rdk.Edge_transport.Transport_root_hold
      ~integrate_constant:true ~scale_by_edge_length:true
      ~normalization:Rdk.Edge_transport.Transport_normalize_components transport_input in
  same_cook "edge_transport_curves explicit fields" ~typed:explicit_curve
    ~factory:Nodes.Edge_transport_curves.factory
    [ "primitive_group", Parameter.Text_value "first"; "owner", Choice_value "Vertex";
      "direction", Choice_value "Backward"; "operation", Choice_value "Total";
      "root_value", Choice_value "Hold"; "integrate_constant", Bool_value true;
      "scale_by_edge_length", Bool_value true; "normalization", Choice_value "Per component" ] transport_input;
  cache_identity ~companions:transport_cache_companions "edge_transport_curves explicit" explicit_curve;
  let parent_geometry = cook 1 transport_input in
  let parent_attribute = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"parent"
      (Rdk.Attribute.Int (Array.init (Rdk.Geometry.point_count parent_geometry)
        (fun index -> max 0 (index - 1)))) |> Result.get_ok in
  let parent_input = Rdk.Geometry.with_attribute parent_attribute parent_geometry |> Result.get_ok
      |> Sop.snapshot |> Sop.group ~name:"all" Select.all_points in
  let parent_transport = Sop.edge_transport_parent parent_input in
  same_cook "edge_transport_parent Lisp defaults" ~typed:parent_transport
    ~factory:Nodes.Edge_transport_parent.factory [] parent_input;
  cache_identity ~companions:transport_cache_companions "edge_transport_parent" parent_transport;
  let explicit_parent = Sop.edge_transport_parent ~point_group:"all"
      ~direction:Rdk.Edge_transport.Transport_backward ~operation:Rdk.Edge_transport.Transport_total
      ~root_value:Rdk.Edge_transport.Transport_root_hold ~integrate_constant:true
      ~scale_by_edge_length:true ~split:Rdk.Edge_transport.Transport_split
      ~merge:Rdk.Edge_transport.Transport_merge_maximum
      ~normalization:Rdk.Edge_transport.Transport_normalize_global parent_input in
  same_cook "edge_transport_parent explicit fields" ~typed:explicit_parent
    ~factory:Nodes.Edge_transport_parent.factory
    [ "point_group", Parameter.Text_value "all"; "direction", Choice_value "Backward";
      "operation", Choice_value "Total"; "root_value", Choice_value "Hold";
      "integrate_constant", Bool_value true; "scale_by_edge_length", Bool_value true;
      "split", Choice_value "Split"; "merge", Choice_value "Maximum";
      "normalization", Choice_value "Global" ] parent_input;
  cache_identity ~companions:transport_cache_companions "edge_transport_parent explicit" explicit_parent;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "edge transports refuse invalid fields at construction")
    [ (fun () -> Sop.edge_transport_curves ~attribute:"P" transport_input);
      (fun () -> Sop.edge_transport_curves ~owner:Rdk.Attribute.Primitive transport_input);
      (fun () -> Sop.edge_transport_parent ~attribute:"" parent_input);
      (fun () -> Sop.edge_transport_parent ~parent_attribute:" " parent_input) ];
  let normal_group = Sop.group_normal warped in
  same_cook "group_normal Lisp defaults" ~typed:normal_group
    ~factory:Nodes.Group_normal.factory [] warped;
  cache_identity "group_normal" normal_group;
  List.iter (fun (owner, choice) ->
    same_cook ("group_normal " ^ choice)
      ~typed:(Sop.group_normal ~owner ~use_existing_normal:false warped)
      ~factory:Nodes.Group_normal.factory
      ["owner", Parameter.Choice_value choice; "use_existing_normal", Bool_value false] warped)
    [ Rdk.Group_ops.Group_points, "Points";
      Rdk.Group_ops.Group_primitives, "Primitives"; Rdk.Group_ops.Group_edges, "Edges" ];
  let normal_input = warped
      |> Sop.set_vector ~owner:Rdk.Attribute.Point ~name:"N" ~value:Vec3.unit_y
      |> Sop.group ~name:"base" Select.all_points in
  let explicit_normal = Sop.group_normal ~owner:Rdk.Group_ops.Group_points
      ~name:"facing" ~normal_attribute:"N" ~base:"base" ~include_opposite:true
      ~merge:Rdk.Group_ops.Group_union ~direction:(Vec3.create 1. 1. 0.)
      ~spread_angle:(Float.pi /. 2.) normal_input in
  same_cook "group_normal explicit fields" ~typed:explicit_normal
    ~factory:Nodes.Group_normal.factory
    [ "owner", Parameter.Choice_value "Points"; "name", Text_value "facing";
      "normal_attribute", Text_value "N"; "base", Text_value "base";
      "include_opposite", Bool_value true; "merge", Choice_value "Union";
      "direction_x", Float_value 1.; "direction_y", Float_value 1.;
      "direction_z", Float_value 0.; "spread_angle", Float_value (Float.pi /. 2.) ] normal_input;
  cache_identity "group_normal explicit" explicit_normal;
  same_cook "group_normal blank optional names"
    ~typed:(Sop.group_normal ~normal_attribute:"" ~base:"" warped)
    ~factory:Nodes.Group_normal.factory [] warped;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "group_normal refuses invalid fields at construction")
    [ (fun () -> Sop.group_normal ~direction:Vec3.zero warped);
      (fun () -> Sop.group_normal ~direction:(Vec3.create nan 0. 0.) warped);
      (fun () -> Sop.group_normal ~owner:Rdk.Group_ops.Group_vertices warped);
      (fun () -> Sop.group_normal ~spread_angle:(-1.) warped);
      (fun () -> Sop.group_normal ~spread_angle:infinity warped);
      (fun () -> Sop.group_normal ~spread_angle:(Float.pi +. 0.1) warped) ];
  check (Result.is_error (Node.apply_parameters normal_group
      ["direction_y", Parameter.Float_value 0.]))
    "group_normal rejects edits that make the direction zero";
  let ordered_default = Sop.ordered_group warped in
  same_cook "ordered_group Lisp defaults" ~typed:ordered_default
    ~factory:Nodes.Ordered_group.factory [] warped;
  cache_identity ~changes:["elements", Parameter.Text_value "1 0"]
    "ordered_group" ordered_default;
  List.iter (fun (owner, choice) ->
    same_cook ("ordered_group " ^ choice)
      ~typed:(Sop.ordered_group ~owner ~name:"authored" ~elements:[2; 0; 3] warped)
      ~factory:Nodes.Ordered_group.factory
      [ "owner", Parameter.Choice_value choice; "name", Text_value "authored";
        "elements", Text_value "2 0 3" ] warped)
    [ Rdk.Group.Point, "Points"; Rdk.Group.Vertex, "Vertices";
      Rdk.Group.Primitive, "Primitives" ];
  check (match Sop.ordered_group ~elements:[0; -1] warped with
      | _ -> false | exception Invalid_argument _ -> true)
    "ordered_group refuses negative indices at construction";
  let piece_input = warped
      |> Sop.set_int ~owner:Rdk.Attribute.Point ~name:"piece" ~value:0
      |> Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"piece" ~value:0 in
  let centroid = Sop.extract_centroid piece_input in
  same_cook "extract_centroid Lisp defaults" ~typed:centroid
    ~factory:Nodes.Extract_centroid.factory [] piece_input;
  cache_identity "extract_centroid" centroid;
  List.iter (fun (run_over, choice) ->
    same_cook ("extract_centroid " ^ choice)
      ~typed:(Sop.extract_centroid ~run_over piece_input)
      ~factory:Nodes.Extract_centroid.factory
      ["run_over", Parameter.Choice_value choice] piece_input)
    [ Sop.Detail, "Detail"; Sop.Primitives, "Primitives";
      Sop.Point_pieces, "Point pieces"; Sop.Primitive_pieces, "Primitive pieces" ];
  List.iter (fun (method_, choice) ->
    same_cook ("extract_centroid " ^ choice)
      ~typed:(Sop.extract_centroid ~method_ piece_input)
      ~factory:Nodes.Extract_centroid.factory
      ["method_", Parameter.Choice_value choice] piece_input)
    [ Rdk.Curve_topology.Centroid_point_mass, "Point mass";
      Rdk.Curve_topology.Centroid_bounding_box, "Bounding box";
      Rdk.Curve_topology.Centroid_convex_hull, "Convex hull" ];
  let piece_centroid = Sop.extract_centroid ~run_over:Sop.Primitive_pieces
      ~piece_attribute:"piece" ~source_primitive_attribute:"source"
      ~piece_output_attribute:"island" piece_input in
  same_cook "extract_centroid output fields" ~typed:piece_centroid
    ~factory:Nodes.Extract_centroid.factory
    [ "run_over", Parameter.Choice_value "Primitive pieces";
      "piece_attribute", Text_value "piece";
      "source_primitive_attribute", Text_value "source";
      "piece_output_attribute", Text_value "island" ] piece_input;
  cache_identity "extract_centroid pieces" piece_centroid;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "extract_centroid refuses invalid attributes at construction")
    [ (fun () -> Sop.extract_centroid ~run_over:Sop.Point_pieces ~piece_attribute:"P" piece_input);
      (fun () -> Sop.extract_centroid ~source_primitive_attribute:"P" piece_input);
      (fun () -> Sop.extract_centroid ~piece_output_attribute:"P" piece_input) ];
  let original_key = Node.parameter_key piece_centroid in
  check (Result.is_error (Node.apply_parameters piece_centroid
      ["piece_attribute", Parameter.Text_value "P"]))
    "extract_centroid returns an error for invalid record edits";
  check (Node.parameter_key piece_centroid = original_key)
    "extract_centroid preserves the existing node after invalid edits";
  List.iter (fun (name, typed, factory) ->
    same_cook name ~typed ~factory [] warped;
    check (Node.parameter_fields typed = []) (name ^ ": has no artificial fields");
    cache_identity name typed)
    [ "null", Sop.null warped, Nodes.Null.factory;
      "compact_points", Sop.compact_points warped, Nodes.Compact_points.factory ];
  let ranged = Sop.group_range warped in
  same_cook "group_range Lisp defaults" ~typed:ranged
    ~factory:Nodes.Group_range.factory [] warped;
  cache_identity "group_range" ranged;
  List.iter (fun (range_mode, choice) ->
    same_cook ("group_range " ^ choice)
      ~typed:(Sop.group_range ~range_mode ~start:1 ~end_:4 ~end_offset:2
        ~length:3 ~partition:1 ~partitions:3 warped)
      ~factory:Nodes.Group_range.factory
      [ "range_mode", Parameter.Choice_value choice; "start", Int_value 1;
        "end_", Int_value 4; "end_offset", Int_value 2; "length", Int_value 3;
        "partition", Int_value 1; "partitions", Int_value 3 ] warped)
    [ Sop.Start_end, "Start and end"; Sop.From_ends, "From ends";
      Sop.Start_length, "Start and length"; Sop.Partition, "Partition" ];
  List.iter (fun (connectivity_mode, choice) ->
    same_cook ("group_range " ^ choice)
      ~typed:(Sop.group_range ~connectivity_mode ~use_region:true ~region:0 warped)
      ~factory:Nodes.Group_range.factory
      [ "connectivity_mode", Parameter.Choice_value choice;
        "use_region", Bool_value true; "region", Int_value 0 ] warped)
    [ Sop.No_connectivity, "None"; Sop.Disconnected, "Disconnected regions";
      Sop.Connected, "Connected with seams" ];
  let range_input = warped
      |> Sop.group ~name:"cut" (Select.point_indices [|0; 1|])
      |> Sop.group ~name:"base" Select.all_points in
  let advanced_range = Sop.group_range ~name:"selected" ~base:"base"
      ~invert:true ~merge:Rdk.Group_ops.Group_union ~start:0 ~end_:3
      ~use_filter:true ~filter_select:2 ~filter_of:3 ~filter_offset:1
      ~connectivity_mode:Sop.Connected ~use_region:true ~region:0
      ~connectivity_attributes:"P" ~connectivity_tolerance:0.25
      ~use_collision:true ~collision_owner:Rdk.Group_ops.Group_points
      ~collision_pattern:"cut" ~keep_boundary:true ~remove_other_regions:true range_input in
  same_cook "group_range advanced fields" ~typed:advanced_range
    ~factory:Nodes.Group_range.factory
    [ "name", Parameter.Text_value "selected"; "base", Text_value "base";
      "invert", Bool_value true; "merge", Choice_value "Union";
      "start", Int_value 0; "end_", Int_value 3; "use_filter", Bool_value true;
      "filter_select", Int_value 2; "filter_of", Int_value 3; "filter_offset", Int_value 1;
      "connectivity_mode", Choice_value "Connected with seams";
      "use_region", Bool_value true; "region", Int_value 0;
      "connectivity_attributes", Text_value "P"; "connectivity_tolerance", Float_value 0.25;
      "use_collision", Bool_value true; "collision_owner", Choice_value "Points";
      "collision_pattern", Text_value "cut"; "keep_boundary", Bool_value true;
      "remove_other_regions", Bool_value true ] range_input;
  cache_identity "group_range advanced" advanced_range;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "group_range refuses invalid fields at construction")
    [ (fun () -> Sop.group_range ~length:(-1) warped);
      (fun () -> Sop.group_range ~partition:(-1) warped);
      (fun () -> Sop.group_range ~partitions:0 warped);
      (fun () -> Sop.group_range ~filter_select:(-1) warped);
      (fun () -> Sop.group_range ~filter_of:0 warped);
      (fun () -> Sop.group_range ~region:(-1) warped);
      (fun () -> Sop.group_range ~connectivity_tolerance:nan warped) ];
  let indexed = Sop.enumerate ~owner:Rdk.Attribute.Point ~name:"id" warped in
  let sorted = Sop.sort indexed in
  same_cook "sort Lisp defaults" ~typed:sorted ~factory:Nodes.Sort.factory [] indexed;
  cache_identity "sort" sorted;
  List.iter (fun (key, choice) ->
    same_cook ("sort " ^ choice) ~typed:(Sop.sort ~key indexed)
      ~factory:Nodes.Sort.factory ["key", Parameter.Choice_value choice] indexed)
    [ Sop.Sort_x, "X"; Sop.Sort_y, "Y"; Sop.Sort_z, "Z";
      Sop.Sort_distance, "Distance to point"; Sop.Sort_vector, "Along vector";
      Sop.Sort_attribute, "Attribute component"; Sop.Sort_vertex_order, "Vertex order";
      Sop.Sort_primitive_index, "Primitive index"; Sop.Sort_spatial, "Spatial locality";
      Sop.Sort_random, "Random"; Sop.Sort_index_attribute, "Index attribute";
      Sop.Sort_reverse, "Reverse"; Sop.Sort_shift, "Shift" ];
  same_cook "sort explicit vector fields"
    ~typed:(Sop.sort ~key:Sop.Sort_vector ~x:2. ~y:3. ~z:4.
      ~owner:Rdk.Ordering.Primitives ~descending:true ~output_indices:"rank" indexed)
    ~factory:Nodes.Sort.factory
    [ "key", Parameter.Choice_value "Along vector"; "x", Float_value 2.;
      "y", Float_value 3.; "z", Float_value 4.; "owner", Choice_value "Primitives";
      "descending", Bool_value true; "output_indices", Text_value "rank" ] indexed;
  same_cook "sort explicit random seed"
    ~typed:(Sop.sort ~key:Sop.Sort_random ~seed:73421 indexed)
    ~factory:Nodes.Sort.factory
    [ "key", Parameter.Choice_value "Random"; "seed", Int_value 73421 ] indexed;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "sort refuses invalid numeric fields at construction")
    [ (fun () -> Sop.sort ~x:nan indexed);
      (fun () -> Sop.sort ~component:(-1) indexed) ];
  let default_box = Sop.box () in
  same_generator "box Lisp defaults" ~typed:default_box ~factory:Nodes.Box.factory [];
  let auto_box = Sop.box ~normals:None () in
  same_generator "box Auto normals" ~typed:auto_box ~factory:Nodes.Box.factory
    ["normals", Parameter.Choice_value "Auto"];
  let point_box = Sop.box ~normals:None
      ~connectivity:Rdk.Box_generator.Box_lattice_points () in
  same_generator "box Auto point normals" ~typed:point_box ~factory:Nodes.Box.factory
    [ "normals", Parameter.Choice_value "Auto";
      "connectivity", Choice_value "Lattice points" ];
  check (Node.parameter_key default_box <> Node.parameter_key auto_box)
    "box: Auto has its own cache identity";
  cache_identity "box" default_box;
  let box = Sop.box ~normals:None ~connectivity:(Rdk.Box_generator.Box_triangles) ~size:(Vec3.create 2. 2. 2.) () in
  let non_planar = Sop.group_non_planar ~tolerance:0.01 ~name:"warped" warped in
  same_cook "group_non_planar" ~typed:non_planar ~factory:Nodes.Group_non_planar.factory
    [ "tolerance", Parameter.Float_value 0.01; "name", Text_value "warped" ] warped;
  let backface = Sop.group_backface ~viewpoint:(Vec3.create 0. 0. 5.) ~name:"hidden"
      ~merge:Rdk.Group_ops.Group_union box in
  same_cook "group_backface" ~typed:backface ~factory:Nodes.Group_backface.factory
    [ "viewpoint_z", Parameter.Float_value 5.; "name", Text_value "hidden";
      "merge", Choice_value "Union" ] box;
  let unshared = Sop.group_unshared ~owner:Rdk.Group_ops.Group_points ~name:"rim" warped in
  same_cook "group_unshared" ~typed:unshared ~factory:Nodes.Group_unshared.factory
    [ "owner", Parameter.Choice_value "Points"; "name", Text_value "rim" ] warped;
  let edges = Sop.group_edges ~use_min_length:true ~name:"rim" ~incidence:Rdk.Group_mesh.Boundary_edge
      ~min_length:0.1 warped in
  same_cook "group_edges" ~typed:edges ~factory:Nodes.Group_edges.factory
    [ "name", Parameter.Text_value "rim"; "incidence", Choice_value "Boundary";
      "use_min_length", Bool_value true; "min_length", Float_value 0.1 ] warped;
  let limited_edges = Sop.group_edges ~use_min_length:true ~min_length:0.1
      ~use_max_length:true ~max_length:10. ~use_min_angle:true ~use_max_angle:true warped in
  same_cook "group_edges enabled limits" ~typed:limited_edges ~factory:Nodes.Group_edges.factory
    [ "use_min_length", Parameter.Bool_value true; "min_length", Float_value 0.1;
      "use_max_length", Bool_value true; "max_length", Float_value 10.;
      "use_min_angle", Bool_value true; "use_max_angle", Bool_value true ] warped;
  let disabled_limits = Sop.group_edges ~min_length:999. ~max_length:0.001
      ~min_angle:Float.pi ~max_angle:0.01 warped in
  same_cook "group_edges disabled limits" ~typed:disabled_limits ~factory:Nodes.Group_edges.factory
    [ "min_length", Parameter.Float_value 999.; "max_length", Float_value 0.001;
      "min_angle", Float_value Float.pi; "max_angle", Float_value 0.01 ] warped;
  check (equal_geometry (cook 1 disabled_limits) (cook 1 (Sop.group_edges warped)))
    "group_edges: inactive limits preserve default geometry";
  cache_identity "group_edges limits" limited_edges;
  List.iter (fun make ->
    check (match make () with
      | _ -> false | exception Invalid_argument _ -> true)
      "group_edges refuses invalid limits at construction")
    [ (fun () -> Sop.group_edges ~min_length:(-1.) warped);
      (fun () -> Sop.group_edges ~max_length:nan warped);
      (fun () -> Sop.group_edges ~min_angle:infinity warped);
      (fun () -> Sop.group_edges ~max_angle:nan warped) ];
  let random = Sop.group_random ~seed:5 ~probability:0.4 ~owner:Rdk.Group_ops.Group_points
      ~name:"random" warped in
  same_cook "group_random" ~typed:random ~factory:Nodes.Group_random.factory
    [ "seed", Parameter.Int_value 5; "probability", Float_value 0.4; "name", Text_value "random" ]
    warped;
  let seeded = Sop.group ~name:"seed" (Select.point_indices [|0|]) warped in
  let depth = Sop.group_edge_depth ~depth:2 ~point_group:"seed" ~name:"near" seeded in
  same_cook "group_edge_depth" ~typed:depth ~factory:Nodes.Group_edge_depth.factory
    [ "depth", Parameter.Int_value 2; "name", Text_value "near" ] seeded;
  let components = Sop.group_boundary_components ~prefix:"rim" warped in
  same_cook "group_boundary_components" ~typed:components
    ~factory:Nodes.Group_boundary_components.factory [ "prefix", Parameter.Text_value "rim" ] warped;
  let boundary = Sop.group_from_attribute_boundary ~owner:Rdk.Group_ops.Group_edges
      ~name:"seams" ~tolerance:1e-6 warped in
  same_cook "group_from_attribute_boundary" ~typed:boundary
    ~factory:Nodes.Group_from_attribute_boundary.factory
    [ "name", Parameter.Text_value "seams"; "tolerance", Float_value 1e-6 ] warped;
  let grouped = Sop.group ~name:"half" (Select.primitive_indices [|0; 1; 2|]) box in
  let bounded = Sop.group_bounds ~name:"bounded" ~size:(Vec3.create 1.5 2. 2.) box in
  same_cook "group_bounds box" ~typed:bounded ~factory:Nodes.Group_bounds.factory
    [ "name", Parameter.Text_value "bounded";
      "size_x", Float_value 1.5; "size_y", Float_value 2.; "size_z", Float_value 2. ] box;
  same_cook "group_bounds sphere"
    ~typed:(Sop.group_bounds ~shape:Sop.Sphere ~radius:1.5 box)
    ~factory:Nodes.Group_bounds.factory
    [ "shape", Parameter.Choice_value "Sphere"; "radius", Float_value 1.5 ] box;
  same_cook "group_bounds defaults" ~typed:(Sop.group_bounds box)
    ~factory:Nodes.Group_bounds.factory [] box;
  cache_identity "group_bounds" bounded;
  List.iter (fun build ->
    check (match build () with _ -> false | exception Invalid_argument _ -> true)
      "group_bounds refuses invalid bounds at construction")
    [ (fun () -> Sop.group_bounds ~center:(Vec3.create 0. nan 0.) box);
      (fun () -> Sop.group_bounds ~size:(Vec3.create (-1.) 1. 1.) box);
      (fun () -> Sop.group_bounds ~radius:infinity box) ];
  let promotions = Sop.group_promotions seeded in
  let ranges = Sop.group_ranges warped in
  same_cook "group_promotions defaults" ~typed:promotions
    ~factory:Nodes.Group_promotions.factory [] seeded;
  same_cook "group_ranges defaults" ~typed:ranges
    ~factory:Nodes.Group_ranges.factory [] warped;
  List.iter (fun (name, node) ->
    cache_identity ~changes:["rules", Parameter.Text_value ""] name node)
    ["group_promotions", promotions; "group_ranges", ranges];
  List.iter (fun (name, node, factory, input) ->
    same_cook (name ^ " empty rules") ~typed:node ~factory
      ["rules", Parameter.Text_value ""] input;
    check (Node.operation node = name && Node.parameter_key node <> "")
      (name ^ ": empty rules retain node identity");
    check (equal_geometry (cook 1 node) (cook 1 input))
      (name ^ ": empty rules preserve input geometry"))
    [ "group_promotions", Sop.group_promotions ~rules:[] seeded,
        Nodes.Group_promotions.factory, seeded;
      "group_ranges", Sop.group_ranges ~rules:[] warped,
        Nodes.Group_ranges.factory, warped ];
  let inverted = Sop.group_invert ~owner:(Sop.Owner Rdk.Group_ops.Group_primitives)
      ~pattern:"half" ~new_name:"other" grouped in
  same_cook "group_invert" ~typed:inverted ~factory:Nodes.Group_invert.factory
    [ "owner", Parameter.Choice_value "Primitives";
      "pattern", Text_value "half"; "new_name", Text_value "other" ] grouped;
  same_cook "group_invert Any defaults" ~typed:(Sop.group_invert grouped)
    ~factory:Nodes.Group_invert.factory [] grouped;
  same_cook "group_invert blank new name"
    ~typed:(Sop.group_invert ~new_name:"" grouped)
    ~factory:Nodes.Group_invert.factory [] grouped;
  let combined = Sop.group_combine ~owner:Rdk.Group_ops.Group_primitives
      ~name:"complement" ~base_pattern:"half" ~base_inverted:true grouped in
  same_cook "group_combine" ~typed:combined ~factory:Nodes.Group_combine.factory
    [ "owner", Parameter.Choice_value "Primitives";
      "name", Text_value "complement"; "base_pattern", Text_value "half";
      "base_inverted", Bool_value true ] grouped;
  same_cook "group_combine defaults" ~typed:(Sop.group_combine grouped)
    ~factory:Nodes.Group_combine.factory [] grouped;
  let piece_source = Sop.set_int ~owner:Rdk.Attribute.Primitive ~name:"piece" ~value:0 grouped in
  let separated = Sop.separate_pieces ~piece_attribute:"piece" ~gap:0.2 piece_source in
  same_cook "separate_pieces" ~typed:separated ~factory:Nodes.Separate_pieces.factory
    [ "piece_attribute", Parameter.Text_value "piece"; "gap", Float_value 0.2 ] piece_source;
  List.iter (fun (name, node) -> cache_identity name node)
    [ "group_invert", inverted; "separate_pieces", separated ];
  cache_identity ~changes:["steps", Parameter.Text_value "union\thalf\tfalse"] "group_combine" combined;
  let named = Sop.name_from_groups ~owner:Rdk.Attribute.Primitive ~pattern:"half"
      ~overlap:Rdk.Group_ops.First_group grouped in
  same_cook "name_from_groups" ~typed:named ~factory:Nodes.Name_from_groups.factory
    [ "pattern", Parameter.Text_value "half"; "overlap", Choice_value "First group" ] grouped;
  let regrouped = Sop.groups_from_name ~owner:Rdk.Attribute.Primitive ~attribute:"name"
      ~prefix:"g_" named in
  same_cook "groups_from_name" ~typed:regrouped ~factory:Nodes.Groups_from_name.factory
    [ "prefix", Parameter.Text_value "g_" ] named;
  let promoted = Sop.group_promote_boundary ~tolerance:(1e-6) ~source:Rdk.Group_ops.Group_primitives
      ~destination:Rdk.Group_ops.Group_points ~group:"half" ~name:"rim" grouped in
  same_cook "group_promote_boundary" ~typed:promoted ~factory:Nodes.Group_promote_boundary.factory
    [ "source", Parameter.Choice_value "Primitives"; "destination", Choice_value "Points";
      "group", Text_value "half"; "name", Text_value "rim";
      (* the typed default differs from the editor default (a listed drift) *)
      "tolerance", Float_value 1e-6 ] grouped;
  let deleted = Sop.group_delete ~delete_unused:true ~rules:[] grouped in
  same_cook "group_delete" ~typed:deleted ~factory:Nodes.Group_delete.factory
    [ "delete_unused", Parameter.Bool_value true ] grouped;
  let renamed = Sop.group_rename ~rules:[] grouped in
  same_cook "group_rename" ~typed:renamed ~factory:Nodes.Group_rename.factory [] grouped;
  let copied = Sop.group_copy ~conflict:Rdk.Group_ops.Copy_overwrite ~copy_empty:true
      grouped box in
  same_cook "group_copy" ~typed:copied ~factory:Nodes.Group_copy.factory
    [ "copy_empty", Parameter.Bool_value true ] grouped ~inputs:[box];
  let transferred = Sop.group_transfer ~conflict:Rdk.Group_ops.Copy_overwrite ~distance:0.5
      grouped box in
  same_cook "group_transfer" ~typed:transferred ~factory:Nodes.Group_transfer.factory
    [ "distance", Parameter.Float_value 0.5 ] grouped ~inputs:[box];
  let copy_rule = { Rdk.Group_ops.copy_owner = Rdk.Group_ops.Group_primitives;
    copy_pattern = "half"; copy_prefix = "picked_"; match_attribute = None } in
  let copy_values = ["rules", Parameter.Text_value "primitive\thalf\tpicked_\t"] in
  let copied_rules = Sop.group_copy ~use_rules:true ~rules:[copy_rule] grouped box in
  same_cook "group_copy enabled rules" ~typed:copied_rules ~factory:Nodes.Group_copy.factory
    (("use_rules", Parameter.Bool_value true) :: copy_values) grouped ~inputs:[box];
  same_cook "group_copy disabled rules"
    ~typed:(Sop.group_copy ~rules:[copy_rule] grouped box)
    ~factory:Nodes.Group_copy.factory copy_values grouped ~inputs:[box];
  let transfer_rule = { Rdk.Group_ops.transfer_owner = Rdk.Group_ops.Group_primitives;
    transfer_pattern = "half"; transfer_prefix = "near_" } in
  let transfer_values = ["rules", Parameter.Text_value "primitive\thalf\tnear_"] in
  let transferred_rules = Sop.group_transfer ~use_rules:true ~rules:[transfer_rule] grouped box in
  same_cook "group_transfer enabled rules" ~typed:transferred_rules ~factory:Nodes.Group_transfer.factory
    (("use_rules", Parameter.Bool_value true) :: transfer_values) grouped ~inputs:[box];
  same_cook "group_transfer disabled rules"
    ~typed:(Sop.group_transfer ~rules:[transfer_rule] grouped box)
    ~factory:Nodes.Group_transfer.factory transfer_values grouped ~inputs:[box];
  List.iter (fun (name, node) ->
    cache_identity ~changes:["rules", Parameter.Text_value ""] name node)
    ["group_copy rules", copied_rules; "group_transfer rules", transferred_rules];
  List.iter (fun distance ->
    check (match Sop.group_transfer ~distance grouped box with
      | _ -> false | exception Invalid_argument _ -> true)
      "group_transfer refuses invalid distance at construction") [-1.; nan; infinity];
  List.iter (fun tolerance ->
    List.iter (fun make ->
      check (match make () with
        | _ -> false | exception Invalid_argument _ -> true)
        "boundary groups refuse invalid tolerance at construction")
      [ (fun () -> Sop.group_from_attribute_boundary ~tolerance grouped);
        (fun () -> Sop.group_promote_boundary ~tolerance grouped) ])
    [-1.; nan; infinity];
  let path_base = Sop.ordered_group ~owner:Rdk.Group.Point ~name:"path" ~elements:[0; 3] warped in
  let path = Sop.group_find_path ~base_group:"path" ~name:"walk" path_base in
  same_cook "group_find_path" ~typed:path ~factory:Nodes.Group_find_path.factory
    [ "base_group", Parameter.Text_value "path"; "name", Text_value "walk" ] path_base;
  let edge_deleted = Sop.delete_edge_group ~name:"rim" edges in
  same_cook "delete_edge_group" ~typed:edge_deleted ~factory:Nodes.Delete_edge_group.factory
    [ "name", Parameter.Text_value "rim" ] edges;
  let edge_renamed = Sop.rename_edge_group ~from:"rim" ~into:"border" edges in
  same_cook "rename_edge_group" ~typed:edge_renamed ~factory:Nodes.Rename_edge_group.factory
    [ "from", Parameter.Text_value "rim"; "into", Text_value "border" ] edges;
  (* topology nodes *)
  let quads = Sop.box ~normals:None ~connectivity:Rdk.Box_generator.Box_quads ~size:(Vec3.create 2. 2. 2.) () in
  let divided = Sop.edge_divide ~divisions:3 quads in
  same_cook "edge_divide" ~typed:divided ~factory:Nodes.Edge_divide.factory
    [ "divisions", Parameter.Int_value 3 ] quads;
  let collapsed = Sop.edge_collapse ~group:"rim" edges in
  same_cook "edge_collapse" ~typed:collapsed ~factory:Nodes.Edge_collapse.factory
    [ "group", Parameter.Text_value "rim" ] edges;
  let dissolved = Sop.dissolve ~collinearity_tolerance:(0.) ~remove_inline_points:(false) ~group:"rim" edges in
  same_cook "dissolve" ~typed:dissolved ~factory:Nodes.Dissolve.factory
    [ "group", Parameter.Text_value "rim";
      (* typed defaults that differ from the editor defaults (listed drifts) *)
      "remove_inline_points", Bool_value false; "collinearity_tolerance", Float_value 0. ] edges;
  let triangulated = Sop.triangulate quads in
  same_cook "triangulate" ~typed:triangulated ~factory:Nodes.Triangulate.factory [] quads;
  let flipped = Sop.edge_flip ~cycles:1 box in
  let reversed = Sop.reverse quads in
  same_cook "reverse defaults" ~typed:reversed ~factory:Nodes.Reverse.factory [] quads;
  let shifted = Sop.reverse ~group:"half" ~operation:Sop.Shift ~shift:(-1) grouped in
  same_cook "reverse shift" ~typed:shifted ~factory:Nodes.Reverse.factory
    [ "group", Parameter.Text_value "half";
      "operation", Choice_value "Shift vertices"; "shift", Int_value (-1) ] grouped;
  cache_identity "reverse" reversed;
  same_cook "edge_flip" ~typed:flipped ~factory:Nodes.Edge_flip.factory [] box;
  let cusped = Sop.edge_cusp ~group:"rim" edges in
  same_cook "edge_cusp" ~typed:cusped ~factory:Nodes.Edge_cusp.factory
    [ "group", Parameter.Text_value "rim" ] edges;
  let straightened = Sop.edge_straighten ~group:"rim" ~output_group:"straight" edges in
  same_cook "edge_straighten" ~typed:straightened ~factory:Nodes.Edge_straighten.factory
    [ "group", Parameter.Text_value "rim"; "output_group", Text_value "straight" ] edges;
  let extruded = Sop.poly_extrude ~group:"half" ~distance:0.2 grouped in
  same_cook "poly_extrude" ~typed:extruded ~factory:Nodes.Poly_extrude.factory
    [ "group", Parameter.Text_value "half"; "distance", Float_value 0.2 ] grouped;
  let filled = Sop.poly_fill ~unique_points:true warped in
  same_cook "poly_fill" ~typed:filled ~factory:Nodes.Poly_fill.factory
    [ "unique_points", Parameter.Bool_value true ] warped;
  let lines = Sop.convert_line ~connect_path:true warped in
  same_cook "convert_line" ~typed:lines ~factory:Nodes.Convert_line.factory
    [ "connect_path", Parameter.Bool_value true ] warped;
  let blasted = Sop.blast ~owner:Rdk.Group.Primitive ~group:"half" grouped in
  same_cook "blast" ~typed:blasted ~factory:Nodes.Blast.factory
    [ "group", Parameter.Text_value "half" ] grouped;
  let creased = Sop.crease ~group:"rim" ~weight:0.5 edges in
  same_cook "crease" ~typed:creased ~factory:Nodes.Crease.factory
    [ "group", Parameter.Text_value "rim"; "weight", Float_value 0.5 ] edges;
  let paths = Sop.poly_path ~maximum_distance:0.25 warped in
  same_cook "poly_path" ~typed:paths ~factory:Nodes.Poly_path.factory
    [ "maximum_distance", Parameter.Float_value 0.25 ] warped;
  let swapped = Sop.swap_attributes ~rules:[] warped in
  same_cook "swap_attributes" ~typed:swapped ~factory:Nodes.Swap_attributes.factory [] warped;
  List.iter (fun (name, node) -> cache_identity name node)
    [ "crease", creased; "poly_path", paths ];
  cache_identity ~changes:["rules", Parameter.Text_value "point\tweight\tweight_copy\tcopy"]
    "swap_attributes" swapped;
  let ends = Sop.ends ~mode:Rdk.Curve_topology.Ends_unroll_new lines in
  same_cook "ends optional mode default" ~typed:(Sop.ends lines)
    ~factory:Nodes.Ends.factory [] lines;
  same_cook "measure optional kind default" ~typed:(Sop.measure quads)
    ~factory:Nodes.Measure.factory [] quads;
  same_cook "ends" ~typed:ends ~factory:Nodes.Ends.factory
    [ "mode", Parameter.Choice_value "Unroll new point" ] lines;
  let measured = Sop.measure ~attribute:"area" ~kind:Rdk.Analysis.Area quads in
  let material = Sop.material ~material:"blue" ~color:(Vec3.create 0.2 0.4 0.8)
      ~roughness:0.3 ~emission:(Vec3.create 0.1 0. 0.) quads in
  same_cook "material" ~typed:material ~factory:Nodes.Material.factory
    [ "material", Parameter.Text_value "blue";
      "color_r", Float_value 0.2; "color_g", Float_value 0.4; "color_b", Float_value 0.8;
      "roughness", Float_value 0.3; "emission_r", Float_value 0.1 ] quads;
  same_cook "material defaults" ~typed:(Sop.material quads)
    ~factory:Nodes.Material.factory [] quads;
  cache_identity "material" material;
  List.iter (fun build ->
    check (match build () with _ -> false | exception Invalid_argument _ -> true)
      "material refuses invalid channels at construction")
    [ (fun () -> Sop.material ~color:(Vec3.create nan 0. 0.) quads);
      (fun () -> Sop.material ~roughness:(-0.1) quads);
      (fun () -> Sop.material ~emission:(Vec3.create 0. 0. 1.1) quads) ];
  same_cook "measure" ~typed:measured ~factory:Nodes.Measure.factory
    [ "attribute", Parameter.Text_value "area" ] quads;
  let uv_quads = Sop.uv_project ~planar_v:Vec3.unit_y quads in
  let unitized = Sop.uv_unitize ~uniform:false ~mode:Rdk.Uv_ops.Per_face uv_quads in
  same_cook "uv_unitize optional mode default" ~typed:(Sop.uv_unitize uv_quads)
    ~factory:Nodes.Uv_unitize.factory [] uv_quads;
  same_cook "uv_unitize" ~typed:unitized ~factory:Nodes.Uv_unitize.factory
    [ "uniform", Parameter.Bool_value false ] uv_quads;
  List.iter (fun (name, node) -> cache_identity name node)
    [ "ends", ends; "measure", measured; "uv_unitize", unitized ];
  (* Omitted typed values now use the Lisp defaults; legacy callers above
     spell out the old values and still cook the same geometry. *)
  same_cook "dissolve defaults" ~typed:(Sop.dissolve edges)
    ~factory:Nodes.Dissolve.factory [] edges;
  same_cook "attribute boundary defaults"
    ~typed:(Sop.group_from_attribute_boundary ~owner:Rdk.Group_ops.Group_edges
      ~name:"seams" warped)
    ~factory:Nodes.Group_from_attribute_boundary.factory
    [ "name", Parameter.Text_value "seams" ] warped;
  same_cook "boundary promotion defaults"
    ~typed:(Sop.group_promote_boundary ~source:Rdk.Group_ops.Group_primitives
      ~destination:Rdk.Group_ops.Group_points ~group:"half" grouped)
    ~factory:Nodes.Group_promote_boundary.factory
    [ "source", Parameter.Choice_value "Primitives";
      "destination", Choice_value "Points"; "group", Text_value "half" ] grouped;
  same_cook "name from groups defaults"
    ~typed:(Sop.name_from_groups ~owner:Rdk.Attribute.Primitive grouped)
    ~factory:Nodes.Name_from_groups.factory [] grouped;
  same_cook "group copy defaults" ~typed:(Sop.group_copy grouped box)
    ~factory:Nodes.Group_copy.factory [] grouped ~inputs:[box];
  same_cook "group transfer defaults" ~typed:(Sop.group_transfer grouped box)
    ~factory:Nodes.Group_transfer.factory [] grouped ~inputs:[box];
  List.iter (fun (name, node) -> cache_identity name node)
    [ "edge_divide", divided; "edge_collapse", collapsed; "dissolve", dissolved;
      "triangulate", triangulated; "edge_flip", flipped; "edge_cusp", cusped;
      "edge_straighten", straightened; "poly_extrude", extruded; "poly_fill", filled;
      "convert_line", lines; "blast", blasted ];
  (* attribute and shape nodes *)
  let flat = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:4 ~rows:4 ~size:2. () in
  let flattened = Sop.uv_flatten ~name:"uv" flat in
  same_cook "uv_flatten" ~typed:flattened ~factory:Nodes.Uv_flatten.factory [] flat;
  let relaxed = Sop.uv_relax ~iterations:10 flattened in
  same_cook "uv_relax" ~typed:relaxed ~factory:Nodes.Uv_relax.factory
    [ "iterations", Parameter.Int_value 10 ] flattened;
  let renamed_attributes = Sop.rename_attributes ~rules:[] warped in
  same_cook "rename_attributes" ~typed:renamed_attributes ~factory:Nodes.Rename_attributes.factory
    [] warped;
  let line = Sop.line ~points:5 ~origin:Vec3.zero ~direction:Vec3.unit_y ~length:2. () in
  same_generator "line" ~typed:line ~factory:Nodes.Line.factory
    [ "points", Parameter.Int_value 5; "length", Float_value 2. ];
  let mirrored = Sop.mirror ~keep_original:false ~origin:Vec3.zero ~normal:Vec3.unit_x box in
  same_cook "mirror" ~typed:mirrored ~factory:Nodes.Mirror.factory
    [ "keep_original", Parameter.Bool_value false ] box;
  let matched = Sop.match_axis ~from:Vec3.unit_y ~into:Vec3.unit_x box in
  same_cook "match_axis" ~typed:matched ~factory:Nodes.Match_axis.factory
    [ "into_x", Parameter.Float_value 1.; "into_y", Float_value 0. ] box;
  let displaced = Sop.noise_displace ~seed:3 ~amplitude:0.2 ~frequency:2. warped in
  same_cook "noise_displace" ~typed:displaced ~factory:Nodes.Noise_displace.factory
    [ "seed", Parameter.Int_value 3; "amplitude", Float_value 0.2; "frequency", Float_value 2. ] warped;
  List.iter (fun (name, node) -> cache_identity name node)
    [ "uv_flatten", flattened; "uv_relax", relaxed;
      "line", line; "mirror", mirrored; "match_axis", matched; "noise_displace", displaced ];
  cache_identity ~changes:["rules", Parameter.Text_value "any\tweight\trenamed_weight\tskip"]
    "rename_attributes" renamed_attributes;
  List.iter (fun (name, node) -> cache_identity name node)
    [ "group_non_planar", non_planar; "group_backface", backface; "group_unshared", unshared;
      "group_edges", edges; "group_random", random; "group_edge_depth", depth;
      "group_boundary_components", components;
      "name_from_groups", named; "groups_from_name", regrouped;
      "group_find_path", path;
      "delete_edge_group", edge_deleted; "rename_edge_group", edge_renamed ];
  List.iter (fun (name, node, rules) ->
    cache_identity ~changes:["rules", Parameter.Text_value rules] name node)
    [ "group_delete", deleted, "any\t*";
      "group_rename", renamed, "any\thalf\trenamed_half\tskip";
      "group_copy", copied, "point\t*\tcopy_\t";
      "group_transfer", transferred, "point\t*\ttransfer_" ];
  cache_identity ~changes:["attributes", Parameter.Text_value "point\tP"]
    "group_from_attribute_boundary" boundary;
  cache_identity ~changes:["attributes", Parameter.Text_value "point\tP"]
    "group_promote_boundary" promoted;
  (* the typed constructor keeps its validation *)
  let primitive_group = Sop.group ~name:"group" (Select.primitive_indices [|0|]) box in
  let edge_group = Sop.group_edges ~name:"edges" warped in
  let ordered = Sop.ordered_group ~owner:Rdk.Group.Point ~name:"ordered" ~elements:[0; 1; 2] warped in
  List.iter (fun (name, typed, factory, input) ->
    same_cook (name ^ " optional field defaults") ~typed ~factory [] input)
    [ "group_non_planar", Sop.group_non_planar warped, Nodes.Group_non_planar.factory, warped;
      "group_backface", Sop.group_backface box, Nodes.Group_backface.factory, box;
      "group_unshared", Sop.group_unshared warped, Nodes.Group_unshared.factory, warped;
      (* Seed absence remains the separate Auto migration; pin the Lisp seed here. *)
      "group_random", Sop.group_random ~seed:0 warped, Nodes.Group_random.factory, warped;
      "group_edge_depth", Sop.group_edge_depth seeded, Nodes.Group_edge_depth.factory, seeded;
      "group_from_attribute_boundary", Sop.group_from_attribute_boundary warped,
        Nodes.Group_from_attribute_boundary.factory, warped;
      "groups_from_name", Sop.groups_from_name named, Nodes.Groups_from_name.factory, named;
      "name_from_groups", Sop.name_from_groups grouped, Nodes.Name_from_groups.factory, grouped;
      "group_promote_boundary", Sop.group_promote_boundary primitive_group,
        Nodes.Group_promote_boundary.factory, primitive_group;
      "group_delete", Sop.group_delete grouped, Nodes.Group_delete.factory, grouped;
      "group_rename", Sop.group_rename grouped, Nodes.Group_rename.factory, grouped;
      "group_find_path", Sop.group_find_path ordered, Nodes.Group_find_path.factory, ordered;
      "delete_edge_group", Sop.delete_edge_group edge_group, Nodes.Delete_edge_group.factory, edge_group;
      "rename_edge_group", Sop.rename_edge_group edge_group, Nodes.Rename_edge_group.factory, edge_group;
      "poly_extrude", Sop.poly_extrude quads, Nodes.Poly_extrude.factory, quads;
      "blast", Sop.blast primitive_group, Nodes.Blast.factory, primitive_group;
      "rename_attributes", Sop.rename_attributes warped, Nodes.Rename_attributes.factory, warped;
      "swap_attributes", Sop.swap_attributes warped, Nodes.Swap_attributes.factory, warped;
      "mirror", Sop.mirror box, Nodes.Mirror.factory, box;
      "match_axis", Sop.match_axis box, Nodes.Match_axis.factory, box;
      "noise_displace", Sop.noise_displace ~seed:0 warped, Nodes.Noise_displace.factory, warped;
      "separate_pieces", Sop.separate_pieces piece_source, Nodes.Separate_pieces.factory, piece_source ];
  same_generator "line optional field defaults" ~typed:(Sop.line ()) ~factory:Nodes.Line.factory [];
  List.iter (fun (name, build) ->
    check (match build () with _ -> false | exception Invalid_argument _ -> true)
      (name ^ " still raises Invalid_argument"))
    [ "group_non_planar empty name", (fun () -> Sop.group_non_planar ~tolerance:0.01 ~name:" " warped);
      "group_non_planar negative tolerance", (fun () -> Sop.group_non_planar ~tolerance:(-1.) ~name:"a" warped);
      "group_backface nan viewpoint", (fun () -> Sop.group_backface ~viewpoint:(Vec3.create nan 0. 0.) ~name:"a" box);
      "group_backface empty base", (fun () -> Sop.group_backface ~base:"" ~viewpoint:Vec3.zero ~name:"a" box);
      "group_unshared empty name", (fun () -> Sop.group_unshared ~owner:Rdk.Group_ops.Group_edges ~name:"" box) ];
  List.iter (fun build ->
    check (match build () with _ -> false | exception Invalid_argument _ -> true)
      "group_promotions refuses non-positive Lisp limits")
    [ (fun () -> Sop.group_promotions ~max_outputs:0 seeded);
      (fun () -> Sop.group_promotions ~max_payload_bytes:0 seeded) ];
  let interpolation_count owner geometry = match owner with
    | Rdk.Attribute.Point -> Rdk.Geometry.point_count geometry
    | Rdk.Attribute.Vertex -> Rdk.Geometry.vertex_count geometry
    | Rdk.Attribute.Primitive -> Rdk.Geometry.primitive_count geometry
    | Rdk.Attribute.Detail -> 1 in
  let interpolation_owners = [Rdk.Attribute.Point,"point"; Vertex,"vertex";
    Primitive,"primitive"; Detail,"detail"] in
  let interpolation_add ~owner ~name storage geometry =
    Rdk.Attribute.create_owned ~owner ~name storage |> Result.get_ok
    |> fun attribute -> Rdk.Geometry.with_attribute attribute geometry |> Result.get_ok in
  let interpolation_source_geometry = List.fold_left (fun geometry (owner,_) ->
    let count = interpolation_count owner geometry in
    geometry |> interpolation_add ~owner ~name:"weight"
      (Rdk.Attribute.Float (Array.init count (fun i -> float (i+1)))))
    (Rdk.Plane_generators.grid ~columns:2 ~rows:2 ~size:2. () |> Result.get_ok)
    interpolation_owners in
  let interpolation_source = Sop.snapshot interpolation_source_geometry in
  let interpolation_rules = "point\tweight\tpoint_weight\nvertex\tweight\tvertex_weight\nprimitive\tweight\tprimitive_weight\ndetail\tweight\tdetail_weight" in
  let interpolation_attributes = List.map (fun (owner, token) ->
    Rdk.Attribute_ops.interpolate_attribute ~owner ~into:(token ^ "_weight") "weight")
    interpolation_owners in
  let interpolation_target_geometry = List.fold_left (fun geometry (owner,_) ->
    let count = interpolation_count owner geometry in
    let offsets = Array.init (count+1) (fun i -> i*2) in
    let numbers = Rdk.Packed.Int_array.create_owned ~offsets
      ~values:(Array.init (count*2) (fun i -> i land 1)) |> Result.get_ok in
    let weights = Rdk.Packed.Float_array.create_owned ~offsets:(Array.copy offsets)
      ~values:(Array.init (count*2) (fun i -> if i land 1 = 0 then -.0.25 else 0.75)) |> Result.get_ok in
    let uvw = Rdk.Packed.Float3.of_owned ~x:(Array.make count 0.25)
      ~y:(Array.make count 0.5) ~z:(Array.make count 0.) |> Result.get_ok in
    geometry |> interpolation_add ~owner ~name:"sourceprim" (Rdk.Attribute.Int (Array.make count 0))
      |> interpolation_add ~owner ~name:"sourceuvw" (Rdk.Attribute.Float3 uvw)
      |> interpolation_add ~owner ~name:"sourcenums" (Rdk.Attribute.Int_array numbers)
      |> interpolation_add ~owner ~name:"sourceweights" (Rdk.Attribute.Float_array weights))
    (Rdk.Plane_generators.grid ~columns:2 ~rows:2 ~size:2. () |> Result.get_ok)
    interpolation_owners in
  let interpolation_target = Sop.snapshot interpolation_target_geometry in
  same_node "Attribute Interpolate Lisp defaults"
    ~typed:(Sop.attribute_interpolate ~attributes:interpolation_rules interpolation_source interpolation_target)
    ~catalog:(from_factory Nodes.Attribute_interpolate.factory
      ["attributes",Text_value interpolation_rules] [interpolation_source;interpolation_target]);
  let interpolation_drivers = [
    Sop.Interpolate_primitive_uvw,"Primitive UVW",Rdk.Attribute_ops.Primitive_uvw {
      primitive_attribute="sourceprim";uvw_attribute="sourceuvw"};
    Sop.Interpolate_point_weights,"Point weights",Rdk.Attribute_ops.Point_weights {
      numbers_attribute="sourcenums";weights_attribute="sourceweights"};
    Sop.Interpolate_vertex_weights,"Vertex weights",Rdk.Attribute_ops.Vertex_weights {
      numbers_attribute="sourcenums";weights_attribute="sourceweights"};
    Sop.Interpolate_primitive_weights,"Primitive weights",Rdk.Attribute_ops.Primitive_weights {
      numbers_attribute="sourcenums";weights_attribute="sourceweights"}] in
  let interpolation_driver_rules driver =
    let supported owner = match driver with
      | Sop.Interpolate_primitive_uvw | Interpolate_vertex_weights -> true
      | Interpolate_point_weights -> owner = Rdk.Attribute.Point || owner = Rdk.Attribute.Detail
      | Interpolate_primitive_weights -> owner = Rdk.Attribute.Primitive || owner = Rdk.Attribute.Detail in
    let owners = List.filter (fun (owner,_) -> supported owner) interpolation_owners in
    String.concat "\n" (List.map (fun (_,token) -> token ^ "\tweight\t" ^ token ^ "_weight") owners),
    List.filter (fun attribute -> supported attribute.Rdk.Attribute_ops.interpolate_owner) interpolation_attributes in
  List.iter (fun (target_owner,owner_name) ->
    List.iter (fun (driver,driver_name,native_driver) ->
      let interpolation_rules, interpolation_attributes = interpolation_driver_rules driver in
      List.iter (fun pre_scale -> List.iter (fun normalize_weights ->
        List.iter (fun threshold -> List.iter (fun blend ->
          List.iter (fun unmatched ->
            let typed = Sop.attribute_interpolate ~target_owner ~driver
              ~attributes:interpolation_rules ~pre_scale ~normalize_weights ~threshold ~blend ~unmatched
              interpolation_source interpolation_target in
            let values = ["target_owner",Parameter.Choice_value (String.capitalize_ascii owner_name);
              "driver",Choice_value driver_name;"attributes",Text_value interpolation_rules;
              "pre_scale",Float_value pre_scale;"normalize_weights",Bool_value normalize_weights;
              "threshold",Float_value threshold;"blend",Float_value blend;
              "unmatched",Choice_value (if unmatched = Rdk.Attribute_ops.Keep_target then "Keep target" else "Default value")] in
            let native = Rdk.Attribute_ops.interpolate ~target_owner ~driver:native_driver
              ~pre_scale ~normalize_weights ~threshold ~blend ~unmatched
              ~attributes:interpolation_attributes ~source:interpolation_source_geometry
              ~target:interpolation_target_geometry () |> fun result -> match result with
              | Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
            check (equal_geometry native (cook 1 typed)) "Attribute Interpolate native numeric parity";
            same_node "Attribute Interpolate numeric modes" ~typed
              ~catalog:(from_factory Nodes.Attribute_interpolate.factory values
                [interpolation_source;interpolation_target]))
            [Rdk.Attribute_ops.Keep_target;Default_value]) [0.25;1.])
          [1e-6;0.5]) [false;true]) [-1.;0.;1.5]) interpolation_drivers)
    interpolation_owners;
  List.iter (fun (target_owner,owner_name) -> List.iter (fun computed_owner ->
    let typed = Sop.attribute_interpolate ~target_owner ~attributes:interpolation_rules
      ~compute_weights:true ~computed_owner interpolation_source interpolation_target in
    let computed = {Rdk.Attribute_ops.computed_owner;
      computed_numbers_attribute="computednums";computed_weights_attribute="computedweights"} in
    let native = Rdk.Attribute_ops.interpolate ~target_owner ~attributes:interpolation_attributes
      ~driver:(Rdk.Attribute_ops.Primitive_uvw {primitive_attribute="sourceprim";uvw_attribute="sourceuvw"})
      ~compute_weights:computed ~source:interpolation_source_geometry ~target:interpolation_target_geometry ()
      |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
    check (equal_geometry native (cook 1 typed)) "Attribute Interpolate computed-array native parity";
    same_node "Attribute Interpolate computed arrays" ~typed
      ~catalog:(from_factory Nodes.Attribute_interpolate.factory [
        "target_owner",Choice_value (String.capitalize_ascii owner_name);
        "attributes",Text_value interpolation_rules;"compute_weights",Bool_value true;
        "computed_owner",Choice_value (if computed_owner=Rdk.Attribute.Point then "Point" else "Vertex")]
        [interpolation_source;interpolation_target])) [Rdk.Attribute.Point;Vertex]) interpolation_owners;
  List.iter (fun (target_owner,token) ->
    let owner = match target_owner with
      | Rdk.Attribute.Point -> Rdk.Group.Point
      | Vertex -> Rdk.Group.Vertex | Primitive -> Rdk.Group.Primitive
      | Detail -> assert false in
    let count = interpolation_count target_owner interpolation_target_geometry in
    let selected = Rdk.Group.init ~owner ~name:"selected" count (fun i -> i mod 2 = 0) in
    let target_geometry = Rdk.Geometry.with_group selected interpolation_target_geometry |> Result.get_ok in
    let target = Sop.snapshot target_geometry in
    List.iter (fun (driver,driver_name,native_driver) ->
      let interpolation_rules, interpolation_attributes = interpolation_driver_rules driver in
      List.iter (fun (group,group_pattern) ->
        let typed = Sop.attribute_interpolate ~target_owner ~driver ~threshold:0.1
          ~attributes:interpolation_rules ~group ~group_pattern interpolation_source target in
        let native = Rdk.Attribute_ops.interpolate ~target_owner ~driver:native_driver
          ~selection:selected ~threshold:0.1 ~normalize_weights:true
          ~attributes:interpolation_attributes ~source:interpolation_source_geometry ~target:target_geometry ()
          |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
        check (equal_geometry native (cook 1 typed)) "Attribute Interpolate selected native parity";
        same_node "Attribute Interpolate exact and patterned selections" ~typed
          ~catalog:(from_factory Nodes.Attribute_interpolate.factory [
            "target_owner",Choice_value (String.capitalize_ascii token);
            "driver",Choice_value driver_name;"threshold",Float_value 0.1;
            "attributes",Text_value interpolation_rules;
            "group",Text_value group;"group_pattern",Text_value group_pattern]
            [interpolation_source;target]))
        ["selected","";"","select*";"missing_ignored","select*"])
      interpolation_drivers) [Rdk.Attribute.Point,"point";Vertex,"vertex";Primitive,"primitive"];
  List.iter (fun keyword ->
    let pattern key = if keyword=key then Some "weight" else None in
    let point_pattern=pattern "point_pattern" and vertex_pattern=pattern "vertex_pattern"
    and primitive_pattern=pattern "primitive_pattern" and detail_pattern=pattern "detail_pattern" in
    let native = Rdk.Attribute_ops.interpolate ~target_owner:Rdk.Attribute.Point
      ~driver:(Rdk.Attribute_ops.Primitive_uvw {primitive_attribute="sourceprim";uvw_attribute="sourceuvw"})
      ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
      ~attributes:[] ~source:interpolation_source_geometry ~target:interpolation_target_geometry ()
      |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
    let typed = Sop.attribute_interpolate ~attributes:""
      ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
      interpolation_source interpolation_target in
    check (equal_geometry native (cook 1 typed)) "Attribute Interpolate pattern expansion native parity";
    same_node "Attribute Interpolate owner pattern fields" ~typed
      ~catalog:(from_factory Nodes.Attribute_interpolate.factory ["attributes",Text_value "";
        keyword,Text_value "weight"] [interpolation_source;interpolation_target]))
    ["point_pattern";"vertex_pattern";"primitive_pattern";"detail_pattern"];
  List.iter (fun (driver,driver_name,native_driver) ->
    let owner,group_owner,keyword = match driver with
      | Sop.Interpolate_primitive_uvw | Interpolate_point_weights -> Rdk.Attribute.Point,Rdk.Group.Point,"point_pattern"
      | Interpolate_vertex_weights -> Rdk.Attribute.Vertex,Rdk.Group.Vertex,"vertex_pattern"
      | Interpolate_primitive_weights -> Rdk.Attribute.Primitive,Rdk.Group.Primitive,"primitive_pattern" in
    let hot = Rdk.Group.init ~owner:group_owner ~name:"hot"
      (interpolation_count owner interpolation_source_geometry) (fun i -> i=0) in
    let source_geometry = Rdk.Geometry.with_group hot interpolation_source_geometry |> Result.get_ok in
    let source = Sop.snapshot source_geometry in
    let pattern key = if keyword=key then Some "weight hot" else None in
    let point_pattern=pattern "point_pattern" and vertex_pattern=pattern "vertex_pattern"
    and primitive_pattern=pattern "primitive_pattern" in
    let native = Rdk.Attribute_ops.interpolate ~target_owner:Rdk.Attribute.Point ~driver:native_driver
      ~threshold:0.1 ~normalize_weights:true ~match_groups:true
      ?point_pattern ?vertex_pattern ?primitive_pattern ~attributes:[]
      ~source:source_geometry ~target:interpolation_target_geometry ()
      |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
    let typed = Sop.attribute_interpolate ~driver ~threshold:0.1 ~match_groups:true ~attributes:""
      ?point_pattern ?vertex_pattern ?primitive_pattern source interpolation_target in
    check (equal_geometry native (cook 1 typed)) "Attribute Interpolate group-match native parity";
    same_node "Attribute Interpolate group matching" ~typed
      ~catalog:(from_factory Nodes.Attribute_interpolate.factory ["driver",Choice_value driver_name;
        "threshold",Float_value 0.1;"match_groups",Bool_value true;"attributes",Text_value "";
        keyword,Text_value "weight hot"] [source;interpolation_target])) interpolation_drivers;
  let interpolation_escaped_geometry = interpolation_add ~owner:Rdk.Attribute.Point ~name:"weight\tvalue"
    (Rdk.Attribute.Float (Array.make (Rdk.Geometry.point_count interpolation_source_geometry) 7.))
    interpolation_source_geometry in
  let interpolation_escaped_source = Sop.snapshot interpolation_escaped_geometry in
  let interpolation_escaped_rules = "point\tweight\\tvalue\tout" in
  let interpolation_escaped = Sop.attribute_interpolate ~attributes:interpolation_escaped_rules
    interpolation_escaped_source interpolation_target in
  let interpolation_escaped_native = Rdk.Attribute_ops.interpolate ~target_owner:Rdk.Attribute.Point
    ~driver:(Rdk.Attribute_ops.Primitive_uvw {primitive_attribute="sourceprim";uvw_attribute="sourceuvw"})
    ~attributes:[Rdk.Attribute_ops.interpolate_attribute ~owner:Rdk.Attribute.Point ~into:"out" "weight\tvalue"]
    ~source:interpolation_escaped_geometry ~target:interpolation_target_geometry ()
    |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
  check (equal_geometry interpolation_escaped_native (cook 1 interpolation_escaped))
    "Attribute Interpolate escaped rule table native parity";
  same_node "Attribute Interpolate escaped rule tables" ~typed:interpolation_escaped
    ~catalog:(from_factory Nodes.Attribute_interpolate.factory ["attributes",Text_value interpolation_escaped_rules]
      [interpolation_escaped_source;interpolation_target]);
  let interpolation_bad_inspector = Sop.attribute_interpolate ~attributes:interpolation_rules
    interpolation_source interpolation_target in
  List.iter (fun values -> check (Result.is_error (Node.apply_parameters interpolation_bad_inspector values))
    "Attribute Interpolate inspector returns validation errors") [
      ["attributes",Text_value "point\tweight"];
      ["pre_scale",Float_value nan];
      ["driver",Choice_value "Point weights"];
      ["compute_weights",Bool_value true;"computed_numbers_attribute",Text_value "P"]];
  cache_identity "Attribute Interpolate all fields"
    ~changes:["attributes",Text_value "point\tweight\tother"]
    ~companions:["driver",["threshold",Float_value 1e-6;"attributes",Text_value "point\tweight\tpoint_weight"]]
    (Sop.attribute_interpolate ~attributes:interpolation_rules interpolation_source interpolation_target);
  List.iter (fun build -> check (match build () with
    | _ -> false | exception Invalid_argument _ -> true)
    "Attribute Interpolate construction refusal") [
    (fun () -> Sop.attribute_interpolate ~attributes:"point\tweight" interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~attributes:"bad\tweight\tout" interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~attributes:"point\t\tout" interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~primitive_attribute:" " interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~driver:Sop.Interpolate_point_weights interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~driver:Sop.Interpolate_vertex_weights ~threshold:0.1 ~compute_weights:true interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~target_owner:Rdk.Attribute.Detail ~group:"g" interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~pre_scale:nan interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~blend:1.1 interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~threshold:(-.1.) interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~compute_weights:true ~computed_numbers_attribute:"computedweights" interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~compute_weights:true ~computed_owner:Rdk.Attribute.Primitive interpolation_source interpolation_target);
    (fun () -> Sop.attribute_interpolate ~compute_weights:true ~computed_weights_attribute:"P" interpolation_source interpolation_target)];
  let transfer_source_geometry=interpolation_source_geometry in
  let transfer_target_geometry=Rdk.Plane_generators.grid ~columns:3 ~rows:2 ~size:3. () |> Result.get_ok in
  let transfer_source=Sop.snapshot transfer_source_geometry
  and transfer_target=Sop.snapshot transfer_target_geometry in
  let native_transfer ?names ?pattern ?source_group ?target_group ?source_vertices
      ~owner ~mode ?max_distance ~blend_width ~falloff ~unmatched ~source ~target () =
    (match owner with
    | Rdk.Attribute.Point -> Rdk.Attribute_ops.transfer_points ?names ?pattern ~mode
        ?max_distance ~blend_width ~falloff ~unmatched ?source_points:source_group
        ?target_points:target_group ~source ~target ()
    | Primitive -> Rdk.Attribute_ops.transfer_primitives ?names ?pattern ~mode
        ?max_distance ~blend_width ~falloff ~unmatched ?source_primitives:source_group
        ?target_primitives:target_group ~source ~target ()
    | Vertex -> Rdk.Attribute_ops.transfer_vertices ?names ?pattern ?max_distance
        ~blend_width ~falloff ~unmatched ?source_primitives:source_group ?source_vertices
        ?target_vertices:target_group ~source ~target ()
    | Detail -> Rdk.Attribute_ops.transfer_detail ?names ?pattern ~source ~target ())
    |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
  same_node "Attribute Transfer Lisp defaults" ~typed:(Sop.attribute_transfer transfer_source transfer_target)
    ~catalog:(from_factory Nodes.Attribute_transfer.factory [] [transfer_source;transfer_target]);
  let transfer_modes=[Sop.Transfer_nearest,"Nearest",Rdk.Attribute_ops.Nearest;
    Transfer_inverse,"Inverse distance",Rdk.Attribute_ops.Inverse_distance {neighbors=3;power=1.5};
    Transfer_links,"Links kernel",Rdk.Attribute_ops.Kernel {neighbors=3;radius=2.;kernel=Links};
    Transfer_renderman,"RenderMan kernel",Rdk.Attribute_ops.Kernel {neighbors=3;radius=2.;kernel=RenderMan};
    Transfer_hart,"Hart kernel",Rdk.Attribute_ops.Kernel {neighbors=3;radius=2.;kernel=Hart}] in
  let transfer_falloffs=[Sop.Transfer_linear,"Linear",Rdk.Attribute_ops.Linear;
    Transfer_smoothstep,"Smoothstep",Rdk.Attribute_ops.Smoothstep;
    Transfer_uniform,"Uniform",Rdk.Attribute_ops.Uniform 0.3] in
  List.iter (fun (owner,owner_name) ->
    List.iter (fun (mode,mode_name,native_mode) ->
      if owner<>Rdk.Attribute.Vertex && owner<>Rdk.Attribute.Detail || mode=Sop.Transfer_nearest then
      List.iter (fun (falloff,falloff_name,native_falloff) ->
        List.iter (fun max_distance -> List.iter (fun blend_width ->
          if owner<>Rdk.Attribute.Detail && (max_distance<>None || blend_width=0.)
              || owner=Rdk.Attribute.Detail && max_distance=None && blend_width=0. then
          List.iter (fun unmatched -> List.iter (fun use_names ->
            let distance_mode=if max_distance=None then Sop.Kernel_auto else Kernel_explicit in
            let maximum=Option.value ~default:1. max_distance in
            let typed=Sop.attribute_transfer ~owner ~mode ~neighbors:3 ~power:1.5 ~kernel_radius:2.
              ~distance_mode ~max_distance:maximum ~blend_width ~falloff ~uniform_bias:0.3
              ~unmatched ~use_names ~names:"weight" ~pattern:"w*" transfer_source transfer_target in
            let native=native_transfer ~owner ~mode:native_mode ?max_distance ~blend_width
              ~falloff:native_falloff ~unmatched
              ?names:(if use_names then Some ["weight"] else None)
              ?pattern:(if use_names then None else Some "w*")
              ~source:transfer_source_geometry ~target:transfer_target_geometry () in
            check (equal_geometry native (cook 1 typed)) "Attribute Transfer native parity";
            same_node "Attribute Transfer owners and sampling controls" ~typed
              ~catalog:(from_factory Nodes.Attribute_transfer.factory [
                "owner",Choice_value (String.capitalize_ascii owner_name);
                "mode",Choice_value mode_name;"neighbors",Int_value 3;"power",Float_value 1.5;
                "kernel_radius",Float_value 2.;"distance_mode",Choice_value (if max_distance=None then "Auto" else "Explicit");
                "max_distance",Float_value maximum;"blend_width",Float_value blend_width;
                "falloff",Choice_value falloff_name;"uniform_bias",Float_value 0.3;
                "unmatched",Choice_value (if unmatched=Rdk.Attribute_ops.Keep_target then "Keep target" else "Default value");
                "use_names",Bool_value use_names;"names",Text_value "weight";"pattern",Text_value "w*"]
                [transfer_source;transfer_target])) [false;true]) [Rdk.Attribute_ops.Keep_target;Default_value])
          [0.;0.75]) [None;Some 0.;Some 0.5;Some 2.]) transfer_falloffs)
      transfer_modes) interpolation_owners;
  List.iter (fun (owner,token) ->
    let source_owner,target_owner=match owner with
      | Rdk.Attribute.Point -> Rdk.Group.Point,Rdk.Group.Point
      | Primitive -> Rdk.Group.Primitive,Rdk.Group.Primitive
      | Vertex -> Rdk.Group.Primitive,Rdk.Group.Vertex | Detail -> assert false in
    let group_count group_owner geometry=match group_owner with
      | Rdk.Group.Point -> Rdk.Geometry.point_count geometry
      | Vertex -> Rdk.Geometry.vertex_count geometry
      | Primitive -> Rdk.Geometry.primitive_count geometry in
    let source_group=Rdk.Group.init ~owner:source_owner ~name:"selected"
      (group_count source_owner transfer_source_geometry) (fun i -> i mod 2=0)
    and target_group=Rdk.Group.init ~owner:target_owner ~name:"selected"
      (group_count target_owner transfer_target_geometry) (fun i -> i mod 2=0) in
    let source_geometry=Rdk.Geometry.with_group source_group transfer_source_geometry |> Result.get_ok
    and target_geometry=Rdk.Geometry.with_group target_group transfer_target_geometry |> Result.get_ok in
    let source=Sop.snapshot source_geometry and target=Sop.snapshot target_geometry in
    List.iter (fun (group,pattern) ->
      let typed=Sop.attribute_transfer ~owner ~pattern:"weight" ~distance_mode:Sop.Kernel_auto
        ~source_group:group ~source_group_pattern:pattern ~target_group:group ~target_group_pattern:pattern source target in
      let native=native_transfer ~owner ~mode:Rdk.Attribute_ops.Nearest ~pattern:"weight"
        ~source_group ~target_group ~blend_width:0. ~falloff:Rdk.Attribute_ops.Linear
        ~unmatched:Rdk.Attribute_ops.Keep_target ~source:source_geometry ~target:target_geometry () in
      check (equal_geometry native (cook 1 typed)) "Attribute Transfer selected native parity";
      same_node "Attribute Transfer exact/pattern groups" ~typed
        ~catalog:(from_factory Nodes.Attribute_transfer.factory ["owner",Choice_value (String.capitalize_ascii token);
          "pattern",Text_value "weight";"distance_mode",Choice_value "Auto";
          "source_group",Text_value group;"source_group_pattern",Text_value pattern;
          "target_group",Text_value group;"target_group_pattern",Text_value pattern] [source;target]))
      ["selected","";"","select*";"ignored_missing","select*"])
    [Rdk.Attribute.Point,"point";Vertex,"vertex";Primitive,"primitive"];
  let transfer_corners=Rdk.Group.init ~owner:Rdk.Group.Vertex ~name:"corners"
    (Rdk.Geometry.vertex_count transfer_source_geometry) (fun i -> i mod 4=0) in
  let transfer_corner_geometry=Rdk.Geometry.with_group transfer_corners transfer_source_geometry |> Result.get_ok in
  let transfer_corner_source=Sop.snapshot transfer_corner_geometry in
  List.iter (fun (source_vertex_selection,selection_name) ->
    let typed=Sop.attribute_transfer ~owner:Rdk.Attribute.Vertex ~pattern:"weight"
      ~distance_mode:Sop.Kernel_auto ~source_vertex_group_pattern:"corner*"
      ~source_vertex_selection transfer_corner_source transfer_target in
    let native=Rdk.Attribute_ops.transfer_vertices ~pattern:"weight" ~source_vertices:transfer_corners
      ~source_vertex_selection ~falloff:Rdk.Attribute_ops.Linear
      ~source:transfer_corner_geometry ~target:transfer_target_geometry ()
      |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
    check (equal_geometry native (cook 1 typed)) "Attribute Transfer all/any vertex selection native parity";
    same_node "Attribute Transfer source-corner selections" ~typed
      ~catalog:(from_factory Nodes.Attribute_transfer.factory ["owner",Choice_value "Vertex";
        "pattern",Text_value "weight";"distance_mode",Choice_value "Auto";
        "source_vertex_group_pattern",Text_value "corner*";
        "source_vertex_selection",Choice_value selection_name] [transfer_corner_source;transfer_target]))
    [Rdk.Attribute_ops.All_triangle_vertices,"All triangle vertices";
     Any_triangle_vertex,"Any triangle vertex"];
  let transfer_escaped_geometry=interpolation_add ~owner:Rdk.Attribute.Point ~name:"weight\tvalue"
    (Rdk.Attribute.Float (Array.make (Rdk.Geometry.point_count transfer_source_geometry) 7.)) transfer_source_geometry in
  let transfer_escaped_source=Sop.snapshot transfer_escaped_geometry in
  let transfer_escaped=Sop.attribute_transfer ~use_names:true ~names:"weight\\tvalue"
    transfer_escaped_source transfer_target in
  let transfer_escaped_native=native_transfer ~owner:Rdk.Attribute.Point ~mode:Rdk.Attribute_ops.Nearest
    ~names:["weight\tvalue"] ~max_distance:1. ~blend_width:0. ~falloff:Rdk.Attribute_ops.Linear
    ~unmatched:Rdk.Attribute_ops.Keep_target ~source:transfer_escaped_geometry ~target:transfer_target_geometry () in
  check (equal_geometry transfer_escaped_native (cook 1 transfer_escaped)) "Attribute Transfer escaped exact-name native parity";
  same_node "Attribute Transfer escaped exact names" ~typed:transfer_escaped
    ~catalog:(from_factory Nodes.Attribute_transfer.factory ["use_names",Bool_value true;
      "names",Text_value "weight\\tvalue"] [transfer_escaped_source;transfer_target]);
  let transfer_inspector=Sop.attribute_transfer transfer_source transfer_target in
  List.iter (fun values -> check (Result.is_error (Node.apply_parameters transfer_inspector values))
    "Attribute Transfer inspector validation error") [
      ["source_vertex_group",Text_value "corners"];
      ["pattern",Text_value "bad["];
      ["use_names",Bool_value true;"names",Text_value "weight\nweight"];
      ["distance_mode",Choice_value "Auto";"blend_width",Float_value 1.]];
  cache_identity "Attribute Transfer all fields"
    ~companions:["source_vertex_group",["owner",Choice_value "Vertex"];
      "source_vertex_group_pattern",["owner",Choice_value "Vertex"]]
    (Sop.attribute_transfer ~pattern:"weight" transfer_source transfer_target);
  List.iter (fun build -> check (match build () with
    | _ -> false | exception Invalid_argument _ -> true) "Attribute Transfer construction refusal") [
      (fun () -> Sop.attribute_transfer ~neighbors:0 transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~power:nan transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~mode:Sop.Transfer_inverse ~power:0. transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~kernel_radius:(-.1.) transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~max_distance:Float.max_float transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~distance_mode:Sop.Kernel_auto ~blend_width:0.5 transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~uniform_bias:1.1 transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~owner:Rdk.Attribute.Detail transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~owner:Rdk.Attribute.Vertex ~mode:Sop.Transfer_links transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~source_vertex_group:"g" transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~source_group_pattern:"bad[" transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~pattern:"bad[" transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~use_names:true ~names:"weight\nweight" transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~use_names:true ~names:"P" transfer_source transfer_target);
      (fun () -> Sop.attribute_transfer ~use_names:true ~names:"weight\tother" transfer_source transfer_target)];
  let composite_geometry offset =
    let geometry = Rdk.Plane_generators.grid ~columns:2 ~rows:2 ~size:2. () |> Result.get_ok in
    List.fold_left (fun geometry (owner,_) ->
      let count = interpolation_count owner geometry in
      let values = Array.init count (fun i -> offset +. float_of_int (i+1)) in
      geometry
      |> interpolation_add ~owner ~name:"value" (Rdk.Attribute.Float values)
      |> interpolation_add ~owner ~name:"vector2" (Rdk.Attribute.Float2
          (Rdk.Packed.Float2.of_owned ~x:(Array.copy values) ~y:(Array.map (( *. ) 2.) values) |> Result.get_ok))
      |> interpolation_add ~owner ~name:"vector3" (Rdk.Attribute.Float3
          (Rdk.Packed.Float3.Private.of_owned_exn ~x:(Array.copy values)
            ~y:(Array.map (( *. ) 2.) values) ~z:(Array.map (( *. ) 3.) values)))
      |> interpolation_add ~owner ~name:"vector4" (Rdk.Attribute.Float4
          (Rdk.Packed.Float4.of_owned ~x:(Array.copy values) ~y:(Array.map (( *. ) 2.) values)
            ~z:(Array.map (( *. ) 3.) values) ~w:(Array.map (( *. ) 4.) values) |> Result.get_ok))
      |> interpolation_add ~owner ~name:"alpha" (Rdk.Attribute.Float
          (Array.init count (fun i -> if i mod 3=0 then 0. else 0.5)))
      |> interpolation_add ~owner ~name:"ignored" (Rdk.Attribute.Int (Array.make count 7)))
      geometry interpolation_owners in
  let composite_base_geometry=composite_geometry 0.
  and composite_layer_geometry=composite_geometry 5. in
  let composite_base=Sop.snapshot composite_base_geometry
  and composite_layer=Sop.snapshot composite_layer_geometry in
  let composite_operations=[Rdk.Attribute_composite.Composite_mean,"Mean";
    Composite_maximum,"Maximum";Composite_minimum,"Minimum";Composite_over,"Over";Composite_under,"Under"] in
  let composite_cases=[None,None,None,None,[],[];
    Some composite_layer,None,None,None,[],[0.75];
    None,Some composite_layer,None,Some composite_layer,[],[0.;1.5];
    Some composite_layer,Some composite_layer,Some composite_layer,Some composite_layer,
      [composite_layer;composite_layer;composite_layer],[0.75;0.;-.0.25;1.5;0.2;1.;-.0.1]] in
  List.iter (fun (operation,operation_name) -> List.iter (fun allow_position ->
    List.iter (fun alpha_attribute -> List.iter (fun selected_owner ->
      let pattern owner=if selected_owner=None || selected_owner=Some owner then "P value vector*" else "^*" in
      let point_attributes=pattern Rdk.Attribute.Point and vertex_attributes=pattern Rdk.Attribute.Vertex
      and primitive_attributes=pattern Rdk.Attribute.Primitive and detail_attributes=pattern Rdk.Attribute.Detail in
      List.iter (fun (layer1,layer2,layer3,layer4,layers,native_weights) ->
        let typed=Sop.attribute_composite ~operation ~weight:1.25 ~point_attributes ~vertex_attributes
          ~primitive_attributes ~detail_attributes ~allow_position ~alpha_attribute
          ~weight1:0.75 ~weight2:0. ~weight3:(-.0.25) ~weight4:1.5 ~weights:"0.2\n1\n-0.1"
          composite_base layer1 layer2 layer3 layer4 layers in
        let inputs=List.map (fun weight -> Rdk.Attribute_composite.input ~weight composite_layer_geometry) native_weights in
        let native=Rdk.Attribute_composite.run ~operation ~weight:1.25 ~point_attributes ~vertex_attributes
          ~primitive_attributes ~detail_attributes ~allow_position
          ?alpha_attribute:(if String.trim alpha_attribute="" then None else Some alpha_attribute)
          ~inputs composite_base_geometry |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
        check (equal_geometry native (cook 1 typed)) "Attribute Composite native operations/owners/weights parity";
        same_node "Attribute Composite fixed and unlimited layer controls" ~typed
          ~catalog:(from_factory ~optional_inputs:(Some composite_base :: layer1 :: layer2 :: layer3 :: layer4
              :: List.map Option.some layers) Nodes.Attribute_composite.factory [
            "operation",Choice_value operation_name;"weight",Float_value 1.25;
            "point_attributes",Text_value point_attributes;"vertex_attributes",Text_value vertex_attributes;
            "primitive_attributes",Text_value primitive_attributes;"detail_attributes",Text_value detail_attributes;
            "allow_position",Bool_value allow_position;"alpha_attribute",Text_value alpha_attribute;
            "weight1",Float_value 0.75;"weight2",Float_value 0.;"weight3",Float_value (-.0.25);
            "weight4",Float_value 1.5;"weights",Text_value "0.2\n1\n-0.1"] [])) composite_cases)
      [None;Some Rdk.Attribute.Point;Some Rdk.Attribute.Vertex;Some Rdk.Attribute.Primitive;Some Rdk.Attribute.Detail])
      ["";" ";"alpha"]) [false;true]) composite_operations;
  let composite_default=Sop.attribute_composite composite_base None None None None [] in
  same_node "Attribute Composite defaults" ~typed:composite_default
    ~catalog:(from_factory ~optional_inputs:[Some composite_base;None;None;None;None]
      Nodes.Attribute_composite.factory [] []);
  let composite_missing_weights=Sop.attribute_composite ~weights:"0.5" composite_base None None None None
    [composite_layer;composite_layer] in
  let composite_missing_native=Rdk.Attribute_composite.run
    ~inputs:[Rdk.Attribute_composite.input ~weight:0.5 composite_layer_geometry;
      Rdk.Attribute_composite.input ~weight:1. composite_layer_geometry] composite_base_geometry |> Result.get_ok in
  check (equal_geometry composite_missing_native (cook 1 composite_missing_weights))
    "Attribute Composite missing additional weights use Lisp default";
  let composite_cache=Sop.attribute_composite composite_base (Some composite_layer) (Some composite_layer)
    (Some composite_layer) (Some composite_layer) [composite_layer] in
  cache_identity "Attribute Composite all fields" ~changes:["weights",Text_value "0.5"] composite_cache;
  List.iter (fun build -> check (match build () with _ -> false | exception Invalid_argument _ -> true)
      "Attribute Composite construction validation") [
    (fun () -> Sop.attribute_composite ~weight:nan composite_base None None None None []);
    (fun () -> Sop.attribute_composite ~weight1:infinity composite_base None None None None []);
    (fun () -> Sop.attribute_composite ~weights:"nan" composite_base None None None None []);
    (fun () -> Sop.attribute_composite ~weights:"1\t2" composite_base None None None None []);
    (fun () -> Sop.attribute_composite ~weights:"invalid" composite_base None None None None []);
    (fun () -> Sop.attribute_composite ~point_attributes:"bad[" composite_base None None None None [])];
  List.iter (fun values -> check (Result.is_error (Node.apply_parameters composite_cache values))
      "Attribute Composite inspector validation") [
    ["weights",Text_value "infinity"];["weights",Text_value "1\t2"];
    ["vertex_attributes",Text_value "bad["]];
  let composite_third_geometry=composite_geometry 9. in
  let composite_third=Sop.snapshot composite_third_geometry in
  List.iter (fun (operation,_) ->
    let typed=Sop.attribute_composite ~operation ~weight:1.25 ~weight2:0.7 ~weight4:0.2
      ~weights:"0.3\n0.4" ~alpha_attribute:"alpha" ~allow_position:true
      composite_base None (Some composite_layer) None (Some composite_third)
      [composite_third;composite_layer] in
    let native=Rdk.Attribute_composite.run ~operation ~weight:1.25 ~alpha_attribute:"alpha" ~allow_position:true
      ~inputs:[Rdk.Attribute_composite.input ~weight:0.7 composite_layer_geometry;
        Rdk.Attribute_composite.input ~weight:0.2 composite_third_geometry;
        Rdk.Attribute_composite.input ~weight:0.3 composite_third_geometry;
        Rdk.Attribute_composite.input ~weight:0.4 composite_layer_geometry] composite_base_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "Attribute Composite distinct ordered layer native parity";
    same_node "Attribute Composite distinct fixed/rest input order" ~typed
      ~catalog:(from_factory ~optional_inputs:[Some composite_base;None;Some composite_layer;None;
        Some composite_third;Some composite_third;Some composite_layer] Nodes.Attribute_composite.factory [
        "operation",Choice_value (List.assoc operation composite_operations);"weight",Float_value 1.25;
        "weight2",Float_value 0.7;"weight4",Float_value 0.2;"weights",Text_value "0.3\n0.4";
        "alpha_attribute",Text_value "alpha";"allow_position",Bool_value true] [])) composite_operations;
  let composite_large offset=Rdk.Line_geometry.points
    (Array.init 10_000 (fun i -> offset +. float i,0.,0.))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"value"
      (Rdk.Attribute.Float (Array.init 10_000 (fun i -> offset +. float (i mod 97)))) in
  let large_base_geometry=composite_large 0. and large_layer_geometry=composite_large 7. in
  let large_base=Sop.snapshot large_base_geometry and large_layer=Sop.snapshot large_layer_geometry in
  List.iter (fun (operation,name) ->
    let typed=Sop.attribute_composite ~operation ~point_attributes:"P value" ~allow_position:true
      ~weight:0.25 ~weights:"0.75" large_base None None None None [large_layer] in
    let native=Rdk.Attribute_composite.run ~operation ~point_attributes:"P value" ~allow_position:true
      ~weight:0.25 ~inputs:[Rdk.Attribute_composite.input ~weight:0.75 large_layer_geometry]
      large_base_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "Attribute Composite parallel native parity";
    same_node "Attribute Composite parallel all-operation parity" ~typed
      ~catalog:(from_factory ~optional_inputs:[Some large_base;None;None;None;None;Some large_layer]
        Nodes.Attribute_composite.factory ["operation",Choice_value name;"point_attributes",Text_value "P value";
          "allow_position",Bool_value true;"weight",Float_value 0.25;"weights",Text_value "0.75"] [])) composite_operations;
  let blend_geometry offset shift =
    let count=9 in
    let values=Array.init count (fun i -> offset +. float (i+1)) in
    let ids=Array.init count (fun i -> (i+shift) mod count) in
    Rdk.Line_geometry.points (Array.init count (fun i -> offset +. float i,0.,0.))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"value" (Rdk.Attribute.Float values)
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"vector2" (Rdk.Attribute.Float2
      (Rdk.Packed.Float2.of_owned ~x:(Array.copy values) ~y:(Array.map (( *. ) 2.) values) |> Result.get_ok))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"vector3" (Rdk.Attribute.Float3
      (Rdk.Packed.Float3.Private.of_owned_exn ~x:(Array.copy values)
        ~y:(Array.map (( *. ) 2.) values) ~z:(Array.map (( *. ) 3.) values)))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"vector4" (Rdk.Attribute.Float4
      (Rdk.Packed.Float4.of_owned ~x:(Array.copy values) ~y:(Array.map (( *. ) 2.) values)
        ~z:(Array.map (( *. ) 3.) values) ~w:(Array.map (( *. ) 4.) values) |> Result.get_ok))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"mask" (Rdk.Attribute.Float
      (Array.init count (fun i -> float ((i+shift) mod 3) *. 0.5)))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"other_mask" (Rdk.Attribute.Float
      (Array.init count (fun i -> float ((i+shift+1) mod 3) *. 0.5)))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"id" (Rdk.Attribute.Int ids)
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"text_id" (Rdk.Attribute.Text (Array.map string_of_int ids))
    |> fun geometry -> Rdk.Geometry.with_group
      (Rdk.Group.init ~owner:Rdk.Group.Point ~name:"selected" count (fun i -> i mod 2=0)) geometry |> Result.get_ok in
  let blend_base_geometry=blend_geometry 0. 0
  and blend_first_geometry=blend_geometry 10. 1
  and blend_second_geometry=blend_geometry 20. 2 in
  let blend_base=Sop.snapshot blend_base_geometry and blend_first=Sop.snapshot blend_first_geometry
  and blend_second=Sop.snapshot blend_second_geometry in
  let blend_modes=[Rdk.Blend_shapes.Blend_normalized,"Normalized";Blend_differencing,"Differencing"]
  and blend_maskings=[Rdk.Blend_shapes.Blend_no_mask,"None";Blend_set_from_attribute,"Set from attribute";
    Blend_scale_from_attribute,"Scale from attribute"]
  and blend_sources=[Rdk.Blend_shapes.Blend_mask_first_input,"First input";Blend_mask_shape,"Shape"] in
  let blend_cases=[None,None,None,None,[],[];
    Some blend_first,None,None,None,[],[1,1.5,blend_first_geometry];
    None,Some blend_first,None,Some blend_second,[],[2,-.0.5,blend_first_geometry;4,0.,blend_second_geometry];
    Some blend_first,Some blend_second,Some blend_first,Some blend_second,[blend_second;blend_first;blend_second],
      [1,1.5,blend_first_geometry;2,-.0.5,blend_second_geometry;3,0.3,blend_first_geometry;4,0.,blend_second_geometry;
       5,0.4,blend_second_geometry;6,-.0.2,blend_first_geometry;7,0.6,blend_second_geometry]] in
  List.iter (fun (mode,mode_name) -> List.iter (fun (masking,masking_name) ->
    List.iter (fun (mask_source,source_name) -> List.iter (fun point_id_attribute ->
      List.iter (fun group -> List.iter (fun attributes -> List.iter (fun overrides ->
        let shape_masks=if overrides then "2\tother_mask\tshape\n5\tother_mask\tfirst\n6\t\tshape" else "" in
        let setting index=if overrides && index=2 then Some "other_mask",Rdk.Blend_shapes.Blend_mask_shape
          else if overrides && index=5 then Some "other_mask",Rdk.Blend_shapes.Blend_mask_first_input
          else if overrides && index=6 then None,Rdk.Blend_shapes.Blend_mask_shape else None,mask_source in
        List.iter (fun (shape1,shape2,shape3,shape4,shapes,native_shapes) ->
          let typed=Sop.blend_shapes ~mode ~masking ~mask_source ~point_id_attribute ~group ~attributes
            ~weight1:1.5 ~weight2:(-.0.5) ~weight3:0.3 ~weight4:0. ~weights:"0.4\n-0.2\n0.6" ~shape_masks
            blend_base shape1 shape2 shape3 shape4 shapes in
          let native_shapes=List.map (fun (index,weight,geometry) ->
            let mask_attribute,mask_source=setting index in
            Rdk.Blend_shapes.shape ?mask_attribute ~mask_source ~weight geometry) native_shapes in
          let points=if group="" then None else Rdk.Geometry.find_group ~owner:Rdk.Group.Point group blend_base_geometry in
          let native=Rdk.Blend_shapes.run ~mode ~masking ?points ~attributes
            ?mask_attribute:(if masking=Rdk.Blend_shapes.Blend_no_mask then None else Some "mask")
            ?point_id_attribute:(if point_id_attribute="" then None else Some point_id_attribute)
            ~shapes:native_shapes blend_base_geometry |> function Ok geometry -> geometry | Error error -> fail (Rdk.Error.to_string error) in
          check (equal_geometry native (cook 1 typed)) "Blend Shapes native modes/masks/matching/weights parity";
          same_node "Blend Shapes flat fixed and unlimited shape controls" ~typed
            ~catalog:(from_factory ~optional_inputs:(Some blend_base::shape1::shape2::shape3::shape4
                :: List.map Option.some shapes) Nodes.Blend_shapes.factory [
              "mode",Choice_value mode_name;"masking",Choice_value masking_name;"mask_source",Choice_value source_name;
              "point_id_attribute",Text_value point_id_attribute;"group",Text_value group;"attributes",Text_value attributes;
              "weight1",Float_value 1.5;"weight2",Float_value (-.0.5);"weight3",Float_value 0.3;"weight4",Float_value 0.;
              "weights",Text_value "0.4\n-0.2\n0.6";"shape_masks",Text_value shape_masks] [])) blend_cases)
        [false;true]) ["^*";"value vector*"]) ["";"selected"])
      ["";"id";"text_id"]) blend_sources) blend_maskings) blend_modes;
  let blend_default=Sop.blend_shapes blend_base None None None None [] in
  same_node "Blend Shapes defaults/empty inputs" ~typed:blend_default
    ~catalog:(from_factory ~optional_inputs:[Some blend_base;None;None;None;None] Nodes.Blend_shapes.factory [] []);
  check (Node.id blend_default<>Node.id blend_base && Node.parameter_key blend_default<>""
    && equal_geometry (cook 1 blend_default) blend_base_geometry) "Blend Shapes empty list retains Lisp node identity";
  let blend_missing_weights=Sop.blend_shapes ~weights:"0.5" blend_base None None None None [blend_first;blend_second] in
  let blend_missing_native=Rdk.Blend_shapes.run
    ~shapes:[Rdk.Blend_shapes.shape ~weight:0.5 blend_first_geometry;
      Rdk.Blend_shapes.shape ~weight:0. blend_second_geometry] blend_base_geometry |> Result.get_ok in
  check (equal_geometry blend_missing_native (cook 1 blend_missing_weights)) "Blend Shapes missing extra weights default to zero";
  let blend_cache=Sop.blend_shapes ~attributes:"value vector*" blend_base (Some blend_first) (Some blend_second)
    (Some blend_first) (Some blend_second) [blend_first] in
  cache_identity "Blend Shapes every field"
    ~changes:["weights",Text_value "0.5";"shape_masks",Text_value "5\tother_mask\tshape"] blend_cache;
  List.iter (fun build -> check (match build () with _ -> false | exception Invalid_argument _ -> true)
    "Blend Shapes constructor validation") [
    (fun () -> Sop.blend_shapes ~weight1:nan blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~weight4:infinity blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~weights:"nan" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~weights:"1\t2" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~shape_masks:"0\tmask\tshape" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~shape_masks:"1\tmask\tbad" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~shape_masks:"1\tmask\tshape\n1\tother_mask\tfirst" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~shape_masks:"1\tmask" blend_base None None None None []);
    (fun () -> Sop.blend_shapes ~attributes:"bad[" blend_base None None None None [])];
  List.iter (fun values -> check (Result.is_error (Node.apply_parameters blend_cache values))
    "Blend Shapes inspector validation") [["weights",Text_value "infinity"];
      ["shape_masks",Text_value "0\tmask\tshape"];["shape_masks",Text_value "1\tmask\tinvalid"];
      ["attributes",Text_value "bad["]];
  List.iter (fun mask_attribute -> List.iter (fun shape_masks ->
    let override=if shape_masks="" then None else Some "other_mask" in
    let typed=Sop.blend_shapes ~group:" " ~point_id_attribute:" " ~mask_attribute
      ~masking:Rdk.Blend_shapes.Blend_scale_from_attribute ~weight1:0.4 ~shape_masks
      blend_base (Some blend_first) None None None [] in
    let native=Rdk.Blend_shapes.run ~masking:Rdk.Blend_shapes.Blend_scale_from_attribute
      ?mask_attribute:(if String.trim mask_attribute="" then None else Some mask_attribute)
      ~shapes:[Rdk.Blend_shapes.shape ~mask_source:Rdk.Blend_shapes.Blend_mask_first_input
        ?mask_attribute:override ~weight:0.4 blend_first_geometry] blend_base_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "Blend Shapes blank global names and per-shape override parity";
    same_node "Blend Shapes optional names and per-shape masks" ~typed
      ~catalog:(from_factory ~optional_inputs:[Some blend_base;Some blend_first;None;None;None] Nodes.Blend_shapes.factory [
        "group",Text_value " ";"point_id_attribute",Text_value " ";"mask_attribute",Text_value mask_attribute;
        "masking",Choice_value "Scale from attribute";"weight1",Float_value 0.4;"shape_masks",Text_value shape_masks] []))
      ["";"1\tother_mask\tfirst"]) ["";" ";"mask"];
  let blend_partial_geometry=Rdk.Line_geometry.points [|50.,0.,0.;60.,0.,0.|]
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"id" (Rdk.Attribute.Int [|0;7|])
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"text_id" (Rdk.Attribute.Text [|"0";"7"|]) in
  let blend_partial=Sop.snapshot blend_partial_geometry in
  List.iter (fun (mode,mode_name) -> List.iter (fun point_id_attribute ->
    let typed=Sop.blend_shapes ~mode ~point_id_attribute ~weights:"0.8" blend_base None None None None [blend_partial] in
    let native=Rdk.Blend_shapes.run ~mode ~point_id_attribute
      ~shapes:[Rdk.Blend_shapes.shape ~weight:0.8 blend_partial_geometry] blend_base_geometry |> Result.get_ok in
    check (equal_geometry native (cook 1 typed)) "Blend Shapes partial ID matching and missing target attribute parity";
    same_node "Blend Shapes differently sized partial-ID targets" ~typed
      ~catalog:(from_factory ~optional_inputs:[Some blend_base;None;None;None;None;Some blend_partial] Nodes.Blend_shapes.factory [
        "mode",Choice_value mode_name;"point_id_attribute",Text_value point_id_attribute;"weights",Text_value "0.8"] []))
      ["id";"text_id"]) blend_modes;
  let blend_large offset shift=let count=10_000 in
    composite_large offset
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"mask" (Rdk.Attribute.Float
      (Array.init count (fun i -> float ((i+shift) mod 3) *. 0.5)))
    |> interpolation_add ~owner:Rdk.Attribute.Point ~name:"id" (Rdk.Attribute.Int
      (Array.init count (fun i -> (i+shift) mod count))) in
  let blend_large_base_geometry=blend_large 0. 0 and blend_large_shape_geometry=blend_large 7. 1 in
  let blend_large_base=Sop.snapshot blend_large_base_geometry and blend_large_shape=Sop.snapshot blend_large_shape_geometry in
  List.iter (fun (mode,mode_name) -> List.iter (fun (masking,masking_name) ->
    List.iter (fun (mask_source,source_name) ->
      let typed=Sop.blend_shapes ~mode ~masking ~mask_source ~point_id_attribute:"id" ~weights:"0.37"
        blend_large_base None None None None [blend_large_shape] in
      let native=Rdk.Blend_shapes.run ~mode ~masking ~mask_attribute:"mask" ~point_id_attribute:"id"
        ~shapes:[Rdk.Blend_shapes.shape ~weight:0.37 ~mask_source blend_large_shape_geometry]
        blend_large_base_geometry |> Result.get_ok in
      check (equal_geometry native (cook 1 typed)) "Blend Shapes native parallel masked/mapped parity";
      same_node "Blend Shapes large parallel modes and masks" ~typed
        ~catalog:(from_factory ~optional_inputs:[Some blend_large_base;None;None;None;None;Some blend_large_shape]
          Nodes.Blend_shapes.factory ["mode",Choice_value mode_name;"masking",Choice_value masking_name;
            "mask_source",Choice_value source_name;"point_id_attribute",Text_value "id";"weights",Text_value "0.37"] []))
      blend_sources) blend_maskings) blend_modes;
  let blend_escaped_geometry=interpolation_add ~owner:Rdk.Attribute.Point ~name:"mask\tvalue"
    (Rdk.Attribute.Float (Array.make 9 0.4)) blend_first_geometry in
  let blend_escaped=Sop.snapshot blend_escaped_geometry in
  let blend_escaped_typed=Sop.blend_shapes ~masking:Rdk.Blend_shapes.Blend_scale_from_attribute
    ~mask_attribute:"" ~weights:"0.75" ~shape_masks:"5\tmask\\tvalue\tshape"
    blend_base None None None None [blend_escaped] in
  let blend_escaped_native=Rdk.Blend_shapes.run ~masking:Rdk.Blend_shapes.Blend_scale_from_attribute
    ~shapes:[Rdk.Blend_shapes.shape ~weight:0.75 ~mask_attribute:"mask\tvalue"
      ~mask_source:Rdk.Blend_shapes.Blend_mask_shape blend_escaped_geometry] blend_base_geometry |> Result.get_ok in
  check (equal_geometry blend_escaped_native (cook 1 blend_escaped_typed)) "Blend Shapes escaped per-shape mask native parity";
  same_node "Blend Shapes escaped mask overrides" ~typed:blend_escaped_typed
    ~catalog:(from_factory ~optional_inputs:[Some blend_base;None;None;None;None;Some blend_escaped]
      Nodes.Blend_shapes.factory ["masking",Choice_value "Scale from attribute";"mask_attribute",Text_value "";
        "weights",Text_value "0.75";"shape_masks",Text_value "5\tmask\\tvalue\tshape"] []);
  same_cook "Group Random actual Lisp defaults" ~typed:(Sop.group_random warped)
    ~factory:Nodes.Group_random.factory [] warped;
  same_cook "Noise Displace actual Lisp defaults" ~typed:(Sop.noise_displace warped)
    ~factory:Nodes.Noise_displace.factory [] warped;
  List.iter (fun context_seed -> List.iter (fun seed ->
    same_cook "Group Random explicit context flag" ~typed:(Sop.group_random ~context_seed ~seed warped)
      ~factory:Nodes.Group_random.factory ["context_seed",Bool_value context_seed;"seed",Int_value seed] warped;
    same_cook "Noise Displace explicit context flag" ~typed:(Sop.noise_displace ~context_seed ~seed warped)
      ~factory:Nodes.Noise_displace.factory ["context_seed",Bool_value context_seed;"seed",Int_value seed] warped)
    [0;17]) [false;true];
  List.iter (fun count ->
    let inputs = List.filteri (fun index _ -> index < count) merge_inputs in
    let a, b, rest = match inputs with a :: b :: rest -> a, b, rest | _ -> fail "switch inputs" in
    List.iteri (fun input branch ->
      let typed = Sop.switch ~input a b rest in
      same_node (Printf.sprintf "switch %d of %d" input count) ~typed
        ~catalog:(from_factory ~optional_inputs:(List.map Option.some inputs) Nodes.Switch.factory
          ["input", Parameter.Int_value input] []);
      check (equal_geometry (cook 1 typed) (cook 1 branch)) "switch cooks its selected branch") inputs;
    check (try ignore (Sop.switch ~input:count a b rest); false with Invalid_argument _ -> true)
      "switch refuses a branch that is not connected")
    [2; 3; 5];
  print_endline "SOP node declaration tests passed"
