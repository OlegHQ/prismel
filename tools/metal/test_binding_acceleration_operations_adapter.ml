type resource = { device : int64; id : int }
let check condition message = if not condition then failwith message

let () =
  let open Binding_acceleration_operations_adapter in
  let table = create ~device:7L ~capacity:4 in
  let buffer = { device = 7L; id = 1 } in
  let visible = { device = 7L; id = 2 } in
  check
    (set_buffer ~buffer_device:(fun value -> value.device) table ~index:0
       (Some (buffer, 16L)) = Ok ())
    "valid buffer binding rejected";
  check (set_function table ~index:1 (Some 42) = Ok ())
    "valid function binding rejected";
  check
    (set_visible_table ~table_device:(fun value -> value.device) table ~index:2
       (Some visible) = Ok ())
    "valid visible-table binding rejected";
  check (retained_count table = 3) "binding retention count drift";
  check
    (Result.is_error
       (set_buffer ~buffer_device:(fun value -> value.device) table ~index:0
          (Some ({ device = 8L; id = 3 }, 0L))))
    "cross-device buffer accepted";
  check (Result.is_error (set_function table ~index:4 None))
    "out-of-range function accepted";
  destroy table;
  check (destroyed table && retained_count table = 0)
    "destroy did not release retained bindings";
  check (Result.is_error (set_function table ~index:0 None))
    "destroyed table accepted mutation";
  print_endline "Metal acceleration operation adapters: lifetime/device/range passed"
