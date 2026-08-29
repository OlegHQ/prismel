let require condition message=if not condition then failwith message
let get=function Ok value->value|Error error->
  failwith(Format.asprintf"%a"Prismel_next_execution.pp_error error)
let drain()=match Metal.Release_queue.drain()with
  |Ok _->()|Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let live_handles()=match Metal.Release_queue.stats()with
  |Ok stats->stats.live_handles
  |Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let pixel bytes offset expected message=
  require(Bytes.sub bytes offset 4=expected)message

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
        let stats=get(Prismel_next_execution.stats execution)in
        require(stats.frames=2L&&stats.presented=0L&&
          stats.logical_submissions=2L)"offscreen no-presentation accounting";
        ignore(get(Prismel_next_execution.destroy execution));drain();
        require(live_handles()=baseline)"offscreen resize Metal live-handle delta";
        print_endline"Prismel offscreen: clear/readback/resize, no present, zero delta"
      with exn->ignore(Prismel_next_execution.destroy execution);drain();raise exn
