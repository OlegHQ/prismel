type error =
  | Scene of Scene_raster2_lowering.error
  | Scene3 of Scene3_raster2_lowering.error
  | Backend of Ogpu.Error.t
  | Unsupported_resource
  | Destroyed

type prepared = {
  key : string;
  bytes : int64;
  buffer : Ogpu.Backend.buffer;
}

type prepared3 = {
  mesh_key : string;
  vertex_buffer : Ogpu.Backend.buffer;
  index_buffer : Ogpu.Backend.buffer;
}

type draw_state = {
  viewport : int * int * int * int;
  scissor : int * int * int * int;
  cull : Raster2.Triangle.cull;
  blend : Raster2.Composite.blend;
  textured : bool;
  depth_clear : float;
}

type t = {
  device : Ogpu.Backend.device;
  queue : Ogpu.Backend.queue;
  mutable surface : Ogpu.Backend.surface;
  mutable target : Ogpu.Backend.texture;
  pipeline : Ogpu.Backend.pipeline;
  command : Ogpu.Backend.command;
  mutable meshes : prepared list;
  mutable meshes3 : prepared3 list;
  mutable textures3 : (string * Ogpu.Backend.texture) list;
  mutable draw_states : draw_state array;
  mutable upload_bytes : int64;
  mutable destroyed : bool;
  mutable configuration : Ogpu.Surface.configuration;
}

let backend = function Ok value -> Ok value | Error value -> Error (Backend value)

let shader stage name =
  Ogpu.Shader.create {
    backend = "mock"; label = Some name; bytes = Bytes.of_string name;
    entry_points = [{ Ogpu.Shader.name; stage }]; bindings = [];
  }

let portable_pipeline device =
  let capabilities = Ogpu.Backend.capabilities device in
  let handle = Ogpu.Backend.device_handle device in
  Result.bind (backend (Ogpu.Binding.create_pipeline_layout ~device:handle
    ~capabilities [])) (fun layout ->
  Result.bind (backend (shader Ogpu.Shader.Compute "scene_main")) (fun shader ->
  Result.bind (backend (Ogpu.Pipeline.create_compute capabilities {
    backend = "mock"; label = Some "prismel-scene"; layout; shader;
    entry = "scene_main";
  })) (fun portable ->
  Result.bind (backend (Ogpu.Backend.adopt_pipeline device portable)) (fun pipeline ->
  Result.bind (backend (Ogpu.Compute_pass.create handle
    ~limits:capabilities.limits ~pipeline:portable ~layout ~groups:[||]
    ~resources:[||] ~dispatch:(Direct { x = 1; y = 1; z = 1 })))
    (fun pass -> Ok (pipeline, Ogpu.Backend.compute pass))))))

let texture_descriptor configuration : Ogpu.Types.texture_descriptor = {
  label = Some "prismel-scene-target";
  width = configuration.Ogpu.Surface.physical_width;
  height = configuration.physical_height; depth = 1; mip_levels = 1;
  sample_count = 1; usage = [Render_attachment; Texture_copy_src];
}

let create driver configuration =
  Result.bind (backend (Ogpu.Backend.create_device driver)) (fun device ->
  let fail value = ignore (Ogpu.Backend.destroy_device device); Error value in
  match backend (Ogpu.Backend.create_queue device) with
  | Error error -> fail error
  | Ok queue ->
      begin match backend (Ogpu.Backend.create_surface device configuration) with
      | Error error -> ignore (Ogpu.Backend.destroy_queue queue); fail error
      | Ok surface ->
          begin match backend (Ogpu.Backend.create_texture device
              (texture_descriptor configuration)), portable_pipeline device with
          | Ok target, Ok (pipeline, command) -> Ok {
              device; queue; surface; target; pipeline; command; meshes = [];
              meshes3 = []; textures3 = []; draw_states = [||];
              upload_bytes = 0L; destroyed = false; configuration;
            }
          | target_result, pipeline_result ->
              begin match target_result with
              | Ok target -> ignore (Ogpu.Backend.destroy_texture target)
              | Error _ -> ()
              end;
              begin match pipeline_result with
              | Ok (pipeline, _) -> ignore (Ogpu.Backend.destroy_pipeline pipeline)
              | Error _ -> ()
              end;
              ignore (Ogpu.Backend.destroy_surface surface);
              ignore (Ogpu.Backend.destroy_queue queue);
              fail (match target_result, pipeline_result with
                | Error error, _ | _, Error error -> error
                | _ -> assert false)
          end
      end)

let geometry_key (value : Raster2.Render_ir.geometry) =
  Digest.to_hex (Digest.string (Marshal.to_string
    (value.vertices, value.indices, value.color) []))

let geometry_bytes (value : Raster2.Render_ir.geometry) =
  Int64.of_int ((Array.length value.vertices * 8) + (Array.length value.indices * 4))

let prepare value ir =
  let geometries = Raster2.Render_ir.commands ir |> Array.to_list
    |> List.filter_map (function Raster2.Render_ir.Geometry item -> Some item | _ -> None) in
  let rec loop resources = function
    | [] -> Ok (List.rev resources)
    | geometry :: rest ->
        let key = geometry_key geometry in
        begin match List.find_opt (fun item -> item.key = key) value.meshes with
        | Some item -> loop (item.buffer :: resources) rest
        | None ->
            let bytes = geometry_bytes geometry in
            let descriptor : Ogpu.Types.buffer_descriptor = {
              label = Some ("scene-mesh-" ^ key); size = max 1L bytes;
              usage = [Vertex; Index; Copy_dst];
            } in
            Result.bind (backend (Ogpu.Backend.create_buffer value.device descriptor))
              (fun buffer ->
                value.meshes <- { key; bytes; buffer } :: value.meshes;
                value.upload_bytes <- Int64.add value.upload_bytes bytes;
                loop (buffer :: resources) rest)
        end
  in
  loop [] geometries

let scene3_mesh_key (draw : Raster2.Scene3_consumer.draw) =
  Digest.to_hex (Digest.string (Marshal.to_string
    (Array.map (fun (item : Raster2.Scene3_consumer.vertex) ->
       item.position, item.normal, item.color, item.u, item.v) draw.vertices,
     draw.indices) []))

let create_mesh3 value (draw : Raster2.Scene3_consumer.draw) =
  let mesh_key = scene3_mesh_key draw in
  match List.find_opt (fun item -> item.mesh_key = mesh_key) value.meshes3 with
  | Some item -> Ok item
  | None ->
      let vertex_bytes = Int64.of_int (Array.length draw.vertices * 48) in
      let index_bytes = Int64.of_int (Array.length draw.indices * 4) in
      let descriptor label size usage : Ogpu.Types.buffer_descriptor =
        { label = Some (label ^ mesh_key); size = max 1L size;
          usage = [usage; Copy_dst] }
      in
      Result.bind (backend (Ogpu.Backend.create_buffer value.device
        (descriptor "scene3-vertices-" vertex_bytes Vertex))) (fun vertex_buffer ->
      match backend (Ogpu.Backend.create_buffer value.device
          (descriptor "scene3-indices-" index_bytes Index)) with
      | Error error -> ignore (Ogpu.Backend.destroy_buffer vertex_buffer); Error error
      | Ok index_buffer ->
          let item = { mesh_key; vertex_buffer; index_buffer } in
          value.meshes3 <- item :: value.meshes3;
          value.upload_bytes <- Int64.add value.upload_bytes
            (Int64.add vertex_bytes index_bytes);
          Ok item)

let texture3 value (texture : Raster2.Triangle.texture) =
  let width = Raster2.Surface.width texture.surface
  and height = Raster2.Surface.height texture.surface in
  let key = Printf.sprintf "%dx%d:%d" width height
    (match texture.filter with Raster2.Image.Nearest -> 0 | Bilinear -> 1) in
  match List.assoc_opt key value.textures3 with
  | Some item -> Ok item
  | None ->
      let descriptor : Ogpu.Types.texture_descriptor = {
        label = Some ("scene3-texture-" ^ key); width; height; depth = 1;
        mip_levels = 1; sample_count = 1;
        usage = [Texture_binding; Texture_copy_dst];
      } in
      Result.map (fun item -> value.textures3 <- (key, item) :: value.textures3; item)
        (backend (Ogpu.Backend.create_texture value.device descriptor))

let default_scene3_resources = {
  Scene3_raster2_lowering.texture = (fun _ -> Error Texture_error);
  shadow = (fun _ -> Error Shadow_error);
}

let prepare_scene3 value resources node =
  let viewport = (0, 0, value.configuration.physical_width,
    value.configuration.physical_height) in
  match Scene3_raster2_lowering.lower_view3d ~resources
      ~default_viewport:viewport node with
  | Error error -> Error (Scene3 error)
  | Ok prepared ->
      let buffers = ref [] and textures = ref [] and states = ref []
      and failure = ref None in
      Array.iter (fun (draw : Raster2.Scene3_consumer.draw) ->
        if !failure = None then match create_mesh3 value draw with
        | Error error -> failure := Some error
        | Ok mesh ->
            buffers := mesh.vertex_buffer :: mesh.index_buffer :: !buffers;
            begin match draw.texture with
            | None -> ()
            | Some texture -> begin match texture3 value texture with
                | Ok item -> textures := item :: !textures
                | Error error -> failure := Some error
                end
            end;
            states := { viewport = (int_of_float draw.viewport.x,
                int_of_float draw.viewport.y, int_of_float draw.viewport.width,
                int_of_float draw.viewport.height);
              scissor = (draw.scissor.x, draw.scissor.y, draw.scissor.width,
                draw.scissor.height); cull = draw.cull; blend = draw.blend;
              textured = Option.is_some draw.texture;
              depth_clear = prepared.clear_depth } :: !states)
        prepared.draws;
      match !failure with Some error -> Error error | None ->
        Ok (List.rev !buffers, List.rev !textures, List.rev !states)

let render_with_scene3 value scene3_resources scene =
  if value.destroyed then Error Destroyed else
  let scene2 = List.filter (function Scene_description.View3d _ -> false | _ -> true) scene
  and scene3 = List.filter (function Scene_description.View3d _ -> true | _ -> false) scene in
  match Scene_raster2_lowering.lower scene2 with
  | Error (Unsupported _) -> Error Unsupported_resource
  | Error error -> Error (Scene error)
  | Ok ir ->
      Result.bind (prepare value ir) (fun buffers2 ->
      let rec prepare3 buffers textures states = function
        | [] -> Ok (buffers, textures, states)
        | node :: rest -> Result.bind (prepare_scene3 value scene3_resources node)
            (fun (more_buffers, more_textures, more_states) ->
              prepare3 (List.rev_append more_buffers buffers)
                (List.rev_append more_textures textures)
                (List.rev_append more_states states) rest)
      in
      Result.bind (prepare3 [] [] [] scene3) (fun (buffers3, textures3, states) ->
      value.draw_states <- Array.of_list (List.rev states);
      Result.bind (backend (Ogpu.Backend.acquire value.surface)) (function
      | `Timeout | `Occluded -> Ok false
      | `Device_lost -> Error (Backend (Ogpu.Error.make
          "Scene_ogpu_renderer.render" Device_lost "device lost"))
      | `Acquired frame ->
          match backend (Ogpu.Backend.submit value.queue value.command
              ~resources:(`Texture value.target ::
                List.map (fun item -> `Buffer item) (buffers2 @ buffers3) @
                List.map (fun item -> `Texture item) textures3)
              ~pipelines:[value.pipeline]) with
          | Error error -> ignore (Ogpu.Backend.discard frame); Error error
          | Ok receipt ->
              Result.bind (backend (Ogpu.Backend.complete_through value.queue receipt.epoch))
                (fun () -> Result.map (fun () -> true)
                  (backend (Ogpu.Backend.present frame))))))

let render value scene = render_with_scene3 value default_scene3_resources scene

let resize value configuration =
  if value.destroyed then Error Destroyed else
  Result.bind (backend (Ogpu.Backend.create_texture value.device
    (texture_descriptor configuration))) (fun replacement ->
  match backend (Ogpu.Backend.configure value.surface configuration) with
  | Error error -> ignore (Ogpu.Backend.destroy_texture replacement); Error error
  | Ok () ->
      let previous = value.target in
      value.target <- replacement; value.configuration <- configuration;
      backend (Ogpu.Backend.destroy_texture previous))

let upload_bytes value = value.upload_bytes

let destroy value =
  if value.destroyed then Ok () else begin
    value.destroyed <- true;
    let first = ref None in
    let take result = match result, !first with Error error, None -> first := Some error | _ -> () in
    List.iter (fun item -> take (backend (Ogpu.Backend.destroy_buffer item.buffer))) value.meshes;
    List.iter (fun item ->
      take (backend (Ogpu.Backend.destroy_buffer item.vertex_buffer));
      take (backend (Ogpu.Backend.destroy_buffer item.index_buffer))) value.meshes3;
    List.iter (fun (_, item) -> take (backend (Ogpu.Backend.destroy_texture item)))
      value.textures3;
    take (backend (Ogpu.Backend.destroy_texture value.target));
    take (backend (Ogpu.Backend.destroy_pipeline value.pipeline));
    take (backend (Ogpu.Backend.destroy_surface value.surface));
    take (backend (Ogpu.Backend.destroy_queue value.queue));
    take (backend (Ogpu.Backend.destroy_device value.device));
    match !first with None -> Ok () | Some error -> Error error
  end

let self_test () =
  let get = function Ok value -> value | Error _ -> failwith "OGPU renderer fixture" in
  let configuration : Ogpu.Surface.configuration = {
    logical_width = 16; logical_height = 16; physical_width = 16;
    physical_height = 16; format = Rgba8_unorm; present_mode = Fifo;
    max_acquired = 2;
  } in
  let run () =
    let driver, control = Ogpu.Backend_mock.create () in
    let renderer = get (create driver configuration) in
    let style : Scene_description.style = { fill = Some Color.white; stroke = None } in
    let scene = [Scene_description.Clear Color.black;
      Triangle ((1, 1), (8, 1), (4, 8), style)] in
    ignore (get (render renderer scene));
    let first = upload_bytes renderer in
    if first <= 0L then failwith "first mesh was not uploaded";
    for _frame = 2 to 600 do ignore (get (render renderer scene)) done;
    if upload_bytes renderer <> first then failwith "stable mesh was reuploaded";
    let mesh = Mesh.create_exn ~normals:[Vec3.unit_z; Vec3.unit_z; Vec3.unit_z]
      [Vec3.create (-0.5) (-0.5) 0.; Vec3.create 0.5 (-0.5) 0.;
       Vec3.create 0. 0.5 0.] in
    let material = Material.unlit Color.red in
    let texture_surface = get (match Raster2.Surface.create ~width:2 ~height:2 () with
      | Ok item -> Ok item | Error _ -> Error Unsupported_resource) in
    let resources = { default_scene3_resources with
      Scene3_raster2_lowering.texture = (fun _ -> Ok {
        Raster2.Triangle.surface = texture_surface; filter = Raster2.Image.Nearest }) }
    in
    let scene3 frame =
      let camera = Camera.orthographic ~height:2.
        ~at:(Vec3.create (float frame *. 0.001) 0. 2.) ~target:Vec3.zero () in
      let colored = Scene3.mesh ~material ~cull:Scene3.Cull_back mesh in
      let textured = Scene3.with_blend Scene3.Alpha
        [Scene3.mesh ~material ~texture:(Scene3.textured (Obj.magic 0)) mesh] in
      [Scene_description.View3d (camera, Scene3.create [colored; textured],
        Some (1, 2, 12, 10))]
    in
    ignore (get (render_with_scene3 renderer resources (scene3 1)));
    let scene3_first = upload_bytes renderer in
    if scene3_first <= first then failwith "Scene3 buffers were not uploaded";
    for frame = 2 to 600 do
      ignore (get (render_with_scene3 renderer resources (scene3 frame)))
    done;
    if upload_bytes renderer <> scene3_first then
      failwith "camera-only Scene3 frame replaced mesh buffers";
    if Array.length renderer.draw_states <> 2 ||
        not renderer.draw_states.(1).textured ||
        renderer.draw_states.(0).viewport <> (1, 2, 12, 10) then
      failwith "Scene3 portable state/order drift";
    let camera = Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero () in
    let unsupported = Scene3.create
      [Scene3.mesh ~material ~shader:(Obj.magic 0) mesh] in
    begin match render renderer
        [Scene_description.View3d (camera, unsupported, None)] with
    | Error (Scene3 Scene3_raster2_lowering.Unsupported_shader) -> ()
    | _ -> failwith "unsupported Scene3 shader was not explicit"
    end;
    let resized = { configuration with physical_width = 32; physical_height = 24 } in
    get (resize renderer resized); ignore (get (render renderer scene));
    begin match render renderer [Scene_description.Text ((0, 0), "x", None, 12)] with
    | Error Unsupported_resource -> () | _ -> failwith "resource node accepted"
    end;
    let trace = Ogpu.Backend_mock.trace control in
    get (destroy renderer);
    if Ogpu.Backend_mock.live_counts control <> (0, 0, 0, 0, 0) then
      failwith "OGPU renderer leaked";
    trace, first
  in
  let expected = run () in
  let workers = Array.init 4 (fun _ -> Domain.spawn run) in
  Array.iter (fun worker -> if Domain.join worker <> expected then
    failwith "OGPU renderer domain drift") workers;
  let driver, control = Ogpu.Backend_mock.create () in
  let renderer = get (create driver configuration) in
  Ogpu.Backend_mock.inject_device_loss control;
  begin match render renderer [Scene_description.Clear Color.black] with
  | Error (Backend error) when error.kind = Device_lost -> ()
  | _ -> failwith "device loss not surfaced"
  end;
  get (destroy renderer)

let () = match Sys.getenv_opt "PRISMEL_TEST_SCENE_OGPU_RENDERER" with
  | Some "1" -> self_test () | _ -> ()
