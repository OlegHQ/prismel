(* Apply reviewed, qualified Pdk.Ops path rewrites to an explicit file list. *)

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let write path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    output_string channel contents)

let is_ident = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true
  | _ -> false

let replace ~old ~new_ ~prefix source =
  let length = String.length source and width = String.length old in
  let buffer = Buffer.create length in
  let rec loop position count =
    if position >= length then Buffer.contents buffer, count
    else if position + width <= length
        && String.sub source position width = old
        && (prefix || position + width = length
            || not (is_ident source.[position + width])) then begin
      Buffer.add_string buffer new_;
      loop (position + width) (count + 1)
    end else begin
      Buffer.add_char buffer source.[position];
      loop (position + 1) count
    end in
  loop 0 0

let mapping path =
  read path |> String.split_on_char '\n' |> List.filter_map (fun line ->
    if line = "" || line.[0] = '#' then None
    else match String.split_on_char '\t' line with
      | [old; new_] ->
          let prefix = String.ends_with ~suffix:"*" old in
          let old = if prefix then String.sub old 0 (String.length old - 1)
            else old in
          Some (old, new_, prefix)
      | _ -> invalid_arg ("invalid codemod row: " ^ line))
  |> List.sort (fun (left, _, _) (right, _, _) ->
    Int.compare (String.length right) (String.length left))

let files () =
  let rec loop paths = match input_line stdin with
    | path -> loop (path :: paths)
    | exception End_of_file -> List.rev paths in
  loop []

let () =
  if Array.length Sys.argv <> 3 || Sys.argv.(2) <> "-" then
    invalid_arg "usage: pdk_ops_codemod MAP.tsv - < FILES.txt";
  let mappings = mapping Sys.argv.(1) in
  files () |> List.iter (fun path ->
    let before = read path in
    let after, count = List.fold_left (fun (contents, count) (old, new_, prefix) ->
      let contents, changed = replace ~old ~new_ ~prefix contents in
      contents, count + changed) (before, 0) mappings in
    if count > 0 then begin
      write path after;
      Printf.printf "%s: %d\n" path count
    end)
