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

(* The factory node carrying [values], built on [input]. *)
let from_factory factory values input =
  let node = Edit_graph.instantiate factory [input] |> get in
  fst (Node.apply_parameters node values |> get)

let same_cook name ~typed ~factory values input =
  let catalog = from_factory factory values input in
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
    let edited = fst (Node.apply_parameters node [view.name, changed view] |> get) in
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
  List.iter (fun (name, node) -> cache_identity name node)
    [ "group_non_planar", non_planar; "group_backface", backface; "group_unshared", unshared ];
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
