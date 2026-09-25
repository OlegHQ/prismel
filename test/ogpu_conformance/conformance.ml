let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let require condition message = if not condition then failwith message

let run ?metallib driver =
  let open Ogpu in
  let device = get (Backend.create_device driver) in
  let capabilities = Backend.capabilities device in
  let profile = get (Caps.create capabilities ~timestamp_queries:false
    ~sparse_memory:false ~conservative_limits:[]) in
  require (Caps.has profile Caps.Ray_tracing = capabilities.ray_tracing)
    "ray-tracing capability mismatch";
  (match Caps.require profile (Caps.Unknown "future") with
   | Error { Error.kind = Unsupported; _ } -> ()
   | _ -> failwith "unknown feature was not typed Unsupported");
  if not (Caps.has profile Caps.Compute_pipeline) then
    (match Caps.require profile Caps.Compute_pipeline with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unavailable compute was not typed Unsupported");
  let descriptor : Types.buffer_descriptor =
    { label = Some "conformance"; size = 16L; usage = [Copy_src; Copy_dst] } in
  let source = get (Backend.create_buffer device descriptor) in
  let destination = get (Backend.create_buffer device descriptor) in
  let queue = get (Backend.create_queue device) in
  require (Command_buffer.completed_epoch queue = 0L)
    "new queue completed an epoch";
  (match Backend.poll_through queue 0L with
   | Error { Error.kind = Invalid_argument; _ } -> ()
   | _ -> failwith "zero completion epoch was accepted");
  let bytes = Bytes.init 16 (fun i -> Char.chr (i * 13 land 255)) in
  get (Backend.write_buffer source ~offset:0L bytes);
  require (get (Backend.read_buffer source ~offset:0L ~length:16) = bytes)
    "buffer round trip differs";
  let pass = Transfer_pass.create (Backend.device_handle device) in
  get (Transfer_pass.copy_buffer pass ~src:(Backend.transfer_buffer source)
    ~src_offset:0L ~dst:(Backend.transfer_buffer destination)
    ~dst_offset:0L ~length:16L);
  let command = get (Backend.transfer pass) in
  let receipt = get (Backend.submit queue command
    ~resources:[`Buffer source; `Buffer destination] ~pipelines:[]) in
  let rec poll receipt attempts =
    match get (Command_buffer.status queue receipt) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 ->
        failwith "submitted epoch did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll receipt (attempts - 1) in
  poll receipt 1000;
  require (Command_buffer.completed_epoch queue = receipt.epoch)
    "queue completed epoch differs from receipt";
  require (get (Backend.poll_through queue receipt.epoch))
    "completed epoch did not remain complete";
  require (get (Backend.read_buffer destination ~offset:0L ~length:16) = bytes)
    "submitted buffer copy differs";
  let transfer_buffer : Types.buffer_descriptor =
    {label=Some "texture-transfer";size=512L;usage=[Copy_src;Copy_dst]} in
  let upload=get (Backend.create_buffer device transfer_buffer) in
  let readback=get (Backend.create_buffer device transfer_buffer) in
  let texture_descriptor : Types.texture_descriptor =
    {label=Some "texture-round-trip";width=2;height=2;depth=1;
     mip_levels=1;sample_count=1;
     usage=[Texture_copy_src;Texture_copy_dst]} in
  let first=get (Backend.create_texture device texture_descriptor) in
  let second=get (Backend.create_texture device texture_descriptor) in
  let padded=Bytes.make 512 '\000' in
  for i=0 to 7 do
    Bytes.set padded i (Char.chr (i*17+3));
    Bytes.set padded (256+i) (Char.chr (i*19+5))
  done;
  get (Backend.write_buffer upload ~offset:0L padded);
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  let origin : Transfer_pass.origin={x=0;y=0;z=0} in
  let extent : Transfer_pass.extent={width=2;height=2;depth=1} in
  let texture_pass=Transfer_pass.create (Backend.device_handle device) in
  get (Transfer_pass.buffer_to_texture texture_pass
    ~src:(Backend.transfer_buffer upload) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L
    ~dst:(Backend.transfer_texture first) ~mip:0 ~origin ~extent);
  get (Transfer_pass.copy_texture texture_pass
    ~src:(Backend.transfer_texture first) ~src_mip:0 ~src_origin:origin
    ~dst:(Backend.transfer_texture second) ~dst_mip:0 ~dst_origin:origin
    ~extent);
  get (Transfer_pass.texture_to_buffer texture_pass
    ~src:(Backend.transfer_texture second) ~mip:0 ~origin ~extent
    ~dst:(Backend.transfer_buffer readback) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L);
  let texture_command=get (Backend.transfer texture_pass) in
  let texture_receipt=get (Backend.submit queue texture_command
    ~resources:[`Buffer upload;`Buffer readback;`Texture first;`Texture second]
    ~pipelines:[]) in
  poll texture_receipt 1000;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "texture round-trip changed row bytes or padding";
  let compact=Bytes.create 16 in
  Bytes.blit padded 0 compact 0 8;
  Bytes.blit padded 256 compact 8 8;
  require (get (Backend.read_texture second ~bytes_per_row:8)=compact)
    "texture copy differs from uploaded pixels";
  let mipped_descriptor={texture_descriptor with width=4;height=4;mip_levels=2} in
  let mip_first=get (Backend.create_texture device mipped_descriptor) in
  let mip_second=get (Backend.create_texture device mipped_descriptor) in
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  let mip_pass=Transfer_pass.create (Backend.device_handle device) in
  get (Transfer_pass.buffer_to_texture mip_pass
    ~src:(Backend.transfer_buffer upload) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L
    ~dst:(Backend.transfer_texture mip_first) ~mip:1 ~origin ~extent);
  get (Transfer_pass.copy_texture mip_pass
    ~src:(Backend.transfer_texture mip_first) ~src_mip:1 ~src_origin:origin
    ~dst:(Backend.transfer_texture mip_second) ~dst_mip:1 ~dst_origin:origin
    ~extent);
  get (Transfer_pass.texture_to_buffer mip_pass
    ~src:(Backend.transfer_texture mip_second) ~mip:1 ~origin ~extent
    ~dst:(Backend.transfer_buffer readback) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L);
  let mip_receipt=get (Backend.submit queue (get (Backend.transfer mip_pass))
    ~resources:[`Buffer upload;`Buffer readback;
      `Texture mip_first;`Texture mip_second] ~pipelines:[]) in
  poll mip_receipt 1000;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "mip-level texture round-trip differs";
  let inset : Transfer_pass.origin={x=1;y=1;z=0} in
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  let inset_pass=Transfer_pass.create (Backend.device_handle device) in
  get (Transfer_pass.buffer_to_texture inset_pass
    ~src:(Backend.transfer_buffer upload) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L
    ~dst:(Backend.transfer_texture mip_first) ~mip:0
    ~origin:inset ~extent);
  get (Transfer_pass.copy_texture inset_pass
    ~src:(Backend.transfer_texture mip_first) ~src_mip:0 ~src_origin:inset
    ~dst:(Backend.transfer_texture mip_second) ~dst_mip:0 ~dst_origin:inset
    ~extent);
  get (Transfer_pass.texture_to_buffer inset_pass
    ~src:(Backend.transfer_texture mip_second) ~mip:0 ~origin:inset ~extent
    ~dst:(Backend.transfer_buffer readback) ~offset:0L
    ~bytes_per_row:256L ~bytes_per_image:512L);
  let inset_receipt=get (Backend.submit queue
    (get (Backend.transfer inset_pass))
    ~resources:[`Buffer upload;`Buffer readback;
      `Texture mip_first;`Texture mip_second] ~pipelines:[]) in
  poll inset_receipt 1000;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "texture subregion round-trip differs";
  let expected_image=Bytes.make 64 '\000' in
  Bytes.blit padded 0 expected_image 20 8;
  Bytes.blit padded 256 expected_image 36 8;
  require (get (Backend.read_texture mip_second ~bytes_per_row:16)=
    expected_image) "texture subregion changed other pixels";
  let compute_source=Bytes.of_string
    "#include <metal_stdlib>\nusing namespace metal;\nkernel void exact_compute(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] = values[i] * 3 + 1; }\n" in
  let shader=get (Shader.create
    {backend="metal";label=Some"exact-compute";bytes=compute_source;
     entry_points=[{name="exact_compute";stage=Shader.Compute}];
     bindings=[{group=0;binding=0;kind=Shader.Storage_buffer;
                visibility=[Shader.Compute]}]}) in
  let group_layout=get (Binding.create_layout
    [{binding=0;kind=Binding.Buffer;visibility=[Binding.Compute]}]) in
  let layout=get (Binding.create_pipeline_layout
    ~device:(Backend.device_handle device) ~capabilities
    [0,group_layout]) in
  let compute_descriptor : Pipeline.compute_descriptor=
    {backend="metal";label=Some"exact-compute";layout;shader;
     entry="exact_compute"} in
  let compiled bytes constants =
    let shader=get (Library.of_metallib
      {backend="metal";label=Some"exact-compute-compiled";bytes;
       entry_points=[{name="exact_compute_compiled";stage=Shader.Compute}];
       bindings=[{group=0;binding=0;kind=Shader.Storage_buffer;
                  visibility=[Shader.Compute]}]} ~constants) in
    ({backend="metal";label=Some"exact-compute-compiled";layout;shader;
      entry="exact_compute_compiled"}:Pipeline.compute_descriptor) in
  if Caps.has profile Caps.Compute_pipeline then begin
    let compute_buffer=get (Backend.create_buffer device
      {label=Some"compute-output";size=16L;
       usage=[Storage;Copy_src;Copy_dst]}) in
    let group=get (Binding.create_group layout ~group:0
      [{binding=0;resource=Backend.binding_buffer compute_buffer}]) in
    let resource : Compute_pass.resource=
      {id=Backend.buffer_id compute_buffer;access=Command.Read_write;
       stages=[Command.Compute_stage]} in
    let run_compute descriptor factor =
      let input=Bytes.create 16 in
      for i=0 to 3 do Bytes.set_int32_le input (i*4) (Int32.of_int i) done;
      get (Backend.write_buffer compute_buffer ~offset:0L input);
      let portable=get (Pipeline.create_compute capabilities descriptor) in
      let pipeline=get (Backend.create_compute_pipeline device descriptor) in
      let pass=get (Compute_pass.create (Backend.device_handle device)
        ~limits:capabilities.limits ~pipeline:portable ~layout
        ~groups:[|0,group|] ~resources:[|resource|]
        ~dispatch:(Compute_pass.Direct{x=4;y=1;z=1})) in
      let receipt=get (Backend.submit queue (Backend.compute pass)
        ~resources:[`Buffer compute_buffer] ~pipelines:[pipeline]) in
      poll receipt 1000;
      let output=get (Backend.read_buffer compute_buffer ~offset:0L
        ~length:16) in
      for i=0 to 3 do
        require (Bytes.get_int32_le output (i*4)=Int32.of_int(i*factor+1))
          "compute output differs"
      done;
      get (Backend.destroy_pipeline pipeline) in
    run_compute compute_descriptor 3;
    Option.iter (fun bytes ->
      run_compute (compiled bytes ["TRIPLE",Shader.Bool true]) 3;
      run_compute (compiled bytes ["TRIPLE",Shader.Bool false]) 2) metallib;
    get (Backend.destroy_buffer compute_buffer)
  end else
    (match Backend.create_compute_pipeline device compute_descriptor with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported compute pipeline was accepted");
  if not (Caps.has profile Caps.Compute_pipeline) then
    Option.iter (fun bytes ->
      match Backend.create_compute_pipeline device
        (compiled bytes ["TRIPLE",Shader.Bool true]) with
      | Error { Error.kind = Unsupported; _ } -> ()
      | _ -> failwith "unsupported compiled pipeline was accepted") metallib;
  let other_queue = get (Backend.create_queue device) in
  require (Command_buffer.completed_epoch other_queue = 0L)
    "new queue inherited another queue's completion";
  let other = get (Backend.submit other_queue command
    ~resources:[`Buffer source; `Buffer destination] ~pipelines:[]) in
  require (other.epoch = 1L) "queue epochs are not independent";
  let rec poll_other attempts =
    match get (Command_buffer.status other_queue other) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 ->
        failwith "second queue did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll_other (attempts - 1) in
  poll_other 1000;
  get (Backend.destroy_buffer source);
  (match Backend.read_buffer source ~offset:0L ~length:1 with
   | Error { Error.kind = Stale_handle; _ } -> ()
   | _ -> failwith "destroyed buffer remained readable");
  get (Backend.destroy_buffer destination);
  get (Backend.destroy_buffer upload);
  get (Backend.destroy_buffer readback);
  get (Backend.destroy_texture first);
  get (Backend.destroy_texture second);
  get (Backend.destroy_texture mip_first);
  get (Backend.destroy_texture mip_second);
  get (Backend.destroy_queue other_queue);
  get (Backend.destroy_queue queue);
  get (Backend.destroy_device device)
