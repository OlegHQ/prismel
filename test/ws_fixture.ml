(* Documents for the editor tests: small workspace texts, checked against the editor's catalog. *)
let of_text ?factories text =
  match Prismel_editor.workspace_catalog ?factories () with
  | Error d -> failwith (Flow.Diagnostic.to_string d)
  | Ok catalog ->
      (match Prismel_editor.Workspace_doc.of_text catalog text with
       | Ok workspace -> workspace
       | Error ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)))

(* one unit box, no camera and no lights (the host's defaults apply) *)
let box ?factories () = of_text ?factories "(workspace box (graph geo :context sop (sop/box)))"
