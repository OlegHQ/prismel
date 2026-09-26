type operation = Reverse_faces.operation =
  | Reverse_vertices
  | Shift_vertices of int

let run_checked ?cancel ?grain ?primitives ?operation geometry =
  Error.guard ~operation:"reverse" ~code:"invalid_topology" (fun () ->
    Reverse_faces.run ?cancel ?grain ?primitives ?operation geometry)
