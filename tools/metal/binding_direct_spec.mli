(** Declarative schema for mechanically generated, handle-backed Metal calls.

    These declarations describe only the private raw/native layer.  They do
    not assert safe-API coverage, ownership, or GPU conformance. *)

type integer_width =
  | Native
  | Bits32
  | Bits64

type scalar =
  | Bool
  | Signed of
      { objc_type : string
      ; width : integer_width
      }
  | Unsigned of
      { objc_type : string
      ; width : integer_width
      }
  | Float64 of
      { objc_type : string
      }

type semantics =
  | Query
  | Command
  | Blocking
  | Process_identity

type method_entry =
  { sdk_id : string
  ; owner : string
  ; selector : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; arguments : scalar list
  ; result : scalar option
  ; semantics : semantics
  ; ocaml_name : string
  ; c_symbol : string
  }

type property_entry =
  { sdk_id : string
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; getter : method_entry
  ; setter : method_entry option
  }

val version : ?patch:int -> int -> int -> Binding_availability.version

val bool : scalar
val nsuint : scalar
val nsint : scalar
val uint32 : scalar
val uint64 : scalar
val double : scalar
val mach_port : scalar
val kern_return : scalar
val named_nsuint : string -> scalar
val named_nsint : string -> scalar

(** Deterministically derives private generated OCaml/C names unless explicit
    golden-compatible overrides are supplied. *)
val method_entry :
  ?ocaml_name:string -> ?c_symbol:string -> sdk_id:string -> owner:string ->
  selector:string -> header:string -> signature:string ->
  ?attributes:string list -> macos_introduced:Binding_availability.version ->
  arguments:scalar list -> result:scalar option -> semantics:semantics -> unit ->
  method_entry

val property_entry :
  sdk_id:string -> owner:string -> name:string -> header:string ->
  signature:string -> ?attributes:string list ->
  macos_introduced:Binding_availability.version -> getter:method_entry ->
  ?setter:method_entry -> unit -> property_entry

val scalar_objc_type : scalar -> string
val scalar_ocaml_type : scalar -> string
val method_inventory_ids : method_entry -> string list
val property_inventory_ids : property_entry -> string list
