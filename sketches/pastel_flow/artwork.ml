open Prismel

(* Normalized art coordinates, independent of the window and backing density.
   These are colored surface meshes; all rasterization is performed by Metal. *)
type control = { key : string; label : string; lo : float; hi : float;
                 waves : float; silk : float }
let c key label lo hi waves silk = { key; label; lo; hi; waves; silk }
let groups = [
  "Composition", [
    c "folds" "Fold strength" 0. 1. 0. 1.;
    c "waves" "Wave visibility" 0. 1. 1. 0.;
    c "zoom" "Zoom" 0.5 2. 1. 1.;
    c "rotation" "Rotation (radians)" (-3.14) 3.14 0. 0.;
    c "pan_x" "Horizontal offset" (-0.5) 0.5 0. 0.;
    c "pan_y" "Vertical offset" (-0.5) 0.5 0. 0. ];
  "Pastel field", [
    c "hue" "Palette hue shift" (-180.) 180. 0. 0.;
    c "saturation" "Saturation" 0. 2. 1. 1.;
    c "exposure" "Brightness" (-0.3) 0.3 0. 0.;
    c "softness" "Color diffusion" 0.5 2. 1. 1.;
    c "mint" "Mint intensity" 0. 2. 1. 1.;
    c "pink" "Pink intensity" 0. 2. 1. 1.;
    c "violet" "Violet intensity" 0. 2. 1. 1.;
    c "blue" "Blue intensity" 0. 2. 1. 1.;
    c "color_x" "Color field X" (-0.5) 0.5 0. 0.;
    c "color_y" "Color field Y" (-0.5) 0.5 0. 0.;
    c "noise_field" "Perlin field mix" 0. 1. 0. 0.;
    c "noise_scale" "Perlin scale" 0.25 3. 1. 1.;
    c "noise_detail" "Perlin detail" 1. 6. 3. 3. ];
  "Wave ribbons", [
    c "count" "Lines per ribbon" 8. 100. 52. 52.;
    c "spacing" "Line spacing" 0.001 0.018 0.0075 0.0075;
    c "width" "Line width" 0.0002 0.004 0.00125 0.00125;
    c "opacity" "Pearl opacity" 0. 1. 0.67 0.67;
    c "bend" "Bend amplitude" 0. 0.4 0.045 0.045;
    c "frequency" "Bend frequency" 0.2 2.5 0.7 0.7;
    c "slope" "Diagonal slope" (-0.8) 0.8 0.4 0.4;
    c "phase" "Wave phase" (-3.14) 3.14 1.2 1.2;
    c "lower_y" "Lower ribbon height" 0.2 1.2 0.73 0.73;
    c "upper_y" "Upper ribbon height" (-0.4) 0.6 0.06 0.06;
    c "upper" "Upper ribbon intensity" 0. 1. 0.48 0.48;
    c "upper_bend" "Upper ribbon bend" 0. 0.4 0.11 0.11;
    c "upper_slope" "Upper ribbon slope" (-0.8) 0.8 0.04 0.04;
    c "upper_phase" "Upper ribbon phase" (-3.14) 3.14 (-0.2) (-0.2);
    c "taper" "Ribbon edge fade" 0.1 4. 1.4 1.4;
    c "interference" "Secondary ripple" 0. 0.04 0.009 0.009 ];
  "Silk folds", [
    c "fold_x" "Fold position" (-0.35) 0.35 0. 0.;
    c "fold_curve" "Fold curvature" 0. 0.4 0.04 0.04;
    c "fold_tilt" "Fold diagonal" (-1.2) 0.2 (-0.64) (-0.64);
    c "fold_width" "Central sheet width" 0.1 1.2 0.50 0.50;
    c "pinch" "Fold neck pinch" 0. 0.25 0.12 0.12;
    c "overhang" "Upper sheet overhang" 0. 1. 1. 1.;
    c "lip_y" "Upper sheet lip height" 0.2 0.7 0.40 0.40;
    c "crease" "Crease sharpness" 0.005 0.2 0.06 0.06;
    c "highlight" "Edge light" 0. 1. 0.65 0.65;
    c "shadow" "Fold shadow" 0. 0.6 0.13 0.13;
    c "iridescence" "Iridescence" 0. 1. 0.45 0.45 ];
  "Finish and motion", [
    c "grain" "Silk microtexture" 0. 0.13 0.012 0.032;
    c "grain_scale" "Texture scale" 0.4 3. 1. 1.;
    c "seed" "Random seed" 0. 999. 37. 37.;
    c "randomness" "Seeded chaos" 0. 1. 0. 0.;
    c "vignette" "Corner shading" 0. 0.4 0.025 0.025;
    c "speed" "Animation speed" 0. 8. 0.12 0.12;
    c "wave_speed" "Wave motion rate" 0. 4. 1. 1.;
    c "fold_speed" "Fold motion rate" 0. 4. 0.25 0.25;
    c "color_speed" "Color motion rate" 0. 4. 0.5 0.5;
    c "motion_chaos" "Motion chaos" 0. 1. 0. 0. ]
]
let controls = List.concat_map snd groups
let clamp a b x = max a (min b x)
(* Control values by key; absent keys use the waves preset. *)
type values = (string * float) list
let preset silk = List.map (fun c -> c.key, if silk then c.silk else c.waves) controls
let set values key value = (key, value) :: List.remove_assoc key values
let get values key =
  let d = List.find (fun c -> c.key = key) controls in
  clamp d.lo d.hi (Option.value ~default:d.waves (List.assoc_opt key values))
let signature values = List.map (fun c -> get values c.key) controls
let mix a b t = Color.blend a b ~pct:(clamp 0. 1. t)
let rgb r g b = Color.rgb r g b
let pearl = rgb 244 255 255
let tau = 2. *. Float.pi
let gauss x y cx cy sx sy = exp (-.(((x-.cx)/.sx)**2. +. ((y-.cy)/.sy)**2.) *. 0.5)
let jitter amount rng =
  let v, rng = Rand.float rng in
  (v -. 0.5) *. 2. *. amount, rng

(* Indexed regular patches allocate their exact cardinality once. O(rows*cols)
   time and storage; there are no per-pixel buffers or CPU image generation. *)
let normals n : Mesh.Private.vec3_view =
  {x=Array.make n 0.; y=Array.make n 0.; z=Array.make n 1.}

let patch ~cols ~rows ~z sample =
  let n = (cols+1)*(rows+1) in
  let x = Array.make n 0. and y = Array.make n 0.
  and zs = Array.make n z and colors = Array.make n Color.white in
  for j = 0 to rows do
    for i = 0 to cols do
      let k = j*(cols+1)+i in
      let px,py,color = sample (float i /. float cols) (float j /. float rows) in
      x.(k) <- px -. 0.5; y.(k) <- 0.5 -. py; colors.(k) <- color
    done
  done;
  let indices = Array.make (cols*rows*6) 0 in
  for j = 0 to rows-1 do for i = 0 to cols-1 do
    let k = (j*cols+i)*6 and a = j*(cols+1)+i in
    indices.(k) <- a; indices.(k+1) <- a+cols+1; indices.(k+2) <- a+1;
    indices.(k+3) <- a+1; indices.(k+4) <- a+cols+1; indices.(k+5) <- a+cols+2
  done done;
  match Mesh.Private.create_packed_owned ~normals:(normals n) ~indices ~colors {x;y;z=zs} with
  | Ok m -> m | Error e -> failwith e

let build ui time =
  let values = Hashtbl.create 64 in
  List.iter (fun c -> Hashtbl.add values c.key (get ui c.key)) controls;
  let p key = Hashtbl.find values key in
  let folds = p "folds" and visibility = p "waves" in
  let randomness = p "randomness" and motion_chaos = p "motion_chaos" in
  let base = time *. p "speed" in
  let wave_t = base *. p "wave_speed" in
  let fold_t = base *. p "fold_speed" in
  let color_t = base *. p "color_speed" in
  let phase = p "phase" +. wave_t in
  let color_phase = p "phase" +. color_t in
  let softness = p "softness" in
  let seed_i = int_of_float (p "seed") in
  (* Composition RNG is independent of the grain stream so randomness=0 keeps
     preset digests bit-identical, including seeded microtexture. *)
  let comp_rng = Rand.seed (seed_i * 104729 + 17) in
  let field_rng, rest = Rand.split comp_rng in
  let fold_rng, wave_rng = Rand.split rest in
  let fold_x_j, field_rng = jitter (randomness *. 0.12) field_rng in
  let fold_y_j, field_rng = jitter (randomness *. 0.10) field_rng in
  let spot_defs = [|
    (0.02,0.34,0.18,0.23,1,p "mint" *. 1.8, 0.18, 0.55);
    (0.9,0.14,0.49,0.29,2,p "pink" *. 2.5, 0.22, 0.70);
    (0.60,1.0,0.21,0.17,3,p "violet" *. 2.0, 0.16, 0.50);
    (0.98,0.70,0.39,0.31,4,p "blue" *. 1.5, 0.20, 0.60);
    (0.00,0.00,0.22,0.20,5,folds *. 1.5, 0.14, 0.45)|] in
  let spots =
    let rng = ref field_rng in
    Array.map (fun (cx,cy,sx,sy,ci,strength,pos_amt,str_amt) ->
      let jx, r = jitter (randomness *. pos_amt) !rng in
      let jy, r = jitter (randomness *. pos_amt) r in
      let jsx, r = jitter (randomness *. 0.35 *. sx) r in
      let jsy, r = jitter (randomness *. 0.35 *. sy) r in
      let jw, r = jitter (randomness *. str_amt) r in
      rng := r;
      (cx+.jx, cy+.jy, max 0.04 (sx+.jsx), max 0.04 (sy+.jsy), ci,
       max 0. (strength+.jw))) spot_defs
  in
  let fold_xj, fold_rng = jitter (randomness *. 0.10) fold_rng in
  let fold_tilt_j, fold_rng = jitter (randomness *. 0.18) fold_rng in
  let fold_curve_j, fold_rng = jitter (randomness *. 0.08) fold_rng in
  let fold_width_j, fold_rng = jitter (randomness *. 0.12) fold_rng in
  let pinch_j, fold_rng = jitter (randomness *. 0.05) fold_rng in
  let lip_j, fold_rng = jitter (randomness *. 0.06) fold_rng in
  let fold_chaos, _ = jitter (randomness *. 1.4 +. motion_chaos *. 0.8) fold_rng in
  let fold_x = p "fold_x" +. fold_xj in
  let fold_tilt = p "fold_tilt" +. fold_tilt_j in
  let fold_curve = max 0. (p "fold_curve" +. fold_curve_j) in
  let fold_width = clamp 0.1 1.2 (p "fold_width" +. fold_width_j) in
  let pinch = clamp 0. 0.25 (p "pinch" +. pinch_j) in
  let lip_y = clamp 0.2 0.7 (p "lip_y" +. lip_j) in
  let palette = [|rgb 173 192 207; rgb 165 255 221; rgb 255 191 248;
        rgb 186 137 247; rgb 144 160 252; rgb 255 239 230|] in
  let field_noise = Noise.create (seed_i * 31 + 101) in
  let noise_mix = p "noise_field" in
  let noise_freq = p "noise_scale" *. (1.35 /. softness) in
  let noise_octaves = max 1 (int_of_float (p "noise_detail" +. 0.5)) in
  let accumulate weights =
    let r = ref (float palette.(0).r *. 0.35)
    and g = ref (float palette.(0).g *. 0.35)
    and b = ref (float palette.(0).b *. 0.35) and total = ref 0.35 in
    Array.iteri (fun i w ->
      let col = palette.(i) in
      r := !r +. w *. float col.r;
      g := !g +. w *. float col.g;
      b := !b +. w *. float col.b;
      total := !total +. w) weights;
    rgb (int_of_float (!r /. !total)) (int_of_float (!g /. !total))
      (int_of_float (!b /. !total))
  in
  let blob_field x y =
    let weights = Array.make 6 0. in
    Array.iter (fun (cx,cy,sx,sy,ci,strength) ->
      weights.(ci) <- weights.(ci)
        +. strength *. gauss x y cx cy (sx*.softness) (sy*.softness)) spots;
    accumulate weights
  in
  let perlin_field x y =
    let nx = x *. noise_freq and ny = y *. noise_freq and nz = color_t *. 0.18 in
    let n_mint = Noise.fbm3 ~octaves:noise_octaves field_noise
        ~x:nx ~y:ny ~z:nz in
    let n_pink = Noise.fbm3 ~octaves:noise_octaves field_noise
        ~x:(nx +. 17.3) ~y:(ny -. 9.1) ~z:(nz +. 0.37) in
    let n_violet = Noise.fbm3 ~octaves:noise_octaves field_noise
        ~x:(nx -. 11.7) ~y:(ny +. 13.4) ~z:(nz -. 0.21) in
    let n_blue = Noise.fbm3 ~octaves:noise_octaves field_noise
        ~x:(nx +. 5.9) ~y:(ny +. 22.0) ~z:(nz +. 0.55) in
    let warp = Noise.sample2 field_noise ~x:(nx *. 0.55) ~y:(ny *. 0.55) in
    let n_warm = Noise.fbm3 ~octaves:(max 1 (noise_octaves - 1)) field_noise
        ~x:(nx +. warp *. 1.8) ~y:(ny -. warp *. 1.2) ~z:(nz +. 0.11) in
    accumulate [|
      0.20 +. 0.15 *. n_warm;
      p "mint" *. 1.8 *. n_mint;
      p "pink" *. 2.5 *. n_pink;
      p "violet" *. 2.0 *. n_violet;
      p "blue" *. 1.5 *. n_blue;
      folds *. 1.5 *. n_warm |]
  in
  let field x y =
    let x = x -. p "color_x" -. fold_x_j *. 0.25 -. 0.04 *. sin color_t
    and y = y -. p "color_y" -. fold_y_j *. 0.25 -. 0.04 *. sin (color_t *. 0.73) in
    if noise_mix <= 0. then blob_field x y
    else if noise_mix >= 1. then perlin_field x y
    else mix (blob_field x y) (perlin_field x y) noise_mix
  in
  let finish x y col =
    let col=if p "hue"=0. then col else Color.rotate_hue col (p "hue") in
    let gray = (float col.Color.r +. float col.g +. float col.b) /. 3. in
    let v = p "vignette" *. ((x-.0.5)**2. +. (y-.0.5)**2.) in
    let channel n = int_of_float (clamp 0. 255.
      (gray +. (float n -. gray)*.p "saturation" +. 255.*.(p "exposure"-.v))) in
    {col with Color.r=channel col.r; g=channel col.g; b=channel col.b}
  in
  let transform x y =
    let a=p "rotation" and zoom=p "zoom" in
    let dx=(x-.0.5)*.zoom and dy=(y-.0.5)*.zoom in
    0.5+.dx*.cos a-.dy*.sin a+.p "pan_x",
    0.5+.dx*.sin a+.dy*.cos a+.p "pan_y"
  in
  let sample x y color = let tx,ty=transform x y in tx,ty,finish x y color in
  let background=patch ~cols:100 ~rows:100 ~z:0.
    (fun u v -> let x=u*.3.-.1. and y=v*.3.-.1. in
      let silk_bg=mix (rgb 190 189 185) (rgb 124 150 209)
        (gauss x y 1.1 0.8 0.32 0.5) in
      sample x y (mix (field x y) silk_bg folds)) in
  let left y = 0.61 +. fold_x +. fold_tilt *. y
    +. fold_curve *. sin (tau*.y+.fold_t+.fold_chaos*.0.35)
    -.pinch *. exp(-. (((y-.0.40)/.0.16)**2.)) in
  let right y = max (left y +. 0.03)
    (0.61+.fold_x+.fold_width+.1.56*.fold_tilt*.y
      +.(0.14+.fold_curve)*.sin(Float.pi*.y+.fold_chaos*.0.2)) in
  let top_left y =
    let t=clamp 0. 1. ((y-.lip_y+.0.05)/.0.20) in
    left y -. p "overhang" *. 0.8 *. t*.t*.(3.-.2.*.t) in
  let sheet side = patch ~cols:100 ~rows:180 ~z:(if side=0 then 0.025 else 0.01)
    (fun u v ->
      let y=v*.1.6-.0.3 in
      let l=(if side=0 then top_left y else left y) and r=right y in
      let x=if side<>1 then (-1.)+.u*.(l+.1.) else l+.u*.(r-.l) in
      let edge = if side<>1 then l-.x else x-.l in
      let base=if side=2 then
          mix (rgb 179 190 235) (rgb 239 250 235)
            (gauss x y 0.25 0.57 0.12 0.3)
        else if side=0 then
          let col=mix (mix palette.(2) palette.(3) (0.12+.0.55*.y)) palette.(5)
            (gauss x y 0.20 0.02 0.16 0.27) in
          mix col (rgb 185 214 228) (gauss x y 0.06 0.72 0.15 0.25)
        else mix (rgb 109 216 225) (rgb 238 253 238)
          (gauss x y 0.70 0.50 0.32 0.20) |> fun col ->
          mix col (rgb 196 163 246) (clamp 0. 1. ((y-.0.55)*.2.3)) in
      let sheen=exp(-. ((edge/.(p "crease"*.2.5))**2.))*.p "highlight" in
      let shimmer=p "iridescence"*.0.4*.(0.5+.0.5*.sin(x*.11.+.y*.7.+.color_phase
        +.fold_chaos*.0.5)) in
      let col=mix base palette.(4) shimmer in
      let col=mix col (rgb 255 255 242) sheen in
      let shadow=if side<>1 then 0. else
        p "shadow" *. exp(-. (((r-.x)/.0.10)**2.)) in
      let col=Color.darken col shadow in
      sample x y (Color.with_alpha col (int_of_float(folds*.255.)))) in
  let edge_light boundary=patch ~cols:4 ~rows:260 ~z:0.03
    (fun u v ->
      let y=v*.1.6-.0.3 in
      let x=boundary y+.(u-.0.5)*.0.0018 in
      let alpha=folds*.p "highlight"*.sin(Float.pi*.u) in
      sample x y (Color.with_alpha pearl (int_of_float(255.*.alpha)))) in
  let line_mesh upper =
    let count=int_of_float(p "count") in
    (* Each line is its own disconnected strip with transparent fringe vertices. *)
    let segments=220 and across=4 in
    let single=(segments+1)*(across+1) in
    let n=count*single in
    let x=Array.make n 0. and y=Array.make n 0. and z=Array.make n 0.04
    and colors=Array.make n Color.transparent in
    let indices=Array.make (count*segments*across*6) 0 in
    let band_rng = if upper then fst (Rand.split wave_rng) else snd (Rand.split wave_rng) in
    let line_phase = Array.make count 0.
    and line_space = Array.make count 0.
    and line_bend = Array.make count 0.
    and line_chaos = Array.make count 0. in
    let rng = ref band_rng in
    for line = 0 to count - 1 do
      let jp, r = jitter (randomness *. 1.35) !rng in
      let js, r = jitter (randomness *. p "spacing" *. 0.55) r in
      let jb, r = jitter (randomness *. 0.9) r in
      let jc, r = jitter (1.) r in
      line_phase.(line) <- jp;
      line_space.(line) <- js;
      line_bend.(line) <- jb;
      line_chaos.(line) <- jc;
      rng := r
    done;
    for line=0 to count-1 do
      let t=(float line+.0.5)/.float count in
      let fade=(sin(Float.pi*.t))**p "taper" in
      let chaos_term = motion_chaos *. line_chaos.(line) *. (0.55 +. 0.45 *. sin (wave_t *. (0.7 +. t))) in
      for i=0 to segments do
        let u=float i/.float segments in
        let px=u*.1.5-.0.25 in
        let bend=if upper then p "upper_bend" *. sin(tau*.0.55*.px
            +.p "upper_phase"+.wave_t+.line_phase.(line)+.chaos_term)
            *. (1. +. line_bend.(line) *. 0.35)
          else p "bend"*.sin(tau*.p "frequency"*.px+.phase+.line_phase.(line)+.chaos_term)
            *. (1. +. line_bend.(line) *. 0.35) in
        let base=if upper then p "upper_y" else p "lower_y" in
        let slope=if upper then p "upper_slope" else p "slope" in
        let cy=base+.slope*.(px-.0.5)+.bend
          +.(float line-.float count/.2.)*.p "spacing"+.line_space.(line)
          +.p "interference"*.sin(px*.14.+.t*.5.+.phase+.chaos_term) in
        let strength=visibility*.p "opacity"*.fade*.
          (if upper then p "upper" else 1.)*.(0.65+.0.35*.sin(px*.6.+.t*.3.)**2.) in
        for j=0 to across do
          let k=line*single+i*(across+1)+j in
          let offset=(float j-.2.)*.p "width"*.0.7 in
          let tx,ty=transform px (cy+.offset) in
          x.(k)<-tx-.0.5; y.(k)<-0.5-.ty;
          let a=if j=0 || j=across then 0. else strength in
          colors.(k)<-Color.with_alpha pearl (int_of_float(a*.255.))
        done
      done;
      for i=0 to segments-1 do for j=0 to across-1 do
        let k=((line*segments+i)*across+j)*6 in
        let a=line*single+i*(across+1)+j in
        indices.(k)<-a; indices.(k+1)<-a+5; indices.(k+2)<-a+1;
        indices.(k+3)<-a+1; indices.(k+4)<-a+5; indices.(k+5)<-a+6
      done done
    done;
    match Mesh.Private.create_packed_owned ~normals:(normals n) ~indices ~colors {x;y;z} with
    | Ok m->m | Error e->failwith e
  in
  let texture () =
    let count= int_of_float (18000. *. p "grain_scale") in
    let state=Rand.seed seed_i in
    let vertices=Array.make (count*3) Vec3.zero
    and colors=Array.make (count*3) Color.transparent in
    let rec fill i rng = if i<count then begin
      let x,rng=Rand.float rng in let y,rng=Rand.float rng in
      let w=0.00065/.p "grain_scale" in
      let alpha =
        if randomness = 0. then p "grain"
        else
          let a = Rand.float_at state ~index:(i + 100_003) in
          clamp 0. 1. (p "grain" *. (1. +. randomness *. (a -. 0.5) *. 0.7))
      in
      let col=Color.with_alpha pearl (int_of_float(255.*.alpha)) in
      for j=0 to 2 do
        let px=x+.(if j=1 then w else 0.) and py=y+.(if j=2 then w*.0.5 else 0.) in
        let tx,ty=transform px py in
        vertices.(i*3+j)<-Vec3.create (tx-.0.5) (0.5-.ty) 0.06;
        colors.(i*3+j)<-col
      done; fill (i+1) rng end in
    fill 0 state;
    match Mesh.Private.create_owned ~normals:(Array.make (count*3) (Vec3.create 0. 0. 1.)) ~colors vertices with Ok m->m|Error e->failwith e
  in
  let meshes=[background] @ (if folds>0. then
      [sheet 1;sheet 2;edge_light left;sheet 0;edge_light top_left] else [])
    @ (if visibility>0. then [line_mesh true;line_mesh false] else [])
    @ (if p "grain">0. then [texture ()] else []) in
  let material=Material.unlit Color.white in
  let nodes=List.map(fun mesh->Scene3.mesh ~material ~cull:Scene3.Cull_none mesh) meshes in
  Scene3.create [Scene3.with_depth (Scene3.depth_state ~comparison:Scene3.Always ~write:false ())
    [Scene3.with_blend Scene3.Alpha nodes]],
  List.fold_left(fun n m->n+Mesh.vertex_count m) 0 meshes
