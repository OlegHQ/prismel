let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let require condition message = if not condition then failwith message

let configuration : Ogpu.Surface.configuration =
  {logical_width=64; logical_height=64; physical_width=64; physical_height=64;
   format=Rgba8_unorm; present_mode=Immediate; max_acquired=2;layer=None}

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
  let driver,live_handles=Ogpu.Impl.create_driver () in
  let before=live_handles () in
  match Scene_execution_fixtures.create_offscreen driver configuration with
  | Error { Ogpu.Error.kind = No_adapter; _ } ->
      print_endline "retained eviction: skipped (no device)"
  | Error error -> failwith (Ogpu.Error.to_string error)
  | Ok renderer ->
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
     | Some _ -> failwith "replay skipped");
    require (Scene_execution.cache_entries renderer<=256) "mesh cache overflow";
    if frame mod 10=0 then Gc.full_major ()
  done;
  (* Automatic admission must obey the same resource lifetime rule. *)
  for _=1 to 4 do
    ignore (get (Scene_execution.render_sampled_resources renderer draws))
  done;
  let retained=Scene_execution.retained_stats renderer in
  require (retained.plan_entries<=2) "retained plans exceeded their two slots";
  get (Scene_execution.destroy renderer);
  let after=live_handles () in
  require (after=before) (Printf.sprintf "%s leaked handles %d -> %d" name before after)

let run () =
  run "plain-300" 300 (fun index ->
    {Scene_execution.family=Scene2; blend=Ogpu.Pipeline.Replace; texture=None;
     auxiliary=None; samples=1;
     draw={mesh=mesh index; state={state with scissor=(index mod 2,0,63,64)}}});
  run "textured-300" 300 (fun index ->
    {Scene_execution.family=Scene2_textured; blend=Ogpu.Pipeline.Replace;
     texture=Some (texture index); auxiliary=None; samples=1;
     draw={mesh=mesh index; state}});
  print_endline "retained eviction: prepared/automatic replays survive mesh and texture eviction, zero delta"
