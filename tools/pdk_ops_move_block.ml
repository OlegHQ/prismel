(* Remove a copied family body from Ops only when the destination contains it
   byte-for-byte. Markers must uniquely identify line starts. *)

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let write path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    output_string channel contents)

let find source needle =
  let width = String.length needle in
  let rec loop at =
    if at + width > String.length source then None
    else if String.sub source at width = needle then Some at
    else loop (at + 1) in
  loop 0

let unique_line source marker =
  let needle = "\n" ^ marker in
  let first = if String.starts_with ~prefix:marker source then Some 0
    else Option.map (( + ) 1) (find source needle) in
  match first with
  | None -> invalid_arg ("missing marker: " ^ marker)
  | Some at ->
      let rest = String.sub source (at + String.length marker)
          (String.length source - at - String.length marker) in
      if Option.is_some (find rest needle) then
        invalid_arg ("duplicate marker: " ^ marker);
      at

let () =
  if Array.length Sys.argv <> 6 then
    invalid_arg "usage: pdk_ops_move_block SOURCE DEST START END REPLACEMENT";
  let source_path = Sys.argv.(1) and destination_path = Sys.argv.(2)
  and start_marker = Sys.argv.(3) and end_marker = Sys.argv.(4)
  and replacement = Sys.argv.(5) in
  let source = read source_path and destination = read destination_path in
  let first = unique_line source start_marker
  and last = unique_line source end_marker in
  if last <= first then invalid_arg "end marker precedes start marker";
  let block = String.sub source first (last - first) in
  if Option.is_none (find destination block) then
    invalid_arg "destination does not contain the exact copied block";
  let replacement = if replacement = "" then "" else replacement ^ "\n\n" in
  write source_path
    (String.sub source 0 first ^ replacement ^
     String.sub source last (String.length source - last));
  Printf.printf "moved %d bytes from %s into %s\n"
    (String.length block) source_path destination_path
