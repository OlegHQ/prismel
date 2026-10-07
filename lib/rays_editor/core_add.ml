open Procedural
open Editor_document
include Core_scope

(* Where a node is added from the list or the pane: the graph the level shows, else the scene
   or World graph that adding an object or a layer creates. *)
let add_target value =
  let ws, _ = value.doc.Document.workspace in
  match graph_name value with
  | Some name ->
      let context = match List.find_opt (fun (g : Flow.Workspace.graph) -> g.name = name) ws.checked.graphs with
        | Some g -> g.context | None -> Flow.Workspace.Sop in
      Some (name, context)
  | None ->
      (match value.level with
       | Document.Scene -> Some ("scene", Flow.Workspace.Scene)
       | Inside id when kind value id = Some "world" -> Some ("world", World)
       | _ -> None)

(* The menu's "Value" entries: a value is a binding with an expression (a number, the time, an
   operator call), which the other nodes read by name ("=number", "=t", "=+", ...). *)
let value_entries =
  (* the colour of a value's square: what it makes, as far as its section says *)
  let entry ?output sub key label =
    let output = match output, sub with
      | Some ty, _ -> ty | None, "Compare" -> Flow.Ty.Bool | None, "Text" -> Text
      | None, "Convert" when key = "=int" -> Int | None, _ -> Float in
    { Pxui_graph.Node_menu.key; label; category = [ "Value"; sub ]; arity = 0; context = "value"; output;
      off = None } in
  let categorize name = (Option.get (Flow.Op.find name Flow.Context.Value)).category in
  [ entry "Math" "=number" "Number"; entry "Math" "=t" "Time (t)"; entry ~output:Flow.Ty.Vec3 "Math" "=vec3" "Vector";
    entry "Text" "=text" "Text"; entry "Text" "=str" "str" ]
  @ List.map (fun op -> entry (categorize op) ("=" ^ op) op) Flow.Workspace.value_ops

(* the expression and the name a "Value" entry makes *)
let value_expression context key =
  let module S = Flow.Syntax in
  let mk node = S.make node in
  let num n = mk (S.Num n) in
  let op = String.sub key 1 (String.length key - 1) in
  match op with
  | "number" -> mk (S.Num "1.0"), "value"
  | "t" -> mk (S.Sym "t"), "time"
  | "vec3" -> mk (S.Vec [ num "0.0"; num "0.0"; num "0.0" ]), "vector"
  | "text" -> mk (S.Str "text"), "text"
  | "str" -> mk (S.List [ mk (S.Sym "str"); mk (S.Str "text") ]), "text"
  | op ->
      let signature = Flow.Workspace.op_signature context op in
      let argument (label, ty) = match Flow_sop.Flow_edit.default_for ty label with
        | Some d -> d
        | None -> (match ty with
            | Flow.Ty.List _ -> mk (S.List [ mk (S.Sym "range"); num "4" ])
            | _ -> num "0.5") in
      let args = match signature with
        | Some s -> List.map argument s.Flow.Workspace.pos | None -> [] in
      mk (S.List (mk (S.Sym op) :: args)),
      (match op with
       | "+" -> "sum" | "-" -> "difference" | "*" -> "product" | "/" -> "quotient"
       | "<" | ">" | "<=" | ">=" | "=" -> "test" | op -> op)

(* A kind picked in the node menu, as one [Add_node] at the selected zone (else the graph
   body), wired to the selected node when the kind takes a geometry input. *)
let scope_add value key =
  match add_target value with
  | Some (_, Flow.Workspace.Scene) when List.mem key [ "geometry"; "world" ] || String.starts_with ~prefix:"of:" key ->
      (* composition: geometry brings its SOP graph, World its world graph, one gesture each *)
      let geometry existing label =
        [ Syntax_batch (label, Editor_document.Scene_sync.add_geometry value.doc ~existing) ] in
      if key = "geometry" then geometry None "Add geometry"
      else if key = "world" then
        (match Editor_document.Scene_sync.add_world value.doc with
         | Ok ops -> [ Syntax_batch ("Add World", ops) ]
         | Error message -> [ Declined message ])
      else
        let graph = String.sub key 3 (String.length key - 3) in
        geometry (Some graph) ("Add geometry of " ^ graph)
  | Some (_, Flow.Workspace.Scene) when key = "material" ->
      [ Syntax_batch ("New material", [ snd (new_material value) ]) ]
  | Some (graph, Flow.Workspace.Scene) when key = "merge" ->
      (* several selected objects move into a new merge; with none selected, an empty merge *)
      (match Pxui_graph.Scope.selected value.scope_view with
       | _ :: _ :: _ as nodes ->
           let ws, _ = value.doc.Document.workspace in
           [ Syntax_edit (Flow_sop.Flow_edit.Group_merge { nodes;
               name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph "group" }) ]
       | _ ->
           let ws, _ = value.doc.Document.workspace in
           [ Syntax_edit (Flow_sop.Flow_edit.Add_node { scope = [ graph ];
               name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph "group";
               expr = Flow.Syntax.make (Flow.Syntax.List [ Flow.Syntax.make (Flow.Syntax.Sym "scene/merge") ]) }) ])
  | Some (graph, context) ->
      let ws, _ = value.doc.Document.workspace in
      let is_value = String.length key > 0 && key.[0] = '=' in
      let material_of = String.starts_with ~prefix:"of-material:" key in
      let arity = match List.find_opt (fun f -> Edit_graph.factory_key f = key)
          (catalog value context) with
        | Some factory -> Edit_graph.factory_arity factory | None -> if material_of then 1 else 0 in
      let selected = Pxui_graph.Scope.selected value.scope_view in
      let scope, input = match selected with
        | _ when (context = Flow.Workspace.Scene || context = World) && not is_value ->
            (* an object joins the scene's merge and a layer goes on top of the stack: the
               edit itself does that *)
            [ graph ], None
        | [ path ] when List.length path >= 2 ->
            let last = List.nth path (List.length path - 1) in
            List.filteri (fun i _ -> i < List.length path - 1) path,
            (if arity > 0 && last.[0] <> ':' && last.[0] <> '@' then Some last else None)
        | _ ->
            (* nothing selected: a kind with an input reads the graph's result, so the text
               still checks (a required input is never left open) *)
            let result = match value.scope_key with
              | Some { scope = { Flow_sop.Projection.result = Link name; _ }; _ } -> Some name
              | _ -> None in
            [ graph ], (if arity > 0 then result else None) in
      let expr, base =
        if is_value then value_expression context key
        else begin
          let head = Flow.Syntax.make (Flow.Syntax.Sym (Flow.Workspace.context_name context ^ "/"
            ^ (if material_of then "material" else key))) in
          let geometry = match context, key, List.find_opt (fun (g : Flow.Workspace.graph) ->
              g.context = Flow.Workspace.Sop) ws.checked.graphs with
            | Scene, "geometry", Some g -> [ Flow.Syntax.make (Flow.Syntax.List
                [ Flow.Syntax.make (Flow.Syntax.Sym "ref"); Flow.Syntax.make (Flow.Syntax.Sym g.name) ]) ]
            | _ -> [] in
          Flow.Syntax.make (Flow.Syntax.List (head :: geometry
            @ (match input with
               | Some n -> [ Flow.Syntax.make (Flow.Syntax.Sym n) ]
               | None -> if arity > 0 && geometry = [] then [ Flow.Syntax.make (Flow.Syntax.Sym "nil") ] else [])
            @ (if material_of then [ Flow.Syntax.make (Flow.Syntax.Kw "material");
                Flow.Syntax.make (Flow.Syntax.List [ Flow.Syntax.make (Flow.Syntax.Sym "ref");
                  Flow.Syntax.make (Flow.Syntax.Sym (String.sub key 12 (String.length key - 12))) ]) ] else []))),
          (if material_of then "material" else key)
        end in
      let name = Flow_sop.Flow_edit.fresh_name ws.source ~root:graph base in
      [ Syntax_edit (Flow_sop.Flow_edit.Add_node { scope; name; expr }) ]
  | None -> [ Declined "Open a graph to add a node to it" ]

