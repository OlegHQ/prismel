type error =
  | Scene of Scene_raster2_lowering.error
  | Backend of Ogpu.Error.t
  | Unsupported_resource
  | Destroyed

type prepared = {
  key : string;
  bytes : int64;
  buffer : Ogpu.Backend.buffer;
}

type t = {
  device : Ogpu.Backend.device;
  queue : Ogpu.Backend.queue;
  mutable surface : Ogpu.Backend.surface;
  mutable target : Ogpu.Backend.texture;
  pipeline : Ogpu.Backend.pipeline;
  command : Ogpu.Backend.command;
  mutable meshes : prepared list;
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

let render value scene =
  if value.destroyed then Error Destroyed else
  match Scene_raster2_lowering.lower scene with
  | Error (Unsupported _) -> Error Unsupported_resource
  | Error error -> Error (Scene error)
  | Ok ir ->
      Result.bind (prepare value ir) (fun buffers ->
      Result.bind (backend (Ogpu.Backend.acquire value.surface)) (function
      | `Timeout | `Occluded -> Ok false
      | `Device_lost -> Error (Backend (Ogpu.Error.make
          "Scene_ogpu_renderer.render" Device_lost "device lost"))
      | `Acquired frame ->
          match backend (Ogpu.Backend.submit value.queue value.command
              ~resources:(`Texture value.target :: List.map (fun item -> `Buffer item) buffers)
              ~pipelines:[value.pipeline]) with
          | Error error -> ignore (Ogpu.Backend.discard frame); Error error
          | Ok receipt ->
              Result.bind (backend (Ogpu.Backend.complete_through value.queue receipt.epoch))
                (fun () -> Result.map (fun () -> true)
                  (backend (Ogpu.Backend.present frame)))))

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
