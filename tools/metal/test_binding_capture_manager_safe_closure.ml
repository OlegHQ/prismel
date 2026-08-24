let () =
  if Array.length Sys.argv <> 2 then invalid_arg "expected inventory";
  let open Yojson.Safe.Util in
  let header_ids =
    Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list
    |> List.filter_map (fun json ->
      if json |> member "header" |> to_string = "Metal/MTLCaptureManager.h"
      then Some (json |> member "id" |> to_string,
                 json |> member "kind" |> to_string,
                 json |> member "classification" |> to_string)
      else None)
  in
  let promoted =
    header_ids |> List.filter_map (fun (id, _, classification) ->
      if List.mem id Binding_capture_manager_tail_handoff.callable_ids
      then Some (id, classification) else None)
  in
  let metadata = header_ids |> List.filter_map (fun (id, kind, classification) ->
    if kind = "class" && classification = "unreviewed" then Some id else None)
    |> List.sort String.compare in
  if List.length promoted <> 19
     || List.exists (fun (_, classification) -> classification <> "bound") promoted
     || metadata <> [ "class:MTLCaptureDescriptor"; "class:MTLCaptureManager" ]
  then failwith "CaptureManager19 safe closure drift";
  Printf.printf "CaptureManager21 exact closure: callable19 bound + metadata2 unreviewed\n%!"
