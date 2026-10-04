(** Reader for [packaging/sdl3.lock] and for the small s-expression files in
    [tools/sdl3]. The lock is the only place an SDL version is written. *)

type version = int * int * int

type sexp =
  | Atom of string
  | List of sexp list

(** Parse a file of s-expressions. [;] starts a comment. Raises [Failure]. *)
val parse_sexps : string -> sexp list

val parse_version : string -> version
val version_string : version -> string

(** The number [SDL_VERSIONNUM] and [SDL_GetVersion] use. *)
val version_number : version -> int

(** Release parity: SDL ships stable releases with an even minor and patch. *)
val stable : version -> bool

type entry =
  { floor : version
  ; tested : version
  }

(** Component keys are [sdl3], [sdl3_image], [sdl3_ttf], [sdl3_mixer]. *)
val read : string -> (string * entry) list

val find : (string * entry) list -> string -> entry

(** The lock key for a pkg-config name: [sdl3-image] is [sdl3_image]. *)
val key_of_package : string -> string

(** Rewrite one component's [tested] in the lock text, keeping comments and
    layout. *)
val set_tested : string -> key:string -> version -> string

val read_file : string -> string
val write_file : string -> string -> unit

(** The policy every binding test and probe applies: both the headers the
    binding compiled against and the linked library are at least the floor,
    the library is not older than the headers, and both are the same
    major.minor series. No patch number is written in a test. *)
val check_installed :
  lock:(string * entry) list -> key:string -> compiled:version ->
  linked:version -> (unit, string) result
