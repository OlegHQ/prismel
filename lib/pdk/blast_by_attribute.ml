type owner = Blast_points | Blast_primitives

type mode =
  | Blast_below of float
  | Blast_range of { minimum : float; maximum : float }
  | Blast_width of { center : float; width : float }

type output = Blast_delete | Blast_group of string

type classifier = Below of float | Closed of float * float

let fail message = Error ("Pdk.Ops.blast_by_attribute: " ^ message)

let group_owner = function
  | Blast_points -> Group.Point
  | Blast_primitives -> Group.Primitive

let attribute_owner = function
  | Blast_points -> Attribute.Point
  | Blast_primitives -> Attribute.Primitive

let owner_name = function
  | Blast_points -> "point"
  | Blast_primitives -> "primitive"

let owner_count owner geometry = match owner with
  | Blast_points -> Geometry.point_count geometry
  | Blast_primitives -> Geometry.primitive_count geometry

let validate_mode = function
  | Blast_below threshold ->
      if Float.is_finite threshold then Ok (Below threshold)
      else fail "threshold must be finite"
  | Blast_range { minimum; maximum } ->
      if not (Float.is_finite minimum && Float.is_finite maximum) then
        fail "range bounds must be finite"
      else if minimum > maximum then
        fail "range minimum must not exceed its maximum"
      else Ok (Closed (minimum, maximum))
  | Blast_width { center; width } ->
      if not (Float.is_finite center && Float.is_finite width) then
        fail "width center and width must be finite"
      else if width < 0. then fail "width must be non-negative"
      else
        let half = width *. 0.5 in
        let minimum = center -. half and maximum = center +. half in
        if not (Float.is_finite minimum && Float.is_finite maximum) then
          fail "width interval exceeds finite floating-point range"
        else Ok (Closed (minimum, maximum))

let atomic_min target candidate =
  let rec update current =
    if candidate >= current then ()
    else if Atomic.compare_and_set target current candidate then ()
    else update (Atomic.get target)
  in
  update (Atomic.get target)

let validate_base ~owner ~length = function
  | None -> Ok ()
  | Some base when Group.owner base <> group_owner owner ->
      fail (Printf.sprintf "base group must own %ss" (owner_name owner))
  | Some base when Group.length base <> length ->
      fail (Printf.sprintf "base group length %d does not match %s count %d"
        (Group.length base) (owner_name owner) length)
  | Some _ -> Ok ()

let blast ?cancel ?(grain = 16_384) ?base ?(invert = false)
    ?(remove_unused_points = false) ~owner ~attribute ~mode ~output geometry =
  Cancel.check_opt cancel;
  if grain <= 0 then fail "grain must be positive"
  else if String.trim attribute = "" then fail "attribute name must not be empty"
  else
    let length = owner_count owner geometry in
    Result.bind (validate_base ~owner ~length base) (fun () ->
    Result.bind (validate_mode mode) (fun classifier ->
    match output with
    | Blast_group name when String.trim name = "" ->
        fail "output group name must not be empty"
    | Blast_group _ when remove_unused_points ->
        fail "remove_unused_points is only valid for primitive deletion"
    | Blast_delete when owner = Blast_points && remove_unused_points ->
        fail "remove_unused_points is only valid for primitive deletion"
    | Blast_delete | Blast_group _ ->
        match Geometry.find_attribute ~owner:(attribute_owner owner) attribute geometry with
        | None -> fail (Printf.sprintf "could not find %s attribute %S"
            (owner_name owner) attribute)
        | Some source ->
            let storage = Attribute.Private.storage source in
            match storage with
            | Attribute.Float _ | Attribute.Int _ ->
                let first_non_finite = Atomic.make length in
                let base_member index = match base with
                  | None -> true
                  | Some base -> Group.mem index base in
                let finish matches = if invert then not matches else matches in
                let selection = match storage with
                  | Attribute.Float values ->
                      Group.init ~grain ~owner:(group_owner owner)
                        ~name:"__blast_by_attribute_selection" length (fun index ->
                          if index land 4095 = 0 then Cancel.check_opt cancel;
                          if not (base_member index) then false
                          else
                            let value = Array.unsafe_get values index in
                            if not (Float.is_finite value) then begin
                              atomic_min first_non_finite index;
                              false
                            end else
                              finish (match classifier with
                                | Below threshold -> value < threshold
                                | Closed (minimum, maximum) ->
                                    value >= minimum && value <= maximum))
                  | Attribute.Int values ->
                      Group.init ~grain ~owner:(group_owner owner)
                        ~name:"__blast_by_attribute_selection" length (fun index ->
                          if index land 4095 = 0 then Cancel.check_opt cancel;
                          if not (base_member index) then false
                          else
                            let value = Float.of_int (Array.unsafe_get values index) in
                            finish (match classifier with
                              | Below threshold -> value < threshold
                              | Closed (minimum, maximum) ->
                                  value >= minimum && value <= maximum))
                  | _ -> assert false in
                let invalid = Atomic.get first_non_finite in
                if invalid < length then fail (Printf.sprintf
                    "%s attribute %S contains a non-finite value at element %d"
                    (owner_name owner) attribute invalid)
                else (match output with
                  | Blast_group name ->
                      Geometry.with_group (Group.with_name name selection) geometry
                  | Blast_delete ->
                      Deletion.delete ?cancel ~grain
                        ~compact_points:remove_unused_points selection geometry)
            | _ -> fail (Printf.sprintf
                "%s attribute %S must have scalar float or integer storage, not %s"
                (owner_name owner) attribute (Attribute.kind_name source))
            ))
