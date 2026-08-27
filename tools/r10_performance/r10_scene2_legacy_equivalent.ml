type scenario = Basic | Pxui | Canvas
type descriptor = { scenario : scenario; semantic_signature : string;
  work_units : int; required_features : string list;
  canonical_parameters : string }
let phase ~frame = frame mod 240
let describe scenario ~width ~height =
  if width <= 0 || height <= 0 then invalid_arg "non-positive artifact extent";
  let name, work_units, required_features, canonical_parameters = match scenario with
  | Basic -> "basic", 9,
      ["generated-image";"rounded-rect";"circle";"alpha-rect";"animated-polygon";
       "affine-image";"bezier";"ui-text";"debug-text"],
      Printf.sprintf "extent=%dx%d;clear=#07111f;panel=18,18,%d,%d,r18,#111827,#475569;circle=120,150,r72,#0891b2;rect=220,74,180,120,rgba244,63,94,190;polygon=translate338,292,rotate(frame*0.01),[-80,-42;76,-54;98,36;0,74;-88,34],#a78bfa,white;image=generated96x96,at470,92,scale1.15,angle-0.18,center48,48;image_scene=#0f172a,rounded4,4,88,88,r14,#155e75,#67e8f9,circle48,48,r30,rgba251,146,60,220,line18,74,78,22,w5,white;bezier=34,404;176,320;282,474;430,382,steps48,#fbbf24;text=32,38,size18,Prismel renderer baseline;debug=472,430,FIXED 8x8" width height (width-36) (height-36)
  | Pxui -> "pxui", 21,
      ["rounded-rect";"circle";"ui-text";"debug-text";"pxui-four-expanded-accordions";
       "toggle";"slider";"integer-slider";"choice"],
      Printf.sprintf "extent=%dx%d;clear=#07111f;text=24,24,size20,PXUI render baseline;panel=18,62,306,382,r12,#111827,#334155;circle=168,236,r94,#155e75;debug=88,420,GRAPH / INSPECTOR;pxui=x348,y16,width276,row29,padding8,max_height448;sections=0..3,label Section i+1,expanded;each=toggle Enabled alternating-even,slider Amount [-1,1] value i/4,int_slider Steps [1,64] value 8+i,choice Mode [Solid,Wire,Points] selected i%%3" width height
  | Canvas -> "canvas", 5,
      ["offscreen-canvas";"animated-circle";"animated-rounded-rect";"debug-text";"image-snapshot"],
      Printf.sprintf "extent=%dx%d;phase=frame%%240;offscreen=clear#07111f,rect0,0,%d,%d,#0f172a,circle(40+(phase*3)%%max(1,%d),%d,r34,#22d3ee),translate%d,%d,rotate(phase*0.02),rounded(-90,-28,180,56,r14,rgba244,63,94,210,white),debug16,16,CANVAS BASELINE;present=clear-black,image-at0,0" width height width height (width-80) (height/2) (width/2) (height/2) in
  let semantic_signature=Printf.sprintf "r10-public-%s-v2:%s" name
      (Digest.to_hex(Digest.string canonical_parameters)) in
  {scenario;semantic_signature;work_units;required_features;canonical_parameters}
