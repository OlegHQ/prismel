(** Declarative schema for the private raw [NSString *] property batch.

    Getter results are copied into OCaml strings before the Objective-C call
    returns.  Setter arguments are borrowed only for the duration of the
    typed direct selector call.  No Objective-C object escapes this boundary,
    and these declarations do not imply safe-API coverage. *)

type nullability = Nonnull | Nullable

type getter_ownership = Copy_to_ocaml
type setter_ownership = Borrow_during_call

type receiver_status =
  | Qualified_direct of Binding_receiver_catalog.receiver
  | Qualified_polymorphic of Binding_receiver_catalog.polymorphic_receiver
  | Pending_receiver_catalog

type entry =
  { property_sdk_id : string
  ; getter_sdk_id : string
  ; setter_sdk_id : string option
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; nullability : nullability
  ; getter_ownership : getter_ownership
  ; setter_ownership : setter_ownership option
  ; receiver_status : receiver_status
  }

val entry :
  ?attributes:string list -> ?setter:bool -> owner:string -> name:string ->
  header:string -> signature:string -> macos_introduced:string -> unit -> entry

val inventory_ids : entry -> string list
val getter_ocaml_type : entry -> string
val setter_ocaml_type : entry -> string option
val getter_selector : entry -> string
val setter_selector : entry -> string option

(** Emits a direct, statically typed Objective-C expression only after the
    receiver has been qualified by [Binding_receiver_catalog]. *)
val native_getter_expression : entry -> string
val native_setter_expression : entry -> string option
