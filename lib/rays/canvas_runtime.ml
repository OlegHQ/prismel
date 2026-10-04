type capture = unit -> (int * int * bytes, string) result
let capture_callback : capture option ref=ref None
let save_callback : (string -> (unit,string) result) option ref=ref None
let install ~capture ~save=capture_callback:=Some capture;save_callback:=Some save
let clear()=capture_callback:=None;save_callback:=None
let capture()=match!capture_callback with Some callback->callback()
  |None->Error"Canvas.capture: no active renderer"
let rec ensure_directory path=
  if path<>""&&path<>"."&&not(Sys.file_exists path)then(
    let parent=Filename.dirname path in
    if parent<>path then ensure_directory parent;
    try Unix.mkdir path 0o755 with Unix.Unix_error(Unix.EEXIST,_,_)->())
let save filename=match!save_callback with
  |None->Error"Canvas.save_screen_png: no active renderer"
  |Some callback->
      (try ensure_directory(Filename.dirname filename);callback filename
       with Unix.Unix_error(error,_,_)->
         Error("Canvas.save_screen_png: "^Unix.error_message error))
