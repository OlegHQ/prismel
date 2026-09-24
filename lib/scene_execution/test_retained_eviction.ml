let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let require condition message = if not condition then failwith message

let configuration : Ogpu.Surface.configuration =
  {logical_width=64; logical_height=64; physical_width=64; physical_height=64;
   format=Rgba8_unorm; present_mode=Immediate; max_acquired=2}

let state : Scene_execution.state =
  {viewport=(0,0,64,64); scissor=(0,0,64,64); cull=Cull_none;
   depth_compare=Always; depth_write=false; depth_load=Load; depth_clear=1.;
   transform_uniforms=None; stencil_state=None; stencil_load=Load; stencil_clear=0}

let mesh index : Scene_execution.mesh =
  let indices=Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
  {key=Printf.sprintf "eviction-%d" index; vertices=Bytes.make 48 '\000';
   vertex_count=3; indices; index_count=3; primitive=Ogpu.Render_pass.Triangle_list}

let texture index : Scene_execution.sampled_texture =
  {key=Printf.sprintf "eviction-texture-%d" index;
   levels=[|{width=1; height=1; bytes=Bytes.of_string "\xff\xff\xff\xff"}|];
   sampler={label=None; min_filter=Nearest; mag_filter=Nearest; mip_filter=No_mip;
     address_u=Clamp_to_edge; address_v=Clamp_to_edge; lod_min=0.; lod_max=0.;
     max_anisotropy=1};gpu=None}

let run name count entry =
  let driver,control=Ogpu.Backend_mock.create () in
  let renderer=get (Scene_execution.create_variants driver configuration) in
  let draws=List.init count entry in
  (* First render succeeds even when resources are evicted during preparation:
     their destruction waits for completion. The next retained replay must not
     submit those now-dead resources. Exercise both prepared entry points. *)
  for frame=1 to 60 do
    ignore (get (Scene_execution.render_prepared_sampled_resources
      ~identity:name ~version:1L renderer draws));
    (match get (Scene_execution.replay_prepared_sampled_resources
        ~identity:name ~version:1L renderer) with
     | None -> ignore (get (Scene_execution.render_prepared_sampled_resources
         ~identity:name ~version:1L renderer draws))
     | Some (true,actual) -> require (actual=count) "replay draw count"
     | Some _ -> failwith "mock replay skipped");
    require (Scene_execution.cache_entries renderer<=256) "mesh cache overflow";
    let buffers,textures,_,_,_=Ogpu.Backend_mock.live_counts control in
    require (buffers<=321 && textures<=258) "resource caches exceeded their bounds";
    if frame mod 10=0 then Gc.full_major ();
    Ogpu.Backend_mock.clear_trace control
  done;
  (* Automatic admission must obey the same resource lifetime rule. *)
  for _=1 to 4 do
    ignore (get (Scene_execution.render_sampled_resources renderer draws))
  done;
  Ogpu.Backend_mock.fail_next_submission control;
  (match Scene_execution.render_prepared_sampled_resources
      ~identity:name ~version:2L renderer draws with
   |Error _ -> () |Ok _ -> failwith "injected submission failure was ignored");
  require (get (Scene_execution.replay_prepared_sampled_resources
    ~identity:name ~version:2L renderer)=None) "failed graph remained replayable";
  ignore (get (Scene_execution.render_prepared_sampled_resources
    ~identity:name ~version:2L renderer draws));
  get (Scene_execution.resize renderer configuration);
  ignore (get (Scene_execution.render_prepared_sampled_resources
    ~identity:name ~version:2L renderer draws));
  get (Scene_execution.destroy renderer);
  require (Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    (name ^ " leaked handles");
  Printf.printf "retained eviction: %s, %d draws, 60 frames, zero handle delta\n%!"
    name count

let run () =
  run "mesh-overflow" 257 (fun index ->
    Scene_execution.Scene2,
    (if index land 1=0 then Ogpu.Pipeline.Replace else Alpha),
    None,None,1,{Scene_execution.mesh=mesh index;state});
  run "texture-overflow" 257 (fun index ->
    Scene_execution.Scene2_textured,Ogpu.Pipeline.Replace,
    Some (texture index),None,1,{Scene_execution.mesh=mesh 0;state});
  run "auxiliary-overflow" 65 (fun index ->
    let auxiliary : Scene_execution.auxiliary_resource =
      {key=Printf.sprintf "auxiliary-%d" index;buffer=Bytes.make 16 '\000';
       texture=texture 0} in
    Scene_execution.Scene3_shadow,Ogpu.Pipeline.Replace,
    None,Some auxiliary,1,{Scene_execution.mesh=mesh 0;state})
