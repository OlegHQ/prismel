let expect_error = function Error _ -> () | Ok _ -> failwith "expected Tensor validation error"
let expect_ok = function Ok value -> value | Error error -> failwith error

let () =
  Binding_tensor_safe_package.validate_handoff ();
  let source = [| 2L; 3L |] in
  let snapshot = expect_ok (Binding_tensor_safe_package.validate_extents source) in
  source.(0) <- 99L;
  if snapshot <> [| 2L; 3L |] then failwith "Tensor extents were not snapshotted";
  expect_error (Binding_tensor_safe_package.validate_extents [||]);
  expect_error (Binding_tensor_safe_package.validate_extents [| 2L; 0L |]);
  expect_error (Binding_tensor_safe_package.validate_shape ~dimensions:[|2L;3L|] ~strides:[|4L|]);
  let required = expect_ok (Binding_tensor_safe_package.validate_slice
    ~tensor_dimensions:[|4L;5L|] ~origin:[|1L;1L|] ~slice_dimensions:[|2L;3L|]
    ~byte_strides:[|20L;4L|] ~element_size:4 ~bytes_length:32) in
  if required <> 32L then failwith "Tensor exact byte requirement";
  expect_error (Binding_tensor_safe_package.validate_slice
    ~tensor_dimensions:[|4L;5L|] ~origin:[|3L;1L|] ~slice_dimensions:[|2L;3L|]
    ~byte_strides:[|20L;4L|] ~element_size:4 ~bytes_length:64);
  expect_error (Binding_tensor_safe_package.validate_slice
    ~tensor_dimensions:[|4L;5L|] ~origin:[|1L;1L|] ~slice_dimensions:[|2L;3L|]
    ~byte_strides:[|20L;4L|] ~element_size:4 ~bytes_length:31);
  Printf.printf "Tensor safe package: callable44 + constructor enablers3 + retained graph5; snapshot/rank/range/overflow/undersized validation passed\n%!"
