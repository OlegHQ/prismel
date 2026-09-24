let () =
  Binding_small_header_safe24.validate ();
  let json =
    In_channel.with_open_bin "../../lib/metal/generated_api_inventory.json"
      In_channel.input_all |> Yojson.Safe.from_string
  in
  let symbols = Hashtbl.create 64 in
  Yojson.Safe.Util.(member "symbols" json |> to_list)
  |> List.iter (fun item ->
       let open Yojson.Safe.Util in
       Hashtbl.replace symbols (member "id" item |> to_string)
         (member "classification" item |> to_string));
  List.iter (fun id ->
    match Hashtbl.find_opt symbols id with
    | None -> invalid_arg ("missing small-header ID " ^ id)
    | Some ("bound" | "unreviewed") -> ()
    | Some status -> invalid_arg (id ^ " has unexpected status " ^ status))
    Binding_small_header_safe24.ids;
  print_endline "small-header safe24: exact public closure"
