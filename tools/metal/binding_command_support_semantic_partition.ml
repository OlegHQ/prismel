let blit_false_mechanical =
  Binding_command_support_audit.items
  |> List.filter_map (fun (item:Binding_command_support_audit.item) ->
      if item.lane=Mechanical_value && String.starts_with ~prefix:"method:-[MTLBlitCommandEncoder " item.id
      then Some item.id else None)

let lane id =
  if List.mem id blit_false_mechanical then `Handwritten_lifecycle
  else match List.find(fun(x:Binding_command_support_audit.item)->x.id=id)Binding_command_support_audit.items with
  | {lane=Mechanical_value;_}->`Mechanical_value
  | {lane=Handwritten_lifecycle;_}->`Handwritten_lifecycle

let count wanted=List.fold_left(fun n id->if lane id=wanted then n+1 else n)0 Binding_command_support_manifest.ids
let ()=
  if List.length blit_false_mechanical<>9 then failwith"command support blit false-mechanical drift";
  if count `Mechanical_value<>18||count `Handwritten_lifecycle<>103 then failwith"command support semantic split drift"
