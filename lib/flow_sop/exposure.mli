val shown :
  ?active:bool -> geometry:bool -> driven:bool -> pin:bool option ->
  overridden:bool -> primary:bool -> unit -> bool
(** Card-row visibility in spec order. Full renders all rows, dimming those
    this rule hides. Inactive unary inputs keep drive and pin precedence. *)

val primary : schema:Param.field_view list -> Port.parameter -> bool
val overridden : Port.parameter -> bool
