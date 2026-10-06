(* The system's file dialogs and files dragged in from the OS.
   O opens one or several images, S asks for a save path, F chooses a folder;
   drag a file from Finder over the window and drop it. A dialog returns at
   once; its outcome arrives later as an [Event.FileDialog] with the same id.
   A trackpad pinch scales the box. *)
open Rays

type model = {
  lines : string list;       (* newest first *)
  dragging : (float * float) option;
  zoom : float;
}

let init _frame = { lines = []; dragging = None; zoom = 1. }

let remember model line =
  { model with lines = line :: List.take 7 model.lines }

let open_dialog ?filters kind =
  match Sketch.show_file_dialog ?filters kind with
  | Ok id -> Printf.sprintf "dialog %d opened" id
  | Error message -> "dialog failed: " ^ message

let handle model = function
  | Event.KeyPressed (Input.KeyChar 'o') ->
      remember model (open_dialog ~filters:[ "Images", [ "png"; "jpg" ]; "All", [] ] Sketch.Open_files)
  | KeyPressed (KeyChar 's') -> remember model (open_dialog Sketch.Save_file)
  | KeyPressed (KeyChar 'f') -> remember model (open_dialog Sketch.Open_folder)
  | FileDialog { id; result = Ok [] } -> remember model (Printf.sprintf "dialog %d cancelled" id)
  | FileDialog { id; result = Ok paths } ->
      List.fold_left (fun model path -> remember model (Printf.sprintf "dialog %d: %s" id path))
        model paths
  | FileDialog { id; result = Error message } ->
      remember model (Printf.sprintf "dialog %d failed: %s" id message)
  | FileDragMoved position -> { model with dragging = Some position }
  | FileDragEnded -> { model with dragging = None }
  | FileDropped path -> remember model ("dropped " ^ path)
  | MousePinched factor -> { model with zoom = Float.max 0.25 (Float.min 4. (model.zoom *. factor)) }
  | _ -> model

let update model (frame : Frame.t) = List.fold_left handle model frame.events

let view model (frame : Frame.t) =
  let side = int_of_float (80. *. model.zoom) in
  Scene.[
    clear (Color.rgb 20 22 28);
    text ~at:(12, 12) "O: open images   S: save   F: folder   drag a file in   pinch to scale";
    rect ~at:(frame.width / 2 - side / 2, 60) ~w:side ~h:side
      ~fill:(Color.rgb 90 170 240) ();
  ]
  @ (match model.dragging with
     | Some (x, y) ->
         Scene.[ circle ~at:(int_of_float x, int_of_float y) ~radius:10 ~fill:(Color.rgb 240 180 60) () ]
     | None -> [])
  @ List.mapi (fun index line -> Scene.text ~at:(12, 200 + (index * 18)) line) (List.rev model.lines)

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with title = "File dialogs"; width = 720; height = 420 }
      ~init ~update ~view ())
