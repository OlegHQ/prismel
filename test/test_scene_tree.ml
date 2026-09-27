(* The scene tree, window-free: the scene opens as a list; arrows move the
   focus, [i] and a double-click enter a geometry object or the World, [u]
   goes up; [Space a l] adds a light (in rename mode), Tab reparents keeping
   its world position, [h] hides; scene edits never re-cook SOPs; [Space e]
   creates and opens the World, which then bakes; [Space l] flips list and
   graph. *)
open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message

let frame ?(mouse = 450, 320) ?(events = []) ?(keys = []) ?(buttons = []) count : Frame.t = {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = float_of_int count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse = (let x, y = mouse in float x, float y);
  mouse_delta = 0., 0.; keys; mouse_buttons = buttons; events;
}

module E = Prismel_editor.Editor3

let run () =
  let cooks = Atomic.make 0 in
  let graph = Sop.box ~label:"box" ~size:(Vec3.create 1. 1. 1.) () in
  let env = E.create ~graph ~factories:Sop_catalog.Editor.factories
      ~lens:{ aperture = 0.3; focus_distance = None }
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun _ output -> Atomic.incr cooks;
        Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [Scene3.mesh mesh]) () |> Result.get_ok in
  let count = ref 0 in
  let step ?mouse ?keys ?buttons env events =
    incr count; E.update env (frame ?mouse ?keys ?buttons ~events !count) in
  let key k = Event.KeyPressed k and char c = Event.KeyPressed (Input.KeyChar c) in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec settle env =
    let env = step env [] in
    if E.prepared env <> None && Atomic.get cooks > 0 then env
    else if Unix.gettimeofday () < deadline then (Unix.sleepf 0.001; settle env)
    else fail "the scene did not cook geo1" in
  let env = settle env in
  let gx, gy, _, _ = (E.panes env (frame 0)).graph in
  (* Focus the graph pane (the list), then walk the rows. *)
  let in_list = gx + 40, gy + 400 in
  let env = step ~mouse:in_list env [Event.MousePressed (Input.LeftButton, (40., 1.));
    Event.MouseReleased (Input.LeftButton, (40., 1.))] in
  let env = step ~mouse:in_list env
      [Event.MousePressed (Input.LeftButton, (float (fst in_list), float (snd in_list)));
       Event.MouseReleased (Input.LeftButton, (float (fst in_list), float (snd in_list)))] in
  let label env = Option.map Node.label (E.selected_node env) in
  let rec select name env tries =
    if label env = Some name then env
    else if tries = 0 then fail ("no list row named " ^ name)
    else select name (step env [key Input.ArrowDown]) (tries - 1) in
  let env = select "camera1" env 6 in
  let camera = E.selected_node env |> Option.get |> Node.id in
  let env = step env [char 'm'] in
  check (Edit_graph.is_bypassed (E.document env) ~node_id:camera
      && Camera.lens (E.render_camera env) = Camera.lens (Easy_camera.camera (E.camera env)))
    "muted ACTIVE camera did not fall back to the viewport lens";
  let env = step ~keys:[Input.Meta] env [char 'z'] in
  check (not (Edit_graph.is_bypassed (E.document env) ~node_id:camera)
      && (Camera.lens (E.render_camera env)).aperture = 0.3)
    "undo did not restore the ACTIVE camera's lens and bypass flag";
  let env = step env [key Input.ArrowUp] in
  let env = select "geo1" env 6 in
  check (E.level env = None) "the editor did not open at the scene level";
  let env = step env [char 'i'] in
  check (E.level env = Some "geo1") "i did not enter the focused geometry object";
  check (E.document env |> Edit_graph.inspect |> List.exists (fun (info : Edit_graph.node_info) ->
      info.operation = "box")) "geo1's network is not the sketch's SOP graph";
  let env = step env [char 'u'] in
  check (E.level env = None) "u did not go back to the scene";
  let env = step env [] in  (* the list is hit-tested from the next frame *)
  (* A double-click on a list row enters it too. *)
  let row_y index = gy + 24 + (24 * index) + 12 in
  let rec row_of name index env =
    if index > 5 then fail (name ^ " row not found") else
    let point = gx + 60, row_y index in
    let click = [Event.MousePressed (Input.LeftButton, (float (fst point), float (snd point)));
      Event.MouseReleased (Input.LeftButton, (float (fst point), float (snd point)))] in
    let env = step ~mouse:point env click in
    if label env = Some name then env, point, click else row_of name (index + 1) env in
  let env, point, click = row_of "geo1" 0 env in
  let env = step ~mouse:point env click in
  check (E.level env = Some "geo1") "double-clicking the geo1 row did not enter it";
  let env = step env [char 'u'] in
  (* Space a opens the add menu; typing searches it, Enter adds a light,
     whose row opens in rename mode. *)
  let add env query =
    let env = step env [key Input.Space; char 'a'] in
    let env = step env [] in
    let env = step env [Event.TextInput query] in
    step env [key Input.Enter] in
  let lights_before = List.length (E.lights env) in
  let env = add env "light" in
  check (List.length (E.lights env) = lights_before + 1) "Space a + light did not add a light";
  let env = step env [] in
  let env = step env [Event.TextInput "key"; key Input.Enter] in

  let env = step env [] in
  check (label env = Some "key") "the new light row did not open in rename mode";
  let directory = Filename.temp_dir "prismel-scene-order" "" in
  let env = Fun.protect ~finally:(fun () ->
      Array.iter (fun file -> Sys.remove (Filename.concat directory file)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
    let snapshot env = E.crash_dump env directory;
      Yojson.Safe.from_file (Filename.concat directory "document.json") in
    let positions env = E.graph_nodes env |> List.map (fun tile ->
      tile.Pxui_graph.id, tile.bounds) in
    let before = snapshot env and at = positions env in
    let reordered = step ~keys:[Input.Alt] env [key Input.ArrowUp] in
    check (snapshot reordered <> before) "scene reorder did not save its positions";
    check (List.length (List.filter (fun (id, bounds) -> List.assoc id at <> bounds)
      (positions reordered)) = 2) "scene reorder did not swap exactly two siblings";
    let restored = step ~keys:[Input.Meta] reordered [char 'z'] in
    check (snapshot restored = before && positions restored = at)
      "scene reorder undo did not restore both saved positions";
    restored) in
  (* Scene edits never re-cook: reparent the light under geo1 with Tab. *)
  let cooked = Atomic.get cooks in
  let position env = match List.rev (E.lights env) with
    | { Light.kind = Area { position; _ }; _ } :: _ -> position
    | _ -> fail "the added light is not an area light" in
  let before = position env in
  let env = step env [key Input.ArrowUp] in
  let env = select "key" env 6 in
  let env = step ~keys:[] env [key Input.Tab] in
  let parent env = Edit_graph.inspect (E.scene_document env)
    |> List.find (fun (info : Edit_graph.node_info) -> info.label = "key")
    |> fun info -> info.inputs.(0) in
  check (parent env <> None) "Tab did not reparent the light under the row above";
  check (Vec3.nearly_equal (position env) before ~eps:1e-6)
    "reparenting moved the light in the world";
  let env = step ~keys:[Input.Shift] env [key Input.Tab] in
  check (parent env = None) "Shift-Tab did not move the light back to the scene root";
  let env = step env [char 'h'] in
  check (List.length (E.lights env) = lights_before) "h did not hide the light";
  let env = List.fold_left (fun env _ -> step env []) env [1; 2; 3; 4; 5] in
  check (Atomic.get cooks = cooked) "a scene-level edit re-cooked SOPs";
  (* Undo walks back through the scene edits. *)
  let undo env = step ~keys:[Input.Meta] env [char 'z'] in
  let env = undo env in
  check (List.length (E.lights env) = lights_before + 1) "undo did not show the light again";
  (* Nor does dragging an object transform slider in the inspector (undo
     itself re-cooks, so let that settle first): rows are 24 points and
     Translate X follows the node header, input source and folder. *)
  let env = List.fold_left (fun env _ -> Unix.sleepf 0.005; step env []) env (List.init 40 Fun.id) in
  let cooked = Atomic.get cooks in
  let rec select_up name env tries =
    if label env = Some name then env
    else if tries = 0 then fail ("no list row named " ^ name)
    else select_up name (step env [key Input.ArrowUp]) (tries - 1) in
  let env = select_up "geo1" env 8 in
  let env = step env [] in
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | None -> ()
   | Some directory ->
       Sketch.export ~directory ~prefix:"scene-inspector" ~frames:1
         ~config:{Sketch.default_config with width=900; height=640}
         (fun _ -> E.scene env (frame 0)));
  let ix, iy, iw, _ = (E.panes env (frame 0)).inspector in
  let slider x = ix + (iw * 70 / 100) + x, iy + 141 in
  let at (x, y) = float x, float y in
  let translate_x env = Option.bind (E.selected_node env) (fun node ->
      List.find_map (fun (field : Parameter.field_view) ->
        if field.name = "translate_x" then Some field.current else None)
        (Node.parameter_fields node)) in
  let before = translate_x env in
  let env = step ~mouse:(slider 0) ~buttons:[Input.LeftButton] env
      [Event.MousePressed (Input.LeftButton, at (slider 0))] in
  let env = List.fold_left (fun env x -> step ~mouse:(slider x) ~buttons:[Input.LeftButton] env [])
      env [4; 8; 12; 16] in
  let env = step ~mouse:(slider 20) env [Event.MouseReleased (Input.LeftButton, at (slider 20))] in
  check (before <> None && translate_x env <> before)
    "dragging the Translate X slider did not edit geo1";
  check (List.map fst (E.objects env) <> [Mat4.identity]) "the transform did not reach objects";
  let env = List.fold_left (fun env _ -> Unix.sleepf 0.005; step env []) env (List.init 20 Fun.id) in
  check (Atomic.get cooks = cooked) "an object transform edit re-cooked SOPs";
  let env = step ~mouse:in_list env
      [Event.MousePressed (Input.LeftButton, (float (fst in_list), float (snd in_list)));
       Event.MouseReleased (Input.LeftButton, (float (fst in_list), float (snd in_list)))] in
  (* Space e creates the World and opens its layers; it bakes. *)
  let env = step env [key Input.Space; char 'e'] in
  check (E.level env = Some "world") "Space e did not open the World";
  let env = step env [] in
  check (E.world env <> None) "the World did not bake";
  let layers env = List.length (Edit_graph.inspect (E.document env)) in
  let before = layers env in
  let env = add env "shape" in
  check (layers env = before + 1) "Space a + shape did not add a shape layer";
  let env = step env [] in
  let env = step env [Event.TextInput "softbox"; key Input.Enter] in
  let selected = E.selected_node env |> Option.get |> Node.id in
  let parameters env id =
    Edit_graph.find (E.document env) ~node_id:id |> Option.get |> Node.parameter_fields
    |> List.map (fun (field : Parameter.field_view) -> field.name, field.current) in
  let original = parameters env selected in
  let others = Edit_graph.inspect (E.document env)
    |> List.filter (fun (info : Edit_graph.node_info) -> info.id <> selected)
    |> List.map (fun (info : Edit_graph.node_info) -> info.id, parameters env info.id) in
  let press = 100., 300. and release = 800., 1000. in
  let camera = E.camera env in
  let env = step ~mouse:(100, 300) ~buttons:[Input.LeftButton] env
      [Event.MousePressed (Input.LeftButton, press)] in
  let env = step ~mouse:(800, 1000) ~buttons:[Input.LeftButton] env
      [Event.MouseMoved release] in
  let moved = parameters env selected in
  check (moved <> original && List.assoc "elevation" moved = Parameter.Float_value (-90.))
    "captured map-layer movement did not clamp outside the map";
  check (List.for_all (fun (id, values) -> parameters env id = values) others)
    "a map-layer gesture edited another stable node";
  let env = step ~mouse:(800, 1000) env [Event.MouseReleased (Input.LeftButton, release)] in
  check (Camera.position (Easy_camera.camera (E.camera env))
      = Camera.position (Easy_camera.camera camera))
    "map-layer movement also navigated the 3D camera";
  let env = step ~keys:[Input.Meta] env [char 'z'] in
  check (parameters env selected = original) "map-layer drag did not undo in one entry";
  let env = step ~mouse:in_list env
      [Event.MousePressed (Input.LeftButton, (float (fst in_list), float (snd in_list)));
       Event.MouseReleased (Input.LeftButton, (float (fst in_list), float (snd in_list)))] in
  let env = select "softbox" env 16 in
  (* World keys: t flips the selected emitter to a real light, ] moves the
     time of day, 3 loads the white room preset. *)
  let env = step env [char 't'] in
  let env = step env [] in
  check (match E.world env with Some baked -> baked.World.lights <> [] | None -> false)
    "t did not promote the selected shape to a light";
  let lit = parameters env selected in
  let env = step env [char 'm'] |> fun env -> step env [] in
  check (Edit_graph.is_bypassed (E.document env) ~node_id:selected
      && parameters env selected = lit
      && match E.world env with Some baked -> baked.World.lights = [] | None -> false)
    "mute did not suppress a World layer without overwriting its literals";
  let env = step env [char 'm'] |> fun env -> step env [] in
  check (match E.world env with Some baked -> baked.World.lights <> [] | None -> false)
    "unmuting a World layer did not restore its contribution";
  let env = add env "scatter" |> fun env -> step env [] in
  let env = step env [Event.TextInput "constellation"; key Input.Enter] in
  let scatter = E.selected_node env |> Option.get |> Node.id in
  let seed env = List.assoc "seed" (parameters env scatter) in
  let before = seed env in
  let env = step env [char 'n'] in
  check (match before, seed env with Int_value a, Int_value b -> b=a+1 | _ -> false)
    "World n did not reseed the selected scatter layer";
  let env = step env [char 'd'] in
  let day_cycle env = List.find_map (fun (info : Edit_graph.node_info) ->
    if info.operation <> "world" then None else List.find_map (fun (field : Parameter.field_view) ->
      if field.name = "day_cycle" then Some field.current else None)
      (Node.parameter_fields info.node)) (Edit_graph.inspect (E.scene_document env)) |> Option.get in
  check (day_cycle env = Float_value 1.) "World d did not start its day cycle";
  let hours env = List.find_map (fun (info : Edit_graph.node_info) ->
      if info.operation <> "world" then None
      else List.find_map (fun (field : Parameter.field_view) ->
        match field.name, field.current with
        | "time_of_day", Parameter.Float_value hours -> Some hours
        | _ -> None) (Node.parameter_fields info.node))
      (Edit_graph.inspect (E.scene_document env)) |> Option.get in
  let before = hours env in
  let env = step env [char ']'] in
  check (Float.abs (hours env -. before -. 0.5) < 1e-9) "] did not step the time of day";
  let env = step env [char '3'] in
  check (List.exists (fun (info : Edit_graph.node_info) -> info.operation = "room")
      (Edit_graph.inspect (E.document env))) "3 did not load the white room preset";
  let env = step env [char 'u'] in
  check (E.level env = None) "u did not leave the World";
  let saved = E.document env and baked = E.world env in
  let env = step env [char 't'; char 'n'; char 'd'] in
  check (E.document env == saved && E.world env = baked) "World keys edited the scene level";
  (* Space l flips the scene between list and graph. *)
  let env = step env [key Input.Space; char 'l'] in
  let env = step env [] in
  let tile = List.find (fun (tile : Pxui_graph.node_view) -> tile.label = "geo1")
      (E.graph_nodes env) in
  let x, y, w, h = tile.bounds in
  let point = x + (w / 3), y + (h / 2) in
  let click = [Event.MousePressed (Input.LeftButton, (float (fst point), float (snd point)));
    Event.MouseReleased (Input.LeftButton, (float (fst point), float (snd point)))] in
  let env = step ~mouse:point env [] in
  let env = step ~mouse:point env click in
  let env = step ~mouse:point env click in
  check (E.level env = Some "geo1") "double-clicking the geo1 tile did not enter it";
  (* Deleting a network's display node never leaves a dangling display:
     delete geo1 from the scene, flip the projection, and come back. *)
  let env = step env [char 'u'] in
  let env = step env [key Input.Space; char 'l'] in
  let env = step env [] in
  let env = select "geo1" env 8 in
  let env = step env [key Input.Delete] in
  let env = step env [key Input.Space; char 'l'] in
  let env = step env [key Input.Space; char 'l'] in
  let env = step env [key Input.Space; char 'e'] in
  let env = step env [char 'u'] in
  check (E.level env = None) "the scene broke after deleting its display object";
  (* The list's right-click menu enters the row under the pointer. *)
  let env = step env [] in
  let env, point, _ = row_of "world" 0 env in
  let fx, fy = float (fst point), float (snd point) in
  let env = step ~mouse:point env [Event.MousePressed (Input.RightButton, (fx, fy));
    Event.MouseReleased (Input.RightButton, (fx, fy))] in
  let env = step ~mouse:point env [] in
  let item = fst point + 20, snd point + 3 + 12 in
  let ix, iy = float (fst item), float (snd item) in
  let env = step ~mouse:item env [] in
  let env = step ~mouse:item env [Event.MousePressed (Input.LeftButton, (ix, iy));
    Event.MouseReleased (Input.LeftButton, (ix, iy))] in
  check (E.level env = Some "world") "the list's right-click Enter did not open the World";
  E.close env;
  (* Every object cooks the same bytes with one domain and with many. *)
  let digest domains =
    let graph = Sop_catalog.Mountain.create ~seed:3 ~height:0.4
        ~frequency:(Vec3.create 1. 1. 1.) ~octaves:3 ~lacunarity:2. ~roughness:0.5
        ~recompute_normals:true
        (Sop_catalog.Grid.create ~columns:40 ~rows:40 ~size:4. ()) in
    let env = E.create ~graph ~domains ~grain:16 ~max_entries:4
        ~max_payload_bytes:(16 * 1024 * 1024)
        ~prepare:(fun _ output ->
          let points = Pdk.Geometry.positions output.Session.geometry in
          Ok (Digest.string (String.concat "," (List.init (Pdk.Packed.Float3.length points)
            (fun index -> let x, y, z = Pdk.Packed.Float3.get points index in
              Printf.sprintf "%h %h %h" x y z)))))
        ~scene3:(fun _ _ -> Scene3.create []) () |> Result.get_ok in
    let deadline = Unix.gettimeofday () +. 5. in
    let rec wait count env = let env = E.update env (frame count) in
      match E.prepared env with
      | Some digest -> E.close env; digest
      | None when Unix.gettimeofday () < deadline -> Unix.sleepf 0.001; wait (count + 1) env
      | None -> fail "the domain-count cook did not finish" in
    wait 0 env in
  check (digest 1 = digest 4) "one domain and four domains cooked different geometry";
  print_endline "scene tree: list keys, enter/up, lights, reparent, World, graph, domains ok"
