open Prismel_next_api

let require condition message = if not condition then failwith message
let ok = function Ok value -> value | Error message -> failwith message

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let contains text needle =
  let rec loop offset =
    offset + String.length needle <= String.length text
    && (String.sub text offset (String.length needle) = needle || loop (offset + 1))
  in
  loop 0

let count text needle =
  let rec loop offset total =
    if offset + String.length needle > String.length text then total
    else if String.sub text offset (String.length needle) = needle then
      loop (offset + String.length needle) (total + 1)
    else loop (offset + 1) total
  in
  loop 0 0

let values source =
  String.split_on_char '\n' source
  |> List.filter_map (fun line ->
    let line = String.trim line in
    if String.starts_with ~prefix:"val " line then
      let rest = String.sub line 4 (String.length line - 4) in
      Some (String.sub rest 0 (String.index rest ' '))
    else None)

let test_coverage low app backend graphics window =
  let omissions =
    [ "Graphics.get_renderer"; "Window.get_window"; "Window.get_renderer";
      "Window.get_window_flags"; "Window.get_renderer_flags";
      "Window.with_gpu_context"; "Window.t.window"; "Window.t.renderer";
      "Window.t.renderer_context" ]
  in
  require (List.length omissions = 9) "Low omission allowlist";
  require (count low "val get_renderer :" = 1)
    "only typed Low.App.get_renderer may remain";
  require (count low "val get_window :" = 1)
    "only Low.App.get_window may remain";
  List.iter (fun name -> require (not (contains low ("val " ^ name ^ " :")))
    ("raw Window." ^ name ^ " escaped"))
    [ "get_window_flags"; "get_renderer_flags"; "with_gpu_context" ];
  List.iter
    (fun (module_name, legacy, removed) ->
      values legacy
      |> List.iter (fun name ->
        if not (List.mem name removed) then
          require (contains low ("val " ^ name ^ " :"))
            (module_name ^ "." ^ name ^ " missing")))
    [ "App", app, [];
      "Backend", backend, [];
      "Graphics", graphics, [ "get_renderer" ];
      "Window", window,
        [ "get_window"; "get_renderer"; "get_window_flags";
          "get_renderer_flags"; "with_gpu_context" ] ];
  require (contains low "val get_renderer : unit -> Window.t")
    "Low.App.get_renderer typed adaptation";
  require (contains low "val present : Window.t")
    "Low.Backend.present typed adaptation"

let test_behavior () =
  let window =
    ok (Low.Backend.start ~width:16 ~height:12 ~title:"low-next"
          ~resizable:false)
  in
  Low.Graphics.init window;
  Low.Graphics.clear Color.black;
  Low.Graphics.set_color Color.red;
  Low.Graphics.rect ~pos:(2, 2) ~w:8 ~h:6 ();
  Low.Graphics.push_matrix ();
  Low.Graphics.translate ~dx:1 ~dy:1;
  Low.Graphics.point ~x:0 ~y:0 ~color:Color.white ();
  Low.Graphics.pop_matrix ();
  ok (Low.Backend.present window ~logical_width:16 ~logical_height:12);
  require (Low.Window.size () = (16, 12)) "Low window facts";
  require (Low.App.get_renderer () == window) "typed renderer adaptation";
  Low.Backend.stop ();
  require (not (Low.Window.exists ())) "Low teardown"

let () =
  if Array.length Sys.argv <> 6 then failwith "expected Low comparison sources";
  test_coverage (read Sys.argv.(1)) (read Sys.argv.(2)) (read Sys.argv.(3))
    (read Sys.argv.(4)) (read Sys.argv.(5));
  test_behavior ();
  print_endline "Prismel next Low compatibility passed"
