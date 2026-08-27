let () =
  Binding_metal4_compiler2_safe_closure.validate ();
  let json = In_channel.with_open_bin
    "../../lib/metal/generated_api_inventory.json" In_channel.input_all
    |> Yojson.Safe.from_string in
  let statuses=Hashtbl.create 4 in
  Yojson.Safe.Util.(member "symbols" json |> to_list)|>List.iter(fun item->
    let open Yojson.Safe.Util in Hashtbl.replace statuses
      (member "id" item|>to_string)(member "classification" item|>to_string));
  List.iter(fun id->match Hashtbl.find_opt statuses id with
    |Some("unreviewed"|"bound")->()|_->invalid_arg("missing compiler2 ID "^id))
    Binding_metal4_compiler2_safe_closure.ids;
  print_endline "MTL4Compiler async ML exact2: pinned"
