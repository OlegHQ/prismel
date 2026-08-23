type field =
  { id : string
  ; owner : string
  ; name : string
  ; objc_type : string
  }

type record =
  { id : string
  ; name : string
  ; header : string
  ; introduced : string option
  ; fields : field list
  }

type selection =
  { records : record list
  ; ids : string list
  }

val select : Yojson.Safe.t -> selection
(** Selects only public, fixed-layout, ownership-free Metal value records. *)

val expected_record_count : int
val expected_field_count : int
val expected_id_count : int
