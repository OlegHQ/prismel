type invocation = {
  global_id : int * int * int;
  local_id : int * int * int;
  group_id : int * int * int;
  num_groups : int * int * int;
  local_size : int * int * int;
  linear_index : int;
  uniforms : Shader3.uniforms;
}

let positive_triplet name (x, y, z) =
  if x <= 0 || y <= 0 || z <= 0 then
    invalid_arg ("Compute3.dispatch: " ^ name ^ " values must be positive")

let checked_product name values =
  List.fold_left
    (fun product value ->
      if product > Sys.max_array_length / value then
        invalid_arg
          ("Compute3.dispatch: " ^ name ^ " exceeds maximum array length");
      product * value)
    1 values

let dispatch ?(grain = 256) ?(uniforms = Shader3.empty_uniforms)
    ~groups:((groups_x, groups_y, groups_z) as groups)
    ~local_size:((local_x, local_y, local_z) as local_size) kernel =
  positive_triplet "group" groups;
  positive_triplet "local_size" local_size;
  if grain <= 0 then invalid_arg "Compute3.dispatch: grain must be positive";
  let width = checked_product "X dimension" [groups_x; local_x]
  and height = checked_product "Y dimension" [groups_y; local_y]
  and depth = checked_product "Z dimension" [groups_z; local_z] in
  let count = checked_product "invocation count" [width; height; depth] in
  List.init count Fun.id
  |> Parallel.map ~grain (fun linear_index ->
    let x = linear_index mod width in
    let yz = linear_index / width in
    let y = yz mod height and z = yz / height in
    kernel {
      global_id = x, y, z;
      local_id = x mod local_x, y mod local_y, z mod local_z;
      group_id = x / local_x, y / local_y, z / local_z;
      num_groups = groups;
      local_size;
      linear_index;
      uniforms;
    })
  |> Array.of_list
