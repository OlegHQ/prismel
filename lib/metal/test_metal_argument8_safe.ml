open Metal

let member name members =
  List.find_opt (fun (value : Reflection.member) -> value.name = name) members

let run () =
  ()
