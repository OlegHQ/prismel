module B = Ogpu.Backend
module C = Rays_execution.Private.Gpu_circles
let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let expect kind = function Error (error:Ogpu.Error.t) -> assert (error.kind=kind) | Ok _ -> assert false
let buffer device count = get (B.create_buffer device {label=None; size=Int64.of_int (max 1 count*12); usage=[Storage]})
let native () =
  let driver,_ = Ogpu.Impl.create_driver () in
  let device=get (B.create_device driver) in
  let queue=get (B.create_queue device) in
  let circles=get (C.create ~device ~queue) and positions=buffer device 3 in
  Fun.protect ~finally:(fun () -> C.close circles; ignore (B.destroy_buffer positions);
    ignore (B.destroy_queue queue); ignore (B.destroy_device device)) (fun () ->
    let coordinates=[|1.;2.;99.; -4.;8.;-10.; 0.;0.;0.|] in
    let input=Bytes.create 36 in
    Array.iteri (fun i value -> Bytes.set_int32_le input (4*i) (Int32.bits_of_float value)) coordinates;
    get (B.write_buffer positions ~offset:0L input);
    List.iter (fun (fill,stroke,width) ->
      let output=get (C.dispatch circles ~source:positions ~count:3 ~radius:2.5 ~fill ~stroke ~stroke_width:width) in
      let actual=get (B.read_buffer output ~offset:0L ~length:(3*64)) in
      let builder=Scene_command.Shape_batch.Builder.create () in
      for i=0 to 2 do Scene_command.Shape_batch.Builder.circle builder
        ~x:coordinates.(3*i) ~y:coordinates.(3*i+1) ~radius:2.5 ~fill ~stroke ~stroke_width:width () done;
      assert (actual=Scene_command.Shape_batch.instances (Scene_command.Shape_batch.Builder.publish builder)))
      [-1l,0l,1.; 0x12345678l,0xff00ff80l,3.; 0l,0l,0.];
    print_endline "GPU circles: native output matches every word of the Shape_batch ABI")
let mock () =
  let base,live=Ogpu.Impl.create_driver () in
  let device=get (B.create_device base) in
  let queue=get (B.create_queue device) in
  expect Unsupported (C.create ~device ~queue);
  ignore (B.destroy_queue queue); ignore (B.destroy_device device); assert (live ()=0);
  let unsupported=B.{create_device=(fun () -> Result.map (fun raw ->
    {raw with capabilities={raw.capabilities with compute_pipeline=true}}) (base.create_device ()))} in
  let device=get (B.create_device unsupported) in
  let queue=get (B.create_queue device) in
  expect Unsupported (C.create ~device ~queue);
  ignore (B.destroy_queue queue); ignore (B.destroy_device device); assert (live ()=0);
  (* Only command lifecycle and bindings are modeled; this driver executes no
     shader arithmetic. Native ABI verification is a separate invocation. *)
  let pipelines=ref 0 and abandoned=ref 0 and ended=ref 0 and reads=ref 0
  and descriptors=ref [] and fail=ref false and uniforms=ref Bytes.empty in
  let driver=B.{create_device=(fun () -> Result.map (fun raw ->
    {raw with capabilities={raw.capabilities with compute_pipeline=true};
      create_buffer=(fun memory descriptor -> descriptors:=descriptor::!descriptors;
        Result.map (fun (resource:B.driver_resource) -> {resource with
          read=(fun offset count -> incr reads; resource.read offset count)}) (raw.create_buffer memory descriptor));
      create_library=(fun shader -> Result.map (fun library -> {library with
        create_compute_pipeline_in=(fun ~entry:_ ~constants:_ ~interface:_ ~linked:_ ->
          incr pipelines; Ok {pipeline_token=1L;
            create_table=(fun ~capacity:_ -> Error (Ogpu.Error.make "test" Unsupported "no table"));
            destroy_pipeline=(fun () -> decr pipelines; Ok ())})}) (raw.create_library shader));
      create_queue=(fun () -> Result.map (fun queue -> {queue with begin_commands=(fun () ->
        Result.map (fun commands -> {commands with
          abandon=(fun () -> incr abandoned; commands.abandon ());
          compute_encoder=(fun () -> Ok {
            set_pipeline=(fun _ -> Ok ()); set_buffer=(fun ~index:_ ~offset:_ _ -> Ok ());
            set_bytes=(fun ~index bytes -> assert (index=2); uniforms:=Bytes.copy bytes; Ok ());
            set_texture=(fun ~index:_ _ -> assert false); set_accel=(fun ~index:_ _ -> assert false);
            set_table=(fun ~index:_ _ -> assert false); compute_use_accels=(fun _ -> assert false);
            dispatch_threads=(fun ~threads ~threadgroup -> assert (threadgroup=(256,1,1));
              assert (threads=(Int32.to_int (Bytes.get_int32_le !uniforms 0),1,1));
              if !fail then Error (Ogpu.Error.make "test" Invalid_state "injected dispatch") else Ok ());
            end_compute=(fun () -> incr ended; Ok ())})}) (queue.begin_commands ()))}) (raw.create_queue ()))})
    (base.create_device ()))} in
  let device=get (B.create_device driver) and other=get (B.create_device driver) in
  let queue=get (B.create_queue device) in
  let circles=get (C.create ~device ~queue) and positions=buffer device 5 in
  Fun.protect ~finally:(fun () -> C.close circles; ignore (B.destroy_buffer positions);
    ignore (B.destroy_queue queue); ignore (B.destroy_device device); ignore (B.destroy_device other)) (fun () ->
    let run count radius width = C.dispatch circles ~source:positions ~count ~radius
      ~fill:(-1l) ~stroke:0l ~stroke_width:width in
    let first=get (run 0 2. 1.) in
    assert (B.buffer_size first=64L && !ended=0);
    let next=get (run 3 2. 1.) in
    assert (B.buffer_size next=256L && get (run 4 2. 1.)==next);
    ignore (get (run 5 2. 1.)); assert (Result.is_error (B.read_buffer next ~offset:0L ~length:0));
    assert (Bytes.length !uniforms=20 && Bytes.get_int32_le !uniforms 4=Int32.bits_of_float 2.
      && Bytes.get_int32_le !uniforms 8=(-1l) && Bytes.get_int32_le !uniforms 12=0l);
    expect Capacity (run (-1) 1. 1.); expect Capacity (run 1_000_001 1. 1.);
    expect Invalid_argument (run 6 1. 1.);
    List.iter (fun bad -> expect Invalid_argument (run 1 bad 1.); expect Invalid_argument (run 1 1. bad))
      [nan;infinity; -1.; 3.5e38];
    let foreign=buffer other 1 in
    expect Cross_device (C.dispatch circles ~source:foreign ~count:1 ~radius:1. ~fill:0l ~stroke:0l ~stroke_width:1.);
    ignore (B.destroy_buffer foreign);
    let before= !ended in fail:=true; expect Invalid_state (run 1 1. 1.);
    assert (!ended=before+1 && !abandoned=2); fail:=false;
    expect Invalid_state (Domain.join (Domain.spawn (fun () -> run 1 1. 1.)));
    assert (Domain.join (Domain.spawn (fun () -> try C.close circles; false with Invalid_argument _ -> true)));
    expect Invalid_state (Domain.join (Domain.spawn (fun () -> C.create ~device ~queue)));
    let dense=buffer device 1_000_000 in
    let largest=get (C.dispatch circles ~source:dense ~count:1_000_000 ~radius:0.
      ~fill:0l ~stroke:0l ~stroke_width:0.) in
    assert (B.buffer_size largest=64_000_000L && get (run 1 1. 1.)==largest);
    ignore (B.destroy_buffer dense);
    C.close circles; C.close circles; expect Invalid_state (run 1 1. 1.);
    assert (!reads=0 && !pipelines=0);
    assert (List.for_all (fun (descriptor:Ogpu.Types.buffer_descriptor) ->
      descriptor.usage=[Storage] || descriptor.usage=[Vertex;Storage]) !descriptors));
  assert (live ()=0);
  print_endline "GPU circles: mock ownership, bounded geometric reuse, style validation, abandonment and no readback pass"
let () =
  if Array.exists ((=) "--source") Sys.argv then print_string C.source
  else if Array.exists ((=) "--native") Sys.argv then native () else mock ()
