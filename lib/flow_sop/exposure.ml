let shown ?(active = true) ~geometry ~driven ~pin ~overridden ~primary () =
  geometry || driven || match pin with
    | Some pinned -> pinned | None -> active && (overridden || primary)
let primary ~schema parameter =
  if List.exists (fun (field : Param.field_view) -> field.primary) schema then
    List.exists (fun (field : Param.field_view) -> field.primary) parameter.Port.fields
  else match schema with
    | [] -> false | first :: _ -> List.exists
        (fun (field : Param.field_view) -> field.folder = first.folder) parameter.Port.fields
let overridden parameter = List.exists
  (fun (field : Param.field_view) -> field.current <> field.default) parameter.Port.fields
