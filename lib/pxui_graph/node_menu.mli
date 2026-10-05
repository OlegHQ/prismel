(** The categorised node menu (leader [Space a]): a search field over the top-level column of
    category paths, submenus that open on hover or click, typed search over the whole
    catalog.  Pure state plus one PXUI popup; the host decides what a picked key adds. *)

type entry = {
  key : string;
  label : string;
  category : string list;
  arity : int;
  context : string;  (** the graph the kind is for: ["sop"], ["value"], ["scene"] ... *)
  output : Flow.Ty.t;  (** what the node makes: the colour of its square in the rows *)
  off : string option;
      (** why the kind cannot be placed in this graph ([Some "not in sop"]), if it cannot: such a
          kind is listed after the others when searching, whole row in ink-3, and cannot be picked *)
}

val entries_of_factories : ?context:string -> Procedural.Edit_graph.factory list -> entry list
(** One entry per factory, its category path being the submenus; a SOP kind makes geometry.  No
    second catalog. *)

type t

val create : ?after:string -> x:int -> y:int -> entry list -> t
(** A menu open at a screen point (clamped inside the bounds it is drawn in); [after] is the node
    the new one goes after, which the title says.  Entries with an
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
