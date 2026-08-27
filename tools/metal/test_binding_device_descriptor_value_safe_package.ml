let () =
  Binding_device_descriptor_value_safe_package.validate ();
  let json =
    In_channel.with_open_bin "../../lib/metal/generated_api_inventory.json"
      In_channel.input_all
    |> Yojson.Safe.from_string
  in
  let ids = Hashtbl.create 128 in
  Yojson.Safe.Util.(member "symbols" json |> to_list)
  |> List.iter (fun symbol ->
       let open Yojson.Safe.Util in
       if member "header" symbol |> to_string = "Metal/MTLDevice.h" then
         Hashtbl.replace ids (member "id" symbol |> to_string) ());
  List.iter
    (fun id -> if not (Hashtbl.mem ids id) then invalid_arg ("missing " ^ id))
    Binding_device_descriptor_value_safe_package.ids;
  Printf.printf
    "MTLDevice residual88: pinned descriptor/value slice25 (ArgumentDescriptor20 + Architecture5)\n"
