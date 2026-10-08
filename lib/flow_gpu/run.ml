module B = Ogpu.Backend
module P = Flow_ir.Packed
type slot = {mutable buffer : B.buffer option; mutable capacity : int; mutable bytes : bytes}
type t = {device:B.device; queue:B.queue; pipelines : Pipelines.t; msl : Emit.msl; inputs : slot array;
  output : slot; table : slot; status:slot; uniforms : bytes; mutable closed : bool; mutable creations : int;
  mutable generation : int; mutable table_ready:bool; domain : Domain.id}
type output = {owner : t; count : int; width : int; gpu_seconds : float option; generation : int}
exception Failed of Flow.Diagnostic.t
let diagnostic error = Flow.Diagnostic.error ~code:"E_GPU" (Ogpu.Error.to_string error)
let get = function Ok value -> value | Error error -> raise (Failed (diagnostic error))
let slot () = {buffer=None;capacity=0;bytes=Bytes.empty}
let nonfinite () =
  Failed(Flow.Diagnostic.error ~code:"E_KERNEL" "GPU inputs must remain finite when represented as float32.")
let pack bytes offset value =
  let bits=Int32.bits_of_float value in
  if not(Float.is_finite(Int32.float_of_bits bits))then raise(nonfinite());
  Bytes.set_int32_le bytes offset bits
(* One loop body keeps the float and its int32 bits unboxed; calling [pack]
   per element boxed both (96 MB/frame at one million vec3 inputs). *)
let pack_array bytes (values : float array) length =
  for index=0 to length-1 do
    let bits=Int32.bits_of_float(Array.unsafe_get values index) in
    if not(Float.is_finite(Int32.float_of_bits bits))then raise(nonfinite());
    Bytes.set_int32_le bytes (index*4) bits
  done
let unpack_array bytes length =
  let values=Array.make length 0. and finite=ref true in
  for index=0 to length-1 do
    let value=Int32.float_of_bits(Bytes.get_int32_le bytes (index*4)) in
    if not(Float.is_finite value) then finite:=false;
    Array.unsafe_set values index value
  done;
  values, !finite
let create_owned device queue pipelines (msl : Emit.msl) =
  if not(Domain.is_main_domain())then invalid_arg "Run.create: initial domain required";
  {device;queue;pipelines;msl;inputs=Array.map (fun _ -> slot ()) msl.input_widths;
    output=slot ();table=slot ();status=slot();uniforms=Bytes.create msl.uniform_bytes;
    closed=false;creations=0;generation=0;table_ready=false;domain=Domain.self ()}
let create gpu=create_owned(Rays_execution.gpu_device gpu)(Rays_execution.gpu_queue gpu)
let ensure t slot length =
  if length>slot.capacity then begin
    let capacity = ref (max 256 slot.capacity) in
    while !capacity<length do
      if !capacity>Sys.max_string_length/2 then capacity:=length else capacity:= !capacity*2
    done;
    let bytes=Bytes.create !capacity in
    let fresh = get (B.create_buffer t.device
      {label=Some "Flow packed compute";size=Int64.of_int !capacity;usage=[Storage;Copy_src;Copy_dst]}) in
    Option.iter (fun buffer -> ignore (B.destroy_buffer buffer)) slot.buffer;
    slot.buffer<-Some fresh;slot.capacity<- !capacity;slot.bytes<-bytes;
    t.creations<-t.creations+1
  end;
  Option.get slot.buffer
let dispatch t (values : P.Private.inputs) =
  let error message = Error (Flow.Diagnostic.error ~code:"E_KERNEL" message) in
  if t.closed || Domain.self ()<>t.domain then error "GPU program owner is closed or called from another domain."
  else if values.count<0 || values.count>Int32.to_int Int32.max_int ||
    values.count>Sys.max_string_length/4/t.msl.output_width then error "GPU count exceeds native storage bounds."
  else if Array.length values.arrays<>Array.length t.inputs then error "GPU input arity changed."
  else if Array.exists (fun index -> Array.length values.arrays.(index)<values.count*t.msl.input_widths.(index))
      (Array.init (Array.length t.inputs) Fun.id) then error "GPU input count changed."
  else begin
  (* Invalidate borrowed output before reallocating or submitting any write,
     including dispatches whose completion subsequently fails. *)
  t.generation<-t.generation+1;
  if values.count=0 then begin
    Ok {owner=t;count=0;width=t.msl.output_width;gpu_seconds=None;generation=t.generation}
  end
  else try
    let msl=t.msl in
    let compiled=match Pipelines.get t.pipelines msl with
      | Ok compiled -> compiled | Error error -> raise (Failed error) in
    Bytes.set_int32_le t.uniforms 0 (Int32.of_int values.count);
    List.iter (fun (name,offset,width) ->
      if String.starts_with ~prefix:"uniform:" name then begin
        let index=int_of_string (String.sub name 8 (String.length name-8)) in
        if index>=Array.length values.uniforms || Array.length values.uniforms.(index)<>width then
          raise (Failed (Flow.Diagnostic.error ~code:"E_KERNEL" "GPU uniform type changed."));
        for component=0 to width-1 do pack t.uniforms (offset+component*4)
          values.uniforms.(index).(component) done
      end else match String.split_on_char ':' name with
        | ["frame";index;_] ->
            let index=int_of_string index in
            if index>=Array.length values.frame then
              raise (Failed (Flow.Diagnostic.error ~code:"E_KERNEL" "GPU frame uniform changed."));
            pack t.uniforms offset values.frame.(index)
        | _ -> assert false) msl.uniform_layout;
    let buffers=Array.mapi (fun index slot ->
      let length=values.count*msl.input_widths.(index)*4 in
      let buffer=ensure t slot length in
      pack_array slot.bytes values.arrays.(index) (length/4);
      get (B.write_buffer buffer ~offset:0L slot.bytes);buffer) t.inputs in
    let output=ensure t t.output (values.count*msl.output_width*4) in
    let status=ensure t t.status 4 in
    Bytes.set_int32_le t.status.bytes 0 0l;
    get(B.write_buffer status ~offset:0L t.status.bytes);
    let table = if msl.table_seeds=[||] then None else begin
      let length=Array.length msl.table_seeds*512*4 in
      let fresh=not t.table_ready in
      let buffer=ensure t t.table length in
      if fresh then begin
        Array.iteri (fun index seed ->
          let permutation=Rays_math.Noise.Private.permutation (Rays_math.Noise.create seed) in
          Array.iteri (fun entry value -> Bytes.set_int32_le t.table.bytes ((index*512+entry)*4)
            (Int32.of_int value)) permutation) msl.table_seeds;
        get (B.write_buffer buffer ~offset:0L t.table.bytes);
        t.table_ready<-true
      end;Some buffer
    end in
    let queue=t.queue in
    let commands=get (B.begin_commands queue) in
    let committed=ref false in
    let receipt=Fun.protect ~finally:(fun () -> if not !committed then ignore (B.abandon commands)) (fun () ->
      let encoder=get (B.compute_encoder commands) in
      Fun.protect ~finally:(fun () -> ignore (B.end_compute encoder)) (fun () ->
        get (B.set_pipeline encoder compiled.pipeline);
        Array.iteri (fun index buffer -> get (B.set_buffer encoder ~index buffer)) buffers;
        let index=Array.length buffers in
        get (B.set_buffer encoder ~index output);
        get (B.set_bytes encoder ~index:(index+1) t.uniforms);
        get(B.set_buffer encoder ~index:(index+2) status);
        Option.iter (fun table -> get (B.set_buffer encoder ~index:(index+3) table)) table;
        get (B.dispatch_threads encoder ~threads:(values.count,1,1) ~threadgroup:(256,1,1)));
      let receipt=get (B.commit commands) in committed:=true;receipt) in
    get (B.complete_through queue receipt.epoch);
    let flags=get(B.read_buffer status ~offset:0L ~length:4)in
    if Bytes.get_int32_le flags 0<>0l then
      raise(Failed(Flow.Diagnostic.error ~code:"E_KERNEL" "GPU output contains a nonfinite value."));
    Ok {owner=t;count=values.count;width=msl.output_width;gpu_seconds=B.gpu_duration queue receipt;
      generation=t.generation}
  with Failed error -> Error error
    | Out_of_memory -> error "GPU staging exceeds available memory."
  end
let readback output =
  if output.owner.closed || Domain.self ()<>output.owner.domain || output.generation<>output.owner.generation then
    Error (Flow.Diagnostic.error ~code:"E_GPU" "GPU output was closed or superseded.")
  else try
    let length=output.count*output.width in
    let values,finite=if length=0 then [||],true else
      unpack_array (get (B.read_buffer (Option.get output.owner.output.buffer) ~offset:0L ~length:(length*4))) length in
    if not finite then
      Error (Flow.Diagnostic.error ~code:"E_KERNEL" "GPU output contains a nonfinite value.")
    else Ok (match output.width with 2 -> Flow.Eval.Vec2_array values
      | 3 -> Vec3_array values | 4 -> Vec4_array values | _ -> Float_array values)
  with Failed error -> Error error
let buffer output = if output.owner.closed || Domain.self()<>output.owner.domain || output.generation<>output.owner.generation
  then None else output.owner.output.buffer
let count output = output.count
let width output = output.width
let gpu_seconds output = output.gpu_seconds
let close t =
  if Domain.self()<>t.domain then invalid_arg "Run.close: creating domain required";
  if not t.closed then begin
  Array.iter (fun slot -> Option.iter (fun buffer -> ignore (B.destroy_buffer buffer)) slot.buffer;
    slot.buffer<-None;slot.bytes<-Bytes.empty;slot.capacity<-0) (Array.append t.inputs [|t.output;t.table;t.status|]);
  t.closed<-true
end
module Private = struct
  let buffer_creations t = t.creations
  let create_owned = create_owned
end
