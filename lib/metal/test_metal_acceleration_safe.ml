open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let check condition message = if not condition then failwith message

let run () =
  let device = get (Device.system_default ()) in
  let vertices = Bytes.make 36 '\000' in
  let vertex =
    get (Buffer.create_copy ~device ~storage:Buffer.Shared vertices)
  in
  let descriptor =
    get
      (Acceleration_structure.Triangle.create ~vertex_buffer:vertex
         ~vertex_stride:12L ~triangle_count:1L ())
  in
  let owned_triangle = get (Acceleration_structure.Descriptor.create device
    (Acceleration_structure.Descriptor.Triangle
       {buffer=vertex;offset=0L;stride=12L;count=1L;element_size=12L})) in
  let owned_primitive = get (Acceleration_structure.Descriptor.create device
    (Acceleration_structure.Descriptor.Primitive [owned_triangle])) in
  (* Generic build descriptors: static and keyframed triangles, bounding
     boxes, instance record layouts, and typed rejections. *)
  let build_module =
    let d = device in
    let open Acceleration_structure.Build in
    let keyframe buffer = { buffer; offset = 0L } in
    let triangles ?(keyframes = [ keyframe vertex ]) () =
      Triangles { vertices = keyframes; vertex_stride = 12L; triangle_count = 1L; index = None
                ; common = default_common } in
    let static = get (primitive d [ triangles () ]) in
    let static_sizes = get (sizes ~device:d static) in
    check (static_sizes.acceleration_structure_size > 0L
           && static_sizes.build_scratch_buffer_size > 0L) "generic triangle sizes";
    let second = get (Buffer.create_copy ~device:d ~storage:Buffer.Shared vertices) in
    let motion = { keyframe_count = 2; start_time = 0.; end_time = 1.
                 ; start_border = Clamp; end_border = Clamp } in
    let moving = get (primitive d ~motion ~usage:[ Refit ]
      [ triangles ~keyframes:[ keyframe vertex; keyframe second ] () ]) in
    check ((get (sizes ~device:d moving)).acceleration_structure_size > 0L) "motion triangle sizes";
    (match primitive d ~motion [ triangles () ] with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "keyframe count mismatch accepted");
    (match primitive d [ Bounding_boxes { boxes = [ keyframe vertex ]; stride = 24L; count = 2L
                                             ; common = default_common } ] with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "bounding box range overflow accepted");
    let boxes = get (Buffer.create_copy ~device:d ~storage:Buffer.Shared (Bytes.make 48 '\000')) in
    let boxed = get (primitive d [ Bounding_boxes { boxes = [ keyframe boxes ]; stride = 24L
                                                        ; count = 2L; common = default_common } ]) in
    check ((get (sizes ~device:d boxed)).acceleration_structure_size > 0L) "bounding box sizes";
    let layout = instance_layout Default_instances in
    check (layout.size = 64 && layout.mask = 52 && layout.structure_index = 60 && layout.user_id = -1)
      "default instance layout";
    let user = instance_layout User_id_instances in
    check (user.size = 68 && user.user_id = 64) "user-id instance layout";
    let motion_layout = instance_layout Motion_instances in
    check (motion_layout.transform = -1 && motion_layout.transforms_start >= 0
           && motion_layout.end_time_offset > motion_layout.start_time_offset)
      "motion instance layout";
    let structure = get (Acceleration_structure.create ~device:d
      ~size:static_sizes.acceleration_structure_size) in
    let records = get (Buffer.create_copy ~device:d ~storage:Buffer.Shared (Bytes.make 136 '\000')) in
    let instanced = get (instances d ~buffer:records ~count:2L ~kind:User_id_instances
      [| structure |]) in
    check (instance_count instanced = 2L && instance_kind instanced = Some User_id_instances)
      "instance descriptor facts";
    check ((get (sizes ~device:d instanced)).acceleration_structure_size > 0L) "instance sizes";
    (match instances d ~buffer:records ~stride:32L ~count:2L [| structure |] with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "undersized instance stride accepted");
    (match instances d ~buffer:records ~count:2L ~kind:Motion_instances [| structure |] with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "motion instances without transforms accepted");
    (match instances d ~buffer:records ~count:3L [| structure |] with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "instance range overflow accepted");
    let scratch_length = Int64.max static_sizes.build_scratch_buffer_size 256L in
    let scratch = get (Buffer.create ~device:d ~length:scratch_length ~storage:Buffer.Private ()) in
    let queue = get (Command_queue.create d) in
    let commands = get (Command_buffer.create queue ()) in
    let encoder = get (Acceleration_encoder.create commands) in
    get (Acceleration_encoder.build_with encoder ~destination:structure ~descriptor:static ~scratch
      ~scratch_offset:0L);
    (match Acceleration_encoder.build_with encoder ~destination:structure ~descriptor:static ~scratch
      ~scratch_offset:scratch_length with
     | Error error when error.kind = Invalid_argument -> ()
     | _ -> failwith "exhausted scratch accepted");
    get (Acceleration_encoder.end_encoding encoder);
    get (Command_buffer.commit commands);
    get (Command_buffer.wait_until_completed commands);
    List.iter (fun destroy -> get (destroy ()))
      [ (fun () -> Command_buffer.destroy commands); (fun () -> Command_queue.destroy queue)
      ; (fun () -> destroy instanced); (fun () -> destroy boxed); (fun () -> destroy moving)
      ; (fun () -> destroy static); (fun () -> Acceleration_structure.destroy structure)
      ; (fun () -> Buffer.destroy scratch); (fun () -> Buffer.destroy records)
      ; (fun () -> Buffer.destroy boxes); (fun () -> Buffer.destroy second) ] in
  ignore build_module;
  let sizes = get (Acceleration_structure.sizes ~device descriptor) in
  check (sizes.acceleration_structure_size > 0L) "empty AS allocation size";
  check (sizes.build_scratch_buffer_size > 0L) "empty AS build scratch size";
  let source =
    get
      (Acceleration_structure.create ~device
         ~size:sizes.acceleration_structure_size)
  in
  let refitted =
    get
      (Acceleration_structure.create ~device
         ~size:sizes.acceleration_structure_size)
  in
  let copied =
    get
      (Acceleration_structure.create ~device
         ~size:sizes.acceleration_structure_size)
  in
  let scratch_size =
    Int64.max sizes.build_scratch_buffer_size sizes.refit_scratch_buffer_size
  in
  let scratch =
    get (Buffer.create ~device ~length:scratch_size ~storage:Buffer.Private ())
  in
  let compacted_size =
    get (Buffer.create ~device ~length:8L ~storage:Buffer.Shared ())
  in
  let queue = get (Command_queue.create device) in
  let commands = get (Command_buffer.create queue ()) in
  let pass = get (Acceleration_pass.create device) in
  (match Resource100.Sample_buffer.create device ~sample_count:2L () with
   | Error error when error.kind=Unsupported -> ()
   | Error error -> failwith (Format.asprintf "%a" pp_error error)
   | Ok samples ->
       let attachment = get (Acceleration_pass.set_attachment pass ~index:0
         ~sample_buffer:samples ~first:0L ~last:1L) in
       (match get (Acceleration_pass.attachment pass ~index:0) with
        | Some retained when retained==attachment -> ()
        | _ -> failwith "acceleration pass attachment identity drift");
       check (Acceleration_pass.attachment_index attachment=0
              &&Acceleration_pass.attachment_range attachment=(0L,1L))
         "acceleration pass attachment range drift";
       get (Acceleration_pass.clear_attachment pass ~index:0);
       get (Acceleration_pass.destroy_attachment attachment);
       get (Resource100.Sample_buffer.destroy samples));
  let encoder = get (Acceleration_pass.create_encoder commands pass) in
  let fence = get (Fence.create device) in
  let heap = get (Heap.create ~device (Heap.make_descriptor ~size:1048576L ())) in
  get (Acceleration_encoder.use_resources encoder ~usage:Acceleration_encoder.Read
    [Acceleration_encoder.Buffer_resource vertex]);
  get (Acceleration_encoder.use_heaps encoder [heap]);
  get (Acceleration_encoder.update_fence encoder fence);
  get (Acceleration_encoder.wait_for_fence encoder fence);
  get
    (Acceleration_encoder.build encoder ~destination:source ~descriptor ~scratch
       ~scratch_offset:0L);
  get
    (Acceleration_encoder.refit encoder ~source ~destination:refitted ~descriptor
       ~scratch ~scratch_offset:0L);
  get
    (Acceleration_encoder.refit_with_options encoder ~source ~destination:refitted
       ~descriptor ~scratch ~scratch_offset:0L ~options:0L);
  get (Acceleration_encoder.copy encoder ~source ~destination:copied);
  get
    (Acceleration_encoder.write_compacted_size encoder ~source
       ~destination:compacted_size ~offset:0L);
  get
    (Acceleration_encoder.write_compacted_size_typed encoder ~source
       ~destination:compacted_size ~offset:0L Acceleration_encoder.Uint64);
  get (Acceleration_encoder.end_encoding encoder);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  let bytes = get (Buffer.read_bytes compacted_size ~offset:0L ~length:8) in
  let compact_size = Bytes.get_int64_le bytes 0 in
  check (compact_size > 0L) "Metal returned an empty compacted AS size";
  let compacted = get (Acceleration_structure.create ~device ~size:compact_size) in
  let compact_commands = get (Command_buffer.create queue ()) in
  let compact_encoder = get (Acceleration_encoder.create compact_commands) in
  get
    (Acceleration_encoder.copy_and_compact compact_encoder ~source
       ~destination:compacted);
  get (Acceleration_encoder.end_encoding compact_encoder);
  get (Command_buffer.commit compact_commands);
  get (Command_buffer.wait_until_completed compact_commands);
  List.iter
    (fun destroy -> get (destroy ()))
    [ (fun () -> Command_buffer.destroy compact_commands)
    ; (fun () -> Command_buffer.destroy commands)
    ; (fun () -> Acceleration_pass.destroy pass)
    ; (fun () -> Heap.destroy heap)
    ; (fun () -> Fence.destroy fence)
    ; (fun () -> Acceleration_structure.destroy compacted)
    ; (fun () -> Acceleration_structure.destroy copied)
    ; (fun () -> Acceleration_structure.destroy refitted)
    ; (fun () -> Acceleration_structure.destroy source)
    ; (fun () -> Acceleration_structure.Descriptor.destroy owned_primitive)
    ; (fun () -> Acceleration_structure.Descriptor.destroy owned_triangle)
    ; (fun () -> Buffer.destroy compacted_size)
    ; (fun () -> Buffer.destroy scratch)
    ; (fun () -> Buffer.destroy vertex)
    ; (fun () -> Command_queue.destroy queue)
    ; (fun () -> Device.destroy device) ];
  ignore (get (Release_queue.drain ()));
  print_endline "Metal safe acceleration API: size/build/refit/copy/compact passed"
