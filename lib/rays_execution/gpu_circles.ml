module B = Ogpu.Backend
type t = { device:B.device; queue:B.queue; library:B.library; pipeline:B.pipeline;
  status:B.buffer;
  uniforms:bytes; domain:Domain.id; mutable output:B.buffer option;
  mutable capacity:int; mutable closed:bool }
let source = {|#include <metal_stdlib>
using namespace metal;
struct CircleStyle { uint count; float radius; uint fill; uint stroke; float stroke_width; };
kernel void rays_gpu_circles(device const float *positions [[buffer(0)]],
    device uint *instances [[buffer(1)]], constant CircleStyle &style [[buffer(2)]],
    device atomic_uint *status [[buffer(3)]],
    uint i [[thread_position_in_grid]]) {
  if (i >= style.count) return;
  float x = positions[3*i], y = positions[3*i+1];
  float4 bounds=float4(x-style.radius,y-style.radius,x+style.radius,y+style.radius);
  if (!all(isfinite(bounds))) {
    atomic_store_explicit(status,1u,memory_order_relaxed); return;
  }
  uint j = 16*i;
  instances[j] = as_type<uint>(x-style.radius);
  instances[j+1] = as_type<uint>(y-style.radius);
  instances[j+2] = as_type<uint>(x+style.radius);
  instances[j+3] = as_type<uint>(y+style.radius);
  instances[j+4] = 0; instances[j+5] = 0; instances[j+6] = 0; instances[j+7] = 0;
  instances[j+8] = style.fill; instances[j+9] = style.stroke; instances[j+10] = 4;
  instances[j+11] = 0;
  instances[j+12] = as_type<uint>(style.stroke == 0 ? 0.0f : style.stroke_width);
  instances[j+13] = as_type<uint>(1.0f); instances[j+14] = 0; instances[j+15] = 0;
}
|}
let interface = List.init 4 (fun binding -> Ogpu.Shader.{group=0; binding;
  kind=(if binding=2 then Uniform_buffer else Storage_buffer); visibility=[Compute]})
let error kind message = Error (Ogpu.Error.make "Gpu_circles" kind message)
exception Failed of Ogpu.Error.t
let get = function Ok value -> value | Error error -> raise (Failed error)
let create ~device ~queue =
  if not (Domain.is_main_domain ()) then error Invalid_state "GPU circles require the initial domain."
  else
    let ( let* ) = Result.bind in
    let* () = Ogpu.Caps.require ~operation:"Gpu_circles.create" (B.capabilities device) Compute_pipeline in
    let* shader = Ogpu.Shader.of_source {backend="metal"; label=Some "GPU circle instances";
      bytes=Bytes.of_string source; entry_points=[{name="rays_gpu_circles";stage=Compute}]; bindings=interface} in
    let* library = B.create_library device shader in
    match B.create_compute_pipeline_from library ~entry:"rays_gpu_circles" ~interface () with
    | Error error -> ignore (B.destroy_library library); Error error
    | Ok pipeline ->
      (match B.create_buffer device {label=Some"GPU circle status";size=4L;
        usage=[Storage;Copy_src;Copy_dst]}with
      |Error error->ignore(B.destroy_pipeline pipeline);ignore(B.destroy_library library);Error error
      |Ok status->Ok {device;queue;library;pipeline;status;uniforms=Bytes.create 20;
        domain=Domain.self (); output=None; capacity=0; closed=false})
let zero_status=Bytes.make 4 '\000'
let ensure t count =
  if t.output=None || count>t.capacity then begin
    let capacity=ref (max 1 t.capacity) in
    while !capacity<count do capacity:=min 1_000_000 (!capacity*2) done;
    let output=get (B.create_buffer t.device {label=Some "GPU circle instances";
      size=Int64.of_int (!capacity*Scene_command.Shape_batch.instance_bytes); usage=[Vertex;Storage]}) in
    Option.iter (fun old -> ignore (B.destroy_buffer old)) t.output;
    t.output<-Some output; t.capacity<- !capacity
  end;
  Option.get t.output
let dispatch t ~source ~count ~radius ~fill ~stroke ~stroke_width =
  let finite value = Float.is_finite value && value>=0. && value<=3.4028234663852886e38 in
  if t.closed || Domain.self ()<>t.domain then error Invalid_state "GPU circle owner is closed or called from another domain."
  else if count<0 || count>1_000_000 then error Capacity "Circle count must be in 0..1,000,000."
  else if not (finite radius && finite stroke_width) then error Invalid_argument "Radius and stroke width must be finite nonnegative float32 values."
  else if B.buffer_size source<Int64.of_int (count*12) then error Invalid_argument "Position buffer is shorter than count scalar xyz triples."
  else try
    let output=ensure t count in
    if count>0 then begin
      get(B.write_buffer t.status~offset:0L zero_status);
      Bytes.set_int32_le t.uniforms 0 (Int32.of_int count);
      Bytes.set_int32_le t.uniforms 4 (Int32.bits_of_float radius);
      Bytes.set_int32_le t.uniforms 8 fill; Bytes.set_int32_le t.uniforms 12 stroke;
      Bytes.set_int32_le t.uniforms 16 (Int32.bits_of_float stroke_width);
      let commands=get (B.begin_commands t.queue) in
      let committed=ref false in
      let receipt=Fun.protect ~finally:(fun () -> if not !committed then ignore (B.abandon commands)) (fun () ->
        let encoder=get (B.compute_encoder commands) in
        let ended=ref false in
        Fun.protect ~finally:(fun () -> if not !ended then ignore (B.end_compute encoder)) (fun () ->
          get (B.set_pipeline encoder t.pipeline);
          get (B.set_buffer encoder ~index:0 source);
          get (B.set_buffer encoder ~index:1 output);
          get (B.set_bytes encoder ~index:2 t.uniforms);
          get(B.set_buffer encoder~index:3 t.status);
          get (B.dispatch_threads encoder ~threads:(count,1,1) ~threadgroup:(256,1,1));
          get (B.end_compute encoder); ended:=true);
        let receipt=get (B.commit commands) in committed:=true; receipt) in
      get (B.complete_through t.queue receipt.epoch);
      let status=get(B.read_buffer t.status~offset:0L~length:4)in
      if Bytes.get_int32_le status 0<>0l then
        raise(Failed(Ogpu.Error.make"Gpu_circles"Invalid_argument
          "GPU circle coordinates or radius-expanded bounds are nonfinite."))
    end;
    Ok output
  with Failed error -> Error error
    | Out_of_memory -> error Capacity "GPU circle conversion exceeds available storage."
let close t =
  if Domain.self ()<>t.domain then invalid_arg "Gpu_circles.close: wrong domain";
  if not t.closed then begin
    Option.iter (fun output -> ignore (B.destroy_buffer output)) t.output; t.output<-None;
    ignore(B.destroy_buffer t.status);
    ignore (B.destroy_pipeline t.pipeline); ignore (B.destroy_library t.library);
    t.capacity<-0; t.closed<-true
  end
