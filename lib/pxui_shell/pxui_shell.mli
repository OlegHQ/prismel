(** Editor chrome built with the shared PXUI handle. *)

module Which_key : sig
  val panel : Pxui.Ui.t -> ('scope, 'action) Editor.Keymap.binding list ->
    focus:'scope -> focus_name:string -> unit
  (** Draw global and focused leader bindings in the standard modal. *)
end

module Status_bar : sig
  val draw : Pxui.Ui.t -> bounds:(int * int * int * int) ->
    text:string -> fps:int option -> unit
  (** Paint the standard status strip in logical-point bounds. *)
end
