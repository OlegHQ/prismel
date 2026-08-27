type request=Image_file of string|Font_file of string*int|Sample_file of string|Music_file of string
type t={root:string;watch:bool;images:(string,Image.t)Hashtbl.t;
  fonts:(string,Font.t)Hashtbl.t;samples:(string,Audio.Sample.t)Hashtbl.t;
  music:(string,Audio.Music.t)Hashtbl.t;stamps:(string,(float*int))Hashtbl.t;mutable destroyed:bool}
let create ?(root=".")?(watch=false)()={root;watch;images=Hashtbl.create 32;
  fonts=Hashtbl.create 32;samples=Hashtbl.create 32;music=Hashtbl.create 32;stamps=Hashtbl.create 32;destroyed=false}
let ensure value=if value.destroyed then invalid_arg"Assets: destroyed"
let root value=value.root
let resolve value path=if Filename.is_relative path then Filename.concat value.root path else path
let cached table key load=match Hashtbl.find_opt table key with Some value->Ok value|None->match load()with Error _ as error->error|Ok value->Hashtbl.add table key value;Ok value
let stamp path=let s=Unix.stat path in s.Unix.st_mtime,s.st_size
let image value path=ensure value;let path=resolve value path in match cached value.images path(fun()->Image.load path)with Ok _ as result->(try Hashtbl.replace value.stamps path(stamp path)with _->());result|Error _ as error->error
let image_exn value path=match image value path with Ok result->result|Error message->failwith message
let font value ~size path=ensure value;let path=resolve value path and key=Printf.sprintf"%s:%d"path size in cached value.fonts key(fun()->match Font.load path size with Ok result->Ok result|Error(`Msg message)->Error message)
let font_exn value ~size path=match font value ~size path with Ok result->result|Error message->failwith message
let sample value path=ensure value;let path=resolve value path in cached value.samples path(fun()->Audio.Sample.load path)
let sample_exn value path=match sample value path with Ok result->result|Error message->failwith message
let music value path=ensure value;let path=resolve value path in cached value.music path(fun()->Audio.Music.load path)
let music_exn value path=match music value path with Ok result->result|Error message->failwith message
let preload value requests=let errors=List.filter_map(function
  |Image_file path->Result.fold~ok:(fun _->None)~error:(fun e->Some e)(image value path)
  |Font_file(path,size)->Result.fold~ok:(fun _->None)~error:(fun e->Some e)(font value ~size path)
  |Sample_file path->Result.fold~ok:(fun _->None)~error:(fun e->Some e)(sample value path)
  |Music_file path->Result.fold~ok:(fun _->None)~error:(fun e->Some e)(music value path))requests in if errors=[]then Ok()else Error errors
let preload_parallel=preload
let image_count value=Hashtbl.length value.images
let font_count value=Hashtbl.length value.fonts
let sample_count value=Hashtbl.length value.samples
let music_count value=Hashtbl.length value.music
let refresh value=ensure value;if not value.watch then Ok[]else let changed=ref[]and errors=ref[]in Hashtbl.iter(fun path image->try let now=stamp path in match Hashtbl.find_opt value.stamps path with Some old when old=now->()|_->begin match Image.Private.reload image path with Ok()->Hashtbl.replace value.stamps path now;changed:=path::!changed|Error error->errors:=error::!errors end with Sys_error error->errors:=error::!errors)value.images;if!errors=[]then Ok(List.rev!changed)else Error(List.rev!errors)
let clear value=Hashtbl.iter(fun _ item->Image.destroy item)value.images;
  Hashtbl.iter(fun _ item->Font.destroy item)value.fonts;
  Hashtbl.iter(fun _ item->Audio.Sample.destroy item)value.samples;
  Hashtbl.iter(fun _ item->Audio.Music.destroy item)value.music;
  Hashtbl.clear value.images;Hashtbl.clear value.fonts;Hashtbl.clear value.samples;Hashtbl.clear value.music;Hashtbl.clear value.stamps
let destroy value=if not value.destroyed then(clear value;value.destroyed<-true)
