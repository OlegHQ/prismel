module P=Runtime_wap_raster2_presenter.Wap_raster2_presenter
let ok=function Ok value->value|Error _->failwith"presenter"
let frame ~w ~h ~pitch seed=
  let rgba=Bytes.make(pitch*h)'\255'in for y=0 to h-1 do for x=0 to w*4-1 do Bytes.set rgba(y*pitch+x)(Char.chr((seed+x+y*13)land 255))done done;
  P.{rgba;pitch;logical_width=w;logical_height=h;drawable_width=w;drawable_height=h}
let()=
  let config={Wap.default_config with interface="127.0.0.1";port=0;max_frame_pool_bytes=4096;compress_frames=false}in
  let presenter=ok(P.create~config())in
  List.iter(fun seed->ok(P.present presenter(frame~w:7~h:5~pitch:32 seed)))[1;2;60;600];
  ok(P.present presenter(frame~w:9~h:3~pitch:40 601));
  let duplicate=frame~w:1~h:1~pitch:8 7 in for _=1 to 100000 do ok(P.present presenter duplicate)done;
  let stats=P.stats presenter in if stats.frames_submitted<>100005||stats.frames_suppressed<99999||stats.source_bytes_submitted<>400668L then failwith"bounded packed queue";
  begin match P.present presenter{duplicate with pitch=3}with Error(P.Invalid_frame _)->()|_->failwith"pitch"end;
  if P.port presenter<=0 then failwith"port";P.destroy presenter;P.destroy presenter;
  begin match P.present presenter duplicate with Error P.Destroyed->()|_->failwith"destroy"end;
  print_endline"SDL-free Wap Raster2 presenter passed"
