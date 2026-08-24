let () =
  if Array.length Sys.argv <> 2 then invalid_arg "expected inventory";
  let open Yojson.Safe.Util in
  let ids =
    Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list
    |> List.filter_map (fun j ->
      if j |> member "classification" |> to_string = "unreviewed"
         && j |> member "header" |> to_string = "Metal/MTLLibrary.h"
      then Some (j |> member "id" |> to_string) else None)
  in
  Binding_library42_native_closure.validate ids;
  print_endline "MTLLibrary42 native closure: existing18 + remaining24 = exact42"
