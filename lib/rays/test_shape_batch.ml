open Rays
module B=Scene_command.Shape_batch
let require condition message=if not condition then failwith message
let rgba (c:Color.t)=Int32.of_int((c.r lsl 24)lor(c.g lsl 16)lor(c.b lsl 8)lor c.a)
let segment_distance (x,y) (ax,ay) (bx,by) =
  let dx=bx-.ax and dy=by-.ay in
  let length2=dx*.dx+.dy*.dy in
  let t=if length2=0. then 0. else Float.max 0.(Float.min 1.
    (((x-.ax)*.dx+.(y-.ay)*.dy)/.length2))in
  Float.hypot(x-.ax-.t*.dx)(y-.ay-.t*.dy)
(* Scene.circle's reference is an integer 32-gon, not an ideal radius. *)
let circle_boundary ~x ~y ~radius = Array.init 32(fun i->
  let angle=2.*.Float.pi*.float i/.32. in
  float(x+int_of_float(float radius*.cos angle)),
  float(y+int_of_float(float radius*.sin angle)))
let boundary_distance points sample =
  Array.fold_left Float.min infinity(Array.mapi(fun i point->
    segment_distance sample point points.((i+1)mod Array.length points))points)
let batch count =
  let b=B.Builder.create ~capacity:count ()in
  for i=0 to count-1 do
    B.Builder.circle b ~x:(8.+.float(i mod 19)*.2.) ~y:(8.+.float(i mod 13)*.2.)
      ~radius:3. ~fill:(rgba(Color.rgba 40 120 180 70)) ()
  done;B.Builder.publish b
let pure ()=
  require(segment_distance (0.5,1.) (0.,0.) (1.,0.)=1.)"sample-center boundary distance";
  require(segment_distance (2.,0.) (0.,0.) (1.,0.)=1.)"boundary endpoint distance";
  require(boundary_distance(circle_boundary ~x:32 ~y:32 ~radius:12)(32.,32.)>10.)
    "circle boundary interior";
  List.iter(fun count->let b=batch count in
    require(B.count b=count)"shape count";
    require(Bytes.length(B.instances b)=64*count)"shape layout";
    let commands=Scene.Private.commands [Scene.Private.shapes b]in
    require(Array.length commands=1)"one packed command";
    require(B.Private.valid b)"packed validation") [0;1;63;64;65;100000];
  let b=B.Builder.create ()in
  B.Builder.line b ~x0:1.25 ~y0:2.5 ~x1:9.75 ~y1:10. ~color:0xffffffffl ~width:1.5;
  let b=B.Builder.publish b in
  let bytes=B.instances b in
  require(Int32.float_of_bits(Bytes.get_int32_le bytes 0)=1.25)"fractional coordinates";
  let ir=Result.get_ok(Scene_command.Render_ir.create [|Shapes b|])in
  let original=Scene_command.Render_ir.serialize ir in
  Bytes.set_int32_le bytes 52 (Int32.bits_of_float nan);
  require(not(B.Private.valid b))"nonfinite anti-alias boundary";
  Bytes.set_int32_le bytes 52 (Int32.bits_of_float 1.);
  Bytes.set_int32_le bytes 0 (Int32.bits_of_float nan);
  require(not(B.Private.valid b))"nonfinite boundary";
  require(Scene_command.Render_ir.create [|Shapes b|]=Error Invalid_cardinality)"invalid commands";
  require(original=Scene_command.Render_ir.serialize ir)"owned command snapshot";
  let b=B.Builder.create ()in
  require((try B.Builder.circle b ~x:0. ~y:0. ~radius:(-1.) ();false
    with Invalid_argument _->true))"negative radius";
  require((try B.Builder.line b ~x0:1e100 ~y0:0. ~x1:1. ~y1:1. ~color:0l ~width:1.;false
    with Invalid_argument _->true))"float32 overflow";
  print_endline "shapes: layout, finite bounds, owned commands, fractional coordinates, 100000 instances"
let native ()=
  let canvas=Canvas.create_exn ~width:64 ~height:64 in
  Fun.protect ~finally:(fun()->Canvas.destroy canvas)(fun()->
    let b=B.Builder.create ()in
    B.Builder.circle b ~x:32. ~y:32. ~radius:12. ~fill:(rgba Color.cyan) ();
    let packed=Scene.Private.shapes(B.Builder.publish b)in
    Canvas.render canvas [Scene.clear Color.black;Scene.circle ~at:(32,32) ~radius:12 ~fill:Color.cyan ()];
    let polygon=Canvas.pixels canvas in
    Canvas.render canvas [Scene.clear Color.black;packed];
    let sdf=Canvas.pixels canvas in
    let boundary=circle_boundary ~x:32 ~y:32 ~radius:12 in
    let worst=ref 0. in
    Array.iteri(fun i expected->
      if sdf.(i)<>expected then
        worst:=Float.max !worst(boundary_distance boundary(float(i mod 64)+.0.5,float(i/64)+.0.5)))polygon;
    Printf.printf "circle rim: differing pixels at most %.3f px from the reference 32-gon\n%!" !worst;
    (* The SDF rim anti-aliases one pixel in each axis: a diagonal neighbour of
       the reference rim is sqrt 2 away (native: 1.414 px on the Apple M1). *)
    require(!worst<=Float.sqrt 2.)"circle differs more than one pixel per axis from the reference 32-gon rim";
    (* Compare against the independent polygon/path renderer. Differences are
       allowed only within one logical pixel of a boundary; interior RGBA must
       agree within one quantization unit, including alpha and stroke. *)
    let compare reference packed =
      let wrap nodes=Scene.clip ~at:(7,9) ~w:43 ~h:37 [Scene.translate 32 32
        [Scene.rotate 0.37 [Scene.scale 1.7 0.8 [Scene.translate (-32) (-32) nodes]]]]in
      Canvas.render canvas [Scene.clear Color.black;wrap [reference]];
      let expected=Canvas.pixels canvas in
      Canvas.render canvas [Scene.clear Color.black;wrap [packed]];
      let actual=Canvas.pixels canvas in
      let inside array x y=x>=0 && x<64 && y>=0 && y<64 && array.(y*64+x)<>expected.(0)in
      let neighbor array x y=List.exists(fun(dx,dy)->inside array (x+dx)(y+dy))
        [-1,-1;0,-1;1,-1;-1,0;0,0;1,0;-1,1;0,1;1,1]in
      Array.iteri(fun i value->let x=i mod 64 and y=i/64 in
        require(not(inside actual x y)||neighbor expected x y)"SDF exceeds one-pixel reference rim";
        require(not(inside expected x y)||neighbor actual x y)"SDF misses reference beyond one-pixel rim";
        let interior array=List.for_all(fun(dx,dy)->inside array(x+dx)(y+dy))
          [-1,-1;0,-1;1,-1;-1,0;0,0;1,0;-1,1;0,1;1,1]in
        if interior expected && interior actual then
          List.iter(fun channel->
            require(abs(channel value-channel actual.(i))<=1)"reference interior RGBA drift")
            [(fun(c:Color.t)->c.r);(fun c->c.g);(fun c->c.b);(fun c->c.a)])expected in
    List.iter(fun alpha->let fill=Color.rgba 40 120 180 alpha
      and stroke=Color.rgba 230 80 20 alpha in
      let b=B.Builder.create ()in
      B.Builder.circle b ~x:32. ~y:32. ~radius:12. ~fill:(rgba fill) ~stroke:(rgba stroke) ();
      compare (Scene.circle ~at:(32,32) ~radius:12 ~fill ~stroke ())
        (Scene.Private.shapes(B.Builder.publish b));
      let b=B.Builder.create ()in
      B.Builder.rect b ~x:12. ~y:14. ~width:26. ~height:21. ~fill:(rgba fill) ~stroke:(rgba stroke) ();
      compare (Scene.rect ~at:(12,14) ~w:26 ~h:21 ~fill ~stroke ())
        (Scene.Private.shapes(B.Builder.publish b));
      let b=B.Builder.create ()in
      B.Builder.line b ~x0:12. ~y0:14. ~x1:41. ~y1:39. ~width:5. ~color:(rgba fill);
      compare (Scene.line ~from_:(12,14) ~to_:(41,39) ~width:5 ~color:fill ())
        (Scene.Private.shapes(B.Builder.publish b))) [70;255];
    let wrap nodes=Scene.clip ~at:(7,9) ~w:43 ~h:37 [Scene.translate 27 23
      [Scene.rotate 0.37 [Scene.scale 1.7 0.8 nodes]]]in
    List.iter(fun (blend:Scene.blend)->List.iter(fun count->
      let b=batch count in
      Canvas.render canvas [Scene.clear Color.black;Scene.blend blend[wrap [Scene.Private.shapes b]]];
      let expected=Canvas.pixels canvas in
      let single=Array.init count(fun i->let one=B.Builder.create ~capacity:1 ()in
        B.Builder.circle one ~x:(8.+.float(i mod 19)*.2.) ~y:(8.+.float(i mod 13)*.2.)
          ~radius:3. ~fill:(rgba(Color.rgba 40 120 180 70)) ();
        Scene.Private.shapes(B.Builder.publish one))in
      Canvas.render canvas [Scene.clear Color.black;Scene.blend blend[wrap(Array.to_list single)]];
      require(Canvas.pixels canvas=expected)"packed/singular transform clip blend alpha parity") [63;64;65])
      [Scene.Alpha;Replace;Add;Multiply];
    (* Independently construct legacy Scene geometry at all packer thresholds.
       Integer axis-aligned opaque rectangles have identical rasterization, so
       this checks exact pixels rather than comparing two uses of the SDF path.
       The 247 repeated positions keep the 100k frame small enough to qualify. *)
    List.iter(fun count->
      let builder=B.Builder.create ~capacity:count ()in
      let reference=List.init count(fun i->
        let x=8+2*(i mod 19)and y=8+2*(i mod 13)in
        B.Builder.rect builder ~x:(float x) ~y:(float y) ~width:2. ~height:2.
          ~fill:(rgba Color.cyan) ();
        Scene.rect ~at:(x,y) ~w:2 ~h:2 ~fill:Color.cyan ())in
      Canvas.render canvas(Scene.clear Color.black::reference);
      let expected=Canvas.pixels canvas in
      Canvas.render canvas [Scene.clear Color.black;Scene.Private.shapes(B.Builder.publish builder)];
      require(Canvas.pixels canvas=expected)
        (Printf.sprintf "legacy/packed rectangle pixels at %d instances" count)) [63;64;65;100000];
    let dense=batch 100000 in
    Canvas.render canvas [Scene.clear Color.black;Scene.Private.shapes dense];
    let before=Canvas.Private.native_stats canvas in
    Canvas.render canvas [Scene.clear Color.black;Scene.Private.shapes dense];
    let after=Canvas.Private.native_stats canvas in
    require(Int64.sub after.logical_draws before.logical_draws=1L)"100000 instances one draw";
    require(after.uploaded_bytes=before.uploaded_bytes)"static shapes reuploaded";
    Printf.printf "shapes native: 100000 instances, one draw, zero retained upload\n%!");
  print_endline "shapes: native circle tolerance, packed/singular alpha, nonuniform scale/rotation/clip"
let ()=if Array.length Sys.argv>1 && Sys.argv.(1)="native"then native()else pure()
