type t = {
  name : string;
  network : Network.t;
  display : int option;
  definitions : Network.definition Network.String_map.t;
}
