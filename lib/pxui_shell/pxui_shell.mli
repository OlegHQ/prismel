(** Editor chrome built with the shared PXUI handle. *)

module Which_key : sig
  val panel : Pxui.Ui.t -> ('scope, 'action) Editor.Keymap.binding list ->
    focus:'scope -> focus_name:string -> unit
  (** Draw global and focused leader bindings in the standard modal. *)
end
