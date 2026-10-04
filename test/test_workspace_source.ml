(* W11 part B: the source file of a .rays sketch: found from the executable or the working
   directory, saved over only while it is what the document came from (atomic, comments intact,
   no self reload), polled twice a second, reloaded as one history entry that keeps view state
   by path, and refused text leaving the last good document. *)
open Rays
module Doc = Editor_document.Workspace_doc
module E3 = Rays_editor.Editor3
module Source = Rays_editor.Source

let fail message = failwith ("test_workspace_source: " ^ message)
let check condition message = if not condition then fail message
let has text sub =
  let n = String.length sub in
  let rec at i = i + n <= String.length text && (String.sub text i n = sub || at (i + 1)) in
  at 0
let read file = In_channel.with_open_bin file In_channel.input_all
let sha = Editor_document.Contexts.sha256
let catalog = Editor_document.Contexts.catalog ~version:1 Sop_catalog.Editor.factories |> Result.get_ok

let sketch radius = Printf.sprintf {|;; the header
(workspace w
  ;; one sphere
  (graph g :context sop []
    (sop/uv_sphere :radius %s :segments 8 :rings 4))) ; the tail
|} radius
let text0 = sketch "0.5" and text1 = sketch "0.7"
let typo = {|(workspace w (graph g :context sop [] (sop/uv_spher :radius 0.5)))|}

let clock = ref 1_700_000_000.
(* a write that always moves the mtime, whatever the file system's resolution *)
let write file text =
  Out_channel.with_open_bin file (fun channel -> output_string channel text);
  clock := !clock +. 10.;
  Unix.utimes file !clock !clock

let directory () = Filename.temp_dir "rays-source" ""
let rec remove_tree dir =
  Array.iter (fun f -> let p = Filename.concat dir f in
    if Sys.is_directory p then remove_tree p
    else Sys.remove p) (Sys.readdir dir);
  Unix.rmdir dir

let printed doc = let t = Doc.to_text doc in if String.ends_with ~suffix:"\n" t then t else t ^ "\n"

let run_files () =
  let dir = directory () in
  let file = Filename.concat dir "sketch.rays" in
  write file text0;
  (* Save: digest match writes the canonical text, comments intact, and re-reading it is the text *)
  let source = Source.at ~file ~digest:(sha text0) in
  let doc = Result.get_ok (Doc.of_text catalog text0) in
  let saved = printed doc in
  let source = match Source.save source saved with Ok s -> s | Error _ -> fail "save refused" in
  check (read file = saved) "the file is the written text";
  check (has (read file) "; the header" && has (read file) "; one sphere" && has (read file) "; the tail")
    ("comments survive: " ^ read file);
  check (printed (Result.get_ok (Doc.of_text catalog (read file))) = saved) "the re-read prints the same";
  check (Sys.readdir dir = [| "sketch.rays" |]) "no temporary file is left";
  check ((Unix.stat file).st_perm land 0o044 <> 0) "the file stays readable";
  (* Save does not reload: the write moved the mtime, the digest is the remembered one *)
  write file (read file);
  check (snd (Source.poll ~now:100. source) = None) "own write reloaded";
  (* digest mismatch: another writer changed the file, so Save refuses *)
  write file text1;
  check (Source.save source "x" = Error `Changed) "saved over another writer's text";
  check (read file = text1) "the refused save left the file alone";
  (* the poll: one content read per half second *)
  let source = Source.at ~file ~digest:(sha text0) in
  let source, changed = Source.poll ~now:0. source in
  check (changed = Some text1) "a file that already differed at startup did not reload on the first poll";
  check (snd (Source.poll ~now:1. source) = None) "the startup difference was reported twice";
  let _, same = Source.poll ~now:0. (Source.at ~file ~digest:(sha text1)) in
  check (same = None) "a file that matches the built text reloaded";
  let source = Source.at ~file ~digest:(sha text1) in
  let source, _ = Source.poll ~now:0. source in
  write file text0;
  let source, early = Source.poll ~now:0.3 source in
  check (early = None) "polled again within half a second";
  let source, late = Source.poll ~now:0.6 source in
  check (late = Some text0) "the change was not seen after half a second";
  let source, again = Source.poll ~now:1.2 source in
  check (again = None) "the same change reported twice";
  let stamp = (Unix.stat file).st_mtime in
  Out_channel.with_open_bin file (fun channel -> output_string channel text1);
  Unix.utimes file stamp stamp;
  let source, changed = Source.poll ~now:1.8 source in
  check (changed = Some text1) "a preserved-mtime content edit was missed";
  let replacement = Filename.concat dir "replacement.rays" in
  write replacement text0;
  Unix.utimes replacement stamp stamp;
  let inode = (Unix.stat file).st_ino in
  Unix.rename replacement file;
  check ((Unix.stat file).st_ino <> inode) "replacement did not change the inode";
  let _, changed = Source.poll ~now:2.4 source in
  check (changed = Some text0) "a same-mtime inode replacement was missed";
  remove_tree dir

let run_find () =
  let start = Sys.getcwd () in
  let dir = directory () in
  Fun.protect ~finally:(fun () -> Sys.chdir start; remove_tree dir) (fun () ->
    Out_channel.with_open_bin (Filename.concat dir "dune-project") ignore;
    Unix.mkdir (Filename.concat dir "sk") 0o755;
    Unix.mkdir (Filename.concat dir "_build") 0o755;
    Out_channel.with_open_bin (Filename.concat dir "_build/dune-project") ignore;
    write (Filename.concat dir "sk/x.rays") text0;
    let expect from =
      Sys.chdir from;
      match Source.find ~path:"sk/x.rays" ~digest:"" with
      | Some s -> check (Unix.realpath (Source.file s) = Unix.realpath (Filename.concat dir "sk/x.rays"))
                    "the source file is joined to the project root"
      | None -> fail ("no source from " ^ from) in
    expect (Filename.concat dir "sk");
    expect (Filename.concat dir "_build");  (* a dune-project under _build is not the root *)
    Sys.chdir start;
    check (Source.find ~path:"sk/nowhere.rays" ~digest:"" = None) "a missing file is no source";
    (* an internal directory is what the temp project's cleanup needs empty *)
    Sys.remove (Filename.concat dir "_build/dune-project"); Unix.rmdir (Filename.concat dir "_build");
    Sys.remove (Filename.concat dir "sk/x.rays"); Unix.rmdir (Filename.concat dir "sk");
    Sys.remove (Filename.concat dir "dune-project"))

(* ---- through the editor ---- *)

let editor ?presets ~source text =
  E3.create ~await:true ~workspace:(Result.get_ok (Doc.of_text catalog text)) ?presets ~source
    ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Procedural.Session.geometry
      |> Result.map_error Rdk.Error.to_string)
    ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) ()
  |> function Ok e -> e | Error m -> fail m

let source_text e = fst (Flow.Lisp.print (E3.workspace e).Doc.source)
let cook_line e = Test_workspace_shell.dump_line e "cook"

let run_editor () =
  let dir = directory () in
  let file = Filename.concat dir "sketch.rays" in
  write file text0;
  let e = ref (editor ~presets:(Filename.concat dir "presets")
      ~source:(Source.at ~file ~digest:(sha text0)) text0) and count = ref 0 in
  let step ?keys events =
    incr count; e := E3.update !e (Test_editor_input.frame ?keys (450., 300.) events !count) in
  let run_for seconds = for _ = 1 to int_of_float (seconds *. 60.) do step [] done in
  (* the editor awaits each frame's cook: nothing is cooking after a frame (a check, not a wait) *)
  let settle () = step [] in
  step []; step []; settle ();
  let history = E3.undo_label !e in
  (* Command-S over the matching source *)
  step ~keys:[ Input.Meta ] [ Event.KeyPressed (Input.KeyChar 's') ];
  settle ();
  check (has (cook_line !e) "Saved sketch.rays") ("the status says it saved: " ^ cook_line !e);
  let written = read file in
  check (written = printed (E3.workspace !e)) "Save wrote the document's text";
  check (has written "; the header" && has written "; the tail") "the saved file keeps its comments";
  check (not (Sys.file_exists (Filename.concat dir "presets"))) "no preset was written";
  run_for 1.5;
  check (E3.undo_label !e = history) "Save reloaded its own write";
  (* an edit from another editor reloads as one history entry; probes stay by path *)
  let zone = [ "g"; "zone" ] in
  e := E3.set_probe !e zone 3;
  write file text1;
  run_for 1.;
  settle ();
  check (has (source_text !e) "0.7") ("the file's text is the document: " ^ source_text !e);
  check (E3.undo_label !e = Some "Reload sketch.rays") "one history entry named Reload sketch.rays";
  check (E3.probe !e zone = Some 3) "the probe survived by path";
  check (has (cook_line !e) "Reloaded sketch.rays" || has (cook_line !e) "Cook complete") (cook_line !e);
  (* text that does not check keeps the last good document and says why *)
  write file typo;
  run_for 1.;
  settle ();
  check (has (source_text !e) "0.7") "the refused text replaced the document";
  check (E3.undo_label !e = Some "Reload sketch.rays") "the refused text made a history entry";
  check (has (cook_line !e) "not reloaded" && has (cook_line !e) "line 1") ("the status names the failure: " ^ cook_line !e);
  (* undoing the typo in the other editor (the text the document has) clears it *)
  write file text1;
  run_for 1.;
  settle ();
  check (has (cook_line !e) "Reloaded") ("the recovered file reloads: " ^ cook_line !e);
  (* a (layout ...) form edited into the file is the new layout; a file without one keeps it *)
  write file (text1 ^ {|(layout (node ["g" "@result"] :at [10 20]) (frame ["g"] "Sphere" :at [0 0] :size [200 100]))|});
  run_for 1.;
  settle ();
  let layout () = (E3.workspace !e).Doc.layout in
  check (Editor_document.Layout_by_path.Path_map.mem [ "g"; "@result" ] (layout ()).at
         && not (Editor_document.Layout_by_path.Path_map.is_empty (layout ()).frames))
    "the layout form of the file was ignored";
  write file text1;
  run_for 1.;
  settle ();
  check (Editor_document.Layout_by_path.Path_map.mem [ "g"; "@result" ] (layout ()).at)
    "a reload without a layout form dropped the layout";
  let before = E3.workspace !e and label = E3.undo_label !e in
  Sys.remove file;
  run_for 1.;
  check (E3.workspace !e == before && E3.undo_label !e = label)
    "unreadable source changed the document/history";
  check (has (cook_line !e) "Source unreadable") ("source read failure was silent: " ^ cook_line !e);
  step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 's')];
  check (has (cook_line !e) "Not saved:") "unreadable source was reported as an external edit";
  check (not (Sys.file_exists file)) "Save recreated an unreadable source";
  write file text1;
  run_for 1.;
  check (has (cook_line !e) "Source readable again") ("source recovery was not reported: " ^ cook_line !e);
  check (E3.workspace !e == before && E3.undo_label !e = label)
    "same-content source recovery made a document change";
  E3.close !e;
  (* a file edited since the build reloads on the first poll, as one history entry *)
  write file text1;
  e := editor ~presets:(Filename.concat dir "presets")
      ~source:(Source.at ~file ~digest:(sha text0)) text0;
  count := 0;
  step []; step []; run_for 1.; settle ();
  check (has (source_text !e) "0.7") ("the edited file was not loaded at startup: " ^ source_text !e);
  check (E3.undo_label !e = Some "Reload sketch.rays") "the startup reload is one history entry";
  E3.close !e;
  (* a file that differs and does not check keeps the built text; Save then falls back to a preset *)
  write file typo;
  e := editor ~presets:(Filename.concat dir "presets")
      ~source:(Source.at ~file ~digest:(sha text0)) text0;
  count := 0;
  step []; step []; run_for 1.; settle ();
  check (has (cook_line !e) "not reloaded") ("the refused startup file says so: " ^ cook_line !e);
  step ~keys:[ Input.Meta ] [ Event.KeyPressed (Input.KeyChar 's') ];
  settle ();
  check (has (cook_line !e) "saved as preset") ("the status says why: " ^ cook_line !e);
  check (read file = typo) "the changed source file was not overwritten";
  check (List.length (Editor_document.Preset.list ~directory:(Filename.concat dir "presets")) = 1) "one preset was written";
  E3.close !e;
  remove_tree dir

let run_autosave () =
  let dir = directory () in
  let file = Filename.concat dir "sketch.rays" and presets = Filename.concat dir "presets" in
  write file text0;
  let create () = editor ~presets ~source:(Source.at ~file ~digest:(sha text0)) text0 in
  let e = ref (create ()) and count = ref 0 in
  let step ?(keys = []) events =
    incr count; e := E3.update !e (Test_editor_input.frame ~keys (200., 300.) events !count) in
  step []; step [];
  let state = Editor_document.Preset.path ~directory:(Filename.concat presets "state")
    ~name:(sha ("file:" ^ Unix.realpath file)) in
  check (not (Sys.file_exists state)) "opening a sketch wrote over its recovery state";
  e := Result.get_ok (E3.edit !e (Flow_sop.Flow_edit.Set_arg {
    node = ["g"; "@result"]; key = Kw "radius"; sub = []; value = Flow.Syntax.make (Num "1.25") }));
  e := E3.set_renderer !e Rays_editor.Renderer.Wireframe;
  step [Event.MouseMoved (200., 300.); Event.MouseScrolled (0., -2.)];
  let saved_eye = Camera.position (Easy_camera.camera (E3.camera !e)) in
  E3.close !e;
  check (has (read state) ":radius 1.25" && has (read state) "; the header"
         && has (read state) "(view") "close did not flush the edited document and viewport";
  check (read file = text0) "autosave rewrote the source file";
  check (Array.length (Sys.readdir (Filename.dirname state)) = 1) "autosave left multiple snapshots or temporary files";
  let snapshot = read state and stamp = (Unix.stat state).st_mtime in
  e := create (); count := 0;
  for _ = 1 to 70 do step [] done;
  check (read state = snapshot && (Unix.stat state).st_mtime = stamp)
    "an unchanged restarted sketch overwrote the last edited state";
  step [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'b')];
  step [Event.KeyPressed Input.Enter];
  check (has (source_text !e) ":radius 1.25" && E3.undo_label !e = Some "Restore last edited state")
    ("Space b did not restore the last edited state as one undo entry: "
      ^ Option.value ~default:"-" (E3.undo_label !e) ^ "; " ^ cook_line !e ^ "; " ^ source_text !e);
  check (Vec3.nearly_equal saved_eye (Camera.position (Easy_camera.camera (E3.camera !e))) ~eps:1e-9)
    "recovery did not restore the viewport";
  check (E3.renderer !e = Rays_editor.Renderer.Wireframe) "recovery did not restore the shared renderer choice";
  step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'z')];
  check (has (source_text !e) ":radius 0.5") "undo did not revert recovery";
  E3.close !e;
  (* A corrupt recovery file is reported without replacing the good document or the file. *)
  write state typo;
  e := create (); count := 0;
  step [];
  step [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'b')];
  step [Event.KeyPressed Input.Enter];
  check (has (source_text !e) ":radius 0.5" && has (cook_line !e) "rejected")
    "a broken autosave replaced the live document or hid its error";
  step [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'b')];
  step [Event.KeyPressed Input.Delete]; step [Event.KeyPressed Input.Delete];
  check (not (Sys.file_exists state)) "Delete twice did not remove the recovery file";
  E3.close !e;
  check (not (Sys.file_exists state)) "closing an unchanged sketch recreated deleted recovery";
  (* Failed writes keep the edit and retry after the destination becomes usable. *)
  Unix.rmdir (Filename.dirname state);
  write (Filename.dirname state) "blocked";
  e := create (); count := 0;
  step [];
  e := Result.get_ok (E3.edit !e (Flow_sop.Flow_edit.Set_arg {
    node = ["g"; "@result"]; key = Kw "radius"; sub = []; value = Flow.Syntax.make (Num "2") }));
  for _ = 1 to 35 do step [] done;
  check (has (Test_workspace_shell.dump_line !e "autosave") "Autosave failed"
         && has (source_text !e) ":radius 2")
    "a failed periodic save lost the edit or hid its error";
  Sys.remove (Filename.dirname state);
  for _ = 1 to 35 do step [] done;
  check (has (read state) ":radius 2" && Test_workspace_shell.dump_line !e "autosave" = "-")
    "autosave did not retry and clear its error while the editor remained open";
  E3.close !e;
  remove_tree dir

let run_autosave2 () =
  let module E2 = Rays_editor.Editor2 in
  let dir = directory () in
  let create () = E2.create ~presets:dir ~await:true
    ~workspace:(Result.get_ok (Doc.of_text catalog text0))
    ~camera:(Easy_camera2.create ~inertia:false ())
    ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> Scene.empty) () |> Result.get_ok in
  let e = ref (create ()) and count = ref 0 in
  let step events = incr count;
    e := E2.update !e (Test_editor_input.frame (200., 300.) events !count) in
  step [];
  step [Event.MouseMoved (200., 300.); Event.MouseScrolled (0., -2.)];
  let saved = E2.camera !e in
  for _ = 1 to 35 do step [] done;
  let state = Editor_document.Preset.path ~directory:(Filename.concat dir "state")
    ~name:(sha "workspace:w") in
  check (has (read state) ":zoom") "2D camera navigation did not autosave while open";
  E2.close !e;
  e := create (); count := 0; step [];
  step [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'b')];
  step [Event.KeyPressed Input.Enter];
  check (Easy_camera2.center (E2.camera !e) = Easy_camera2.center saved
         && Easy_camera2.zoom (E2.camera !e) = Easy_camera2.zoom saved)
    "2D recovery did not restore the viewport";
  E2.close !e;
  remove_tree dir

let run () = run_files (); run_find (); run_editor (); run_autosave (); run_autosave2 ();
  print_endline "workspace source tests passed"
