let of_factories ~version factories =
  let seen = Hashtbl.create (List.length factories) in
  let rec build reversed = function
    | [] -> Ok Flow.Check.{version; kinds = List.rev reversed}
    | entry :: rest ->
        let open Procedural.Edit_graph in
        let key = factory_key entry in
        let names = factory_slot_names entry
        and requirements = factory_inputs entry in
        if Hashtbl.mem seen key then Error (Flow.Diagnostic.error
          ~code:"E_CATALOG" ("Duplicate SOP key " ^ key))
        else if List.length names <> List.length requirements then
          Error (Flow.Diagnostic.error ~code:"E_CATALOG"
            ("Slot signature mismatch for " ^ key))
        else let slots = List.map2 (fun name requirement ->
          Flow.Check.{name; required = requirement <> Optional; rest = requirement = Rest})
          names requirements in
        Hashtbl.add seen key ();
        Result.bind (Port.parameters (factory_fields entry))
          (fun ports ->
            let parameters = List.map (fun port ->
              let label = match port.Port.fields with
                | (field : Param.field_view) :: _ -> field.label
                | [] -> port.path in
              Flow.Check.{name = port.path; label; ty = port.ty;
                fields = List.map (fun (field : Param.field_view) ->
                  field.name, field.kind, field.default) port.fields}) ports in
            let kind = Flow.Check.{qualified = "sop/" ^ key;
              aliases = []; context = Flow.Context.Sop; slots; parameters;
              outputs = ["geo", Flow.Port_type.Geometry]} in
            build (kind :: reversed) rest) in
  build [] factories
