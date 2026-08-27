open Ogpu_metal
let get = function Ok value -> value | Error value -> failwith (Ogpu.Error.to_string value)
let get_metal = function Ok value -> value | Error value -> failwith (Format.asprintf "%a" Metal.pp_error value)
let expect kind = function Error value when value.Ogpu.Error.kind = kind -> () | _ -> failwith "unexpected synchronization result"
let () =
  let device = get (Device.system_default ()) in
  let other = get (Device.system_default ()) in
  let before = get_metal (Metal.Release_queue.stats ()) in
  let fence = get (Sync.create_fence device ~initial:0L) in
  expect Ogpu.Error.Unsupported (Sync.signal_fence device fence 1L);
  expect Ogpu.Error.Cross_device (Sync.wait_fence other fence 1L);
  let event = get (Sync.create_event device ~initial:0L) in
  ignore (get (Sync.signal_event device event 2L));
  ignore (get (Sync.wait_event device event 2L));
  expect Ogpu.Error.Unsupported (Sync.wait_event device event 3L);
  let destination = get (Buffer.create device ~memory:Buffer.Readback
    {Ogpu.Types.size=4096L; usage=[Copy_dst]; label=Some "query-results"}) in
  let queries = Sync.create_query_set device ~kind:Ogpu.Sync.Timestamp ~count:2 in
  let query_path = ref "unsupported" in
  (match queries with Ok queries ->
    query_path := "executed";
    if not (Sync.query_supported queries) then failwith "created query set is unsupported";
    let description = get (Sync.execute_query_pass device queries ~first:0 ~count:2 ~destination
      ~destination_offset:0L ~completion_epoch:1L) in
    (match description.Ogpu.Query_pass.resolve with Ogpu.Sync.Resolve value when value.count=2 && value.first=0 -> () | _ -> failwith "query description drift");
    let bytes = get (Buffer.read_bytes device destination ~offset:0L ~length:16) in
    if Bytes.length bytes <> 16 then failwith "timestamp result length drift";
    expect Ogpu.Error.Invalid_argument (Sync.execute_query_pass device queries ~first:1 ~count:2 ~destination
      ~destination_offset:0L ~completion_epoch:2L);
    get (Sync.destroy_query_set queries)
  | Error value when value.Ogpu.Error.kind=Ogpu.Error.Unsupported -> ()
  | Error value -> failwith (Ogpu.Error.to_string value));
  get (Buffer.destroy destination);
  get (Sync.destroy_event event); expect Ogpu.Error.Stale_handle (Sync.signal_event device event 4L);
  get (Sync.destroy_fence fence);
  get (Device.destroy device); get (Device.destroy other);
  ignore (get_metal (Metal.Release_queue.drain ()));
  let after = get_metal (Metal.Release_queue.stats ()) in
  if after.live_handles <> before.live_handles - 2 then failwith "sync/query live-handle delta";
  Printf.printf "ogpu_metal sync/query: typed M1 %s, zero delta ok\n" !query_path
