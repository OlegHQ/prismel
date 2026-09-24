open Prismel
open Chromatic_art
let smoke=ref false and bench=ref false and export=ref "" and frames=ref 120
let domains=ref 1 and seed=ref 42 and preset=ref 0
let quality=ref 2 and grain_amount=ref 0.35
let settings_file=ref "_out/chromatic-drift.json"
let () = Arg.parse [
  "--smoke",Arg.Set smoke,"Run twelve animated native frames";
  "--bench",Arg.Set bench,"Measure warmed geometry construction";
  "--export",Arg.Set_string export,"DIR export artwork-only PNG sequence";
  "--frames",Arg.Set_int frames,"Export frame count (default 120)";
  "--domains",Arg.Set_int domains,"Domain count";
  "--seed",Arg.Set_int seed,"Composition seed";
  "--palette",Arg.Set_int preset,"Palette 0..3";
  "--quality",Arg.Set_int quality,"Geometry detail 1..3 (default 2)";
  "--grain",Arg.Set_float grain_amount,"Film grain strength 0..0.8";
  "--settings",Arg.Set_string settings_file,"FILE save/load controls"
] (fun s->raise(Arg.Bad s)) "Chromatic Drift";
  if !frames<1 || !domains<1 || !preset<0 || !preset>3 || !quality<1 || !quality>3
     || not(Float.is_finite !grain_amount) || !grain_amount<0. || !grain_amount>0.8 then
    raise(Arg.Bad "Positive frames/domains and palette 0..3 required")
let controls = [
  "bend","Noise amplitude",0.,0.55,0.10;
  "scale","Noise scale",0.35,2.4,1.1;
  "slope","Diagonal tilt",(-1.4),1.4,1.1;
  "spread","Band spacing",0.65,1.5,1.;
  "sweep","Sweeping curvature",0.,1.2,0.85;
  "radiance","Broad light pools",0.,1.5,0.8;
  "color_depth","Color depth",0.,1.,0.7;
  "glow","Fold light",0.,1.,0.95;
  "softness","Fold light width",0.,1.,0.5;
  "quality","Geometry detail (1..3)",1.,3.,float !quality;
  "depth","Soft surface depth",0.,0.3,0.025;
  "curl","Edge curl (optional)",0.,1.,0.;
  "shadow","Crease shading (optional)",0.,0.8,0.;
  "roughness","Surface roughness",0.,1.,0.95;
  "light_angle","Light direction",(-3.14),3.14,0.7;
  "grain","Film grain strength",0.,0.8,!grain_amount;
  "grain_size","Grain size (native px)",0.75,4.,1.3;
    "speed","Drift speed",0.,1.5,0.18;
  "warp","Domain warp",0.,2.,0.45;
  "detail","Secondary noise",0.,1.,0.25;
  "independent","Independent band motion",0.,1.,0.5;
  "breathing","Spacing breath",0.,1.,0.25;
  "offset","Vertical composition",(-0.4),0.4,0.;
  "hue","Hue rotation",(-180.),180.,0.;
  "saturation","Saturation",0.2,1.8,1.15;
  "exposure","Exposure",(-0.2),0.2,0.;
  "color_mix","Blend next palette",0.,1.,0.;
  "variation","Color turbulence",0.,1.5,0.35;
  "color_speed","Color motion",0.,3.,0.5;

  "seed","Composition seed",0.,9999.,float !seed;
  "palette","Palette (0..3)",0.,3.,float !preset ]
(* Control values live in the model; the panel reads and returns them. *)
type controls = { play : bool; sliders : float array }
let defaults () =
  { play = true; sliders = Array.of_list (List.map (fun (_,_,_,_,v) -> v) controls) }
let slot key =
  let rec find index = function
    | [] -> invalid_arg ("unknown control " ^ key)
    | (k,_,_,_,_) :: rest -> if k = key then index else find (index + 1) rest in
  find 0 controls
let get values key =
  let _,_,lo,hi,d=List.find(fun (k,_,_,_,_)->k=key) controls in
  let v=values.sliders.(slot key) in
  if Float.is_finite v then Drift.clamp lo hi v else d
let set values key v =
  let sliders = Array.copy values.sliders in sliders.(slot key) <- v;
  { values with sliders }
let parameters ui : Drift.settings = {
  seed=int_of_float(get ui "seed"); palette=int_of_float(get ui "palette");
  bend=get ui "bend"; scale=get ui "scale"; slope=get ui "slope";
    spread=get ui "spread"; glow=get ui "glow"; softness=get ui "softness";
  warp=get ui "warp"; detail=get ui "detail"; independent=get ui "independent";
  breathing=get ui "breathing"; offset=get ui "offset"; hue=get ui "hue";
  saturation=get ui "saturation"; exposure=get ui "exposure";
  color_mix=get ui "color_mix"; variation=get ui "variation";
  color_speed=get ui "color_speed"; quality=int_of_float(get ui "quality");
  depth=get ui "depth"; curl=get ui "curl"; shadow=get ui "shadow";
  roughness=get ui "roughness"; light_angle=get ui "light_angle";
  sweep=get ui "sweep"; radiance=get ui "radiance"; color_depth=get ui "color_depth" }
let settings values : Pxui.Settings.t =
  ("play", Pxui.Settings.Bool values.play)
  :: List.mapi (fun i (key,_,_,_,_) -> key, Pxui.Settings.Float values.sliders.(i)) controls
let of_settings saved =
  List.fold_left (fun values (key,_,_,_,_) ->
    match Pxui.Settings.float saved key with Some v -> set values key v | None -> values)
    { (defaults ()) with play = Option.value ~default:true (Pxui.Settings.bool saved "play") }
    controls

(* One kit panel; returns the edited values and the pressed actions. *)
let panel ui values (f:Frame.t) =
  Pxui.Ui.panel ui ~x:16. ~y:16. ~width:286. ~row_height:30
    ~max_height:(float (max 120 (f.height-32))) "chromatic-drift" (fun () ->
    Pxui.Ui.label ui "CHROMATIC / DRIFT";
    Pxui.Ui.label ui "Noise-shaped light and color";
    let play = Pxui.Ui.toggle ui "Animate" values.play in
    let sliders = Array.of_list (List.mapi (fun i (_,label,lo,hi,_) ->
      Pxui.Ui.slider ui label ~range:(lo,hi) values.sliders.(i)) controls) in
    let actions = List.filter (fun (_, label) -> Pxui.Ui.button ui label) [
      `Surprise, "Surprise me / remix everything"; `Shuffle, "New composition";
      `Palette, "Next curated palette"; `Reset, "Reset composition and time";
      `Save, "Save settings"; `Load, "Load settings" ] |> List.map fst in
    Pxui.Ui.label ui "Tab: artwork only / Esc: quit";
    { play; sliders }, actions)

type model = {ui:Pxui.Ui.t; values:controls; p:Drift.settings; phase:float; art:Scene3.t;
  grain:Scene3.t; amount:float; grain_size:float; grain_height:int;
  hidden:bool; status:string; ms:float}
let build p phase = let t=Unix.gettimeofday() in
  let art=Drift.build p phase in art,(Unix.gettimeofday()-.t)*.1000.
let init (f:Frame.t) =
  let values=defaults () in let p=parameters values in let art,ms=build p 0. in
  let amount=get values "grain" in
  let grain_size=get values "grain_size" and grain_height=f.drawable_height in
  {ui=Pxui.Ui.create ~font_size:12 ();values;p;phase=0.;art;ms;
   grain=Drift.grain p.seed amount ~size:grain_size ~height:grain_height;
   amount;grain_size;grain_height;
   hidden=(!export<>"");status="Five flowing sheets / deterministic seed"}
let update m (f:Frame.t) =
  if Frame.has_event(function Event.KeyPressed Input.Escape->true|_->false) f then Sketch.quit();
  let hidden=if Frame.has_event(function Event.KeyPressed Input.Tab->true|_->false) f then not m.hidden else m.hidden in
  let values,actions=if hidden then m.values,[]
    else Pxui.Ui.frame m.ui f (fun ui -> panel ui m.values f) in
  let values,status,reset=List.fold_left(fun (values,status,reset)->function
    | `Surprise ->
        let next=(int_of_float(get values "seed")+137) mod 10000 in
        let rng=Rand.seed next in
        let values=List.fold_left(fun values (i,key,lo,hi)->
          set values key (lo+.(hi-.lo)*.Rand.float_at rng ~index:i)) values [
          0,"bend",0.15,0.55; 1,"scale",0.4,2.4; 2,"slope",(-0.6),0.6;
          3,"spread",0.7,1.4; 4,"glow",0.3,1.; 5,"softness",0.05,0.8;
          6,"warp",0.,2.; 7,"detail",0.,1.; 8,"independent",0.3,1.;
          9,"breathing",0.,1.; 10,"hue",(-180.),180.;
          11,"saturation",0.8,1.6; 12,"color_mix",0.,1.;
          13,"variation",0.2,1.5; 14,"color_speed",0.2,2.;
          15,"palette",0.,3.999; 16,"offset",(-0.2),0.2;
          17,"sweep",0.,1.2; 18,"radiance",0.3,1.4; 19,"color_depth",0.3,0.9] in
        set values "seed" (float next),"Remixed shapes, palette and motion",false
    | `Shuffle->set values "seed"
        (float ((int_of_float(get values "seed")+137) mod 10000)),"New seeded composition",false
    | `Palette->set values "palette"
        (float ((int_of_float(get values "palette")+1) mod 4)),status,reset
    | `Reset->defaults (),"Reset",true
    | `Save->values,(match Pxui.Settings.save !settings_file (settings values) with
        Ok()->"Saved settings"|Error e->e),reset
    | `Load->(match Pxui.Settings.load !settings_file with
        Ok saved->of_settings saved,"Loaded settings",true|Error e->values,e,reset))
    (values,m.status,false) actions in
  let p=parameters values in
  let phase=if reset then 0. else if values.play
    then m.phase+.f.dt*.get values "speed" else m.phase in
  let art,ms=if p<>m.p || phase<>m.phase then build p phase else m.art,m.ms in
  let amount=get values "grain" in
  let grain_size=get values "grain_size" and grain_height=f.drawable_height in
  let grain=if p.seed<>m.p.seed || amount<>m.amount || grain_size<>m.grain_size
      || grain_height<>m.grain_height then
      Drift.grain p.seed amount ~size:grain_size ~height:grain_height else m.grain in
  {m with values;p;phase;art;ms;grain;amount;grain_size;grain_height;hidden;status}
let on_stop m = Pxui.Ui.destroy m.ui
let camera=Camera.orthographic ~height:1. ~near:0.1 ~far:3.
  ~at:(Vec3.create 0. 0. 2.) ~target:Vec3.zero ()
let view m (f:Frame.t) =
  let left=if m.hidden then 0 else min 318 (f.width/2) in
  let viewport=(left,0,max 1 (f.width-left),f.height) in
  [Scene.clear (Color.rgb 9 8 30); Scene.view3d ~viewport ~camera m.art]
  @ (if m.amount=0. then [] else [Scene.view3d ~viewport ~camera m.grain])
  @ if m.hidden then [] else Pxui.Ui.scene m.ui @ [Scene.text ~at:(left+18,f.height-30)
      ~size:12 ~color:Color.white (Printf.sprintf "%s / %.1f ms geometry / %.0f fps"
        Drift.palettes.(m.p.palette) m.ms f.fps);
      Scene.text ~at:(left+18,18) ~size:12 ~color:Color.white m.status]
let () =
  if !bench then begin
    let p=parameters(defaults ()) in ignore(build p 0.);
    for i=1 to 5 do
      Gc.full_major(); let before=Gc.quick_stat() in
      let _,ms=build p (float i*.0.02) in let after=Gc.quick_stat() in
      Printf.printf "vertices=%d wall_ms=%.3f major_words=%.0f promoted_words=%.0f heap_words=%d\n%!"
        (Drift.vertex_count p) ms (after.major_words-.before.major_words)
        (after.promoted_words-.before.promoted_words) after.heap_words
    done
  end else begin
    let config={Sketch.default_config with width=(if !export="" then 1398 else 1080);
      height=800;title="Chromatic Drift";domains=Some !domains;clock=Sketch.Fixed(1./.60.)} in
    let m=if !export<>"" then Sketch.export_state ~config ~directory:!export ~prefix:"drift"
        ~frames:!frames ~init ~update ~view ~on_stop ()
      else Sketch.run_state ~config ?max_frames:(if !smoke then Some 12 else None) ~init ~update ~view
        ~on_stop () in
    Printf.printf "chromatic_drift: phase=%.4f geometry_ms=%.3f\n%!" m.phase m.ms
  end
