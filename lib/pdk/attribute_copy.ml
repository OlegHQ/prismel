open Prismel

type match_mode =
  | Cyclic
  | By_values of { source_attribute : string; target_attribute : string }
  | To_element of { target_attribute : string }

type rule = {
  copy_owner : Attribute.owner;
  copy_pattern : string;
  copy_into : string option;
}

type payload = Position | Ordinary of Attribute.t
type selected = {
  source_owner : Attribute.owner;
  source_name : string;
  target_name : string;
  payload : payload;
}
type mapping_kind = No_match | Identity | General

type selector = Select of Attribute_pattern.t | Rewrite of Attribute_pattern.rewrite

module Int_table = Hashtbl.Make (struct
  type t = int
  let equal = Int.equal
  let hash value = value land max_int
end)

module String_table = Hashtbl.Make (struct
  type t = string
  let equal = String.equal
  let hash = Hashtbl.hash
end)

let owner_count geometry = function
  | Attribute.Point -> Geometry.point_count geometry
  | Attribute.Vertex -> Geometry.vertex_count geometry
  | Attribute.Primitive -> Geometry.primitive_count geometry
  | Attribute.Detail -> 1

let group_count geometry = function
  | Group.Point -> Geometry.point_count geometry
  | Group.Vertex -> Geometry.vertex_count geometry
  | Group.Primitive -> Geometry.primitive_count geometry

let group_name = function
  | Group.Point -> "point"
  | Group.Vertex -> "vertex"
  | Group.Primitive -> "primitive"

let owner_index = function
  | Attribute.Point -> 0
  | Attribute.Vertex -> 1
  | Attribute.Primitive -> 2
  | Attribute.Detail -> 3

let selected_elements count = function
  | None -> Array.init count Fun.id
  | Some group ->
      let elements = Array.make (Group.cardinality group) 0 and next = ref 0 in
      Group.iter_ordered (fun element ->
        elements.(!next) <- element;
        incr next) group;
      elements

let validate_group ~label owner count = function
  | None -> Ok ()
  | Some group when Group.owner group = owner && Group.length group = count -> Ok ()
  | Some _ -> Error (Printf.sprintf
      "Attribute Copy: %s group must be a matching %s group"
      label (group_name owner))

let find_match_attribute ~label ~owner ~name geometry =
  if String.trim name = "" then Error ("Attribute Copy: empty " ^ label)
  else match Geometry.find_attribute ~owner name geometry with
    | None -> Error (Printf.sprintf "Attribute Copy: missing %s %s attribute %S"
        label (match owner with
          | Attribute.Point -> "point" | Attribute.Vertex -> "vertex"
          | Attribute.Primitive -> "primitive" | Attribute.Detail -> "detail") name)
    | Some attribute -> Ok attribute

let cyclic_mapping ?cancel ~grain ~source_elements ~target_elements target_count =
  let mapping = Array.make target_count (-1) in
  let source_count = Array.length source_elements in
  if source_count > 0 && Array.length target_elements > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(Array.length target_elements - 1) (fun rank ->
        if rank land 4095 = 0 then Cancel.check_opt cancel;
        mapping.(target_elements.(rank)) <- source_elements.(rank mod source_count));
  mapping

(* Match-plan construction is kept separate from topology projection so every
   copied attribute owner can reuse the same base correspondence. *)
let base_mapping ?cancel ~grain ~owner ~match_ ~source_group ~target_group
    ~source ~target () =
  let source_count = group_count source owner
  and target_count = group_count target owner in
  Result.bind (validate_group ~label:"source" owner source_count source_group)
    (fun () ->
  Result.bind (validate_group ~label:"destination" owner target_count target_group)
    (fun () ->
  let source_elements = selected_elements source_count source_group
  and target_elements = selected_elements target_count target_group in
  match match_ with
  | Cyclic -> Ok (cyclic_mapping ?cancel ~grain ~source_elements
      ~target_elements target_count, target_elements)
  | To_element { target_attribute } ->
      let attribute_owner = match owner with
        | Group.Point -> Attribute.Point | Group.Vertex -> Attribute.Vertex
        | Group.Primitive -> Attribute.Primitive in
      Result.bind (find_match_attribute ~label:"destination element"
          ~owner:attribute_owner ~name:target_attribute target) (fun attribute ->
        match Attribute.Private.storage attribute with
        | Attribute.Int values ->
            let mapping = Array.make target_count (-1) in
            if Array.length target_elements > 0 then
              Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(Array.length target_elements - 1) (fun rank ->
                  if rank land 4095 = 0 then Cancel.check_opt cancel;
                  let destination = target_elements.(rank)
                  and source_element = values.(target_elements.(rank)) in
                  if source_element >= 0 && source_element < source_count
                      && (match source_group with None -> true
                          | Some group -> Group.mem source_element group) then
                    mapping.(destination) <- source_element);
            Ok (mapping, target_elements)
        | _ -> Error
            "Attribute Copy: destination element attribute must use integer storage")
  | By_values { source_attribute; target_attribute } ->
      if owner = Group.Vertex then Error
          "Attribute Copy: value matching supports point or primitive groups only"
      else
        let attribute_owner = match owner with
          | Group.Point -> Attribute.Point
          | Group.Primitive -> Attribute.Primitive
          | Group.Vertex -> assert false in
        Result.bind (find_match_attribute ~label:"source match"
            ~owner:attribute_owner ~name:source_attribute source) (fun source_match ->
        Result.bind (find_match_attribute ~label:"destination match"
            ~owner:attribute_owner ~name:target_attribute target) (fun target_match ->
          let mapping = Array.make target_count (-1) in
          match Attribute.Private.storage source_match,
              Attribute.Private.storage target_match with
          | Attribute.Int source_values, Attribute.Int target_values ->
              let table = Int_table.create (max 16 (Array.length source_elements)) in
              Array.iteri (fun rank element ->
                if rank land 4095 = 0 then Cancel.check_opt cancel;
                let value = source_values.(element) in
                match Int_table.find_opt table value with
                | None -> Int_table.add table value element
                | Some previous when element > previous ->
                    Int_table.replace table value element
                | Some _ -> ()) source_elements;
              if Array.length target_elements > 0 then
                Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(Array.length target_elements - 1) (fun rank ->
                    if rank land 4095 = 0 then Cancel.check_opt cancel;
                    let element = target_elements.(rank) in
                    match Int_table.find_opt table target_values.(element) with
                    | None -> ()
                    | Some source_element -> mapping.(element) <- source_element);
              Ok (mapping, target_elements)
          | Attribute.Text source_values, Attribute.Text target_values ->
              let table = String_table.create
                  (max 16 (Array.length source_elements)) in
              Array.iteri (fun rank element ->
                if rank land 4095 = 0 then Cancel.check_opt cancel;
                let value = source_values.(element) in
                match String_table.find_opt table value with
                | None -> String_table.add table value element
                | Some previous when element > previous ->
                    String_table.replace table value element
                | Some _ -> ()) source_elements;
              if Array.length target_elements > 0 then
                Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(Array.length target_elements - 1) (fun rank ->
                    if rank land 4095 = 0 then Cancel.check_opt cancel;
                    let element = target_elements.(rank) in
                    match String_table.find_opt table target_values.(element) with
                    | None -> ()
                    | Some source_element -> mapping.(element) <- source_element);
              Ok (mapping, target_elements)
          | _ -> Error
              "Attribute Copy: value-match attributes must have the same integer or text storage"))
  ))

let compile_rule rule =
  match rule.copy_into with
  | None -> Result.map (fun pattern -> rule, Select pattern)
      (Attribute_pattern.compile rule.copy_pattern)
  | Some into when String.trim into = "" ->
      Error "Attribute Copy: destination rewrite must not be empty"
  | Some into -> Result.map (fun rewrite -> rule, Rewrite rewrite)
      (Attribute_pattern.compile_rewrite ~pattern:rule.copy_pattern ~replacement:into)

let select_attributes ~allow_position ~rules source =
  let compiled = List.fold_left (fun result rule ->
    Result.bind result (fun output ->
      Result.map (fun compiled -> compiled :: output) (compile_rule rule)))
      (Ok []) rules |> Result.map List.rev in
  Result.bind compiled (fun compiled ->
    let source_attributes = Geometry.Private.attributes source
    and seen = Hashtbl.create (Array.length (Geometry.Private.attributes source) + 1)
    and output = ref [] and failure = ref None in
    let add rule selector source_name payload =
      if !failure = None then
        let target_name = match selector with
          | Select pattern ->
              if Attribute_pattern.matches pattern source_name then Some source_name
              else None
          | Rewrite rewrite -> Attribute_pattern.rewrite rewrite source_name in
        match target_name with
        | None -> ()
        | Some target_name when String.trim target_name = "" ->
            failure := Some "Attribute Copy: rewrite produced an empty name"
        | Some "P" when rule.copy_owner <> Attribute.Point ->
            failure := Some "Attribute Copy: canonical P must be point owned"
        | Some "P" when not allow_position ->
            failure := Some "Attribute Copy: writing canonical P requires allow_position"
        | Some target_name ->
            let key = rule.copy_owner, target_name in
            if Hashtbl.mem seen key then failure := Some (Printf.sprintf
                "Attribute Copy: duplicate destination attribute %S" target_name)
            else begin
              Hashtbl.add seen key ();
              output := { source_owner = rule.copy_owner; source_name; target_name;
                payload } :: !output
            end in
    List.iter (fun (rule, selector) ->
      if rule.copy_owner = Attribute.Point && allow_position then
        add rule selector "P" Position;
      Array.iter (fun attribute ->
        if Attribute.owner attribute = rule.copy_owner then
          add rule selector (Attribute.name attribute) (Ordinary attribute))
        source_attributes) compiled;
    match !failure with
    | Some message -> Error message
    | None -> Ok (Array.of_list (List.rev !output)))

let related_count topology index base_owner attribute_owner element =
  if attribute_owner = Attribute.Detail then 1
  else match base_owner, attribute_owner with
    | Group.Point, Attribute.Point
    | Group.Vertex, Attribute.Vertex
    | Group.Primitive, Attribute.Primitive -> 1
    | Group.Point, (Attribute.Vertex | Attribute.Primitive) ->
        let view : Topology_index.Private.view = Option.get index in
        view.point_offsets.(element + 1) - view.point_offsets.(element)
    | Group.Vertex, (Attribute.Point | Attribute.Primitive) -> 1
    | Group.Primitive, (Attribute.Point | Attribute.Vertex) ->
        topology.Topology.Private.primitive_offsets.(element + 1)
        - topology.primitive_offsets.(element)
    | _, Attribute.Detail -> assert false

let related_element topology index base_owner attribute_owner element local =
  if attribute_owner = Attribute.Detail then 0
  else match base_owner, attribute_owner with
    | Group.Point, Attribute.Point
    | Group.Vertex, Attribute.Vertex
    | Group.Primitive, Attribute.Primitive -> element
    | Group.Point, Attribute.Vertex ->
        let view : Topology_index.Private.view = Option.get index in
        view.point_vertices.(view.point_offsets.(element) + local)
    | Group.Point, Attribute.Primitive ->
        let view : Topology_index.Private.view = Option.get index in
        let vertex = view.point_vertices.(view.point_offsets.(element) + local) in
        view.primitive_of_vertex.(vertex)
    | Group.Vertex, Attribute.Point -> topology.Topology.Private.vertex_points.(element)
    | Group.Vertex, Attribute.Primitive ->
        let view : Topology_index.Private.view = Option.get index in
        view.primitive_of_vertex.(element)
    | Group.Primitive, Attribute.Vertex ->
        topology.Topology.Private.primitive_offsets.(element) + local
    | Group.Primitive, Attribute.Point ->
        topology.Topology.Private.vertex_points.(
          topology.primitive_offsets.(element) + local)
    | _, Attribute.Detail -> assert false

let projection_is_disjoint base_owner attribute_owner =
  attribute_owner = Attribute.Detail
  || match base_owner, attribute_owner with
    | Group.Point, (Attribute.Point | Attribute.Vertex)
    | Group.Vertex, Attribute.Vertex
    | Group.Primitive, (Attribute.Primitive | Attribute.Vertex) -> true
    | _ -> false

let project_mapping ?cancel ~grain ~base_owner ~attribute_owner ~base_mapping
    ~target_elements ~source ~target () =
  if (match base_owner, attribute_owner with
      | Group.Point, Attribute.Point | Group.Vertex, Attribute.Vertex
      | Group.Primitive, Attribute.Primitive -> true | _ -> false) then
    base_mapping
  else if attribute_owner = Attribute.Detail then
    [|if Array.exists (fun source -> source >= 0) base_mapping then 0 else -1|]
  else
    let source_topology = Topology.Private.view (Geometry.topology source)
    and target_topology = Topology.Private.view (Geometry.topology target) in
    let needs_index = base_owner = Group.Point
        || (base_owner = Group.Vertex && attribute_owner = Attribute.Primitive) in
    let source_index = if needs_index then Some (Topology_index.create ?cancel
        (Geometry.topology source) |> Topology_index.Private.view) else None
    and target_index = if needs_index then Some (Topology_index.create ?cancel
        (Geometry.topology target) |> Topology_index.Private.view) else None in
    let mapping = Array.make (owner_count target attribute_owner) (-1) in
    let copy_pair rank =
      if rank land 4095 = 0 then Cancel.check_opt cancel;
      let target_base = target_elements.(rank)
      and source_base = base_mapping.(target_elements.(rank)) in
      if source_base >= 0 then begin
        let source_related = related_count source_topology source_index base_owner
            attribute_owner source_base
        and target_related = related_count target_topology target_index base_owner
            attribute_owner target_base in
        if source_related > 0 then
          for local = 0 to target_related - 1 do
            let destination = related_element target_topology target_index base_owner
                attribute_owner target_base local
            and source_element = related_element source_topology source_index base_owner
                attribute_owner source_base (local mod source_related) in
            mapping.(destination) <- source_element
          done
      end in
    if Array.length target_elements > 0
        && projection_is_disjoint base_owner attribute_owner then
      Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(Array.length target_elements - 1) copy_pair
    else Array.iteri (fun rank _ -> copy_pair rank) target_elements;
    mapping

let same_storage_kind source target =
  String.equal (Attribute.kind_name source) (Attribute.kind_name target)

let initial_storage source existing count =
  match Attribute.Private.storage source,
      Option.map Attribute.Private.storage existing with
  | Attribute.Float _, Some (Attribute.Float values) ->
      Attribute.Float (Array.copy values)
  | Attribute.Float _, _ -> Attribute.Float (Array.make count 0.)
  | Attribute.Int _, Some (Attribute.Int values) -> Attribute.Int (Array.copy values)
  | Attribute.Int _, _ -> Attribute.Int (Array.make count 0)
  | Attribute.Int_array _, Some (Attribute.Int_array values) ->
      Attribute.Int_array values
  | Attribute.Int_array _, _ -> Attribute.Int_array
      (Packed.Int_array.Private.create_validated_owned
        ~offsets:(Array.make (count + 1) 0) ~values:[||])
  | Attribute.Float_array _, Some (Attribute.Float_array values) ->
      Attribute.Float_array values
  | Attribute.Float_array _, _ -> Attribute.Float_array
      (Packed.Float_array.Private.create_validated_owned
        ~offsets:(Array.make (count + 1) 0) ~values:[||])
  | Attribute.Text _, Some (Attribute.Text values) -> Attribute.Text (Array.copy values)
  | Attribute.Text _, _ -> Attribute.Text (Array.make count "")
  | Attribute.Float2 _, Some (Attribute.Float2 values) ->
      let values = Packed.Float2.Private.view values in
      Attribute.Float2 (Packed.Float2.of_owned ~x:(Array.copy values.x)
        ~y:(Array.copy values.y) |> Result.get_ok)
  | Attribute.Float2 _, _ -> Attribute.Float2 (Packed.Float2.of_owned
      ~x:(Array.make count 0.) ~y:(Array.make count 0.) |> Result.get_ok)
  | Attribute.Float3 _, Some (Attribute.Float3 values) ->
      let values = Packed.Float3.Private.view values in
      Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.copy values.x) ~y:(Array.copy values.y) ~z:(Array.copy values.z))
  | Attribute.Float3 _, _ -> Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:(Array.make count 0.)
        ~y:(Array.make count 0.) ~z:(Array.make count 0.))
  | Attribute.Float4 _, Some (Attribute.Float4 values) ->
      let values = Packed.Float4.Private.view values in
      Attribute.Float4 (Packed.Float4.of_owned ~x:(Array.copy values.x)
        ~y:(Array.copy values.y) ~z:(Array.copy values.z)
        ~w:(Array.copy values.w) |> Result.get_ok)
  | Attribute.Float4 _, _ -> Attribute.Float4 (Packed.Float4.of_owned
      ~x:(Array.make count 0.) ~y:(Array.make count 0.)
      ~z:(Array.make count 0.) ~w:(Array.make count 0.) |> Result.get_ok)

let copy_storage ?cancel ~grain ~mapping source output =
  let transfer source output =
    if Array.length mapping > 0 then Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(Array.length mapping - 1) (fun destination ->
          if destination land 4095 = 0 then Cancel.check_opt cancel;
          let source_element = mapping.(destination) in
          if source_element >= 0 then output.(destination) <- source.(source_element)) in
  match Attribute.Private.storage source, output with
  | Attribute.Float source, Attribute.Float output ->
      transfer source output; Attribute.Float output
  | Attribute.Int source, Attribute.Int output ->
      transfer source output; Attribute.Int output
  | Attribute.Int_array source, Attribute.Int_array existing ->
      Attribute.Int_array (Ragged_ops.overlay_int ?cancel ~grain mapping
        ~source ~existing)
  | Attribute.Float_array source, Attribute.Float_array existing ->
      Attribute.Float_array (Ragged_ops.overlay_float ?cancel ~grain mapping
        ~source ~existing)
  | Attribute.Text source, Attribute.Text output ->
      transfer source output; Attribute.Text output
  | Attribute.Float2 source, Attribute.Float2 output ->
      let source = Packed.Float2.Private.view source
      and output = Packed.Float2.Private.view output in
      transfer source.x output.x; transfer source.y output.y;
      Attribute.Float2 (Packed.Float2.of_owned ~x:output.x ~y:output.y |> Result.get_ok)
  | Attribute.Float3 source, Attribute.Float3 output ->
      let source = Packed.Float3.Private.view source
      and output = Packed.Float3.Private.view output in
      transfer source.x output.x; transfer source.y output.y; transfer source.z output.z;
      Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:output.x ~y:output.y ~z:output.z)
  | Attribute.Float4 source, Attribute.Float4 output ->
      let source = Packed.Float4.Private.view source
      and output = Packed.Float4.Private.view output in
      transfer source.x output.x; transfer source.y output.y;
      transfer source.z output.z; transfer source.w output.w;
      Attribute.Float4 (Packed.Float4.of_owned ~x:output.x ~y:output.y
        ~z:output.z ~w:output.w |> Result.get_ok)
  | _ -> assert false

let classify_mapping ?cancel ~source_count mapping =
  let any = ref false and identity = ref (Array.length mapping = source_count) in
  for destination = 0 to Array.length mapping - 1 do
    if destination land 16_383 = 0 then Cancel.check_opt cancel;
    let source = mapping.(destination) in
    if source >= 0 then any := true;
    if source <> destination then identity := false
  done;
  if not !any then No_match else if !identity then Identity else General

let attribute_owner_of_group = function
  | Group.Point -> Attribute.Point
  | Group.Vertex -> Attribute.Vertex
  | Group.Primitive -> Attribute.Primitive

let install_identity_selection ~source selected target =
  let generated = Array.make (Array.length selected) None
  and position = ref None and failure = ref None in
  Array.iteri (fun index selected -> if !failure = None then begin
    let source_attribute = match selected.payload with
      | Ordinary attribute -> attribute
      | Position -> Attribute.create_owned ~name:"P" ~owner:Attribute.Point
          (Attribute.Float3 (Geometry.positions source)) |> Result.get_ok in
    if String.equal selected.target_name "P" then
      match Attribute.Private.storage source_attribute with
      | Attribute.Float3 positions -> position := Some positions
      | _ -> failure := Some "Attribute Copy: canonical P requires float3 storage"
    else
      match Attribute.with_name selected.target_name source_attribute with
      | Error message -> failure := Some message
      | Ok attribute -> generated.(index) <- Some attribute
  end) selected;
  match !failure with
  | Some message -> Error message
  | None ->
      let attributes = Array.fold_right (fun attribute output ->
        match attribute with None -> output | Some attribute -> attribute :: output)
          generated [] |> Array.of_list in
      Result.bind (Geometry.Private.with_merged_attributes_owned attributes target)
        (fun geometry -> match !position with
          | None -> Ok geometry
          | Some positions -> Geometry.with_positions positions geometry)

let copy ?cancel ?(grain = 16_384) ?source_group ?target_group
    ?(match_ = Cyclic) ?(allow_position = false) ~group_owner ~rules
    ~source ~target () =
  if grain <= 0 then invalid_arg "Attribute Copy: grain must be positive";
  Cancel.check_opt cancel;
  Result.bind (select_attributes ~allow_position ~rules source) (fun selected ->
  if Array.length selected = 0 then Ok target
  else if match_ = Cyclic && source_group = None && target_group = None
      && group_count source group_owner = group_count target group_owner
      && group_count source group_owner > 0
      && Array.for_all (fun selected ->
        selected.source_owner = attribute_owner_of_group group_owner
        || selected.source_owner = Attribute.Detail) selected then
    install_identity_selection ~source selected target
  else Result.bind (base_mapping ?cancel ~grain ~owner:group_owner ~match_
      ~source_group ~target_group ~source ~target ())
    (fun (base_mapping, target_elements) ->
      let mappings = Array.make 4 None in
      let mapping owner =
        let slot = owner_index owner in
        match mappings.(slot) with
        | Some mapping -> mapping
        | None ->
            let mapping = project_mapping ?cancel ~grain ~base_owner:group_owner
                ~attribute_owner:owner ~base_mapping ~target_elements
                ~source ~target () in
            let kind = classify_mapping ?cancel
                ~source_count:(owner_count source owner) mapping in
            let plan = mapping, kind in
            mappings.(slot) <- Some plan;
            plan in
      let generated = Array.make (Array.length selected) None
      and position = ref None and failure = ref None in
      Array.iteri (fun index selected -> if !failure = None then begin
        let mapping, mapping_kind = mapping selected.source_owner in
        let source_attribute = match selected.payload with
          | Ordinary attribute -> attribute
          | Position -> Attribute.create_owned ~name:"P" ~owner:Attribute.Point
              (Attribute.Float3 (Geometry.positions source)) |> Result.get_ok in
        let count = owner_count target selected.source_owner in
        if mapping_kind = No_match then ()
        else if mapping_kind = Identity then begin
          if String.equal selected.target_name "P" then
            match Attribute.Private.storage source_attribute with
            | Attribute.Float3 positions -> position := Some positions
            | _ -> failure := Some "Attribute Copy: canonical P requires float3 storage"
          else
            match Attribute.with_name selected.target_name source_attribute with
            | Error message -> failure := Some message
            | Ok attribute -> generated.(index) <- Some attribute
        end else begin
        let existing = if String.equal selected.target_name "P" then
            if selected.source_owner = Attribute.Point then
              Some (Attribute.create_owned ~name:"P" ~owner:Attribute.Point
                (Attribute.Float3 (Geometry.positions target)) |> Result.get_ok)
            else None
          else Geometry.find_attribute ~owner:selected.source_owner
              selected.target_name target in
        let output = initial_storage source_attribute
            (match existing with Some target when same_storage_kind source_attribute target ->
               Some target | None | Some _ -> None) count
          |> copy_storage ?cancel ~grain ~mapping source_attribute in
        if String.equal selected.target_name "P" then
          match output with
          | Attribute.Float3 positions -> position := Some positions
          | _ -> failure := Some "Attribute Copy: canonical P requires float3 storage"
        else
          match Attribute.create_owned ~name:selected.target_name
              ~owner:selected.source_owner output with
          | Error message -> failure := Some message
          | Ok attribute -> generated.(index) <- Some attribute
        end
      end) selected;
      match !failure with
      | Some message -> Error message
      | None ->
          let attributes = Array.fold_right (fun attribute output ->
            match attribute with None -> output | Some attribute -> attribute :: output)
              generated [] |> Array.of_list in
          Result.bind (Geometry.Private.with_merged_attributes_owned attributes target)
            (fun geometry -> match !position with
              | None -> Ok geometry
              | Some positions -> Geometry.with_positions positions geometry)))
