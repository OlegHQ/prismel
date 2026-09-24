type output =
  { ocaml_ml : string
  ; ocaml_mli : string
  ; test_ml : string
  ; native_checks : string
  }

val generate : Binding_value_record_plan.selection -> output
