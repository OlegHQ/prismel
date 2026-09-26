let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let run () =
  let driver, live_handles = Ogpu.Impl.create_driver () in
  let before = live_handles () in
  let configuration : Ogpu.Surface.configuration =
    { logical_width=4; logical_height=4; physical_width=4;
      physical_height=4; format=Bgra8_unorm; present_mode=Fifo;
      max_acquired=1;layer=None }
  in
  match Scene_execution_fixtures.create_offscreen driver configuration with
  | Error { Ogpu.Error.kind = No_adapter; _ } ->
      print_endline "offscreen Metal execution: skipped (no device)"
  | Error error -> failwith (Ogpu.Error.to_string error)
  | Ok renderer ->
      if not(get(Scene_execution.render~clear:(0.125,0.25,0.5,1.)renderer[]))then
        failwith"layerless clear-only submission was skipped";
      let clear_pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
      if Bytes.sub clear_pixels 0 4<>Bytes.of_string"\x20\x40\x80\xff"then
        failwith"layerless clear-only pixel drift";
      let indices=Bytes.make 12 '\000' in
      Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
      let mesh : Scene_execution.mesh =
        {key="offscreen-fullscreen";vertices=Bytes.make 48 '\000';
         vertex_count=3;indices;index_count=3; primitive=Ogpu.Render_pass.Triangle_list}
      and state : Scene_execution.state =
        {viewport=(0,0,4,4);scissor=(0,0,4,4);
         cull=Ogpu.Render_pass.Cull_none;depth_compare=Always;
         depth_write=false;depth_load=Load;depth_clear=1.;
         transform_uniforms=None;stencil_state=None;stencil_load=Load;
         stencil_clear=0}
      in
      let expected = Bytes.of_string "\xff\xff\xff\xff" in
      for frame=1 to 600 do
        if not (get (Scene_execution.render renderer [{mesh;state}])) then
          failwith "layerless offscreen submission was skipped";
        if List.mem frame [1;2;60;600] then begin
          let pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16) in
          if Bytes.sub pixels 0 4 <> expected then
            failwith (Printf.sprintf "offscreen pixel drift at frame %d" frame)
        end
      done;
      let retained=Scene_execution.retained_stats renderer in
      if retained.plan_hits<590L||retained.plan_entries<>1 then
        failwith (Printf.sprintf "stable frames did not replay the retained plan: hits %Ld entries %d failures %Ld (%s)"
          retained.plan_hits retained.plan_entries retained.plan_failures
          (Option.value retained.plan_last_failure ~default:"none"));
      let uploaded=Scene_execution.upload_bytes renderer in
      if uploaded<=0L || Scene_execution.Private.cache_count_for_report renderer>2 then
        failwith "offscreen cache accounting is unbounded or empty";
      (* Distinct scissors prevent coalescing: this graph crosses the mesh
         cache limit and must rebuild after completion-time eviction. *)
      let dense=List.init 257 (fun index ->
        {Scene_execution.family=Scene2;blend=Ogpu.Pipeline.Replace;
         texture=None;auxiliary=None;samples=1;
         draw={mesh={mesh with key=Printf.sprintf "dense-%d" index};
           state={state with scissor=(index mod 2,0,3,4)}}}) in
      let expected_dense=ref None in
      for frame=1 to 60 do
        ignore (get (Scene_execution.render_prepared_sampled_resources
          ~identity:"dense-eviction" ~version:1L renderer dense));
        (match get (Scene_execution.replay_prepared_sampled_resources
            ~identity:"dense-eviction" ~version:1L renderer) with
         |None -> () |Some _ -> failwith "evicted native graph retained");
        if List.mem frame [1;2;60] then begin
          let pixels=get(Scene_execution.read_pixels renderer ~bytes_per_row:16) in
          (match !expected_dense with
           |None -> expected_dense:=Some (Bytes.copy pixels)
           |Some expected when Bytes.equal expected pixels -> ()
           |Some _ -> failwith "dense eviction native pixel drift")
        end;
        if Scene_execution.Private.cache_count_for_report renderer>256 then
          failwith "dense native cache overflow"
      done;
      let stats=Scene_execution.retained_stats renderer in
      if stats.plan_builds<>stats.plan_evictions then
        failwith (Printf.sprintf "indirect plans leaked: %Ld built, %Ld dropped" stats.plan_builds stats.plan_evictions);
      get (Scene_execution.destroy renderer);
      let after=live_handles () in
      if after<>before then
        failwith (Printf.sprintf "offscreen native live-handle delta %d -> %d" before after);
      print_endline
        "offscreen Metal execution: exact clear/frame1/2/60/600 + retained replay + 257-draw eviction, bounded, zero delta"
