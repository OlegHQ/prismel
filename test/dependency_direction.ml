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
  | [_; pdk_path; geom_path; procedural_path; pxui_path; sop_ui_path;
      pxui_graph_path; sop_catalog_path; sketch_path; sketch_ui_path] ->
      let pdk = read pdk_path and geom = read geom_path
      and procedural = read procedural_path and pxui = read pxui_path
      and sop_ui = read sop_ui_path and pxui_graph = read pxui_graph_path
      and sop_catalog = read sop_catalog_path and sketch = read sketch_path
      and sketch_ui = read sketch_ui_path in
      reject pdk_path pdk
        ["geom"; "procedural"; "pxui"; "sop_ui"; "runtime"];
      reject geom_path geom
        ["procedural"; "pxui"; "sop_ui"; "runtime"];
      reject procedural_path procedural ["pxui"; "sop_ui"; "runtime"];
      reject pxui_path pxui ["procedural"; "sop_ui"; "runtime"];
      reject sop_ui_path sop_ui ["runtime"];
      reject pxui_graph_path pxui_graph ["sop_ui"; "sketch_support";
        "sketch_ui"; "runtime"];
      reject sop_catalog_path sop_catalog ["geom"; "pxui"; "pxui_graph";
        "sop_ui"; "sketch_support"; "sketch_ui"; "runtime"];
      reject sketch_path sketch ["geom"; "pxui"; "sop_ui"; "runtime"];
      reject sketch_ui_path sketch_ui ["runtime"];
      if not (contains geom "(libraries prismel pdk)") then
        failwith "Geom must consume PDK as its single mesh compute core";
      if not (contains procedural "(libraries prismel pdk") then
        failwith "Procedural must consume PDK directly";
      if not (contains sop_ui "(libraries procedural pxui)") then
        failwith "Sop_ui must be the one-way Procedural/PXUI bridge";
      if not (contains sketch "(libraries prismel pdk procedural)") then
        failwith "Sketch_support must be a leaf over Prismel, PDK, and Procedural";
      if not (contains pxui_graph "(libraries prismel procedural pxui)") then
        failwith "Pxui_graph must be the read-only Procedural/PXUI bridge";
      if not (contains sop_catalog "(libraries prismel pdk procedural)") then
        failwith "Sop_catalog must wrap Procedural/PDK without UI dependencies";
      if not (contains sketch_ui
          "(libraries prismel procedural pxui pxui_graph sop_ui sketch_support)")
      then failwith "Sketch_ui must compose only public leaf libraries";
      print_endline "geometry dependency direction passed"
  | _ -> invalid_arg
      "dependency_direction: expected geometry and sketch leaf dune files"
