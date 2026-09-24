let ()=
  if Array.length Sys.argv<>2 then invalid_arg"inventory";
  let open Yojson.Safe.Util in
  let symbols=Yojson.Safe.from_file Sys.argv.(1)|>member"symbols"|>to_list in
  let status id=match List.find_opt(fun json->json|>member"id"|>to_string=id)symbols with
    |None->failwith("missing Drawable8 ID: "^id)
    |Some json->json|>member"classification"|>to_string in
  Binding_drawable_safe_package.validate_handoff();
  List.iter(fun id->if status id<>"bound"then failwith("Drawable8 ID is not bound: "^id))
    Binding_drawable_safe_package.callable_ids;
  let actual=symbols|>List.filter_map(fun json->
    let id=json|>member"id"|>to_string in
    if List.mem id Binding_drawable_safe_package.callable_ids then Some id else None)
    |>List.sort_uniq String.compare in
  if actual<>List.sort String.compare Binding_drawable_safe_package.callable_ids then
    failwith"Drawable8 inventory membership drift";
  print_endline"Drawable8 exact safe closure: 8/8 bound"
