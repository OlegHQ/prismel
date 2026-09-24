open Binding_acceleration_scalar_plan
let validate selection =
  List.iter (fun value ->
    if value.getter.classification <> "bound" then invalid_arg ("Metal acceleration getter classification drift: " ^ value.getter.id);
    Option.iter (fun setter -> if setter.classification <> "bound" then invalid_arg ("Metal acceleration setter classification drift: " ^ setter.id)) value.setter;
    let expected = "instance () -> " ^ value.property.signature in
    if value.getter.signature <> expected then invalid_arg ("Metal acceleration getter signature drift: " ^ value.getter.id);
    Option.iter (fun setter -> let expected = "instance (" ^ value.property.signature ^ ") -> void" in if setter.signature <> expected then invalid_arg ("Metal acceleration setter signature drift: " ^ setter.id)) value.setter) selection.properties
