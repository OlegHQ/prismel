let check condition message = if not condition then failwith message

type buffer = { device : int64; length : int64 }
type child = { device : int64; id : int }

let () =
  let open Binding_acceleration_ownership_adapter in
  let validate =
    validate ~expected_device:7L ~buffer_device:(fun (value : buffer) -> value.device)
      ~buffer_length:(fun (value : buffer) -> value.length)
      ~element_device:(fun (value : child) -> value.device)
      ~acceleration_device:(fun (value : child) -> value.device)
  in
  check (validate (Buffer_range { buffer = { device = 7L; length = 64L }; offset = 16L; length = 48L }) = Ok ()) "valid range rejected";
  check (Result.is_error (validate (Buffer_range { buffer = { device = 7L; length = 64L }; offset = 17L; length = 48L }))) "out-of-range accepted";
  check
    (Result.is_error
       (validate
          (Buffer_range
             { buffer = { device = 7L; length = Int64.max_int }
             ; offset = Int64.max_int
             ; length = 1L })))
    "overflowing range accepted";
  check (Result.is_error (validate (Buffer (Some { device = 8L; length = 64L })))) "cross-device buffer accepted";
  check (Result.is_error (validate (Elements [ { device = 7L; id = 0 }; { device = 8L; id = 1 } ]))) "cross-device child accepted";
  let live = ref 0 in
  let retain child = if child.id = 2 then Error "injected" else (incr live; Ok child) in
  let release _ = decr live in
  check (Result.is_error (copy_retained_array ~retain ~release [ {device=7L;id=0}; {device=7L;id=1}; {device=7L;id=2} ])) "injected retain failure accepted";
  check (!live = 0) "retained prefix leaked";
  let live = ref 0 in
  let retain child = if child.id = 2 then raise Exit else (incr live; Ok child) in
  let release _ = decr live in
  check
    (match copy_retained_array ~retain ~release [ {device=7L;id=0}; {device=7L;id=1}; {device=7L;id=2} ] with
     | _ -> false
     | exception Exit -> true)
    "injected retain exception did not propagate";
  check (!live = 0) "exceptional retained prefix leaked";
  let live = ref 0 in
  let retain child = incr live; Ok child in
  let release _ = decr live in
  let owned =
    match copy_retained_array ~retain ~release [ {device=7L;id=0}; {device=7L;id=1} ] with
    | Ok owned -> owned
    | Error message -> failwith message
  in
  Array.iter release owned;
  check (!live = 0) "successful retained copy did not permit exact teardown";
  print_endline "Metal acceleration ownership adapters: device/range/copy/unwind passed"
