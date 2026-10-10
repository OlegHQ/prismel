open Rays
module T = Flow.Ty
module C = Flow.Context
module W = Flow.Workspace
module D = Editor_document.Workspace_doc
module P = Flow_graph.Projection
module M = Pxui_graph.Node_menu
module L = Rays_editor.Private.Lisp_text

let checks = ref 0
let check condition message = incr checks; if not condition then failwith message
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let doc = function Ok x -> x | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds))
let contains text fragment =
  let rec go i = i + String.length fragment <= String.length text
    && (String.sub text i (String.length fragment) = fragment || go (i + 1)) in
  go 0

let frame : Frame.t = {
  width = 1000; height = 700; size = 1000, 700;

  pixel_scale = 1., 1.; time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse = 0., 0.; mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [];
}

let painted_color ui (color : Color.t) =
  let rgba = Int32.of_int ((color.r lsl 24) lor (color.g lsl 16) lor (color.b lsl 8) lor color.a) in
  let staged = Scene.Private.stage_native ~width:1000 ~height:700 (Pxui.Ui.scene ui) |> Result.get_ok in
  List.exists (function
    | Scene.Private.Ui_layer (batch, _) ->
        let bytes = Scene_command.Ui_batch.instances batch in
        let rec find i = i < Scene_command.Ui_batch.count batch
          && (Bytes.get_int32_le bytes (i * Scene_command.Ui_batch.instance_bytes + 32) = rgba || find (i + 1)) in
        find 0
    | _ -> false) staged.layers

let () =
  let toy = ok (T.register ~color:`Vec3 "toy") in
  let declaration = C.{name = "toy"; result = toy; supports_values = true;
    label = "Toy"; color = `Vec3; group = "Toy"; catalog_prefix = Some "toynodes"} in
  let context = ok (C.register declaration) in
  check (ok (T.register ~color:`Vec3 "toy") = toy && ok (C.register declaration) = context)
    "identical registration is not idempotent";
  check (ok (T.register ~color:`Geometry ~default:(Flow.Syntax.make (Sym "nil")) "geometry") = T.geometry)
    "identical default with fresh syntax identity was refused";
  check (T.of_string "toy" = Some toy && T.of_syntax (Flow.Syntax.make (Sym "toy")) = Some toy)
    "registered type is absent from annotations";
  check (T.of_string (T.to_string (T.Record ["x", T.List toy])) = Some (T.Record ["x", T.List toy]))
    "nested nominal type did not round trip";
  check (Marshal.from_string (Marshal.to_string (toy, context) []) 0 = (toy, context))
    "registry identities did not marshal";
  check (T.fits toy toy && not (T.fits toy T.geometry) && T.join toy T.geometry = None)
    "nominal type identity is not distinct";
  let types = T.names () and contexts = C.all () in
  List.iter (fun name -> check (Result.is_error (T.register name)) ("invalid type accepted: " ^ name))
    ["float"; "t"; "bad-name"; ""; "rec{x:int}"];
  check (Result.is_error (T.register ~color:`Int "toy")) "conflicting type accepted";
  check (Result.is_error (C.register {declaration with color = `Int})) "conflicting context accepted";
  check (Result.is_error (C.register {declaration with name = "other"})) "duplicate prefix accepted";
  check (Result.is_error (C.register {declaration with name = "unknown"; result = T.Named "missing";
    catalog_prefix = None})) "unknown result type accepted";
  check (T.names () = types && C.all () = contexts) "refused registrations changed registries";
  check (ok (C.of_string "toy") = context && C.of_qualified "toynodes/emit" = Some context)
    "registered context did not resolve";
  let ops = [Flow.Op.{name = "toy/emit"; ctx = context;
    signature = {pos = ["number", T.Float]; opt = []; rest = None; kw = ["gain", T.Float]};
    out = (fun _ -> toy); any_num = false; choices = []; shape = Scalar; live = false;
    check = (fun _ -> ()); body = (fun ~live:_ ~node args -> node "toy/emit" args);
    category = "Toy"; arithmetic = None; packed_extension = None}] in
  let catalog = Flow.Check.{version = 1; kinds = []} in
  let kernel = Flow.Op.{name = "toy/kernel"; ctx = context;
    signature = {pos = []; opt = []; rest = None;
      kw = ["field", T.Fn (Some {params = [T.Vec3]; result = T.Float})]};
    out = (fun _ -> toy); any_num = false; choices = []; shape = Scalar; live = false;
    check = (fun _ -> ()); body = (fun ~live:_ ~node args -> node "toy/kernel" args);
    category = "Toy"; arithmetic = None; packed_extension = None} in
  let kernel_ops = kernel :: ops in
  let field_source = "(workspace w (graph g :context toy (let* [surface (toy/kernel :field (fn [p] p.x))] surface)))" in
  let field_doc = doc (D.of_text ~ops:kernel_ops catalog field_source) in
  let field_scope = P.of_graph catalog field_doc.checked "g" in
  check (List.exists (fun (n : P.node) ->
    Option.fold ~none:false ~some:(fun (z : P.zone) -> z.kind = P.Fn) n.zone) field_scope.nodes)
    "external function port did not project as a zone";
  let field_plan = ok (Flow.Eval.static field_doc.checked) in
  (match List.assoc "field" field_plan.plan.nodes.(0).args with
   | Flow.Eval.Fn fn ->
       let params, body = Option.get (Flow.Eval.Private.function_body fn) in
       check (params = [W.Name "p", Some T.Vec3] && body.ty = T.Float)
         "external function port lost its specialization"
   | _ -> failwith "external function port lost its callable");
  List.iter (fun body -> check (Result.is_error (D.of_text ~ops:kernel_ops catalog
    ("(workspace w (graph g :context toy (toy/kernel :field " ^ body ^ ")))")))
      "external function port accepted an invalid function") ["1.0"; "(fn [a b] a.x)"];
  let changed_field = ok (D.edit catalog field_doc (Flow_graph.Flow_edit.Set_arg {
    node = ["g"; "surface"]; key = Kw "field"; sub = [];
    value = List.hd (ok (Flow.Syntax.parse "(fn [p] (* p.x 2.0))"))})) in
  check (contains (D.to_text changed_field) "(* p.x 2.0)")
    "external function-port edit was not retained";
  let text = "(workspace w\n\
    (defn make :context toy [(n : float)] (toy/emit n :gain 2.0))\n\
    (graph g :context toy (let* [first (toy/emit 1.0 :gain 3.0) second (make 4.0)] second)))" in
  let workspace = doc (D.of_text ~ops catalog text) in
  let evaluated = ok (Flow.Eval.static ~record:true workspace.checked) in
  check (List.assoc "g" evaluated.results = Flow.Eval.Deferred (toy, 1)
    && Array.length evaluated.plan.nodes = 2) "custom operator did not evaluate to its typed plan";
  check (List.for_all (fun (node : Flow.Eval.node) -> node.ty = toy && node.kind = "toy/emit")
    (Array.to_list evaluated.plan.nodes)) "custom plan lost nominal type";
  check (Option.fold ~none:false ~some:(fun op -> op == List.hd ops)
    (Flow.Op.find ~extra:ops "emit" context)) "bare context operator did not resolve";
  let scope = P.of_graph catalog workspace.checked "g" in
  check (List.exists (fun (node : P.node) -> node.path = ["g"; "first"] && node.ty = toy) scope.nodes)
    "custom node did not project";
  let edited = ok (D.edit catalog workspace (Flow_graph.Flow_edit.Set_arg {
    node = ["g"; "first"]; key = Kw "gain"; sub = []; value = Flow.Syntax.make (Num "7.0")})) in
  check (edited.checked.ops == ops && contains (D.to_text edited) ":gain 7.0")
    "checked edit discarded custom operators";
  let reloaded = doc (D.of_text ~ops catalog (D.to_text edited)) in
  check ((ok (Flow.Eval.static edited.checked)).plan = (ok (Flow.Eval.static reloaded.checked)).plan)
    "custom operator edit did not survive reload";
  let replaced = doc (D.of_text ~ops:[{(List.hd ops) with category = "Changed"}] catalog text) in
  check (not (P.same_graph workspace.checked replaced.checked "g")) "changed declarations reused stale projection";
  let color = (Pxui.Theme.ports Pxui.default_theme).vec3 in
  check (M.port_color Pxui.default_theme toy = color) "custom port ignored declared color";
  let ui = Pxui.Ui.create ~font_size:11 () in
  Fun.protect ~finally:(fun () -> Pxui.Ui.destroy ui) (fun () ->
    let view = Pxui_graph.Scope.create ~width:1000 ~height:700 ()
      |> Pxui_graph.Scope.with_scope ~key:"g" scope in
    ignore (Pxui.Ui.frame ui frame (fun ui -> Pxui_graph.Scope.update view ui frame));
    check (painted_color ui color) "custom card was not painted in its declared color";
    let menu = M.create ~x:100 ~y:100 (M.of_ops ~extra:ops context) in
    check (M.Private.keys menu ~query:"toy" = ["=toy/emit"]) "menu omitted custom operator";
    let next, _ = Pxui.Ui.frame ui frame (fun ui -> M.update menu ui ~bounds:(0, 0, 1000, 700)) in
    check (painted_color ui color) "menu ignored custom operator's output color";
    let menu = Option.get next in
    let _, picked = Pxui.Ui.frame ui {frame with events = [Event.KeyPressed Input.Enter]}
      (fun ui -> M.update menu ui ~bounds:(0, 0, 1000, 700)) in
    check (picked = Some "=toy/emit") "custom menu entry could not be picked");
  let vocab = L.vocab ~ops [] in
  let prefix = "(workspace w (graph g :context toy (toy/" in
  check (List.exists (fun (entry : Pxui.Ui.completion) -> entry.insert = "toy/emit")
    (L.complete vocab prefix (String.length prefix))) "text pane omitted custom operator completion";
  let help = "(graph g :context toy (toy/emit 1.0))" in
  let _, _, op_help = Option.get (L.describe vocab help 25) in
  check (contains op_help "number:float") "text pane omitted custom operator signature";
  let _, _, context_help = Option.get (L.describe vocab help 10) in
  List.iter (fun context ->
    let desc = C.descriptor context in
    check (desc.label <> "" && desc.group <> "" && T.of_string (T.to_string desc.result) = Some desc.result)
      ("incomplete context descriptor: " ^ desc.name);
    ignore (M.color Pxui.default_theme desc.color);
    check (contains context_help desc.name) ("context missing from help: " ^ desc.name)) (C.all ());
  check (Flow.Op.validate (ops @ ops) <> None) "duplicate immutable operators accepted";
  check (Result.is_error (D.of_text catalog text)) "extra operator leaked into default checker";
  let kind = Flow.Check.{qualified = "toynodes/item"; context; aliases = []; slots = [];
    parameters = []; outputs = []; facts = None} in
  let catalog = {catalog with kinds = [kind]} in
  let declared = doc (D.of_text catalog "(workspace w (graph g :context toy (item)))") in
  check (List.assoc "g" (ok (Flow.Eval.static declared.checked)).results = Flow.Eval.Deferred (toy, 0))
    "custom catalog context ignored declared result type";
  let vocab = L.vocab [Flow_sop.Catalog.{qualified = "toynodes/item"; key = "item";
    operation = "item"; label = "Item"; category = ["Toy"]; slots = []; slot_types = []; keyword_inputs = []; fields = []}] in
  let prefix = "(workspace w (graph g :context toy (item" in
  check (List.exists (fun (entry : Pxui.Ui.completion) -> entry.insert = "toynodes/item")
    (L.complete vocab prefix (String.length prefix))) "catalog completion confused prefix with context identity";
  check (not (List.exists (fun (d : Flow.Diagnostic.t) -> d.code = "E_NAMESPACE")
    (snd (W.check {catalog with kinds = []}
      (Flow.Syntax.parse "(workspace w (graph g :context toy (toynodes/missing)))" |> Result.get_ok)))))
    "registered catalog prefix was not recognized";
  let module E = Rays_editor.Editor in
  let host_text = "(workspace host (graph g :context toy (toy/emit 1.0 :gain 3.0))\n\
    (graph editor :context editor (ui/workspace (ui/split \"horizontal\" (ui/graph \"g\") (ui/lisp)))))" in
  let workspace = doc (Rays_editor.Workspace.load ~ops host_text) in
  let presets = Filename.temp_dir "rays-domain-test" "" in
  let host = ref (E.create ~workspace ~await:true ~domains:1 ~presets
    ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Scene3.create []) () |> Result.get_ok) in
  Fun.protect ~finally:(fun () -> E.close !host) (fun () ->
    let step events = host := E.update !host {frame with events} in
    step [];
    check (Option.is_some (E.node_box !host ["g"; "@result"])) "host omitted registered domain's card";
    let x, y, width, height = (E.panes !host frame).graph in
    let point = float (x + width / 2), float (y + height / 2) in
    step [Event.MouseMoved point; Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point)];
    step [Event.KeyPressed (Input.KeyChar '/')];
    step [Event.KeyPressed (Input.KeyChar 'a')];
    step [Event.TextInput "toy/emit"];
    step [Event.KeyPressed Input.Enter];
    check (Array.length (ok (Flow.Eval.static (E.workspace !host).checked)).plan.nodes = 2)
      "host menu did not insert registered domain's operator";
    let path = Filename.concat presets "saved.rays" in
    Out_channel.with_open_bin path (fun oc -> output_string oc (D.to_text (E.workspace !host)));
    let loaded = Editor_document.Preset.load_with_ops ~ops ~path ~factories:Sop_catalog.Editor.factories
      ~settings:Editor_document.Settings.none |> Result.get_ok in
    check (Array.length (snd loaded.doc.workspace).evaluated.plan.nodes = 2)
      "preset reload discarded custom operators");
  print_endline (Printf.sprintf "open domain: %d checks passed" !checks)
