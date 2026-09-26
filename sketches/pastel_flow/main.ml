open Prismel

let preset = ref "waves"
let export_dir = ref ""
let settings = ref "_out/pastel-flow.json"
let size = ref 1000
let domains = ref 1
let benchmark = ref false
let frames = ref 1
let animate = ref false
let () = Arg.parse [
  "--preset", Arg.Set_string preset, "waves | silk";
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

(* All controls as one Param schema: the shared inspector draws them (groups
   become accordions) and every edit is one undo entry. *)
let schema =
  let open Editor_core.Param in
  schema ~name:"pastel_flow" ~default:(Artwork.preset false, false)
    (field ~name:"animate" ~label:"Animate" ~kind:Toggle ~default:false
       ~get:snd ~set:(fun animate (values, _) -> values, animate) ()
     :: List.concat_map (fun (group, controls) ->
       List.map (fun (c:Artwork.control) ->
         field ~name:c.key ~label:c.label ~folder:[group]
           ~kind:(floating ~min:c.lo ~max:c.hi ()) ~default:c.waves
           ~get:(fun (values, _) -> Artwork.get values c.key)
           ~set:(fun value (values, animate) -> Artwork.set values c.key value, animate) ())
         controls) Artwork.groups)

let keys : (unit, [`Undo | `Redo]) Editor_core.Keymap.binding list = Editor_core.Keymap.[
  { trigger = Chord (Input.KeyChar 'z', [Input.Meta]); label = "undo"; scope = None; action = `Undo };
  { trigger = Chord (Input.KeyChar 'z', [Input.Meta; Input.Shift]); label = "redo";
    scope = None; action = `Redo } ]

(* The kit panel over values held in the model. *)
let panel ui controls (frame:Frame.t) =
  Pxui.Ui.panel ui ~x:16. ~y:16. ~width:310. ~row_height:29
    ~max_height:(float (max 180 (frame.height-32))) "pastel-flow" (fun () ->
    Pxui.Ui.label ui "PASTEL / FLOW";
    Pxui.Ui.label ui "Procedural light, silk and interference";
    let waves = Pxui.Ui.button ui "01  /  Pearl waves" in
    let silk = Pxui.Ui.button ui "02  /  Iridescent silk" in
    let controls = match Pxui_shell.Inspector.record ui ~expanded:["Composition"]
        schema controls with Ok (controls, _) -> controls | Error _ -> controls in
    let save = Pxui.Ui.button ui "Save controls" in
    let load = Pxui.Ui.button ui "Load controls" in
    Pxui.Ui.label ui "Tab: hide panel   /   Esc: quit";
    Pxui.Ui.label ui "Scroll panel. Click a value to type. Cmd-Z undoes.";
    controls,
    List.filter_map (fun (pressed, action) -> if pressed then Some action else None)
      [waves, `Waves; silk, `Silk; save, `Save; load, `Load])

let to_settings (values, animate) : Editor_core.Store.Settings.t =
  ("animate", Editor_core.Store.Settings.Bool animate)
  :: List.map (fun (c:Artwork.control) ->
    c.key, Editor_core.Store.Settings.Float (Artwork.get values c.key)) Artwork.controls
let of_settings (values, animate) saved =
  List.fold_left (fun values (c:Artwork.control) ->
    match Editor_core.Store.Settings.float saved c.key with
    | Some v -> Artwork.set values c.key v | None -> values) values Artwork.controls,
  Option.value ~default:animate (Editor_core.Store.Settings.bool saved "animate")

type model = { ui:Pxui.Ui.t; history:(Artwork.values * bool) Editor_core.History.t; art:Scene3.t;
  signature:float list; time:float;
  hidden:bool; status:string; vertices:int; build_ms:float }
let build values time =
  let start=Unix.gettimeofday() in
  let art,vertices=Artwork.build values time in
  art,vertices,(Unix.gettimeofday()-.start)*.1000.
let init (_:Frame.t) =
  let controls=Artwork.preset (!preset="silk"), !animate in
  let controls,status=if Sys.file_exists !settings then
      match Editor_core.Store.Settings.load ~sketch:"pastel_flow" !settings with
      | Ok saved->of_settings controls saved,"Controls loaded" | Error e->controls,e
    else controls,"Choose a preset; expand a section to explore." in
  let art,vertices,build_ms=build (fst controls) 0. in
  {ui=Pxui.Ui.create ~font_size:12 ();history=Editor_core.History.create controls;art;signature=Artwork.signature (fst controls);
    time=0.;hidden=(!export_dir<>"");status;vertices;build_ms}
let update model (frame:Frame.t) =
  if Frame.has_event (function Event.KeyPressed Input.Escape->true|_->false) frame then Sketch.quit();
  let hidden=if Frame.has_event (function Event.KeyPressed Input.Tab->true|_->false) frame
    then not model.hidden else model.hidden in
  let previous=Editor_core.History.present model.history in
  let controls,actions=if hidden then previous,[]
    else Pxui.Ui.frame model.ui frame (fun ui -> panel ui previous frame) in
  let controls,status=List.fold_left(fun (controls,_status)->function
    | `Waves -> (Artwork.preset false, snd controls),"Pearl waves preset"
    | `Silk -> (Artwork.preset true, snd controls),"Iridescent silk preset"
    | `Save -> controls,(match Editor_core.Store.Settings.save ~sketch:"pastel_flow" !settings (to_settings controls) with
        Ok()->"Saved "^ !settings|Error e->e)
    | `Load -> (match Editor_core.Store.Settings.load ~sketch:"pastel_flow" !settings with
        Ok saved->of_settings controls saved,"Controls loaded"|Error e->controls,e))
    (controls,model.status) actions in
  (* A slider drag is one undo entry; presets and loads are one each. *)
  let history=if controls==previous then model.history
    else Editor_core.History.record ~label:"Controls"
      ~merge:(if Frame.mouse_down Input.LeftButton frame then Gesture 0 else Step)
      controls model.history in
  let history=if Frame.has_event (function
      | Event.MouseReleased (Input.LeftButton,_) -> true | _ -> false) frame
    then Editor_core.History.seal history else history in
  let _,undo_redo,_=Editor_core.Router.step keys ~focus:()
      ~text_focus:(Pxui.Ui.text_input_focused model.ui) ~frame Idle in
  let history,status=List.fold_left (fun (history,status) action ->
      match (if action=`Undo then Editor_core.History.undo else Editor_core.History.redo) history with
      | Some history -> history,(if action=`Undo then "Undo" else "Redo")
      | None -> history,status) (history,status) undo_redo in
  let values, animate = Editor_core.History.present history in
  let time=if animate then model.time+.frame.dt else model.time in
  let signature=Artwork.signature values in
  let art,vertices,build_ms=if signature<>model.signature || time<>model.time then build values time
    else model.art,model.vertices,model.build_ms in
  {model with history;art;signature;time;hidden;status;vertices;build_ms}
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
    else Sketch.run_state ~config ~init ~update ~view ~on_stop () in
  Printf.printf "pastel_flow: %d vertices, build %.2f ms, %s\n%!"
    result.vertices result.build_ms !preset
