(** Owned cache for sketch images and fonts.

    Returned resources are borrowed from the cache: do not destroy them
    individually. Destroying the cache releases each unique resource once. *)

type t
type request =
  | Image_file of string
  | Font_file of string * int
  | Sample_file of string
  | Music_file of string

val create : ?root:string -> ?watch:bool -> unit -> t
val root : t -> string
val resolve : t -> string -> string

val image : t -> string -> (Image.t, string) result
val image_exn : t -> string -> Image.t
val font : t -> size:int -> string -> (Font.t, string) result
val font_exn : t -> size:int -> string -> Font.t
val sample : t -> string -> (Audio.Sample.t, string) result
val sample_exn : t -> string -> Audio.Sample.t
val music : t -> string -> (Audio.Music.t, string) result
val music_exn : t -> string -> Audio.Music.t

val preload : t -> request list -> (unit, string list) result
(** Load all requests, returning every error rather than stopping at the first. *)

val preload_parallel : t -> request list -> (unit, string list) result
(** Read image files concurrently, then decode/upload them and load other media
    in request order on the initial domain. Errors remain ordered. *)

val image_count : t -> int
val font_count : t -> int
val sample_count : t -> int
val music_count : t -> int
val refresh : t -> (string list, string list) result
(* Reload changed cached image files in place. Returns changed resolved paths,
   or all reload/stat errors. Has no effect unless created with [watch=true]. *)
val clear : t -> unit
val destroy : t -> unit
