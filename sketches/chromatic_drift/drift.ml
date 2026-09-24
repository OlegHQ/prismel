open Prismel

type settings = { seed:int; palette:int; bend:float; scale:float;
  slope:float; spread:float; glow:float; softness:float;
  warp:float; detail:float; independent:float; breathing:float;
  hue:float; saturation:float; exposure:float; color_mix:float;
  variation:float; color_speed:float; offset:float;
  quality:int; depth:float; curl:float; shadow:float; roughness:float; light_angle:float;
  sweep:float; radiance:float; color_depth:float }
let default = {seed=42; palette=0; bend=0.10; scale=1.1; slope=1.1;
  spread=1.; glow=0.95; softness=0.5; warp=0.45; detail=0.25;
  independent=0.5; breathing=0.25; hue=0.; saturation=1.15;
  exposure=0.; color_mix=0.; variation=0.35; color_speed=0.5; offset=0.;
  quality=2; depth=0.025; curl=0.; shadow=0.; roughness=0.95; light_angle=0.7;
  sweep=0.85; radiance=0.8; color_depth=0.7 }
let palettes = [| "Afterglow"; "Lagoon"; "Ember"; "Orchid" |]
let rgb = Color.rgb
let colors = [|
  [|rgb 255 97 183; rgb 255 121 111; rgb 250 30 160; rgb 87 28 203; rgb 25 13 98|];
  [|rgb 247 211 164; rgb 82 207 190; rgb 26 107 133; rgb 135 237 223; rgb 5 31 67|];
  [|rgb 255 137 96; rgb 227 68 83; rgb 126 33 99; rgb 248 165 106; rgb 38 12 56|];
  [|rgb 238 144 240; rgb 166 104 233; rgb 67 44 151; rgb 144 184 252; rgb 24 13 69|]
|]
let clamp a b x = max a (min b x)
let mix a b t = Color.blend a b ~pct:(clamp 0. 1. t)
let resolution p = let q=max 1 (min 3 p.quality) in 128*q,24*q
let vertex_count p = let cols,rows=resolution p in 5*(cols+1)*(rows+1)
(* Adjacent sheets share exactly the same boundary samples. The differential
   displacement is bounded below half the minimum spacing, preventing crossings. *)
let boundaries p noise time x =
  let warped=x*.p.scale +. p.warp*.(Noise.sample3 noise
    ~x:(x*.0.7) ~y:9.3 ~z:(time*.0.6)-.0.5)*.3. in
  let common=p.bend*.(
    (Noise.sample3 noise ~x:warped ~y:0.31 ~z:time-.0.5)*.2.
    +. p.detail*.(Noise.sample3 noise ~x:(warped*.2.7)
      ~y:4.1 ~z:(time*.1.3)-.0.5)) in
  let spacing=0.255*.p.spread*.(1.+.0.15*.p.breathing*.sin(time*.0.8)) in
  let sweep= -.p.sweep*.(sqrt(0.12+.(x+.0.55)**2.)-.0.55) in
  let offsets=[|0.; -0.8; -0.32; 0.18; 1.5; 0.|] in
  Array.init 6 (fun i ->
    if i=0 then -8. else if i=5 then 8. else
    offsets.(i)*.(spacing/.0.255) +.p.slope*.x+.sweep+.common+.p.offset
    +.spacing*.0.7*.p.independent*.
      (Noise.sample3 noise ~x:(warped*.0.7)
        ~y:(float i*.1.7) ~z:(time*.0.7)-.0.5))
let build p time =
  let cols,rows=resolution p in
  let noise=Noise.create p.seed in
  let edges=Array.init (cols+1) (fun i ->
    boundaries p noise time (-2. +. 4.*.float i/.float cols)) in
  let palette=colors.(p.palette) in
  let meshes=List.init 5 (fun band ->
    let n=(cols+1)*(rows+1) in
    let x=Array.make n 0. and y=Array.make n 0. and z=Array.make n 0.
    and color=Array.make n Color.white in
        let alternate=colors.((p.palette+1) mod Array.length colors) in
    let base=mix palette.(band) alternate.(band) p.color_mix in
    let base=Color.rotate_hue base (p.hue +. p.variation*.45.*.
      (Noise.sample2 noise ~x:(float band*.2.3) ~y:(time*.p.color_speed)-.0.5)) in
    let tint=if band<3 then rgb 255 246 207 else rgb 206 231 255 in
    let br=float base.r and bg=float base.g and bb=float base.b
    and tr=float tint.r and tg=float tint.g and tb=float tint.b in
    let us=Array.init (rows+1) (fun j -> 0.5-.0.5*.cos(Float.pi*.float j/.float rows)) in
    let arches=Array.map (fun u -> sin(Float.pi*.u)) us in
    let curls=Array.map (fun u -> exp(-.u/.0.065)) us in
    for i=0 to cols do
      let px= -2. +. 4.*.float i/.float cols in
      let top=edges.(i).(band) and bottom=edges.(i).(band+1) in
      let drift=clamp 0. 1. (0.5+.0.3*.sin(px*.1.8+.float band+.time*.p.color_speed)
        +.p.variation*.(Noise.sample3 noise ~x:(px*.1.8)
          ~y:(float band*.2.1) ~z:(time*.p.color_speed)-.0.5)*.2.) in
      let ripple=0.8+.0.2*.sin(px*.2.7+.time+.float band) in
      let pool_center=if band<3 then 0.45 else -0.42 in
      let pool_x=exp(-.(((px-.pool_center-.0.16*.sin(time*.0.4))/.0.5)**2.)) in
      for j=0 to rows do
        (* Cluster samples near visible boundaries, including terminal sheets. *)
        let u=us.(j) in
        let py=top+.(bottom-.top)*.u in
        let k=i*(rows+1)+j in
        x.(k)<-px; y.(k)<- -.py;
        z.(k)<-p.depth*.(arches.(j)*.ripple+.p.curl*.curls.(j));
        let distance=if band<3 then bottom-.py else py-.top in
        let width=0.035+.p.softness*.0.25 in
        let light=exp(-.((distance/.width)**2.))*.p.glow*.
          (if band=2 || band=4 then 0. else 1.) in
        let pool_y=if band<3 then -0.45 else 0.3 in
        let pool=p.radiance*.pool_x*.exp(-.(((py-.pool_y)/.0.6)**2.)) in
        let blend=clamp 0. 1. (0.06*.drift+.light*.0.92+.
          pool*.(if band<3 then 0.9 else 0.5)) in
        let inv=1.-.blend in
        let shade=p.color_depth*.(if band<3 then 0.1 else 0.5)*.(1.-.light)*.
          exp(-.(((distance-.width*.1.8)/.(0.20+.width))**2.)) +.
          p.shadow*.exp(-.(py-.top)/.(0.015+.p.depth*.0.3)) in
        let shade=1.-.clamp 0. 1. shade in
        (* Preserve Color.blend's rounding without temporary color records. *)
        let r=float(int_of_float(float(int_of_float(br*.inv+.tr*.blend+.0.5))*.shade+.0.5))
        and g=float(int_of_float(float(int_of_float(bg*.inv+.tg*.blend+.0.5))*.shade+.0.5))
        and b=float(int_of_float(float(int_of_float(bb*.inv+.tb*.blend+.0.5))*.shade+.0.5)) in
        let gray=0.2126*.r+.0.7152*.g+.0.0722*.b in
        let channel v=int_of_float(clamp 0. 255.
          (gray+.(v-.gray)*.p.saturation+.p.exposure*.255.)) in
        color.(k)<-Color.rgb (channel r) (channel g) (channel b)

      done
    done;
    let indices=Array.make (cols*rows*6) 0 in
    for i=0 to cols-1 do for j=0 to rows-1 do
      let k=(i*rows+j)*6 and a=i*(rows+1)+j in
      indices.(k)<-a; indices.(k+1)<-a+1; indices.(k+2)<-a+rows+1;
      indices.(k+3)<-a+1; indices.(k+4)<-a+rows+2; indices.(k+5)<-a+rows+1
    done done;
    (* Height-field gradients account for the curved band parameterization.
       Locally owned numeric arrays; O(vertices), no topology kernel needed. *)
    let normals:Mesh.Private.vec3_view={x=Array.make n 0.;y=Array.make n 0.;z=Array.make n 1.} in
    for i=0 to cols do for j=0 to rows do
      let k=i*(rows+1)+j in
      let l=max 0 (i-1)*(rows+1)+j and r=min cols (i+1)*(rows+1)+j in
      let a=i*(rows+1)+max 0 (j-1) and b=i*(rows+1)+min rows (j+1) in
      let zy=(z.(b)-.z.(a))/.(y.(b)-.y.(a)) in
      let zx=((z.(r)-.z.(l))-.zy*.(y.(r)-.y.(l)))/.(x.(r)-.x.(l)) in
      let inv=1./.sqrt(1.+.zx*.zx+.zy*.zy) in
      normals.x.(k)<- -.zx*.inv; normals.y.(k)<- -.zy*.inv; normals.z.(k)<-inv
    done done;
    let spec=int_of_float(100.*.(1.-.p.roughness)) in
    let material=Material.create ~diffuse:Color.white ~ambient:Color.white
      ~specular:(rgb spec spec spec) ~shininess:(8.+.100.*.(1.-.p.roughness)) () in
    match Mesh.Private.create_packed_owned ~indices ~normals ~colors:color {x;y;z} with
    | Ok mesh-> Scene3.mesh ~material ~cull:Scene3.Cull_none mesh
    | Error e->failwith e) in
  Scene3.create ~ambient:(rgb 179 179 179) ~lights:[Light.directional
    ~intensity:0.35 ~direction:(Vec3.create (cos p.light_angle*.0.65)
      (sin p.light_angle*.0.65) (-1.)) ()] meshes

(* A bounded procedural texture, sampled/blended by Metal. A sum of independent
   uniforms gives softer photographic grain than isolated triangular flecks. *)
let grain seed amount ~size ~height =
  let side=256 in
  let rng=Rand.seed seed in
  let table=Array.init 511 (fun i ->
    let d=float(i-255)/.255. in
    Color.with_alpha (if d>=0. then Color.white else Color.black)
      (int_of_float(amount*.255.*.abs_float d))) in
  let pixels=Array.init (side*side) (fun i ->
    let sample=ref 0. in
    for j=0 to 3 do sample:= !sample+.Rand.float_at rng ~index:(i*4+j) done;
    table.(int_of_float(clamp 0. 510. (255.+.(!sample-.2.)*.127.5)))) in
  let texture=match Texture.Private.create_owned ~width:side ~height:side pixels with
    | Ok t->t | Error e->failwith e in
  let repeats=float height/.(float side*.size) in
  let mesh=Mesh.create_exn ~indices:[0;1;2;2;1;3]
    ~normals:(List.init 4 (fun _->Vec3.create 0. 0. 1.))
    ~tex_coords:[Vec2.create 0. 0.; Vec2.create 0. repeats;
      Vec2.create (4.*.repeats) 0.; Vec2.create (4.*.repeats) repeats]
    [Vec3.create (-2.) 0.5 0.; Vec3.create (-2.) (-0.5) 0.;
     Vec3.create 2. 0.5 0.; Vec3.create 2. (-0.5) 0.] in
  Scene3.create [Scene3.with_depth (Scene3.depth_state ~comparison:Scene3.Always ~write:false ())
    [Scene3.with_blend Scene3.Alpha
      [Scene3.mesh ~texture:(Scene3.textured ~filter:Texture.Bilinear
        ~wrap_u:Texture.Repeat ~wrap_v:Texture.Repeat texture)
        ~material:(Material.unlit Color.white) ~cull:Scene3.Cull_none mesh]]]
