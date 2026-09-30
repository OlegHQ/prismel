open Procedural

let flow_result result = Result.map_error Flow.Diagnostic.to_string result
let update_geometry edit document =
  Result.bind (edit document.Flow_sop.Network.geometry) (fun geometry ->
    flow_result (Flow_sop.Network.with_geometry geometry document))
let cook_effects = Parameter.add_impact Parameter.Cook Parameter.no_effects

(* Set parameters of one node (a scene object or World layer, or a lowered node). *)
let apply_parameters document ~node_id values =
  Result.bind (Edit_graph.apply_parameters document.Flow_sop.Network.geometry ~node_id values)
    (fun (geometry, effects) -> Result.map (fun document -> document, effects)
      (update_geometry (fun _ -> Ok geometry) document))

let relabel document ~node_id label = flow_result (Flow_sop.Network.relabel ~node_id label document)

(* One gesture on a workspace document: rewrite and re-check the source, then
   lower it into the document's objects.  Atomic: an error changes nothing. *)
let syntax_edit_result ~factories (doc : Editor_document.Document.t) op =
  let workspace, _ = doc.workspace in
  let ( let* ) = Result.bind in
  let* catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version factories in
  let* workspace = Editor_document.Workspace_doc.edit catalog workspace op in
  Editor_document.Contexts.of_workspace ~factories ~previous:doc workspace

let syntax_edit ~factories (doc : Editor_document.Document.t) op =
  Result.map_error Flow.Diagnostic.to_string (syntax_edit_result ~factories doc op)

(* The whole workspace text, edited (plan W7): parsed and checked as a
   document, lowered, atomic. *)
let text_edit ~factories (doc : Editor_document.Document.t) text =
  let workspace, _ = doc.workspace in
  let ( let* ) = Result.bind in
  let one result = Result.map_error (fun d -> [ d ]) result in
  let* catalog = one (Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version factories) in
  let* edited = Editor_document.Workspace_doc.of_text ~settings:workspace.settings catalog text in
  one (Editor_document.Contexts.of_workspace ~factories ~previous:doc
    (* a [(layout ...)] or [(settings ...)] form in the text is the new value; without one
       the running layout (keyed by path) stays, and the settings the text does not name *)
    { edited with layout = (if Editor_document.Layout_by_path.is_empty edited.layout
                            then workspace.layout else edited.layout) })

(* A change to the workspace's layout keys (a moved item, a collapsed zone):
   the source and the lowering are untouched, so nothing recooks. *)
let layout_edit (doc : Editor_document.Document.t) f =
  let workspace, lowered = doc.workspace in
  { doc with workspace = { workspace with layout = f workspace.layout }, lowered }
