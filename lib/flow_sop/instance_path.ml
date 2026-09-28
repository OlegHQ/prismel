type t = int list
module Map = Map.Make (struct type nonrec t = t let compare = Stdlib.compare end)
