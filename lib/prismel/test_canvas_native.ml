open Prismel

let require condition message=if not condition then failwith message
let channel canvas ~x ~y=
  match Canvas.pixel canvas~x~y with
  |Some color->Color.to_tuple color
  |None->failwith"Canvas native pixel is out of bounds"
let drain()=match Metal.Release_queue.drain()with
  |Ok _->()|Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let live_handles()=match Metal.Release_queue.stats()with
  |Ok stats->stats.live_handles
  |Error error->failwith(Format.asprintf"%a"Metal.pp_error error)

let ()=
  let baseline=live_handles()in
  let canvas=Canvas.create_exn~width:8~height:8 in
  let rendered=ref 0 in
  let render scene=Canvas.render canvas scene;incr rendered in
  try
    render Scene.[clear(Color.rgba 7 11 13 17)];
    require(channel canvas~x:0~y:0=(7,11,13,17))
      "Canvas native clear-only pixel";
    render Scene.[clear Color.blue;
      rect~at:(2,2)~w:4~h:4~fill:Color.green()];
    require(channel canvas~x:0~y:0=(0,0,255,255))
      "Canvas native drawn background";
    require(channel canvas~x:3~y:3=(0,255,0,255))
      "Canvas native drawn foreground";
    for frame=3 to 600 do
      let clear_color=if frame land 1=0 then Color.red else Color.blue in
      render Scene.[clear clear_color;
        rect~at:(2,2)~w:4~h:4~fill:Color.green()];
      if frame=60||frame=600 then begin
        require(channel canvas~x:0~y:0=(255,0,0,255))
          "Canvas native repeated-frame background";
        require(channel canvas~x:3~y:3=(0,255,0,255))
          "Canvas native repeated-frame foreground"
      end
    done;
    require(!rendered=600)"Canvas native frame count";
    let stats=Canvas.Private.native_stats canvas in
    require(stats.frames=600L&&stats.logical_submissions=600L&&
      stats.logical_passes=600L)"Canvas native submission accounting";
    require(stats.logical_draws>=599L)"Canvas native draw accounting";
    require(stats.uploaded_bytes>0L)"Canvas native upload accounting";
    require(stats.cache_entries<=32)"Canvas native bounded execution cache";
    let image=Result.get_ok(Canvas.to_image canvas)in
    Fun.protect~finally:(fun()->Image.destroy image)(fun()->
      require(Image.get_size image=(8,8))"Canvas native to_image extent";
      let pixels=Result.get_ok(Image.Private.pixels image)in
      require(Bytes.sub pixels 0 4=Bytes.of_string"\255\000\000\255")
        "Canvas native to_image exact pixel");
    Canvas.destroy canvas;drain();
    require(live_handles()=baseline)"Canvas native Metal live-handle delta";
    print_endline
      "Canvas native: clear/draw/readback/to_image frames1/2/60/600, bounded cache, zero delta"
  with exn->Canvas.destroy canvas;drain();raise exn
