let fail message = invalid_arg ("Device residual safe package: " ^ message)

let () =
  Binding_device_residual_safe_package.validate ();
  let source =
    In_channel.with_open_bin "../../lib/metal/generated_api_inventory.json"
      In_channel.input_all
  in
  let inventory = Yojson.Safe.from_string source in
  let symbols = Yojson.Safe.Util.member "symbols" inventory |> Yojson.Safe.Util.to_list in
  let table = Hashtbl.create 128 in
  List.iter
    (fun symbol ->
      let open Yojson.Safe.Util in
      if member "header" symbol |> to_string = "Metal/MTLDevice.h" then
        Hashtbl.replace table (member "id" symbol |> to_string)
          (member "classification" symbol |> to_string))
    symbols;
  List.iter
    (fun id ->
      match Hashtbl.find_opt table id with
      | Some ("unreviewed" | "bound") -> ()
      | Some status -> fail (id ^ " has unexpected status " ^ status)
      | None -> fail (id ^ " is absent from the pinned Device inventory"))
    Binding_device_residual_safe_package.ids;
  Printf.printf
    "MTLDevice residual88: synchronous owned slice25 = already-safe15 + missing-safe10; callbacks and observers remain isolated\n"
