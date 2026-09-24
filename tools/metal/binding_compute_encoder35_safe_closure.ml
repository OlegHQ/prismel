let callable_ids = Binding_compute_encoder35_native_closure.callable_ids
let validate () =
  if List.length callable_ids <> 35 then invalid_arg "ComputeEncoder safe35 drift";
  List.iter (fun id -> if not (List.mem id Binding_compute_encoder35_native_closure.callable_ids) then invalid_arg ("ComputeEncoder safe ID outside native closure: " ^ id)) callable_ids
