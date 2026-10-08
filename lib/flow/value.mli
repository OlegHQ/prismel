(** Pure workspace values, parameterized by the evaluator's functions and residuals. *)
type ('f, 'r) t =
  | Int of int | Float of float | Bool of bool | Text of string
  | Vec2 of float * float
  | Vec3 of float * float * float
  | Vec4 of float * float * float * float
  | List of ('f, 'r) t array
  | Float_array of float array
  | Vec3_array of float array  (** interleaved xyz coordinates *)
  | Record of (string * ('f, 'r) t) list
  | Deferred of Ty.t * int | No_geo
  | Struct of string * Ty.t * (string * ('f, 'r) t) list
  | Fn of 'f | Residual of 'r

exception Fail of string * string * Diagnostic.span option
val fail : string -> string -> 'a
val failf : string -> ('a, unit, string, 'b) format4 -> 'a
val hash : float list -> float
val to_int : string -> float -> int
val fin : string -> float -> float
val num : ('f, 'r) t -> float
val truthy : ('f, 'r) t -> bool
val int_of : ('f, 'r) t -> int
val ty_of : ('f, 'r) t -> Ty.t
val elem_ty : ('f, 'r) t array -> Ty.t
val coerce_to : Ty.t -> ('f, 'r) t -> ('f, 'r) t
val show_with : (('f, 'r) t -> ('f, 'r) t) -> ('f, 'r) t -> string
val key_of : residual:('r -> int) -> ('f, 'r) t -> string
val comps : ('f, 'r) t -> float * float * float
val is_vec : ('f, 'r) t -> bool
val arith : string -> (float -> float -> float) -> ('f, 'r) t -> ('f, 'r) t -> ('f, 'r) t
val list_arg : ('f, 'r) t -> ('f, 'r) t array
val array_length : ('f, 'r) t -> int
val array_get : ('f, 'r) t -> int -> ('f, 'r) t
val array_init : Ty.t -> int -> (int -> ('f, 'r) t) -> ('f, 'r) t
val validate : ('f, 'r) t -> unit
