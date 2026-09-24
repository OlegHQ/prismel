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
  get (Backend.complete_through queue receipt.epoch);
  get (Backend.destroy_buffer source);
  (match Backend.read_buffer source ~offset:0L ~length:1 with
   | Error { Error.kind = Stale_handle; _ } -> ()
   | _ -> failwith "destroyed buffer remained readable");
  get (Backend.destroy_buffer destination);
  get (Backend.destroy_queue queue);
  get (Backend.destroy_device device)
