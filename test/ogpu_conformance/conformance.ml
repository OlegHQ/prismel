let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let require condition message = if not condition then failwith message

let run driver =
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
  let rec poll attempts =
    match get (Command_buffer.status queue receipt) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 ->
        failwith "submitted epoch did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll (attempts - 1) in
  poll 1000;
  require (Command_buffer.completed_epoch queue = receipt.epoch)
    "queue completed epoch differs from receipt";
  require (get (Backend.poll_through queue receipt.epoch))
    "completed epoch did not remain complete";
  require (get (Backend.read_buffer destination ~offset:0L ~length:16) = bytes)
    "submitted buffer copy differs";
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
  get (Backend.destroy_queue other_queue);
  get (Backend.destroy_queue queue);
  get (Backend.destroy_device device)
