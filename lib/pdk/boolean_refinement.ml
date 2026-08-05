open Prismel

type t = {
  constraints : Boolean_constraints.t;
  left : Boolean_face_cdt.t option array;
  right : Boolean_face_cdt.t option array;
  refined_left : int;
  refined_right : int;
}

let operation = "boolean_refinement"
let error code message = Error (Error.make ~operation ~code message)

let left_face_count value = Array.length value.left
let right_face_count value = Array.length value.right
let left_face value face = value.left.(face)
let right_face value face = value.right.(face)
let refined_left_count value = value.refined_left
let refined_right_count value = value.refined_right

module Private = struct
  let constraints value = value.constraints
end

let build_side ?cancel ?coplanar ~grain constraints side face_count range
    coplanar_range =
  let output = Array.make face_count None and errors = Array.make face_count None in
  if face_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(face_count - 1) (fun face ->
    if face land 255 = 0 then Cancel.check_opt cancel;
    let first, last = range constraints face in
    let coplanar_first, coplanar_last = match coplanar with
      | None -> 0, 0
      | Some value -> coplanar_range value face in
    if first < last || coplanar_first < coplanar_last then
      match Boolean_face_arrangement.build ?cancel ?coplanar constraints
          ~side ~triangle:face with
      | Error failure -> errors.(face) <- Some failure
      | Ok arrangement ->
          (match Boolean_face_cdt.build ?cancel constraints arrangement
              ~side ~triangle:face with
           | Ok triangulation -> output.(face) <- Some triangulation
           | Error failure -> errors.(face) <- Some failure));
  let first_error = ref None and face = ref 0 and refined = ref 0 in
  while Option.is_none !first_error && !face < face_count do
    (match errors.(!face) with
     | Some failure -> first_error := Some failure
     | None -> if Option.is_some output.(!face) then incr refined);
    incr face
  done;
  match !first_error with
  | Some failure -> Error failure
  | None -> Ok (output, !refined)

let build ?cancel ?coplanar ~grain constraints =
  try
    if grain <= 0 then error "invalid_parameter" "grain must be positive"
    else
      let left_count = Boolean_constraints.left_triangle_count constraints
      and right_count = Boolean_constraints.right_triangle_count constraints in
      match build_side ?cancel ~grain constraints Boolean_face_arrangement.Left
          ?coplanar left_count Boolean_constraints.left_constraint_range
          Boolean_coplanar.Private.left_pair_range with
      | Error failure -> Error failure
      | Ok (left, refined_left) ->
          match build_side ?cancel ~grain constraints Boolean_face_arrangement.Right
              ?coplanar right_count Boolean_constraints.right_constraint_range
              Boolean_coplanar.Private.right_pair_range with
          | Error failure -> Error failure
          | Ok (right, refined_right) ->
              Ok { constraints; left; right; refined_left; refined_right }
  with Cancel.Cancelled -> error "cancelled" "Boolean refinement was cancelled"
