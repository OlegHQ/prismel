open Prismel

exception Cardinality_error of string

type seam_storage =
  | Seam_float of float array
  | Seam_int of int array
  | Seam_text of string array
  | Seam_float2 of Packed.Float2.Private.view
  | Seam_float3 of Packed.Float3.Private.view
  | Seam_float4 of Packed.Float4.Private.view
  | Seam_int_array of Packed.Int_array.Private.view
  | Seam_float_array of Packed.Float_array.Private.view
  | Seam_group of bytes

type seam = {
  name : string;
  owner : Attribute.owner;
  storage : seam_storage;
}

type numeric_component =
  | Component_float of seam
  | Component_float2 of seam * int
  | Component_float3 of seam * int
  | Component_float4 of seam * int

let element primitive_of_vertex seam vertex = match seam.owner with
  | Attribute.Vertex -> vertex
  | Attribute.Primitive -> primitive_of_vertex.(vertex)
  | Attribute.Point | Attribute.Detail -> assert false

let[@inline always] float_equal tolerance left right =
  abs_float (left -. right) <= tolerance

let[@inline always] group_mem bits element =
  Char.code (Bytes.unsafe_get bits (element lsr 3))
  land (1 lsl (element land 7)) <> 0

let row_equal_int left left_row right right_row =
  let left_first = left.Packed.Int_array.Private.offsets.(left_row)
  and left_last = left.offsets.(left_row + 1)
  and right_first = right.Packed.Int_array.Private.offsets.(right_row)
  and right_last = right.offsets.(right_row + 1) in
  let count = left_last - left_first in
  if count <> right_last - right_first then false
  else begin
    let equal = ref true and index = ref 0 in
    while !equal && !index < count do
      equal := left.values.(left_first + !index)
          = right.values.(right_first + !index);
      incr index
    done;
    !equal
  end

let row_equal_float tolerance left left_row right right_row =
  let left_first = left.Packed.Float_array.Private.offsets.(left_row)
  and left_last = left.offsets.(left_row + 1)
  and right_first = right.Packed.Float_array.Private.offsets.(right_row)
  and right_last = right.offsets.(right_row + 1) in
  let count = left_last - left_first in
  if count <> right_last - right_first then false
  else begin
    let equal = ref true and index = ref 0 in
    while !equal && !index < count do
      equal := float_equal tolerance left.values.(left_first + !index)
          right.values.(right_first + !index);
      incr index
    done;
    !equal
  end

let seam_equal ~tolerance ~primitive_of_vertex seams left right =
  let equal = ref true and at = ref 0 in
  while !equal && !at < Array.length seams do
    let seam = seams.(!at) in
    let left = element primitive_of_vertex seam left
    and right = element primitive_of_vertex seam right in
    equal := (match seam.storage with
      | Seam_float values -> float_equal tolerance values.(left) values.(right)
      | Seam_int values -> values.(left) = values.(right)
      | Seam_text values -> String.equal values.(left) values.(right)
      | Seam_float2 values ->
          float_equal tolerance values.x.(left) values.x.(right)
          && float_equal tolerance values.y.(left) values.y.(right)
      | Seam_float3 values ->
          float_equal tolerance values.x.(left) values.x.(right)
          && float_equal tolerance values.y.(left) values.y.(right)
          && float_equal tolerance values.z.(left) values.z.(right)
      | Seam_float4 values ->
          float_equal tolerance values.x.(left) values.x.(right)
          && float_equal tolerance values.y.(left) values.y.(right)
          && float_equal tolerance values.z.(left) values.z.(right)
          && float_equal tolerance values.w.(left) values.w.(right)
      | Seam_int_array values -> row_equal_int values left values right
      | Seam_float_array values ->
          row_equal_float tolerance values left values right
      | Seam_group bits -> group_mem bits left = group_mem bits right);
    incr at
  done;
  !equal

let compare_int_rows values left right =
  let left_first = values.Packed.Int_array.Private.offsets.(left)
  and left_last = values.offsets.(left + 1)
  and right_first = values.offsets.(right)
  and right_last = values.offsets.(right + 1) in
  let common = min (left_last - left_first) (right_last - right_first) in
  let result = ref 0 and at = ref 0 in
  while !result = 0 && !at < common do
    result := Int.compare values.values.(left_first + !at)
        values.values.(right_first + !at);
    incr at
  done;
  if !result <> 0 then !result
  else Int.compare (left_last - left_first) (right_last - right_first)

let compare_float_rows values left right =
  let left_first = values.Packed.Float_array.Private.offsets.(left)
  and left_last = values.offsets.(left + 1)
  and right_first = values.offsets.(right)
  and right_last = values.offsets.(right + 1) in
  let common = min (left_last - left_first) (right_last - right_first) in
  let result = ref 0 and at = ref 0 in
  while !result = 0 && !at < common do
    result := Float.compare values.values.(left_first + !at)
        values.values.(right_first + !at);
    incr at
  done;
  if !result <> 0 then !result
  else Int.compare (left_last - left_first) (right_last - right_first)

let seam_compare ~primitive_of_vertex seams left right =
  let result = ref 0 and at = ref 0 in
  let compare_component left right =
    if !result = 0 then result := Float.compare left right in
  while !result = 0 && !at < Array.length seams do
    let seam = seams.(!at) in
    let left = element primitive_of_vertex seam left
    and right = element primitive_of_vertex seam right in
    (match seam.storage with
     | Seam_float values -> compare_component values.(left) values.(right)
     | Seam_int values -> result := Int.compare values.(left) values.(right)
     | Seam_text values -> result := String.compare values.(left) values.(right)
     | Seam_float2 values ->
         compare_component values.x.(left) values.x.(right);
         compare_component values.y.(left) values.y.(right)
     | Seam_float3 values ->
         compare_component values.x.(left) values.x.(right);
         compare_component values.y.(left) values.y.(right);
         compare_component values.z.(left) values.z.(right)
     | Seam_float4 values ->
         compare_component values.x.(left) values.x.(right);
         compare_component values.y.(left) values.y.(right);
         compare_component values.z.(left) values.z.(right);
         compare_component values.w.(left) values.w.(right)
     | Seam_int_array values -> result := compare_int_rows values left right
     | Seam_float_array values -> result := compare_float_rows values left right
     | Seam_group bits ->
         result := Bool.compare (group_mem bits left) (group_mem bits right));
    incr at
  done;
  if !result <> 0 then !result else Int.compare left right

let component_value primitive_of_vertex component vertex = match component with
  | Component_float seam ->
      let element = element primitive_of_vertex seam vertex in
      (match seam.storage with Seam_float values -> values.(element) | _ -> assert false)
  | Component_float2 (seam, component) ->
      let element = element primitive_of_vertex seam vertex in
      (match seam.storage with
       | Seam_float2 values ->
           if component = 0 then values.x.(element) else values.y.(element)
       | _ -> assert false)
  | Component_float3 (seam, component) ->
      let element = element primitive_of_vertex seam vertex in
      (match seam.storage with
       | Seam_float3 values ->
           if component = 0 then values.x.(element)
           else if component = 1 then values.y.(element) else values.z.(element)
       | _ -> assert false)
  | Component_float4 (seam, component) ->
      let element = element primitive_of_vertex seam vertex in
      (match seam.storage with
       | Seam_float4 values ->
           if component = 0 then values.x.(element)
           else if component = 1 then values.y.(element)
           else if component = 2 then values.z.(element) else values.w.(element)
       | _ -> assert false)

let sift_down compare values first length root =
  let root = ref root and moving = ref true in
  while !moving do
    let child = (2 * !root) + 1 in
    if child >= length then moving := false
    else begin
      let child = if child + 1 < length
          && compare values.(first + child) values.(first + child + 1) < 0
        then child + 1 else child in
      if compare values.(first + !root) values.(first + child) < 0 then begin
        let temporary = values.(first + !root) in
        values.(first + !root) <- values.(first + child);
        values.(first + child) <- temporary;
        root := child
      end else moving := false
    end
  done

let sort_range compare values first last =
  let length = last - first in
  if length > 1 then begin
    for root = (length / 2) - 1 downto 0 do
      sift_down compare values first length root
    done;
    for finish = length - 1 downto 1 do
      let temporary = values.(first) in
      values.(first) <- values.(first + finish);
      values.(first + finish) <- temporary;
      sift_down compare values first finish 0
    done
  end

let seam_of_attribute attribute =
  let storage = match Attribute.Private.storage attribute with
    | Attribute.Float values -> Seam_float values
    | Attribute.Int values -> Seam_int values
    | Attribute.Text values -> Seam_text values
    | Attribute.Float2 values -> Seam_float2 (Packed.Float2.Private.view values)
    | Attribute.Float3 values -> Seam_float3 (Packed.Float3.Private.view values)
    | Attribute.Float4 values -> Seam_float4 (Packed.Float4.Private.view values)
    | Attribute.Int_array values ->
        Seam_int_array (Packed.Int_array.Private.view values)
    | Attribute.Float_array values ->
        Seam_float_array (Packed.Float_array.Private.view values) in
  { name = Attribute.name attribute; owner = Attribute.owner attribute; storage }

let numeric_components seams =
  let result = ref [] in
  Array.iter (fun seam -> match seam.storage with
    | Seam_float _ -> result := Component_float seam :: !result
    | Seam_float2 _ ->
        result := Component_float2 (seam, 1) :: Component_float2 (seam, 0) :: !result
    | Seam_float3 _ ->
        result := Component_float3 (seam, 2) :: Component_float3 (seam, 1)
            :: Component_float3 (seam, 0) :: !result
    | Seam_float4 _ ->
        result := Component_float4 (seam, 3) :: Component_float4 (seam, 2)
            :: Component_float4 (seam, 1) :: Component_float4 (seam, 0) :: !result
    | Seam_int _ | Seam_text _ | Seam_int_array _ | Seam_float_array _
    | Seam_group _ -> ()) seams;
  Array.of_list (List.rev !result)

let validate_finite seam =
  let invalid = ref (-1) in
  let check values =
    let index = ref 0 in
    while !invalid < 0 && !index < Array.length values do
      if not (Float.is_finite values.(!index)) then invalid := !index;
      incr index
    done in
  (match seam.storage with
   | Seam_float values -> check values
   | Seam_float2 values -> check values.x; check values.y
   | Seam_float3 values -> check values.x; check values.y; check values.z
   | Seam_float4 values -> check values.x; check values.y; check values.z; check values.w
   | Seam_float_array values -> check values.values
   | Seam_int _ | Seam_text _ | Seam_int_array _ | Seam_group _ -> ());
  if !invalid < 0 then Ok () else Error (Printf.sprintf
      "Point Split attribute %S contains a non-finite value" seam.name)

let checked_add label left right =
  if right > max_int - left then Error ("Point Split " ^ label ^
      " exceeds integer cardinality limits")
  else Ok (left + right)

let select_float ?cancel ~grain mapping source =
  let output = Array.make (Array.length mapping) 0. in
  if Array.length output > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(Array.length output - 1) (fun target ->
        if target land 4095 = 0 then Cancel.check_opt cancel;
        output.(target) <- source.(mapping.(target)));
  output

let promote_attribute ?cancel ~grain ~primitive_of_vertex ~point_representative
    seam =
  let count = Array.length point_representative in
  let source point =
    let vertex = point_representative.(point) in
    if vertex < 0 then -1 else element primitive_of_vertex seam vertex in
  let fill_float values =
    let output = Array.make count 0. in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
        (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          let source = source point in
          if source >= 0 then output.(point) <- values.(source));
    output in
  let fill_int values =
    let output = Array.make count 0 in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
        (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          let source = source point in
          if source >= 0 then output.(point) <- values.(source));
    output in
  let fill_text values =
    let output = Array.make count "" in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
        (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          let source = source point in
          if source >= 0 then output.(point) <- values.(source));
    output in
  let storage = match seam.storage with
    | Seam_float values -> Attribute.Float (fill_float values)
    | Seam_int values -> Attribute.Int (fill_int values)
    | Seam_text values -> Attribute.Text (fill_text values)
    | Seam_float2 values -> Attribute.Float2 (Packed.Float2.of_owned
        ~x:(fill_float values.x) ~y:(fill_float values.y) |> Result.get_ok)
    | Seam_float3 values -> Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(fill_float values.x) ~y:(fill_float values.y)
        ~z:(fill_float values.z))
    | Seam_float4 values -> Attribute.Float4 (Packed.Float4.of_owned
        ~x:(fill_float values.x) ~y:(fill_float values.y)
        ~z:(fill_float values.z) ~w:(fill_float values.w) |> Result.get_ok)
    | Seam_int_array values ->
        let offsets = Array.make (count + 1) 0 in
        for point = 0 to count - 1 do
          let source = source point in
          let row_length = if source < 0 then 0
            else values.offsets.(source + 1) - values.offsets.(source) in
          if row_length > max_int - offsets.(point) then
            raise (Cardinality_error
              "Point Split promoted integer array exceeds cardinality limits");
          offsets.(point + 1) <- offsets.(point) + row_length
        done;
        let output = Array.make offsets.(count) 0 in
        if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
            (fun point ->
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let source = source point in
              if source >= 0 then begin
                let first = values.offsets.(source)
                and length = values.offsets.(source + 1) - values.offsets.(source) in
                Array.blit values.values first output offsets.(point) length
              end);
        Attribute.Int_array (Packed.Int_array.Private.create_validated_owned
          ~offsets ~values:output)
    | Seam_float_array values ->
        let offsets = Array.make (count + 1) 0 in
        for point = 0 to count - 1 do
          let source = source point in
          let row_length = if source < 0 then 0
            else values.offsets.(source + 1) - values.offsets.(source) in
          if row_length > max_int - offsets.(point) then
            raise (Cardinality_error
              "Point Split promoted float array exceeds cardinality limits");
          offsets.(point + 1) <- offsets.(point) + row_length
        done;
        let output = Array.make offsets.(count) 0. in
        if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
            (fun point ->
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let source = source point in
              if source >= 0 then begin
                let first = values.offsets.(source)
                and length = values.offsets.(source + 1) - values.offsets.(source) in
                Array.blit values.values first output offsets.(point) length
              end);
        Attribute.Float_array (Packed.Float_array.Private.create_validated_owned
          ~offsets ~values:output)
    | Seam_group _ -> assert false in
  Attribute.create_owned ~name:seam.name ~owner:Attribute.Point storage
  |> Result.get_ok

let run ?cancel ?(grain = 16_384) ?selection ?(attributes = "")
    ?(tolerance = 1e-5) ?(promote_attributes = false) geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.point_split: grain must be positive";
  if not (Float.is_finite tolerance) || tolerance < 0. then
    Error "Point Split tolerance must be finite and non-negative"
  else
    let topology_value = Geometry.topology geometry in
    match Element_selection.validate ~operation:"Point Split" topology_value selection with
    | Error message -> Error message
    | Ok () ->
        (match selection with
         | Some (Element_selection.Selected_edges _) ->
             Error "Point Split selection must own points, vertices, or primitives"
         | None | Some (Element_selection.Selected_points _
             | Element_selection.Selected_vertices _
             | Element_selection.Selected_primitives _) ->
    let pattern_result = if String.trim attributes = "" then Ok None
      else Result.map Option.some (Attribute_pattern.compile attributes) in
    Result.bind pattern_result (fun pattern ->
      let matched_attributes = match pattern with
        | None -> [||]
        | Some pattern -> Geometry.attributes geometry
            |> List.filter (fun attribute ->
              (Attribute.owner attribute = Attribute.Vertex
               || Attribute.owner attribute = Attribute.Primitive)
              && Attribute_pattern.matches pattern (Attribute.name attribute))
            |> List.map seam_of_attribute |> Array.of_list in
      let matched_groups = match pattern with
        | None -> [||]
        | Some pattern -> Geometry.groups geometry
            |> List.filter_map (fun group ->
              let owner = match Group.owner group with
                | Group.Vertex -> Some Attribute.Vertex
                | Group.Primitive -> Some Attribute.Primitive
                | Group.Point -> None in
              match owner with
              | Some owner when Attribute_pattern.matches pattern (Group.name group) ->
                  Some { name = Group.name group; owner;
                    storage = Seam_group (Group.Private.bits_view group) }
              | None | Some _ -> None)
            |> Array.of_list in
      let matched = Array.append matched_attributes matched_groups in
      if Option.is_some pattern && Array.length matched = 0 then
        Error (Printf.sprintf
          "Point Split pattern %S matched no vertex/primitive attributes or groups"
          attributes)
      else begin
        let validation = ref (Ok ()) and at = ref 0 in
        while Result.is_ok !validation && !at < Array.length matched do
          validation := validate_finite matched.(!at);
          incr at
        done;
        Result.bind !validation (fun () ->
        let promotion_conflict = ref None in
        if promote_attributes then begin
          let names = Hashtbl.create (Array.length matched) in
          Array.iter (fun seam -> match Hashtbl.find_opt names seam.name with
            | None -> Hashtbl.add names seam.name seam.owner
            | Some owner -> promotion_conflict := Some (Printf.sprintf
                "Point Split promoted attribute %S is present on both %s and %s owners"
                seam.name
                (match owner with Attribute.Vertex -> "vertex" | Attribute.Primitive -> "primitive" | _ -> assert false)
                (match seam.owner with Attribute.Vertex -> "vertex" | Attribute.Primitive -> "primitive" | _ -> assert false))) matched_attributes
        end;
        match !promotion_conflict with
        | Some message -> Error message
        | None ->
        let topology = Topology.Private.view topology_value in
        let point_count = topology.point_count
        and vertex_count = Array.length topology.vertex_points in
        if vertex_count = 0 then Ok geometry else begin
          let point_index = Point_index.create ?cancel topology_value in
          let incidence = Point_index.Private.view point_index in
          let selected = Bytes.make vertex_count '\000' in
          if vertex_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(vertex_count - 1) (fun vertex ->
                if vertex land 4095 = 0 then Cancel.check_opt cancel;
                let value = match selection with
                  | None -> true
                  | Some (Element_selection.Selected_points group) ->
                      Group.mem topology.vertex_points.(vertex) group
                  | Some (Element_selection.Selected_vertices group) ->
                      Group.mem vertex group
                  | Some (Element_selection.Selected_primitives group) ->
                      Group.mem incidence.primitive_of_vertex.(vertex) group
                  | Some (Element_selection.Selected_edges _) -> assert false in
                if value then Bytes.unsafe_set selected vertex '\001');
          let selected_count = ref 0 in
          for vertex = 0 to vertex_count - 1 do
            if Bytes.unsafe_get selected vertex <> '\000' then incr selected_count
          done;
          if !selected_count = 0 then Ok geometry else begin
            let has_seams = Array.length matched > 0
            and has_promotable_seams = Array.length matched_attributes > 0 in
            let ordered = if has_seams then Array.copy incidence.point_vertices
              else incidence.point_vertices
            and local_cluster = Array.make vertex_count 0
            and point_extra = Array.make point_count 0
            and point_representative = Array.make point_count (-1)
            and unselected_representatives = if has_seams
              then Array.make vertex_count 0 else [||]
            and selected_representatives = if has_seams
              then Array.make vertex_count 0 else [||] in
            let components = numeric_components matched in
            let chosen = if tolerance > 0. && Array.length components > 0
              then Some components.(0) else None in
            let compare_vertex = match chosen with
              | None -> seam_compare ~primitive_of_vertex:incidence.primitive_of_vertex matched
              | Some component -> fun left right ->
                  let comparison = Float.compare
                      (component_value incidence.primitive_of_vertex component left)
                      (component_value incidence.primitive_of_vertex component right) in
                  if comparison <> 0 then comparison
                  else seam_compare ~primitive_of_vertex:incidence.primitive_of_vertex
                      matched left right in
            let find_match representatives first count candidate =
              if count = 0 then -1
              else match chosen with
                | None when tolerance = 0. ->
                    let at = count - 1 in
                    if seam_equal ~tolerance
                        ~primitive_of_vertex:incidence.primitive_of_vertex matched
                        representatives.(first + at) candidate then at else -1
                | None ->
                    let found = ref (-1) and at = ref (count - 1) in
                    while !found < 0 && !at >= 0 do
                      if seam_equal ~tolerance
                          ~primitive_of_vertex:incidence.primitive_of_vertex matched
                          representatives.(first + !at) candidate then found := !at;
                      decr at
                    done;
                    !found
                | Some component ->
                    let value = component_value incidence.primitive_of_vertex
                        component candidate in
                    let found = ref (-1) and at = ref (count - 1)
                    and searching = ref true in
                    while !found < 0 && !at >= 0 && !searching do
                      let other = component_value incidence.primitive_of_vertex
                          component representatives.(first + !at) in
                      if value -. other > tolerance then searching := false
                      else if seam_equal ~tolerance
                          ~primitive_of_vertex:incidence.primitive_of_vertex matched
                          representatives.(first + !at) candidate then found := !at;
                      decr at
                    done;
                    !found in
            Parallel.for_ ~chunk_size:(max 1 (grain / 8)) ~start:0
              ~finish:(point_count - 1) (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                let first = incidence.point_offsets.(point)
                and last = incidence.point_offsets.(point + 1) in
                if first < last then begin
                  if Array.length matched = 0 then begin
                    let unselected = ref false and base = ref (-1)
                    and next_cluster = ref 0 in
                    for at = first to last - 1 do
                      let vertex = ordered.(at) in
                      if Bytes.unsafe_get selected vertex = '\000' then begin
                        unselected := true;
                        if !base < 0 || vertex < !base then base := vertex
                      end
                    done;
                    point_representative.(point) <- if !base >= 0 then !base
                      else ordered.(first);
                    for at = first to last - 1 do
                      let vertex = ordered.(at) in
                      if Bytes.unsafe_get selected vertex <> '\000' then begin
                        let cluster = if not !unselected && !next_cluster = 0
                          then 0 else !next_cluster + (if !unselected then 1 else 0) in
                        local_cluster.(vertex) <- cluster;
                        incr next_cluster
                      end
                    done;
                    point_extra.(point) <- if !unselected then !next_cluster
                      else max 0 (!next_cluster - 1)
                  end else begin
                    sort_range compare_vertex ordered first last;
                    let unselected_count = ref 0 and base = ref (-1) in
                    for at = first to last - 1 do
                      let vertex = ordered.(at) in
                      if Bytes.unsafe_get selected vertex = '\000' then begin
                        if !base < 0 || vertex < !base then base := vertex;
                        if find_match unselected_representatives first
                            !unselected_count vertex < 0 then begin
                          unselected_representatives.(first + !unselected_count) <- vertex;
                          incr unselected_count
                        end
                      end
                    done;
                    let selected_rep_count = ref 0 and extra = ref 0 in
                    for at = first to last - 1 do
                      let vertex = ordered.(at) in
                      if Bytes.unsafe_get selected vertex <> '\000' then begin
                        if find_match unselected_representatives first
                            !unselected_count vertex >= 0 then
                          local_cluster.(vertex) <- 0
                        else begin
                          let match_at = find_match selected_representatives first
                              !selected_rep_count vertex in
                          if match_at >= 0 then
                            local_cluster.(vertex) <- local_cluster.
                                (selected_representatives.(first + match_at))
                          else begin
                            let cluster = if !unselected_count = 0
                                && !selected_rep_count = 0 then 0
                              else begin incr extra; !extra end in
                            selected_representatives.(first + !selected_rep_count) <- vertex;
                            if cluster = 0 then point_representative.(point) <- vertex;
                            incr selected_rep_count;
                            local_cluster.(vertex) <- cluster
                          end
                        end
                      end
                    done;
                    if !base >= 0 then point_representative.(point) <- !base;
                    point_extra.(point) <- !extra
                  end
                end);
            let extra_offsets = Array.make (point_count + 1) 0
            and overflow = ref None in
            for point = 0 to point_count - 1 do
              match checked_add "point count" extra_offsets.(point)
                  point_extra.(point) with
              | Ok value -> extra_offsets.(point + 1) <- value
              | Error message -> overflow := Some message
            done;
            match !overflow with
            | Some message -> Error message
            | None ->
              Result.bind (checked_add "point count" point_count
                  extra_offsets.(point_count)) (fun output_points ->
              if output_points = point_count
                  && not (promote_attributes && has_promotable_seams)
              then Ok geometry
              else begin
                let point_source = Array.init output_points (fun point ->
                  if point < point_count then point else 0)
                and output_representative =
                  if promote_attributes && has_promotable_seams
                  then Array.make output_points (-1) else [||] in
                if Array.length output_representative > 0 then
                  Array.blit point_representative 0 output_representative 0 point_count;
                let vertex_points = Array.make vertex_count 0 in
                if vertex_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                    ~finish:(vertex_count - 1) (fun vertex ->
                      if vertex land 4095 = 0 then Cancel.check_opt cancel;
                      let source_point = topology.vertex_points.(vertex)
                      and cluster = local_cluster.(vertex) in
                      let target = if cluster = 0 then source_point
                        else point_count + extra_offsets.(source_point) + cluster - 1 in
                      vertex_points.(vertex) <- target;
                      if cluster > 0 then begin
                        point_source.(target) <- source_point;
                        if Array.length output_representative > 0 then
                          output_representative.(target) <- vertex
                      end);
                let target_topology = if output_points = point_count then topology_value
                  else Topology.Private.create_validated_owned
                    ~point_count:output_points ~vertex_points
                    ~primitive_offsets:(Array.copy topology.primitive_offsets)
                    ~primitive_kinds:(Bytes.copy topology.primitive_kinds) in
                let source_positions = Packed.Float3.Private.view
                    (Geometry.positions geometry) in
                let positions = if output_points = point_count
                  then Geometry.positions geometry
                  else Packed.Float3.Private.of_owned_exn
                    ~x:(select_float ?cancel ~grain point_source source_positions.x)
                    ~y:(select_float ?cancel ~grain point_source source_positions.y)
                    ~z:(select_float ?cancel ~grain point_source source_positions.z) in
                let promoted_result = try Ok (if promote_attributes then
                    Array.map (promote_attribute ?cancel ~grain
                      ~primitive_of_vertex:incidence.primitive_of_vertex
                      ~point_representative:output_representative)
                      matched_attributes
                  else [||]) with Cardinality_error message -> Error message in
                Result.bind promoted_result (fun promoted ->
                let promoted_name name = Array.exists
                    (fun seam -> String.equal seam.name name) matched_attributes in
                let attributes = Geometry.attributes geometry
                  |> List.filter_map (fun attribute ->
                    if promote_attributes && promoted_name (Attribute.name attribute)
                        && (Attribute.owner attribute = Attribute.Point
                            || Attribute.owner attribute = Attribute.Vertex
                            || Attribute.owner attribute = Attribute.Primitive)
                    then None
                    else if Attribute.owner attribute = Attribute.Point
                        && output_points <> point_count then
                      Some (Topology_remap.attribute ?cancel ~grain point_source attribute)
                    else Some attribute)
                  |> fun values -> values @ Array.to_list promoted in
                let groups = Geometry.groups geometry |> List.map (fun group ->
                  if Group.owner group = Group.Point && output_points <> point_count
                  then Topology_remap.group ?cancel ~grain point_source group
                  else group) in
                let edge_groups = match Geometry.edge_groups geometry with
                  | [] -> Ok []
                  | source_groups ->
                      Topology_remap.split_point_edge_groups ?cancel ~grain
                        ~source_index:(Topology_index.create ?cancel topology_value)
                        ~target_topology source_groups in
                Result.bind edge_groups (fun edge_groups ->
                  Geometry.create ~positions ~topology:target_topology ~attributes
                    ~groups ~edge_groups ()))
              end)
          end
        end)
      end))
