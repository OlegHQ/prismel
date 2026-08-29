let require condition message=if not condition then failwith message
let get=function Ok value->value|Error error->
  failwith(Format.asprintf"%a"Prismel_next_execution.pp_error error)
let get_resource=function Ok value->value|Error error->
  failwith(Format.asprintf"%a"Prismel_next_resources.pp_error error)
let get_ir=function Ok value->value|Error _->failwith"render IR fixture"
let expect_error message=function Error _->()|Ok _->failwith message
let drain()=match Metal.Release_queue.drain()with
  |Ok _->()|Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let live_handles()=match Metal.Release_queue.stats()with
  |Ok stats->stats.live_handles
  |Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let pixel bytes offset expected message=
  require(Bytes.sub bytes offset 4=expected)message
let putf bytes offset value=Bytes.set_int64_le bytes offset(Int64.bits_of_float value)
let scene3_draw key red=
  let vertices=Bytes.make(3*68)'\000'and indices=Bytes.create 12 in
  List.iteri(fun index(x,y)->let offset=index*68 in
    putf vertices offset x;putf vertices(offset+8)y;
    putf vertices(offset+16)0.;putf vertices(offset+24)1.;
    putf vertices(offset+28)red;putf vertices(offset+36)0.;
    putf vertices(offset+44)0.;putf vertices(offset+52)0.;
    putf vertices(offset+60)0.)[-1.,1.;1.,1.;-1.,-1.];
  List.iteri(fun index value->Bytes.set_int32_le indices(index*4)value)[0l;1l;2l];
  let mesh:Scene_execution.mesh={key;vertices;vertex_count=3;indices;index_count=3}
  and state:Scene_execution.state={viewport=(0,0,5,4);scissor=(0,0,5,4);
    cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
    depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;
    transform_uniforms=None;stencil_state=None;
    stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0}in
  Prismel_next_execution.prepared_draw~family:Scene3
    {Scene_execution.mesh;state}

let ()=
  let baseline=live_handles()in
  let configuration={Prismel_next_execution.default_configuration with
    logical_width=3;logical_height=2;drawable_width=3;drawable_height=2;
    title="offscreen-test";vsync=false}in
  match Prismel_next_execution.create_offscreen configuration with
  |Error _->print_endline"Prismel offscreen: skipped (no native Metal device)"
  |Ok execution->
      try
        ignore(get(Prismel_next_execution.step~clear:(1.,0.,0.,1.)execution[]));
        let first=get(Prismel_next_execution.capture execution)in
        require(Bytes.length first=3*2*4)"offscreen initial extent";
        pixel first 0(Bytes.of_string"\255\000\000\255")
          "offscreen initial clear pixel";
        let first_into=Bytes.create(Bytes.length first)in
        ignore(get(Prismel_next_execution.capture_into execution
          ~destination:first_into));
        require(first_into=first)"offscreen caller-owned capture changed pixels";
        expect_error"offscreen caller-owned capture accepted a short destination"
          (Prismel_next_execution.capture_into execution
            ~destination:(Bytes.create(Bytes.length first-1)));
        ignore(get(Prismel_next_execution.resize execution~logical_width:5
          ~logical_height:4~drawable_width:5~drawable_height:4));
        ignore(get(Prismel_next_execution.step~clear:(0.,0.,1.,1.)execution[]));
        let resized=get(Prismel_next_execution.capture execution)in
        require(Bytes.length resized=5*4*4)"offscreen resized extent";
        pixel resized((5*4-1)*4)(Bytes.of_string"\000\000\255\255")
          "offscreen resized clear pixel";
        let facts=get(Prismel_next_execution.presentation_facts execution)in
        require(facts.logical_width=5&&facts.logical_height=4&&
          facts.drawable_width=5&&facts.drawable_height=4&&not facts.vsync)
          "offscreen resized facts";
        let render_retained version draw=
          let submission=get(Prismel_next_execution.Private.begin_submission execution)in
          let batch=get(Prismel_next_execution.Private.adopt_draws submission[draw])in
          ignore(get(Prismel_next_execution.Private.step~identity:"offscreen-retained"
            ~version submission[batch]))in
        let red=scene3_draw"retained-red"1. in
        render_retained 1L red;
        let uploaded=(get(Prismel_next_execution.stats execution)).uploaded_bytes in
        render_retained 1L(scene3_draw"ignored-same-version"0.);
        require((get(Prismel_next_execution.stats execution)).uploaded_bytes=uploaded)
          "retained replay revalidated or uploaded a same-version payload";
        render_retained 2L(scene3_draw"retained-black"0.);
        require((get(Prismel_next_execution.stats execution)).uploaded_bytes>uploaded)
          "retained version invalidation did not prepare the replacement payload";
        let incomplete=get(Prismel_next_execution.Private.begin_submission execution)in
        let incomplete_batch=get(Prismel_next_execution.Private.adopt_draws incomplete[red])in
        expect_error"retained identity without version was accepted"
          (Prismel_next_execution.Private.step~identity:"incomplete"incomplete
            [incomplete_batch]);
        let stats=get(Prismel_next_execution.stats execution)in
        require(stats.frames=5L&&stats.presented=0L&&
          stats.logical_submissions=5L)"offscreen no-presentation accounting";
        let image=get_resource(Prismel_next_resources.Image.create~width:1
          ~height:1~rgba:(Bytes.of_string"\xff\x00\x00\xff"))in
        let replacement=ref 0 in
        let replace image=
          incr replacement;
          let red=if !replacement land 1=0 then '\xff' else '\x00' in
          Prismel_next_resources.Image.replace image~width:1~height:1
            ~rgba:(Bytes.of_string(String.make 1 red^"\x00\x00\xff"))in
        Fun.protect
          ~finally:(fun()->ignore(Prismel_next_resources.Image.destroy image))
          (fun()->
            let rect:Scene_command.Render_ir.rect=
              {x=0.;y=0.;width=1.;height=1.}in
            let image_ir=get_ir(Scene_command.Render_ir.create[|
              Scene_command.Render_ir.Image
                {resource_id=1;source=rect;destination=rect}|])
            and missing_ir=get_ir(Scene_command.Render_ir.create[|
              Scene_command.Render_ir.Image
                {resource_id=2;source=rect;destination=rect}|])in
            let resolve=function 1->Some(Prismel_next_execution.Image image)|_->None in
            ignore(get(Prismel_next_execution.lower_scene2 execution~density:1
              ~resource:resolve image_ir));
            ignore(get_resource(replace image));
            let first=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 first~density:1
              ~resource:resolve image_ir));
            ignore(get_resource(replace image));
            let failed=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 failed~density:1
              ~resource:resolve image_ir));
            expect_error"two isolated snapshot leases did not bound mutation"
              (replace image);
            expect_error"later lowering failure was accepted"
              (Prismel_next_execution.Private.lower_scene2 failed~density:1
                ~resource:resolve missing_ir);
            let overlap=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 overlap~density:1
              ~resource:resolve image_ir));
            expect_error"failed submission released another submission's lease"
              (replace image);
            Prismel_next_execution.Private.cancel first;
            ignore(get_resource(replace image));
            Prismel_next_execution.Private.cancel first;
            Prismel_next_execution.Private.cancel overlap;
            let step_failed=get(Prismel_next_execution.Private.begin_submission execution)in
            let step_draws=get(Prismel_next_execution.Private.lower_scene2 step_failed
              ~density:1~resource:resolve image_ir)in
            ignore(get_resource(replace image));
            let step_overlap=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 step_overlap
              ~density:1~resource:resolve image_ir));
            expect_error"step-failure overlap fixture did not exhaust snapshots"
              (replace image);
            expect_error"non-finite clear unexpectedly submitted"
              (Prismel_next_execution.Private.step~clear:(Float.nan,0.,0.,1.)
                step_failed[step_draws]);
            ignore(get_resource(replace image));
            expect_error"consumed failed submission was reusable"
              (Prismel_next_execution.Private.step step_failed[]);
            Prismel_next_execution.Private.cancel step_failed;
            Prismel_next_execution.Private.cancel step_overlap;
            let cross_first=get(Prismel_next_execution.Private.begin_submission execution)in
            let cross_batch=get(Prismel_next_execution.Private.lower_scene2 cross_first
              ~density:1~resource:resolve image_ir)in
            let cross_second=get(Prismel_next_execution.Private.begin_submission execution)in
            expect_error"cross-submission draw batch was accepted"
              (Prismel_next_execution.Private.step cross_second[cross_batch]);
            Prismel_next_execution.Private.cancel cross_first;
            let two_image_ir=get_ir(Scene_command.Render_ir.create[|
              Scene_command.Render_ir.Image
                {resource_id=1;source=rect;destination=rect};
              Scene_command.Render_ir.Image
                {resource_id=2;source=rect;destination=rect}|])in
            let second_lookups=ref 0 in
            let raising_resolver=function
              |1->Some(Prismel_next_execution.Image image)
              |2->incr second_lookups;
                  if !second_lookups>1 then raise Exit
                  else Some(Prismel_next_execution.Image image)
              |_->None in
            let exceptional=get(Prismel_next_execution.Private.begin_submission execution)in
            expect_error"raising resolver escaped the typed boundary"
              (Prismel_next_execution.Private.lower_scene2 exceptional
                ~density:1~resource:raising_resolver two_image_ir);
            let exception_probe=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 exception_probe
              ~density:1~resource:resolve image_ir));
            ignore(get_resource(replace image));
            Prismel_next_execution.Private.cancel exception_probe;
            let succeeded=get(Prismel_next_execution.Private.begin_submission execution)in
            let succeeded_batch=get(Prismel_next_execution.Private.lower_scene2 succeeded
              ~density:1~resource:resolve image_ir)in
            let expected=get_resource(Prismel_next_resources.Image.pixels image)in
            ignore(get(Prismel_next_execution.Private.step succeeded[succeeded_batch]));
            let submitted=get(Prismel_next_execution.capture execution)in
            pixel submitted 0 expected"successful transaction changed snapshot pixels";
            ignore(get_resource(replace image));
            let destroy_first=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 destroy_first
              ~density:1~resource:resolve image_ir));
            ignore(get_resource(replace image));
            let destroy_second=get(Prismel_next_execution.Private.begin_submission execution)in
            ignore(get(Prismel_next_execution.Private.lower_scene2 destroy_second
              ~density:1~resource:resolve image_ir));
            expect_error"destroy overlap fixture did not exhaust snapshots"
              (replace image);
            ignore(get(Prismel_next_execution.destroy execution));
            ignore(get_resource(replace image));
            expect_error"destroyed coordinator began a submission"
              (Prismel_next_execution.Private.begin_submission execution);
            Prismel_next_execution.Private.cancel destroy_first;
            Prismel_next_execution.Private.cancel destroy_second);
        ignore(get(Prismel_next_execution.destroy execution));drain();
        require(live_handles()=baseline)"offscreen resize Metal live-handle delta";
        print_endline"Prismel offscreen: clear/readback/resize, no present, zero delta"
      with exn->ignore(Prismel_next_execution.destroy execution);drain();raise exn
