exception Error of string

type declaration =
  { id : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; signature : string
  ; classification : string
  ; constant_value : string option
  }

type selected_case =
  { declaration : declaration
  ; ocaml_name : string
  ; unsigned_decimal : string
  ; bits : int64
  }

type family =
  { sdk_name : string
  ; module_name : string
  ; enum_declaration : declaration
  ; typedef_declaration : declaration
  ; cases : selected_case list
  }

type selection =
  { families : family list
  ; identifiers : string list
  ; family_count : int
  ; case_count : int
  ; scope_excluded_case_count : int
  ; declaration_count : int
  }

(** Convert an SDK identifier to a valid, non-keyword OCaml value identifier.
    Raises [Error] instead of silently repairing an unsupported identifier. *)
val ocaml_value_identifier : string -> string

(** Convert an SDK identifier to a valid, non-keyword OCaml module identifier.
    Raises [Error] instead of silently repairing an unsupported identifier. *)
val ocaml_module_identifier : string -> string

(** Parse a canonical unsigned decimal integer from 0 through 2^64 - 1.
    The returned [int64] is its exact two's-complement bit pattern. *)
val uint64_bits : string -> int64

(** Select complete enum families from an inventory. Family enum declarations
    and typedef companions must remain [unreviewed]. Individual enum cases may
    be [unreviewed] or [scope-excluded]; every other classification fails
    closed. The result is canonicalized by family and case name and includes
    all enum, typedef, and case declaration identifiers. *)
val select : family_names:string list -> declaration list -> selection

(** Render a private raw implementation fragment. Constants are emitted as
    exact 64-bit hexadecimal literals under nested OCaml modules. *)
val render_raw_ml : ?outer_module:string -> selection -> string

(** Render the matching private raw interface fragment. *)
val render_raw_mli : ?outer_module:string -> selection -> string

(** Deterministic generator-manifest metadata for the selected enum batch,
    including every case classification and the aggregate selected
    [scope-excluded] case count. *)
val manifest_json : selection -> Yojson.Safe.t
