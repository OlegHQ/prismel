module E = Flow.Eval
module G = Rdk.Geometry
module A = Rdk.Attribute
module P = Rdk.Packed.Float3
module N = Procedural.Node

let sources value =
  let seen = Hashtbl.create 16 and ids = ref [] in
  let rec visit = function
    | E.Deferred (ty, id) when Flow.Ty.is_geometry ty -> ids := id :: !ids
    | Residual r ->
        let id = E.Private.residual_id r in
        if not (Hashtbl.mem seen id) then begin
          Hashtbl.add seen id ();
          (* Evaluator captures are already trimmed to lexically free bindings. *)
          List.iter (fun (_, v) -> visit v) (E.Private.residual_view r).bindings
        end
    | List vs -> Array.iter visit vs
    | Fn f -> List.iter (fun (_, v) -> visit v) (E.Private.function_bindings f)
    | Record fs | Struct (_, _, fs) -> List.iter (fun (_, v) -> visit v) fs
    | _ -> () in
  visit value; List.sort_uniq Int.compare !ids

let error code message = Error (Flow.Diagnostic.error ~code message)
let read name geometry =
  let positions = if name = "P" then Some (G.positions geometry) else
    Option.bind (G.find_attribute ~owner:A.Point name geometry)
      (A.get (A.key ~name ~owner:A.Point A.float3)) in
  match positions with
  | None -> error "E_ATTR_TYPE" ("Point attribute " ^ name ^ " is missing or is not vec3.")
  | Some positions ->
      let p = P.Private.view positions in
      let count = G.point_count geometry in
      let values = Array.make (count * 3) 0. in
      for i = 0 to count - 1 do
        values.(i * 3) <- p.x.(i);
        values.(i * 3 + 1) <- p.y.(i);
        values.(i * 3 + 2) <- p.z.(i)
      done;
      Ok (E.Vec3_array values)

let resolve ~geometry = function
  | E.Struct ("sop/attr", _, args) ->
      (match List.assoc_opt "geometry" args, List.assoc_opt "attribute" args with
       | Some (E.Deferred (ty, id)), Some (E.Text name) when Flow.Ty.is_geometry ty ->
           (match geometry id with Some geometry -> read name geometry
            | None -> error "E_DATA_SOURCE" "Attribute source has not been cooked.")
       | _ -> error "E_ATTR_TYPE" "sop/attr needs geometry and an attribute name.")
  | _ -> error "E_DATA_SOURCE" "Unknown packed data source."

let write ~grain name values geometry = match values with
  | E.Vec3_array values ->
      let count = G.point_count geometry in
      if Array.length values <> count * 3 then
        error "E_ATTR_COUNT" (Printf.sprintf "%s needs %d point values; got %d."
          name count (Array.length values / 3))
      else if (let finite = ref true in
        for i = 0 to Array.length values - 1 do
          if not (Float.is_finite values.(i)) then finite := false
        done; not !finite) then
        error "E_NONFINITE" "Point attributes must be finite."
      else if name = "P" then Ok (Rdk.Kernel.edit_point_ranges ~grain
        (fun ~first ~last ~x ~y ~z -> for i = first to last - 1 do
          x.(i) <- values.(i * 3); y.(i) <- values.(i * 3 + 1); z.(i) <- values.(i * 3 + 2)
        done) geometry)
      else
        let storage = P.Private.of_owned_exn
          ~x:(Array.init count (fun i -> values.(i * 3)))
          ~y:(Array.init count (fun i -> values.(i * 3 + 1)))
          ~z:(Array.init count (fun i -> values.(i * 3 + 2))) in
        Result.map_error (Flow.Diagnostic.error ~code:"E_ATTR_TYPE")
          (Result.bind (A.create_owned ~name ~owner:A.Point (A.Float3 storage))
            (fun attr -> G.with_attribute attr geometry))
  | _ -> error "E_ATTR_TYPE" "sop/with_attr takes a packed vec3 array."

let prepare ?profile ~sources inputs values =
  if List.compare_lengths sources inputs <> 0 then
    error "E_DATA_SOURCE" "Attribute source ids and inputs must correspond."
  else
  let origins = Hashtbl.create 16 in
  let rec point_origin node =
    match Hashtbl.find_opt origins (N.id node) with
    | Some origin -> origin
    | None ->
        let facts = N.facts node in
        let input = match facts.cook_mode with
          | N.Duplicate_input i | In_place i | Instance_input i | Passthrough i -> Some i
          | _ -> None in
        let origin = match facts.topology, facts.elementwise, input with
          | N.Preserved, (N.Points | Primitives), Some i ->
              let inputs = N.Private.input_array node in
              if i >= 0 && i < Array.length inputs then point_origin inputs.(i) else N.id node
          | _ -> N.id node in
        Hashtbl.add origins (N.id node) origin; origin in
  let by_source = List.combine sources inputs |> List.map (fun (id, node) -> id, point_origin node) in
  let rec captured bindings (term : Flow.Workspace.term) = match term.node with
    | Ref_binding (name, fields) ->
        List.fold_left (fun value field -> Option.bind value (function
          | E.Record fields | Struct (_, _, fields) -> List.assoc_opt field fields | _ -> None))
          (List.assoc_opt name bindings) fields
    | Get (term, field) -> Option.bind (captured bindings term) (function
        | E.Record fields | Struct (_, _, fields) -> List.assoc_opt field fields | _ -> None)
    | Bypass body | Expanded {body; _} -> captured bindings body
    | _ -> None in
  let attribute_source = function
    | E.Struct ("sop/attr", _, args) -> List.assoc_opt "geometry" args | _ -> None in
  let count_source residual (term : Flow.Workspace.term) =
    let bindings = (E.Private.residual_view residual).bindings in
    let geometry = match term.node with
      | Op {op = "sop/attr"; args; _} -> Option.bind (List.assoc_opt "geometry" args) (captured bindings)
      | _ -> Option.bind (captured bindings term) attribute_source in
    Option.bind geometry (function
      | E.Deferred (ty, id) when Flow.Ty.is_geometry ty ->
          Option.map (fun origin -> ["@sop-points"; string_of_int origin], []) (List.assoc_opt id by_source)
      | _ -> None) in
  Flow_ir.Executor.compile ?profile ~count_source values

let node ?state ?(reference = false) ?elems ?profile ~source ~name ~values ~sources inputs =
  let program = prepare ?profile ~sources inputs values in
  let parameters = source ^ ";" ^ name ^ ";" ^ Flow.Value.key_of ~residual:E.Private.residual_id values
    ^ Option.fold ~none:"" ~some:(fun bindings -> Flow.Value.key_of
        ~residual:E.Private.residual_id (E.Record bindings)) elems
    ^ Option.fold ~none:"" ~some:E.state_stamp state in
  let node = N.Private.make ~label:("Write " ^ name) ~operation:"flow.with_attr" ~version:1
    ~parameters ~cook_mode:(N.Duplicate_input 0)
    ~dependencies:(if E.frame_dependent values then
        Procedural.Context.Dependencies.one Procedural.Context.Dependencies.Input
      else Procedural.Context.Dependencies.static)
    ~inputs:(Array.of_list inputs)
    (fun ~node_id:_ context geometries ->
      let resolve = resolve ~geometry:(fun id -> Option.map (fun index -> geometries.(index))
        (List.find_index ((=) id) sources)) in
      let result = if geometries = [||] then error "E_DATA_SOURCE" "Attribute write needs geometry."
        else if Procedural.Context.cancelled context then error "E_CANCELLED" "Attribute kernel cancelled."
        else Result.bind program (fun program ->
          Result.bind (Flow_ir.Executor.force ?state ?elems ~reference ~resolve program
            ~live:(Procedural.Context.input context))
            (fun values -> if Procedural.Context.cancelled context then
                error "E_CANCELLED" "Attribute kernel cancelled."
              else write ~grain:(Procedural.Context.grain context) name values geometries.(0))) in
      Result.map_error (fun (d : Flow.Diagnostic.t) -> Procedural.Diagnostic.error ~code:d.code d.message)
        (Result.map (fun geometry -> N.Private.{geometry; diagnostics = []; instances = None}) result)) in
  N.Private.with_facts { (N.facts node) with elementwise = N.Points;
    topology = N.Preserved; reads = ["*"]; writes = [name] } node
