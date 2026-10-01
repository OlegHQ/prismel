(** The categorised node menu (leader [Space a]): a search field over the top-level column of
    category paths, submenus that open on hover or click, typed search over the whole
    catalog.  Pure state plus one PXUI popup; the host decides what a picked key adds. *)

type entry = { key : string; label : string; category : string list; arity : int }

val entries_of_factories : Procedural.Edit_graph.factory list -> entry list
(** One entry per factory, its category path being the submenus.  No second catalog. *)

type t

val create : x:int -> y:int -> entry list -> t
(** A menu open at a screen point (clamped inside the bounds it is drawn in).  Entries with an
    empty key, label or category path, or a repeated key, are dropped. *)

val position : t -> int * int
(** The screen point the menu was opened at (where the host places what it adds). *)

val update : t -> Pxui.Ui.t -> bounds:int * int * int * int -> t option * string option
(** Build the popup inside [Pxui.Ui.frame]: the menu while it stays open ([None] after Escape, a
    press outside or a pick) and the key of the entry picked this frame. *)

module Private : sig
  val keys : t -> query:string -> string list
  (** The entry keys the query lists, in order (tests). *)
end
