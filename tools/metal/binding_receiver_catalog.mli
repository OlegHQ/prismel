(** Audited native-receiver vocabulary for mechanical Metal direct-call
    generation.

    This describes how SDK owners already represented by [Handle_kind] in
    [lib/metal/metal_bridge.mm] are recovered on the Objective-C++ side.  It is
    deliberately not a safe-API or ownership specification. *)

type owner_binding =
  | One_to_one
  | Distinct_role of string

type bridge_access =
  | Object_of_handle
  | Object_of_helper of string
  | Wrapped_property of
      { wrapper_type : string
      ; property : string
      }

type receiver =
  { sdk_owner : string
  ; objc_receiver_type : string
  ; handle_kind : string
  ; local_name : string
  ; raw_name : string
  ; owner_binding : owner_binding
  ; bridge_access : bridge_access
  }

(** A protocol whose receiver can be recovered from more than one concrete
    handle kind.  This is separate from [receiver] so Buffer/Texture resource
    polymorphism cannot be mistaken for a one-to-one handle mapping. *)
type polymorphic_receiver =
  { sdk_owner : string
  ; objc_receiver_type : string
  ; accepted_handle_kinds : string list
  ; helper : string
  ; local_name : string
  ; raw_name : string
  }

type exclusion =
  { handle_kind : string
  ; reason : string
  }

val receivers : receiver list
val polymorphic_receivers : polymorphic_receiver list
val exclusions : exclusion list

val expected_receiver_count : int
val expected_polymorphic_receiver_count : int
val expected_catalog_count : int
val expected_handle_kind_count : int
val expected_exclusion_count : int

(** Files whose exact bytes define this declarative catalog. *)
val source_paths : string list

(** The handwritten bridge audited to construct the catalog.  This is
    evidence, not a generated-plan source file. *)
val audited_bridge_path : string

val validate : unit -> unit
