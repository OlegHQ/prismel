open Prismel_next_api
let require condition message=if not condition then failwith message
let ()=
 let canvas=Canvas.create_exn~width:8~height:8 in
 Canvas.render canvas Scene.[clear(Color.rgb 1 2 3);rect~at:(2,2)~w:3~h:3~fill:Color.white()];
 require(Canvas.pixel canvas~x:0~y:0=Some(Color.rgb 1 2 3))"render clear";
 require(Canvas.pixel canvas~x:3~y:3=Some Color.white)"render geometry";
 let offscreen_before=Raster2.Offscreen.counters()in
 let repeated=Scene.[clear(Color.rgb 1 2 3);rect~at:(2,2)~w:3~h:3~fill:Color.white()]in
 Gc.full_major();let allocated_before=Gc.allocated_bytes()in
 for _=1 to 1000 do Canvas.render canvas repeated done;
 let allocated_per_render=(Gc.allocated_bytes()-.allocated_before)/.1000. in
 let offscreen_after=Raster2.Offscreen.counters()in
 require(offscreen_before=offscreen_after)"Canvas.render allocated Offscreen owners";
 require(allocated_per_render<20_000.)"Canvas.render allocation ceiling";
 Printf.printf"Canvas.render allocation: %.0f bytes/render\n"allocated_per_render;
 Canvas.destroy canvas;
 let seen=ref false and output=Filename.temp_file"next-screen-"".png"in
 Fun.protect~finally:(fun()->if Sys.file_exists output then Sys.remove output)(fun()->
  ignore(Sketch.run_state~config:{Sketch.default_config with width=8;height=8}
   ~init:(fun _->())~update:(fun()_->())~view:(fun()_->Scene.[clear(Color.rgb 4 5 6)])
   ~on_stop:(fun()->let captured=Result.get_ok(Canvas.capture())in require(Canvas.size captured=(8,8))"capture size";seen:=true;Canvas.destroy captured;Result.get_ok(Canvas.save_screen_png output))());
 require!seen"capture lifecycle";
 print_endline"next Canvas render/capture/save_screen_png passed")
