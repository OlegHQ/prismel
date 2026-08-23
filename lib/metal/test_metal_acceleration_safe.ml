open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let check condition message = if not condition then failwith message

let () =
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
  let encoder = get (Acceleration_encoder.create commands) in
  get
    (Acceleration_encoder.build encoder ~destination:source ~descriptor ~scratch
       ~scratch_offset:0L);
  get
    (Acceleration_encoder.refit encoder ~source ~destination:refitted ~descriptor
       ~scratch ~scratch_offset:0L);
  get (Acceleration_encoder.copy encoder ~source ~destination:copied);
  get
    (Acceleration_encoder.write_compacted_size encoder ~source
       ~destination:compacted_size ~offset:0L);
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
    ; (fun () -> Acceleration_structure.destroy compacted)
    ; (fun () -> Acceleration_structure.destroy copied)
    ; (fun () -> Acceleration_structure.destroy refitted)
    ; (fun () -> Acceleration_structure.destroy source)
    ; (fun () -> Buffer.destroy compacted_size)
    ; (fun () -> Buffer.destroy scratch)
    ; (fun () -> Buffer.destroy vertex)
    ; (fun () -> Command_queue.destroy queue)
    ; (fun () -> Device.destroy device) ];
  ignore (get (Release_queue.drain ()));
  print_endline "Metal safe acceleration API: size/build/refit/copy/compact passed"
