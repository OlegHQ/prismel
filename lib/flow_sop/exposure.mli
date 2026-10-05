(** Which parameter rows a card shows (flow.md section 5.1).  The one place the rule lives: the
    canvas, the list badges and the inspector's toggle all ask it. *)

type facts = {
  slot : bool;  (** a geometry slot: always shown *)
  driven : bool;  (** a wire, an expression or a nested node is written there *)
  pin : bool option;  (** the node's row pin ([layout.rows]), when it has one *)
  differs : bool;  (** a literal differing from the schema default is written *)
  primary : bool;  (** a primary row of the schema *)
}

val shown : facts -> bool
(** Evaluated in order: a geometry slot shows; a driven row shows and no pin can hide it; a pin
    decides; a row set off its default shows; a primary row shows; the rest is hidden (the card
    ends with a [+ N more] row). *)
