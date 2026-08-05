open Prismel

type t = { source : Node.t; transforms : Mat4.t array }

let matrix_copy matrix =
  let a, b, c, d = Mat4.to_rows matrix in Mat4.of_rows a b c d

let validate matrix =
  for row = 0 to 3 do for column = 0 to 3 do
    if not (Float.is_finite (Mat4.get matrix ~row ~column)) then
      invalid_arg "Instances: transforms must be finite"
  done done

let create ?(transforms = [|Mat4.identity|]) source =
  Array.iter validate transforms;
  { source; transforms = Array.map matrix_copy transforms }

let source value = value.source
let count value = Array.length value.transforms
let transforms value = Array.map matrix_copy value.transforms
let payload_bytes value = Array.length value.transforms * 16 * 8

let transform matrix value =
  validate matrix;
  { value with
    transforms = Array.map (fun transform -> Mat4.mul matrix transform)
      value.transforms }

let duplicate ?(copies = 1) ?(cumulative = true) ?(transform = Mat4.identity)
    value =
  if copies < 0 then invalid_arg "Instances.duplicate: negative copy count";
  validate transform;
  if copies = 0 || Array.length value.transforms = 0 then value
  else if copies = max_int then invalid_arg "Instances.duplicate: copy count is too large"
  else
    let total = copies + 1 and sources = Array.length value.transforms in
    if sources > Sys.max_array_length / total then
      invalid_arg "Instances.duplicate: transform output exceeds array limits";
    let powers = Array.make total Mat4.identity in
    for copy = 1 to total - 1 do
      powers.(copy) <- if cumulative then Mat4.mul powers.(copy - 1) transform
        else transform
    done;
    let transforms = Array.init (sources * total) (fun index ->
      let source = index / total and copy = index mod total in
      Mat4.mul powers.(copy) value.transforms.(source)) in
    { value with transforms }

module Private = struct
  let scene3 ?material ?texture ?shader ?mode ?cull ?shading mesh value =
    Scene3.instances_array ?material ?texture ?shader ?mode ?cull ?shading
      mesh value.transforms
end
