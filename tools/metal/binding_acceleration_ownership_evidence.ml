open Binding_acceleration_ownership_plan
let validate selection =
  let setters = List.fold_left (fun count value -> count + Option.fold ~none:0 ~some:(fun _ -> 1) value.setter) 0 selection.properties in
  if setters <> 48 then invalid_arg "Metal acceleration ownership setter count drift";
  List.iter (fun value ->
    if value.getter.classification <> "unreviewed" && value.getter.classification <> "bound" then invalid_arg ("Metal acceleration ownership classification drift: " ^ value.getter.id);
    if value.getter.signature <> "instance () -> " ^ value.property.signature then invalid_arg ("Metal acceleration ownership signature drift: " ^ value.getter.id);
    Option.iter (fun setter -> if setter.signature <> "instance (" ^ value.property.signature ^ ") -> void" then invalid_arg ("Metal acceleration ownership setter drift: " ^ setter.id)) value.setter) selection.properties
