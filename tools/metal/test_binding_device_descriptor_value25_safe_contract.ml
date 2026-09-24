open Binding_device_descriptor_value25_safe_contract
let require x message=if not x then failwith message
let ()=
  let value={access=2L;array_length=7L;constant_block_alignment=16L;
    data_type=33L;index=3L;texture_type=2L}in
  require(validate value)"valid descriptor rejected";
  require(not(validate{value with array_length=0L}))"zero array accepted";
  require(not(validate{value with constant_block_alignment=3L}))"alignment accepted";
  let copy=snapshot value in require(copy=value)"snapshot drift";
  require(validate_architecture_name"Apple M1")"architecture name rejected";
  require(not(validate_architecture_name""))"empty architecture accepted";
  print_endline"Device value25 contract: ArgumentDescriptor20 + Architecture5"
