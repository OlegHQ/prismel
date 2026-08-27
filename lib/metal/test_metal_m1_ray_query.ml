open Metal

let fail fmt = Printf.ksprintf failwith fmt
let get = function Ok value -> value | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let source = {|
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

kernel void prismel_m1_ray_query(
    primitive_acceleration_structure scene [[buffer(0)]],
    device uint *output [[buffer(1)]],
    uint tid [[thread_position_in_grid]]) {
  const float origins[4] = { 0.0f, 0.25f, 2.0f, -2.0f };
  ray query;
  query.origin = float3(origins[tid], 0.0f, 1.0f);
  query.direction = float3(0.0f, 0.0f, -1.0f);
  query.min_distance = 0.001f;
  query.max_distance = 10.0f;
  intersector<triangle_data> trace;
  trace.assume_geometry_type(geometry_type::triangle);
  auto hit = trace.intersect(query, scene);
  output[tid] = (hit.type == intersection_type::triangle ? 0xa5000000u : 0x5a000000u) | tid;
}
|}

let put_float bytes offset value = Bytes.set_int32_le bytes offset (Int32.bits_of_float value)

let triangle_bytes () =
  let bytes = Bytes.make 36 '\000' in
  [| -1.; -1.; 0.; 1.; -1.; 0.; 0.; 1.; 0. |]
  |> Array.iteri (fun index value -> put_float bytes (index * 4) value);
  bytes

let fnv1a bytes =
  let hash = ref 0xcbf29ce484222325L in
  Bytes.iter (fun byte -> hash := Int64.logxor !hash (Int64.of_int (Char.code byte)); hash := Int64.mul !hash 0x100000001b3L) bytes;
  !hash

let destroy functions = List.iter (fun function_ -> get (function_ ())) functions

let () =
  match Device.system_default () with
  | Error _ -> print_endline "Metal M1 ray query: skipped (no device)"
  | Ok device ->
      let baseline = get (Release_queue.stats ()) in
      let info = get (Device.info device) in
      if not info.raytracing then begin
        get (Device.destroy device);
        ignore (get (Release_queue.drain ()));
        let finished = get (Release_queue.stats ()) in
        if finished.live_handles <> baseline.live_handles - 1 then fail "unsupported ray-query path leaked handles";
        print_endline "Metal M1 ray query: unsupported capability rejected without handle delta"
      end else begin
        let vertices = get (Buffer.create_copy ~device ~storage:Buffer.Shared (triangle_bytes ())) in
        let triangle = get (Acceleration_structure.Triangle.create ~vertex_buffer:vertices ~vertex_stride:12L ~triangle_count:1L ()) in
        let sizes = get (Acceleration_structure.sizes ~device triangle) in
        let scene = get (Acceleration_structure.create ~device ~size:sizes.acceleration_structure_size) in
        let scratch = get (Buffer.create ~device ~length:sizes.build_scratch_buffer_size ~storage:Buffer.Private ()) in
        let output = get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ()) in
        let library = get (Library.compile_source ~device source) in
        let function_ = get (Function.find ~library "prismel_m1_ray_query") in
        let pipeline = get (Compute_pipeline.create function_) in
        let queue = get (Command_queue.create device) in
        let build_commands = get (Command_buffer.create queue ()) in
        let build = get (Acceleration_encoder.create build_commands) in
        get (Acceleration_encoder.build build ~destination:scene ~descriptor:triangle ~scratch ~scratch_offset:0L);
        get (Acceleration_encoder.end_encoding build);
        get (Command_buffer.commit build_commands);
        get (Command_buffer.wait_until_completed build_commands);
        let commands = get (Command_buffer.create queue ()) in
        let encoder = get (Compute_encoder.create commands) in
        get (Compute_encoder.set_pipeline encoder pipeline);
        get (Compute_encoder.set_acceleration_structure encoder ~index:0 (Some scene));
        get (Compute_encoder.set_buffer encoder ~index:1 ~offset:0L output);
        get (Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1) ~threadgroup:(4, 1, 1));
        get (Compute_encoder.end_encoding encoder);
        get (Command_buffer.commit commands);
        get (Command_buffer.wait_until_completed commands);
        let actual = get (Buffer.read_bytes output ~offset:0L ~length:16) in
        let expected = Bytes.make 16 '\000' in
        [| 0xa5000000l; 0xa5000001l; 0x5a000002l; 0x5a000003l |]
        |> Array.iteri (fun index value -> Bytes.set_int32_le expected (index * 4) value);
        if actual <> expected then
          fail "ray-query bytes mismatch: [%08lx;%08lx;%08lx;%08lx], hash=%016Lx"
            (Bytes.get_int32_le actual 0) (Bytes.get_int32_le actual 4)
            (Bytes.get_int32_le actual 8) (Bytes.get_int32_le actual 12)
            (fnv1a actual);
        destroy [ (fun () -> Command_buffer.destroy commands); (fun () -> Command_buffer.destroy build_commands);
          (fun () -> Command_queue.destroy queue); (fun () -> Compute_pipeline.destroy pipeline);
          (fun () -> Function.destroy function_); (fun () -> Library.destroy library);
          (fun () -> Buffer.destroy output); (fun () -> Buffer.destroy scratch);
          (fun () -> Acceleration_structure.destroy scene); (fun () -> Buffer.destroy vertices);
          (fun () -> Device.destroy device) ];
        ignore (get (Release_queue.drain ()));
        let finished = get (Release_queue.stats ()) in
        if finished.live_handles <> baseline.live_handles - 1 then fail "ray-query teardown leaked handles: baseline=%d final=%d" baseline.live_handles finished.live_handles;
        Printf.printf "Metal M1 ray query: hash=%016Lx, no live-handle delta\n%!" (fnv1a actual)
      end
