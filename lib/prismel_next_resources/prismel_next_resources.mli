(** Target-neutral owned resource snapshots for the SDL3 migration. *)

type error_kind = Wrong_domain | Destroyed | Invalid_argument | Decode | Io
type error = private { operation:string; kind:error_kind; message:string }
val pp_error : Format.formatter -> error -> unit

module Image : sig
  type t
  val create : width:int -> height:int -> rgba:bytes -> (t,error) result
  val load_file : string -> (t,error) result
  val load_bytes : ?kind:string -> bytes -> (t,error) result
  val identity : t -> int
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val pixels : t -> (bytes,error) result
  val replace : t -> width:int -> height:int -> rgba:bytes -> (unit,error) result
  (* Stable-identity watched replacement. Decode failure retains the previous
      valid generation and pixels. *)
  val reload_file : t -> string -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Canvas : sig
  type t
  val create : width:int -> height:int -> (t,error) result
  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> ((int*int),error) result
  val clear : t -> int32 -> (unit,error) result
  val set_pixel : t -> x:int -> y:int -> int32 -> (unit,error) result
  val draw_image : t -> Image.t -> x:int -> y:int -> (unit,error) result
  val resize : t -> width:int -> height:int -> (unit,error) result
  val capture : t -> (Image.t,error) result
  val save_png : t -> string -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Assets : sig
  type t
  val create : unit -> t
  (* Register an owner hook and return the same borrowed value. *)
  val borrow : t -> destroy:(unit -> (unit,error) result) -> 'a -> ('a,error) result
  val count : t -> int
  val destroy : t -> (unit,error) result
end
