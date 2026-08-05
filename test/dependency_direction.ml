let read path =
  let input = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
    really_input_string input (in_channel_length input))

let contains text needle =
  let text_length = String.length text and needle_length = String.length needle in
  let rec search index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || search (index + 1))
  in
  search 0

let tokens text =
  String.map (fun character ->
    match character with
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> character
    | _ -> ' ') text
  |> String.split_on_char ' '
  |> List.filter (fun token -> token <> "")

let reject path text names =
  let words = tokens text in
  List.iter (fun name ->
    if List.mem name words then
      failwith (Printf.sprintf "%s imports forbidden upward library %s" path name))
    names

let () = match Array.to_list Sys.argv with
  | [_; pdk_path; geom_path; procedural_path] ->
      let pdk = read pdk_path and geom = read geom_path
      and procedural = read procedural_path in
      reject pdk_path pdk ["geom"; "procedural"; "runtime"; "wap"];
      reject geom_path geom ["procedural"; "runtime"; "wap"];
      reject procedural_path procedural ["runtime"; "wap"];
      if not (contains geom "(libraries prismel pdk)") then
        failwith "Geom must consume PDK as its single mesh compute core";
      if not (contains procedural "(libraries prismel pdk") then
        failwith "Procedural must consume PDK directly";
      print_endline "geometry dependency direction passed"
  | _ -> invalid_arg "dependency_direction: expected pdk, geom, procedural dune files"
