type t
type request=Image_file of string|Font_file of string*int|Sample_file of string|Music_file of string
val create : ?root:string -> ?watch:bool -> unit -> t
val root:t->string
val resolve:t->string->string
val image:t->string->(Image.t,string)result
val image_exn:t->string->Image.t
val font:t->size:int->string->(Font.t,string)result
val font_exn:t->size:int->string->Font.t
val sample:t->string->(Audio.Sample.t,string)result
val sample_exn:t->string->Audio.Sample.t
val music:t->string->(Audio.Music.t,string)result
val music_exn:t->string->Audio.Music.t
val preload:t->request list->(unit,string list)result
val preload_parallel:t->request list->(unit,string list)result
val image_count:t->int
val font_count:t->int
val sample_count:t->int
val music_count:t->int
val refresh:t->(string list,string list)result
val clear:t->unit
val destroy:t->unit
