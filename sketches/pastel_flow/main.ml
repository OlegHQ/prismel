open Prismel

let preset = ref "waves"
let smoke = ref false
let export_dir = ref ""
let settings = ref "pastel-flow.json"
let size = ref 1000
let domains = ref 1
let benchmark = ref false
let frames = ref 1
let animate = ref false
let () = Arg.parse [
  "--preset", Arg.Set_string preset, "waves | silk";
  "--smoke", Arg.Set smoke, "Render eight native frames and exit";
  "--export", Arg.Set_string export_dir, "DIR export one artwork-only native PNG";
  "--settings", Arg.Set_string settings, "FILE saved control values (load if present)";
  "--size", Arg.Set_int size, "Logical artwork/export size (256..2400)";
  "--domains", Arg.Set_int domains, "Domain count"
  ; "--bench", Arg.Set benchmark, "Measure five geometry builds without opening a window"
  ; "--frames", Arg.Set_int frames, "Number of exported frames"
  ; "--animate", Arg.Set animate, "Start with animation enabled"
] (fun s -> raise (Arg.Bad s)) "Pastel Flow";
  if not(List.mem !preset ["waves";"silk"]) then failwith "Preset must be waves or silk";
  size := max 256 (min 2400 !size);
  if !frames < 1 || !domains < 1 then failwith "Frames and domains must be positive"

(* The kit panel over values held in the model. *)
let panel ui (values, animate) (frame:Frame.t) =
  Pxui.Ui.panel ui ~x:16. ~y:16. ~width:310. ~row_height:29
    ~max_height:(float (max 180 (frame.height-32))) "pastel-flow" (fun () ->
    Pxui.Ui.label ui "PASTEL / FLOW";
    Pxui.Ui.label ui "Procedural light, silk and interference";
    let waves = Pxui.Ui.button ui "01  /  Pearl waves" in
    let silk = Pxui.Ui.button ui "02  /  Iridescent silk" in
    let animate = Pxui.Ui.toggle ui "Animate" animate in
    let values = List.fold_left (fun values (label, controls) ->
      Option.value ~default:values
        (Pxui.Ui.accordion ui ~expanded:(label="Composition") label (fun () ->
          List.fold_left (fun values (c:Artwork.control) ->
            Artwork.set values c.key
              (Pxui.Ui.slider ui c.label ~range:(c.lo,c.hi) (Artwork.get values c.key)))
            values controls))) values Artwork.groups in
    let save = Pxui.Ui.button ui "Save controls" in
    let load = Pxui.Ui.button ui "Load controls" in
    Pxui.Ui.label ui "Tab: hide panel   /   Esc: quit";
    Pxui.Ui.label ui "Scroll panel. Click a value to type.";
    (values, animate),
    List.filter_map (fun (pressed, action) -> if pressed then Some action else None)
      [waves, `Waves; silk, `Silk; save, `Save; load, `Load])

let to_settings (values, animate) : Pxui.Settings.t =
  ("animate", Pxui.Settings.Bool animate)
  :: List.map (fun (c:Artwork.control) ->
    c.key, Pxui.Settings.Float (Artwork.get values c.key)) Artwork.controls
let of_settings (values, animate) saved =
  List.fold_left (fun values (c:Artwork.control) ->
    match Pxui.Settings.float saved c.key with
    | Some v -> Artwork.set values c.key v | None -> values) values Artwork.controls,
  Option.value ~default:animate (Pxui.Settings.bool saved "animate")

type model = { ui:Pxui.Ui.t; controls:Artwork.values * bool; art:Scene3.t;
  signature:float list; time:float;
  hidden:bool; status:string; vertices:int; build_ms:float }
let build values time =
  let start=Unix.gettimeofday() in
  let art,vertices=Artwork.build values time in
  art,vertices,(Unix.gettimeofday()-.start)*.1000.
let init (_:Frame.t) =
  let controls=Artwork.preset (!preset="silk"), !animate in
  let controls,status=if Sys.file_exists !settings then
      match Pxui.Settings.load !settings with
      | Ok saved->of_settings controls saved,"Controls loaded" | Error e->controls,e
    else controls,"Choose a preset; expand a section to explore." in
  let art,vertices,build_ms=build (fst controls) 0. in
  {ui=Pxui.Ui.create ~font_size:12 ();controls;art;signature=Artwork.signature (fst controls);
    time=0.;hidden=(!export_dir<>"");status;vertices;build_ms}
let update model (frame:Frame.t) =
  if Frame.has_event (function Event.KeyPressed Input.Escape->true|_->false) frame then Sketch.quit();
  let hidden=if Frame.has_event (function Event.KeyPressed Input.Tab->true|_->false) frame
    then not model.hidden else model.hidden in
  let controls,actions=if hidden then model.controls,[]
    else Pxui.Ui.frame model.ui frame (fun ui -> panel ui model.controls frame) in
  let controls,status=List.fold_left(fun (controls,_status)->function
    | `Waves -> (Artwork.preset false, snd controls),"Pearl waves preset"
    | `Silk -> (Artwork.preset true, snd controls),"Iridescent silk preset"
    | `Save -> controls,(match Pxui.Settings.save !settings (to_settings controls) with
        Ok()->"Saved "^ !settings|Error e->e)
    | `Load -> (match Pxui.Settings.load !settings with
        Ok saved->of_settings controls saved,"Controls loaded"|Error e->controls,e))
    (controls,model.status) actions in
  let controls=if !smoke then
      let values=Artwork.set (fst controls) "rotation" (0.015 *. float frame.count) in
      Artwork.set values "grain" (if frame.count mod 2=0 then 0. else 0.03), snd controls
    else controls in
  let values, animate = controls in
  let time=if animate then model.time+.frame.dt else model.time in
  let signature=Artwork.signature values in
  let art,vertices,build_ms=if signature<>model.signature || time<>model.time then build values time
    else model.art,model.vertices,model.build_ms in
  {model with controls;art;signature;time;hidden;status;vertices;build_ms}
let on_stop model = Pxui.Ui.destroy model.ui
let camera=Camera.orthographic ~height:1. ~near:0.1 ~far:3.
  ~at:(Vec3.create 0. 0. 2.) ~target:Vec3.zero ()
let view model (frame:Frame.t) =
  let left=if model.hidden then 0 else 344 in
  let room=max 1 (frame.width-left) in
  let side=min room frame.height in
  let x=left+(room-side)/2 and y=(frame.height-side)/2 in
  [Scene.clear (Color.rgb 21 24 32);
   Scene.view3d ~viewport:(x,y,side,side) ~camera model.art]
  @ if model.hidden then [] else
    Pxui.Ui.scene model.ui @ [Scene.text ~at:(left+12,frame.height-42) ~size:11
      ~color:(Color.rgb 174 187 207) model.status;
      Scene.text ~at:(left+12,frame.height-24) ~size:11 ~color:(Color.rgb 130 147 170)
      (Printf.sprintf "%d vertices  /  rebuild %.1f ms  /  %.0f fps" model.vertices model.build_ms frame.fps)]
let () =
  if !benchmark then begin
    let ui=Artwork.preset (!preset="silk") in
    ignore(build ui 0.);
    for sample=1 to 5 do
      Gc.full_major ();
      let before=Gc.quick_stat () in
      let _,vertices,ms=build ui 0. in
      let after=Gc.quick_stat () in
      Printf.printf "sample=%d vertices=%d wall_ms=%.3f major_words=%.0f promoted_words=%.0f\n%!"
        sample vertices ms (after.major_words-.before.major_words)
        (after.promoted_words-.before.promoted_words)
    done;
    exit 0
  end;
  let config={Sketch.default_config with width=(if !export_dir="" then !size+344 else !size);
    height= !size; title="Pastel Flow | Pearl waves & iridescent silk";
    domains=Some !domains; clock=Sketch.Fixed(1./.60.)} in
  let result=if !export_dir<>"" then
      Sketch.export_state ~config ~directory:!export_dir ~prefix:!preset ~frames:!frames ~init ~update ~view ~on_stop ()
    else Sketch.run_state ~config ?max_frames:(if !smoke then Some 8 else None) ~init ~update ~view ~on_stop () in
  Printf.printf "pastel_flow: %d vertices, build %.2f ms, %s\n%!"
    result.vertices result.build_ms !preset
