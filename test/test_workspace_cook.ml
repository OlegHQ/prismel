(* W2: every workspace fixture lowers and cooks, byte for byte the same at 1
   and 3 domains; node counts; provenance. *)
open Flow_sop

let fail message = failwith ("test_workspace_cook: " ^ message)
let check condition message = if not condition then fail message
let read path = In_channel.with_open_bin path In_channel.input_all
let cases = "../specification/workspace/cases"
let factories = Sop_catalog.Editor.factories

let lower ?inputs name =
  match Flow.Syntax.parse (read (Filename.concat cases (name ^ ".lisp"))) with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok forms -> (match Lower.workspace ~factories ?inputs forms with
      | Ok lowered -> lowered
      | Error d -> fail (name ^ ": " ^ Flow.Diagnostic.to_string d))

let geometry_bytes geometry =
  let open Pdk in
  let encode value = Marshal.to_string value [Marshal.No_sharing] in
  let attribute (attribute : Attribute.t) =
    let payload = match Attribute.storage attribute with
      | Float values -> encode values | Int values -> encode values
      | Text values -> encode values
      | Int_array values -> encode (Packed.Int_array.Private.view values)
      | Float_array values -> encode (Packed.Float_array.Private.view values)
      | Float2 values -> let v = Packed.Float2.Private.view values in encode (v.x, v.y)
      | Float3 values -> let v = Packed.Float3.Private.view values in encode (v.x, v.y, v.z)
      | Float4 values -> let v = Packed.Float4.Private.view values in encode (v.x, v.y, v.z, v.w) in
    Attribute.owner attribute, Attribute.name attribute, Attribute.kind_name attribute, payload in
  let groups = List.map (fun group -> Group.owner group, Group.name group,
    Array.init (Group.length group) (fun index -> Group.mem index group),
    Group.ordered_elements group) (Geometry.groups geometry) in
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  encode (positions.x, positions.y, positions.z,
    Topology.Private.view (Geometry.topology geometry),
    List.map attribute (Geometry.attributes geometry), groups)

let cook ~domains (graph : Lower.graph) =
  match graph.root with
  | None -> None
  | Some root ->
      let compiled = match Procedural.Edit_graph.compile_node
          graph.network.geometry ~node_id:root with
        | Ok compiled -> compiled | Error message -> fail message in
      let context = match Procedural.Context.create ~domains ~grain:97 ~seed:42L () with
        | Ok context -> context | Error message -> fail message in
      let session = Procedural.Session.create ~max_entries:512
          ~max_payload_bytes:(256 * 1024 * 1024) |> Result.get_ok in
      Fun.protect ~finally:(fun () -> Procedural.Session.close session) (fun () ->
        match Procedural.Session.cook session ~context compiled with
        | Ok output -> Some output.geometry
        | Error error -> fail (Procedural.Diagnostic.error_to_string error))

let fixtures = ["bloom"; "facade"; "garland"; "kit"; "orrery"; "rosette";
  "sunflower"; "tiles"; "tree"; "tunnel"; "variations"; "wave"]

let nodes (graph : Lower.graph) =
  List.length (Procedural.Edit_graph.inspect graph.network.geometry)

let operations (graph : Lower.graph) operation =
  List.length (List.filter (fun (n : Procedural.Edit_graph.node_info) ->
    n.operation = operation) (Procedural.Edit_graph.inspect graph.network.geometry))

let run () =
  let cooked = ref 0 in
  List.iter (fun name ->
    let lowered = lower name in
    List.iter (fun (graph : Lower.graph) ->
      match (try cook ~domains:1 graph, cook ~domains:3 graph
             with Failure m -> fail (name ^ "/" ^ graph.name ^ ": " ^ m)) with
      | None, None -> ()
      | Some a, Some b ->
          incr cooked;
          check (geometry_bytes a = geometry_bytes b)
            (Printf.sprintf "%s/%s differs at 1 and 3 domains" name graph.name);
          (* lowering twice gives the same geometry (fresh ids do not leak) *)
          let again = List.find (fun (g : Lower.graph) ->
            g.instance = graph.instance) (lower name).graphs in
          (match cook ~domains:1 again with
           | Some c -> check (geometry_bytes a = geometry_bytes c)
               (name ^ "/" ^ graph.name ^ " is not deterministic")
           | None -> fail "second lowering lost its root")
      | _ -> fail "root differs") lowered.graphs) fixtures;
  check (!cooked >= 10) (Printf.sprintf "only %d graphs cooked" !cooked);
  (* Bloom: flower is 12 petals of (uv_sphere, transform, set_color,
     transform), a merge, the heart (uv_sphere, set_color) and the result
     merge; the ref override with 7 petals is its own network. *)
  let bloom = lower "bloom" in
  (match bloom.graphs with
   | [flower; small] ->
       check (nodes flower = 12 * 4 + 1 + 2 + 1) "bloom flower node count";
       check (operations flower "merge" = 2) "bloom flower merges";
       check (nodes small = 7 * 4 + 1 + 2 + 1) "bloom ref override node count";
       check (small.instance <> flower.instance) "distinct instances";
       (* provenance: the ring merge's input k is petal k's last transform *)
       let ring = List.find_map (fun (n : Procedural.Edit_graph.node_info) ->
         let inputs = n.inputs in
         if n.operation = "merge" && Array.length inputs = 12 then Some n.id
         else None) (Procedural.Edit_graph.inspect flower.network.geometry)
         |> Option.get in
       for k = 0 to 11 do
         let origin = snd (List.find (fun (_, (o : Lower.origin)) -> o.merge = ring && o.input = k)
           (Network.Int_map.bindings bloom.provenance)) in
         check (origin.iter = [k]) "bloom provenance iteration";
         check (Some origin.source = (Option.get (Procedural.Edit_graph.inputs
           flower.network.geometry ~node_id:ring)).(k)) "bloom provenance source"
       done;
       check (Network.Int_map.cardinal bloom.provenance
         = 12 + 2 + 7 + 2) "bloom provenance size"
   | graphs -> fail (Printf.sprintf "bloom has %d sop networks" (List.length graphs)));
  (* every collecting merge tags its primitives with the input index *)
  let sunflower = lower "sunflower" in
  let graph = List.hd sunflower.graphs in
  check (nodes graph = 241) "sunflower node count";
  let geometry = Option.get (cook ~domains:1 graph) in
  (match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      Lower.source_attribute geometry with
   | Some attribute ->
       (match Pdk.Attribute.Private.storage attribute with
        | Pdk.Attribute.Int values ->
            check (Array.length values = Pdk.Geometry.primitive_count geometry
              && values.(0) = 0 && values.(Array.length values - 1) = 239)
              "sunflower source attribute"
        | _ -> fail "source attribute is not int")
   | None -> fail "sunflower merge wrote no source attribute");
  (* Wave: the curve is a native node; t-dependent points are pending and
     the static cook uses t = 0 *)
  let wave = lower "wave" in
  check (List.length wave.pending >= 6
    && List.for_all (fun (p : Lower.pending) -> p.field = "points") wave.pending)
    "wave pending live parameters";
  check (Option.is_some (cook ~domains:1 (List.hd wave.graphs))) "wave cooks";
  (* ids are stable when the previous ids and sites are passed back *)
  let again = match Flow.Syntax.parse (read (Filename.concat cases "bloom.lisp")) with
    | Ok forms -> Lower.workspace ~factories ~compiled_ids:bloom.compiled_ids
        ~sites:bloom.sites forms |> Result.get_ok
    | Error _ -> fail "parse" in
  check (again.compiled_ids = bloom.compiled_ids
    && Flow_sop.Network.Int_map.equal ( = ) again.compiled bloom.compiled)
    "compiled ids are stable";
  (* the checker runs first *)
  (match Lower.workspace ~factories
     (Flow.Syntax.parse "(workspace w (graph g :context sop (sop/nope)))" |> Result.get_ok) with
   | Error _ -> ()
   | Ok _ -> fail "lowering accepted an unchecked workspace");
  print_endline "workspace cook tests passed"
