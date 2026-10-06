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
    | Ok value -> value.geometry
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  output

(* The factory node carrying [values], built on [inputs]. *)
let from_factory factory values inputs =
  let node = Edit_graph.instantiate factory inputs |> get in
  fst (Node.apply_parameters node values |> get)

let same_cook ?(inputs = []) name ~typed ~factory values input =
  let catalog = from_factory factory values (input :: inputs) in
  check (Node.parameter_key typed = Node.parameter_key catalog && Node.parameter_key typed <> "")
    (name ^ ": typed constructor and factory share the schema key");
  let one = cook 1 typed in
  List.iter (fun (what, geometry) -> check (equal_geometry one geometry)
      (name ^ ": " ^ what ^ " cooks the same geometry"))
    [ "typed at four domains", cook 4 typed;
      "factory at one domain", cook 1 catalog;
      "factory at four domains", cook 4 catalog ]

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

let cache_identity name node =
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
    (* an encoded table rejects an arbitrary text: that field is not probed *)
    match Node.apply_parameters node [view.name, changed view] with
    | Error _ when view.kind = Parameter.Text_view -> ()
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

let run () =
  let warped = Sop.grid ~columns:6 ~rows:6 ~size:2. ()
      |> Sop.point_jitter ~seed:7 ~scale:0.3 in
  let box = Sop.box ~size:(Vec3.create 2. 2. 2.) () in
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
  let edges = Sop.group_edges ~name:"rim" ~incidence:Rdk.Group_mesh.Boundary_edge
      ~min_length:0.1 warped in
  same_cook "group_edges" ~typed:edges ~factory:Nodes.Group_edges.factory
    [ "name", Parameter.Text_value "rim"; "incidence", Choice_value "Boundary";
      "use_min_length", Bool_value true; "min_length", Float_value 0.1 ] warped;
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
  let named = Sop.name_from_groups ~owner:Rdk.Attribute.Primitive ~pattern:"half"
      ~overlap:Rdk.Group_ops.First_group grouped in
  same_cook "name_from_groups" ~typed:named ~factory:Nodes.Name_from_groups.factory
    [ "pattern", Parameter.Text_value "half"; "overlap", Choice_value "First group" ] grouped;
  let regrouped = Sop.groups_from_name ~owner:Rdk.Attribute.Primitive ~attribute:"name"
      ~prefix:"g_" named in
  same_cook "groups_from_name" ~typed:regrouped ~factory:Nodes.Groups_from_name.factory
    [ "prefix", Parameter.Text_value "g_" ] named;
  let promoted = Sop.group_promote_boundary ~source:Rdk.Group_ops.Group_primitives
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
      ~source:grouped ~target:box () in
  same_cook "group_copy" ~typed:copied ~factory:Nodes.Group_copy.factory
    [ "copy_empty", Parameter.Bool_value true ] grouped ~inputs:[box];
  let transferred = Sop.group_transfer ~conflict:Rdk.Group_ops.Copy_overwrite ~distance:0.5
      ~source:grouped ~target:box () in
  same_cook "group_transfer" ~typed:transferred ~factory:Nodes.Group_transfer.factory
    [ "distance", Parameter.Float_value 0.5 ] grouped ~inputs:[box];
  let path_base = Sop.ordered_group ~owner:Rdk.Group.Point ~name:"path" [|0; 3|] warped in
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
  let quads = Sop.box ~connectivity:Rdk.Box_generator.Box_quads ~size:(Vec3.create 2. 2. 2.) () in
  let divided = Sop.edge_divide ~divisions:3 quads in
  same_cook "edge_divide" ~typed:divided ~factory:Nodes.Edge_divide.factory
    [ "divisions", Parameter.Int_value 3 ] quads;
  let collapsed = Sop.edge_collapse ~group:"rim" edges in
  same_cook "edge_collapse" ~typed:collapsed ~factory:Nodes.Edge_collapse.factory
    [ "group", Parameter.Text_value "rim" ] edges;
  let dissolved = Sop.dissolve ~group:"rim" edges in
  same_cook "dissolve" ~typed:dissolved ~factory:Nodes.Dissolve.factory
    [ "group", Parameter.Text_value "rim";
      (* typed defaults that differ from the editor defaults (listed drifts) *)
      "remove_inline_points", Bool_value false; "collinearity_tolerance", Float_value 0. ] edges;
  let triangulated = Sop.triangulate quads in
  same_cook "triangulate" ~typed:triangulated ~factory:Nodes.Triangulate.factory [] quads;
  let cleaned = Sop.clean ~consolidate_distance:0.05 warped in
  same_cook "clean" ~typed:cleaned ~factory:Nodes.Clean.factory
    [ "consolidate_distance", Parameter.Float_value 0.05;
      "remove_nan_points", Bool_value false; "remove_unused_points", Bool_value false;
      "delete_unused_groups", Bool_value false ] warped;
  let flipped = Sop.edge_flip ~cycles:1 box in
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
  List.iter (fun (name, node) -> cache_identity name node)
    [ "edge_divide", divided; "edge_collapse", collapsed; "dissolve", dissolved;
      "triangulate", triangulated; "clean", cleaned; "edge_flip", flipped; "edge_cusp", cusped;
      "edge_straighten", straightened; "poly_extrude", extruded; "poly_fill", filled;
      "convert_line", lines; "blast", blasted ];
  List.iter (fun (name, node) -> cache_identity name node)
    [ "group_non_planar", non_planar; "group_backface", backface; "group_unshared", unshared;
      "group_edges", edges; "group_random", random; "group_edge_depth", depth;
      "group_boundary_components", components; "group_from_attribute_boundary", boundary;
      "name_from_groups", named; "groups_from_name", regrouped;
      "group_promote_boundary", promoted; "group_delete", deleted; "group_rename", renamed;
      "group_copy", copied; "group_transfer", transferred; "group_find_path", path;
      "delete_edge_group", edge_deleted; "rename_edge_group", edge_renamed ];
  (* the typed constructor keeps its validation *)
  List.iter (fun (name, build) ->
    check (match build () with _ -> false | exception Invalid_argument _ -> true)
      (name ^ " still raises Invalid_argument"))
    [ "group_non_planar empty name", (fun () -> Sop.group_non_planar ~tolerance:0.01 ~name:" " warped);
      "group_non_planar negative tolerance", (fun () -> Sop.group_non_planar ~tolerance:(-1.) ~name:"a" warped);
      "group_backface nan viewpoint", (fun () -> Sop.group_backface ~viewpoint:(Vec3.create nan 0. 0.) ~name:"a" box);
      "group_backface empty base", (fun () -> Sop.group_backface ~base:"" ~viewpoint:Vec3.zero ~name:"a" box);
      "group_unshared empty name", (fun () -> Sop.group_unshared ~owner:Rdk.Group_ops.Group_edges ~name:"" box) ];
  print_endline "SOP node declaration tests passed"
