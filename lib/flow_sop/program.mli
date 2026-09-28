type t = {
  name : string;
  network : Network.t;
  display : int option;
  definitions : Network.definition Network.String_map.t;
}
(** A checked Flow program ready to seed an editor workspace. *)
