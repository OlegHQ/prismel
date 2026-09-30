module Edit = Procedural.Edit_graph

type descriptor = {
  qualified : string; key : string; operation : string; label : string;
  category : string list; slots : (string * Edit.input_requirement) list;
  fields : Param.field_view list;
}

let descriptor factory = {
  qualified = "sop/" ^ Edit.factory_key factory; key = Edit.factory_key factory;
  operation = Edit.factory_operation factory; label = Edit.factory_label factory;
  category = Edit.factory_category factory;
  slots = List.combine (Edit.factory_slot_names factory) (Edit.factory_inputs factory);
  fields = Edit.factory_fields factory }

let context_of qualified = List.find_map (fun context ->
  if String.starts_with ~prefix:(Flow.Context.name context ^ "/") qualified
  then Some context else None) Flow.Context.[Sop; Scene; World; Settings]

let of_factories ~version ?(extra = []) factories =
  let seen = Hashtbl.create 64 in
  let rec build reversed = function
    | [] -> Ok Flow.Check.{version; kinds = List.rev reversed}
    | (entry : descriptor) :: rest ->
        if Hashtbl.mem seen entry.qualified then Error (Flow.Diagnostic.error
          ~code:"E_CATALOG" ("Duplicate kind " ^ entry.qualified))
        else begin
          let slots = List.map (fun (name, requirement) ->
            Flow.Check.{name; required = requirement <> Edit.Optional;
              rest = requirement = Edit.Rest}) entry.slots in
          Hashtbl.add seen entry.qualified ();
          Result.bind (Port.parameters entry.fields) (fun ports ->
            let parameters = List.map (fun port ->
              let label = match port.Port.fields with
                | (field : Param.field_view) :: _ -> field.label
                | [] -> port.path in
              Flow.Check.{name = port.path; label; ty = port.ty;
                fields = List.map (fun (field : Param.field_view) ->
                  field.name, field.kind, field.default) port.fields}) ports in
            let context = Option.get (context_of entry.qualified) in
            let outputs = if context = Flow.Context.Sop
              then ["geo", Flow.Port_type.Geometry] else [] in
            build (Flow.Check.{qualified = entry.qualified; aliases = [];
              context; slots; parameters; outputs} :: reversed) rest)
        end in
  build [] (List.map descriptor factories @ extra)
