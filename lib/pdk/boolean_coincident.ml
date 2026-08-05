type side = Left | Right

type t = {
  offsets : int array;
  sides : bytes;
  faces : int array;
  triangles : int array;
  windings : bytes;
}

let operation = "boolean_coincident"
let error code message = Error (Error.make ~operation ~code message)

let group_count value = Array.length value.offsets - 1
let member_range value group = value.offsets.(group), value.offsets.(group + 1)
let member_side value member =
  if Bytes.unsafe_get value.sides member = '\000' then Left else Right
let member_face value member = value.faces.(member)
let member_triangle value member = value.triangles.(member)
let member_winding value member =
  if Bytes.unsafe_get value.windings member = '\000' then 1 else -1

type facets = {
  offsets : int array;
  faces : int array;
  triangles : int array;
  values : Boolean_face_cdt.t option array;
}

let flatten face_count face =
  let values = Array.init face_count face and offsets = Array.make (face_count + 1) 0 in
  for index = 0 to face_count - 1 do
    let count = match values.(index) with
      | None -> 0 | Some value -> Boolean_face_cdt.triangle_count value in
    if offsets.(index) > Sys.max_array_length - count then
      invalid_arg "coincident facet cardinality exceeds array limits";
    offsets.(index + 1) <- offsets.(index) + count
  done;
  let total = offsets.(face_count) in
  let faces = Array.make total 0 and triangles = Array.make total 0 in
  for face = 0 to face_count - 1 do
    for triangle = 0 to offsets.(face + 1) - offsets.(face) - 1 do
      let facet = offsets.(face) + triangle in
      faces.(facet) <- face;
      triangles.(facet) <- triangle
    done
  done;
  { offsets; faces; triangles; values }

let facet_value facets facet =
  Option.get facets.values.(facets.faces.(facet))

let facet_point facets facet local =
  let value = facet_value facets facet in
  Boolean_face_cdt.Private.point value
    (Boolean_face_cdt.triangle_point value facets.triangles.(facet) local)

let permutation left left_facet right right_facet =
  let mapping = Array.make 3 (-1) and valid = ref true in
  for right_local = 0 to 2 do
    let point = facet_point right right_facet right_local in
    let left_local = ref 0 in
    while !left_local < 3
        && not (Implicit_point.equal point
          (facet_point left left_facet !left_local)) do
      incr left_local
    done;
    if !left_local = 3 then valid := false
    else mapping.(right_local) <- !left_local
  done;
  if !valid then Some mapping else None

let same_facet left left_facet right right_facet =
  Option.is_some (permutation left left_facet right right_facet)

let find parent value =
  let root = ref value in
  while parent.(!root) <> !root do root := parent.(!root) done;
  let cursor = ref value in
  while parent.(!cursor) <> !cursor do
    let next = parent.(!cursor) in parent.(!cursor) <- !root; cursor := next
  done;
  !root

let unite parent left right =
  let left = find parent left and right = find parent right in
  if left <> right then
    if left < right then parent.(right) <- left else parent.(left) <- right

let parity mapping =
  let inversions = ref 0 in
  for left = 0 to 1 do
    for right = left + 1 to 2 do
      if mapping.(left) > mapping.(right) then incr inversions
    done
  done;
  if !inversions land 1 = 0 then 1 else -1

let build ?cancel constraints coplanar refinement =
  try
    Cancel.check_opt cancel;
    if Boolean_coplanar.Private.constraints coplanar != constraints then
      invalid_arg "coplanar plan belongs to a different constraint plan";
    let left = flatten (Boolean_refinement.left_face_count refinement)
        (Boolean_refinement.left_face refinement)
    and right = flatten (Boolean_refinement.right_face_count refinement)
        (Boolean_refinement.right_face refinement) in
    let left_total = Array.length left.faces and right_total = Array.length right.faces in
    if left_total > Sys.max_array_length - right_total then
      invalid_arg "coincident facet union exceeds array limits";
    let total = left_total + right_total in
    let parent = Array.init total Fun.id in
    for pair = 0 to Boolean_coplanar.pair_count coplanar - 1 do
      if pair land 255 = 0 then Cancel.check_opt cancel;
      if Boolean_coplanar.kind coplanar pair = Boolean_coplanar.Polygon then begin
        let left_face = Boolean_coplanar.left_triangle coplanar pair
        and right_face = Boolean_coplanar.right_triangle coplanar pair in
        let left_first = left.offsets.(left_face)
        and left_last = left.offsets.(left_face + 1)
        and right_first = right.offsets.(right_face)
        and right_last = right.offsets.(right_face + 1) in
        for left_facet = left_first to left_last - 1 do
          for right_facet = right_first to right_last - 1 do
            if same_facet left left_facet right right_facet then
              unite parent left_facet (left_total + right_facet)
          done
        done
      end
    done;
    for facet = 0 to total - 1 do parent.(facet) <- find parent facet done;
    let sizes = Array.make total 0 in
    for facet = 0 to total - 1 do
      sizes.(parent.(facet)) <- sizes.(parent.(facet)) + 1
    done;
    let group_of_root = Array.make total (-1) and groups = ref 0 in
    for root = 0 to total - 1 do
      if parent.(root) = root && sizes.(root) > 1 then begin
        group_of_root.(root) <- !groups;
        incr groups
      end
    done;
    let offsets = Array.make (!groups + 1) 0 in
    for root = 0 to total - 1 do
      let group = group_of_root.(root) in
      if group >= 0 then offsets.(group + 1) <- sizes.(root)
    done;
    for group = 0 to !groups - 1 do
      offsets.(group + 1) <- offsets.(group + 1) + offsets.(group)
    done;
    let member_count = offsets.(!groups) in
    let sides = Bytes.make member_count '\000' and faces = Array.make member_count 0
    and triangles = Array.make member_count 0 and windings = Bytes.make member_count '\000'
    and cursor = Array.copy offsets in
    for facet = 0 to total - 1 do
      let root = parent.(facet) and group = group_of_root.(parent.(facet)) in
      if group >= 0 then begin
        let member = cursor.(group) in
        cursor.(group) <- member + 1;
        let root_is_left = root < left_total and facet_is_left = facet < left_total in
        let root_facets, root_facet = if root_is_left then left, root
          else right, root - left_total
        and member_facets, member_facet = if facet_is_left then left, facet
          else right, facet - left_total in
        let mapping = Option.get
            (permutation root_facets root_facet member_facets member_facet) in
        let root_source_winding = Boolean_face_cdt.Private.source_winding
            (facet_value root_facets root_facet)
        and member_source_winding = Boolean_face_cdt.Private.source_winding
            (facet_value member_facets member_facet) in
        if parity mapping * root_source_winding * member_source_winding < 0 then
          Bytes.unsafe_set windings member '\001';
        if facet_is_left then begin
          faces.(member) <- left.faces.(facet);
          triangles.(member) <- left.triangles.(facet)
        end else begin
          Bytes.unsafe_set sides member '\001';
          let right_facet = facet - left_total in
          faces.(member) <- right.faces.(right_facet);
          triangles.(member) <- right.triangles.(right_facet)
        end
      end
    done;
    Ok { offsets; sides; faces; triangles; windings }
  with
  | Cancel.Cancelled -> error "cancelled" "Coincident facet grouping was cancelled"
  | Invalid_argument message -> error "invalid_refinement" message
