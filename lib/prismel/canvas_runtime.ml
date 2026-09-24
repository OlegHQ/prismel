type capture = unit -> (int * int * bytes, string) result
let capture_callback : capture option ref=ref None
let save_callback : (string -> (unit,string) result) option ref=ref None
let install ~capture ~save=capture_callback:=Some capture;save_callback:=Some save
let clear()=capture_callback:=None;save_callback:=None
let capture()=match!capture_callback with Some callback->callback()
  |None->Error"Canvas.capture: no active renderer"
let save filename=match!save_callback with Some callback->callback filename
  |None->Error"Canvas.save_screen_png: no active renderer"
