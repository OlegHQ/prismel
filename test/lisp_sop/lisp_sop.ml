let factories = Sop_catalog.Editor.factories

let snapshot geometry =
  let parameters = Printf.sprintf "data_id=%d;bytes=%d"
      (Rdk.Geometry.data_id geometry) (Rdk.Geometry.payload_bytes geometry) in
  Sop.Node.Private.make_geometry ~operation:"snapshot" ~version:1 ~parameters
    ~cook_mode:Sop.Node.Generator
    ~dependencies:Sop.Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ _context _inputs ->
      Ok Sop.Node.Private.{geometry; diagnostics = []; instances = None})

(* An external node may itself have inputs, but a factory node cannot: the lowering sees an
   input-free marker per external node and the real nodes are put back afterwards. *)
let marker name =
  Sop.Node.Private.make_geometry ~operation:"lisp_sop_ext" ~version:1
    ~parameters:name ~cook_mode:Sop.Node.Generator
    ~dependencies:Sop.Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ _context _inputs -> failwith "Lisp_sop: marker cooked")

let restore with_ root =
  let module Node = Sop.Node in
  let rec go node =
    if Node.operation node = "lisp_sop_ext" then List.assoc (Node.parameters node) with_
    else match Node.inputs node with
      | [] -> node
      | inputs ->
          let rebuilt = List.map go inputs in
          if List.for_all2 (==) inputs rebuilt then node
          else Node.Private.rebuild_with_inputs node (Array.of_list rebuilt) in
  go root

let node_result ?(with_ = []) text =
  let external_factories = List.map (fun (name, _) ->
    let marker = marker name in
    Sop.Edit_graph.factory ~key:("ext_" ^ name) ~label:("Ext " ^ name)
      ~category:["Test"] ~arity:0 (fun _ -> marker)) with_ in
  let factories = external_factories @ factories in
  let source = "(workspace w (graph g :context sop " ^ text ^ "))" in
  match Flow.Syntax.parse source with
  | Error d -> Error (Flow.Diagnostic.to_string d)
  | Ok forms ->
      match Flow_sop.Lower.workspace ~extra:Editor_document.Contexts.descriptors
              ~factories forms with
      | Error d -> Error (Flow.Diagnostic.to_string d)
      | Ok lowered ->
          let graph = List.hd lowered.graphs in
          match graph.root with
          | None -> Error "the graph has no result"
          | Some root ->
              Result.map (restore with_)
                (Sop.Edit_graph.compile_node graph.network.geometry ~node_id:root)

let node ?with_ text = match node_result ?with_ text with
  | Ok node -> node
  | Error message -> failwith ("Lisp_sop: " ^ message ^ "\n" ^ text)

(* Printing OCaml values as Lisp literals, for the holes of ported tests. *)
let float x =
  let rec go p = let s = Printf.sprintf "%.*g" p x in
    if p >= 17 || float_of_string s = x then s else go (p + 1) in
  let s = go 15 in
  if String.exists (fun c -> c = '.' || c = 'e' || c = 'n' || c = 'i') s then s else s ^ ".0"

let vec3 (v : Rays_math.Vec3.t) = Printf.sprintf "[%s %s %s]" (float v.x) (float v.y) (float v.z)

let curve_points points =
  "[" ^ String.concat " " (List.map (fun (x, y, z) ->
    Printf.sprintf "[%s %s %s]" (float x) (float y) (float z)) (Array.to_list points)) ^ "]"
