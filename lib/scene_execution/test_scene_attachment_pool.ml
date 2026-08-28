let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)

let configuration width height : Ogpu.Surface.configuration =
  { logical_width=width; logical_height=height; physical_width=width;
    physical_height=height; format=Rgba8_unorm; present_mode=Fifo; max_acquired=2 }

let texture_count control =
  let _,textures,_,_,_ = Ogpu.Backend_mock.live_counts control in textures

let () =
  let driver,control = Ogpu.Backend_mock.create () in
  let device = get (Ogpu.Backend.create_device driver) in
  let pool = Scene_attachment_pool.create ~device ~configuration:(configuration 8 6)
      ~sample_counts:[1;4] in
  if texture_count control <> 0 then failwith "create eagerly allocated attachments";
  let color = get (Scene_attachment_pool.acquire pool Scene_attachment_pool.Color ~samples:1) in
  let color_again = get (Scene_attachment_pool.acquire pool Scene_attachment_pool.Color ~samples:1) in
  if Ogpu.Backend.texture_id color <> Ogpu.Backend.texture_id color_again then
    failwith "same attachment key did not reuse its exact handle";
  ignore (get (Scene_attachment_pool.acquire pool Scene_attachment_pool.Depth ~samples:4));
  ignore (get (Scene_attachment_pool.acquire pool Scene_attachment_pool.Stencil ~samples:4));
  if texture_count control <> 3 then failwith "unexpected attachment count";
  begin match Scene_attachment_pool.acquire pool Scene_attachment_pool.Color ~samples:2 with
  | Error error when error.Ogpu.Error.kind=Invalid_argument -> ()
  | _ -> failwith "unsupported sample count was accepted"
  end;
  let old = Scene_attachment_pool.allocated pool in
  ignore (get (Scene_attachment_pool.resize pool (configuration 16 12)));
  let resized = Scene_attachment_pool.allocated pool in
  if List.length resized <> 3 || List.exists (fun (_,_,id) ->
      List.exists (fun (_,_,old_id) -> id=old_id) old) resized then
    failwith "resize did not replace exactly the allocated attachments";
  if texture_count control <> 3 then failwith "resize leaked old attachments";
  Ogpu.Backend_mock.fail_depth_allocation_after control 0;
  let before_failure = Scene_attachment_pool.allocated pool in
  begin match Scene_attachment_pool.resize pool (configuration 32 24) with
  | Error _ -> () | Ok () -> failwith "injected resize failure succeeded"
  end;
  if Scene_attachment_pool.allocated pool <> before_failure || texture_count control <> 3 then
    failwith "failed resize did not preserve the old pool transactionally";
  Scene_attachment_pool.destroy pool;
  Scene_attachment_pool.destroy pool;
  if texture_count control <> 0 then failwith "destroy leaked attachments";
  begin match Scene_attachment_pool.acquire pool Scene_attachment_pool.Color ~samples:1 with
  | Error _ -> () | Ok _ -> failwith "destroyed pool allowed acquisition"
  end;
  ignore (get (Ogpu.Backend.destroy_device device));
  if Ogpu.Backend_mock.live_counts control <> (0,0,0,0,0) then
    failwith "attachment pool test leaked backend objects"
