(** The workspace language's static types (port of the study's type strings).
    {!Port_type} is the smaller set a driven parameter port carries at run time. *)

type t =
  | Named of string | Float | Int | Bool | Vec3 | Text
  | Color  (** text or vec3; only catalog parameters ask for it *)
  | List of t
  | Array of t  (** packed float or vec3 data; its length is not graph structure *)
  | Record of (string * t) list  (** fields in written order *)
  | Fn
  | Any  (** unknown or unconstrained: unannotated fn parameters, empty lists *)

type color = [ `Geometry | `Float | `Int | `Bool | `Vec3 | `Text | `Fn | `Record | `Output | `Compound ]
type nominal = {name : string; shape : bool; color : color; default : Syntax.t option}
val geometry : t
val image : t
val drawing : t
val scene : t
val world : t
val settings : t
val panel : t
val editor : t
val material : t
val is_geometry : t -> bool
val is_cooked : t -> bool

val register : ?shape:bool -> ?color:color -> ?default:Syntax.t -> string -> (t, Diagnostic.t) result
(** Declare on the initial domain before checking workspaces. Identical declarations
    are idempotent; conflicts and invalid or reserved names are refused. *)

val descriptor : string -> nominal option
val shape : t -> bool
val color : t -> color
val default : t -> Syntax.t option

val of_syntax : Syntax.t -> t option
(** A type annotation as written in a parameter: a type name, [fn],
    [(list T)] or [{:field T ...}] (unique lowercase field names).  [Any] and
    [Color] are not writable. *)

val names : unit -> (string * t) list
val to_string : t -> string
(** Diagnostic spelling: [float], [list:int], [rec{a:int,b:float}]. *)

val of_string : string -> t option
(** Inverse of [to_string]. *)

val has_fn : t -> bool
(** A function type anywhere inside; such values cannot be stored (E_FN_ESCAPES). *)

val fits : t -> t -> bool
(** [fits have want]: [have] may be used where [want] is expected, possibly
    through {!coerce}.  Numbers and bool interconvert, numbers widen to vec3,
    records fit when they have every wanted field. *)

val coerce : t -> t -> t
(** [coerce have want] is the type of a [have] value after conversion to [want]. *)

val join : t -> t -> t option
(** The least type both fit into ([int]+[float] is [float]); [Any] is neutral. *)

val unify : t -> t -> t option
(** [join], else [have] when the two fit each other. *)

val elem : t -> t option
(** Element type of a list. *)
