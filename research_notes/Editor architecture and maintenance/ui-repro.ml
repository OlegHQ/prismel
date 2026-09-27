open Prismel
let frame ?(events=[]) ?(mouse=(330.,300.)) n : Frame.t = {
 width=900; height=640; size=900,640; drawable_width=900; drawable_height=640;
 drawable_size=900,640; pixel_scale=1.,1.; time=float n/.60.; dt=1./.60.; fps=60.;
 count=n; mouse; mouse_delta=0.,0.; keys=[]; mouse_buttons=[]; events }
let palette = [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar '/')]
let wheel = [Event.MouseMoved (330.,300.); Event.MouseScrolled (0.,1.)]
let () =
 let graph = Procedural.Sop.points [||] in
 let e = Result.get_ok (Prismel_editor.Editor3.create ~graph ~prepare:(fun _ _ -> Ok ())
   ~scene3:(fun _ _ -> Scene3.empty) ()) in
 let e = Prismel_editor.Editor3.update e (frame 0) in
 let e = Prismel_editor.Editor3.update e (frame ~events:palette 1) in
 let e = Prismel_editor.Editor3.update e (frame 2) in
 let before = Easy_camera.distance (Prismel_editor.Editor3.camera e) in
 let e = Prismel_editor.Editor3.update e (frame ~events:wheel 3) in
 let after = Easy_camera.distance (Prismel_editor.Editor3.camera e) in
 Printf.printf "3D palette wheel: distance %.9g -> %.9g\n" before after;
 Prismel_editor.Editor3.close e;
 let e = Result.get_ok (Prismel_editor.Editor2.create ~graph ~prepare:(fun _ _ -> Ok ())
   ~scene2:(fun _ _ -> Scene.empty) ()) in
 let e = Prismel_editor.Editor2.update e (frame 0) in
 let e = Prismel_editor.Editor2.update e (frame ~events:palette 1) in
 let e = Prismel_editor.Editor2.update e (frame 2) in
 let before = Easy_camera2.zoom (Prismel_editor.Editor2.camera e) in
 let e = Prismel_editor.Editor2.update e (frame ~events:wheel 3) in
 let after = Easy_camera2.zoom (Prismel_editor.Editor2.camera e) in
 Printf.printf "2D palette wheel: zoom %.9g -> %.9g\n" before after;
 Prismel_editor.Editor2.close e;
 let ui = Pxui.Ui.create () in
 let body ui = Pxui.Ui.panel ui "panel" (fun () -> ignore (Pxui.Ui.text_field ui "Text" "draft")) in
 ignore (Pxui_shell.Shell.frame ui (frame 0) ~visible:true ~body ~overlay:None);
 ignore (Pxui_shell.Shell.frame ui (frame ~events:[Event.MousePressed (Input.LeftButton,(200.,25.)); Event.MouseReleased (Input.LeftButton,(200.,25.))] 1) ~visible:true ~body ~overlay:None);
 Printf.printf "shell focused before hide: %b\n" (Pxui.Ui.text_input_focused ui);
 ignore (Pxui_shell.Shell.frame ui (frame ~events:[Event.WindowFocusLost] 2) ~visible:false ~body ~overlay:None);
 Printf.printf "hidden shell focus after WindowFocusLost: %b\n" (Pxui.Ui.text_input_focused ui);
 Pxui.Ui.destroy ui
