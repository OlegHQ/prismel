let () =
  if Array.length Sys.argv <> 2 then invalid_arg "expected inventory";
  let open Yojson.Safe.Util in
  let header_ids =
    Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list
    |> List.filter_map (fun json ->
      if json |> member "header" |> to_string = "Metal/MTLCaptureManager.h"
         && json |> member "classification" |> to_string = "unreviewed"
      then Some (json |> member "id" |> to_string, json |> member "kind" |> to_string)
      else None)
  in
  let callable = header_ids |> List.filter_map (fun (id, kind) ->
    if kind = "method" || kind = "property" then Some id else None) |> List.sort String.compare in
  let metadata = header_ids |> List.filter_map (fun (id, kind) ->
    if kind = "class" then Some id else None) |> List.sort String.compare in
  if callable <> List.sort String.compare Binding_capture_manager_tail_handoff.callable_ids
     || metadata <> [ "class:MTLCaptureDescriptor"; "class:MTLCaptureManager" ]
  then failwith "CaptureManager19 safe closure drift";
  Printf.printf "CaptureManager21 exact closure: callable19 + metadata2 (unpromoted)\n%!"
