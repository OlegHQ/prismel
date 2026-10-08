module Edit = Procedural.Edit_graph

type descriptor = {
  qualified : string; key : string; operation : string; label : string;
  category : string list; slots : (string * Edit.input_requirement) list;
  slot_types : string list;
  keyword_inputs : string list;
  fields : Param.field_view list;
}

let descriptor factory = {
  qualified = "sop/" ^ Edit.factory_key factory; key = Edit.factory_key factory;
  operation = Edit.factory_operation factory; label = Edit.factory_label factory;
  category = Edit.factory_category factory;
  slots = List.combine (Edit.factory_slot_names factory) (Edit.factory_inputs factory);
  slot_types = Edit.factory_input_types factory;
  keyword_inputs = Edit.factory_keyword_inputs factory;
  fields = Edit.factory_fields factory }

let context_of = Flow.Context.of_qualified

let of_factories ~version ?(extra = []) factories =
  let declarations = Hashtbl.create (List.length factories) in
  List.iter (fun factory ->
    let facts = Edit.factory_facts factory in
    Hashtbl.replace declarations ("sop/" ^ Edit.factory_key factory) Flow.Check.{
      elementwise = (match facts.elementwise with Points -> Points | Primitives -> Primitives | None -> Irregular);
      reads = facts.reads; writes = facts.writes;
      preserves_topology = (facts.topology = Procedural.Node.Preserved); exact = facts.exact}) factories;
  let seen = Hashtbl.create 64 in
  let rec build reversed = function
    | [] -> Ok Flow.Check.{version; kinds = List.rev reversed}
    | (entry : descriptor) :: rest ->
        if entry.slot_types <> [] && List.length entry.slot_types <> List.length entry.slots then
          Error (Flow.Diagnostic.error ~code:"E_CATALOG" ("Input type count differs in " ^ entry.qualified))
        else if not (List.for_all (fun name -> match Flow.Ty.of_string name with
          | Some (Flow.Ty.Named _ | Flow.Ty.Fn (Some _)) -> true | _ -> false) entry.slot_types) then
          Error (Flow.Diagnostic.error ~code:"E_CATALOG" ("Unknown input type in " ^ entry.qualified))
        else if List.length (List.sort_uniq String.compare entry.keyword_inputs) <> List.length entry.keyword_inputs
            || List.exists (fun name ->
              match List.find_index (fun (slot, _) -> slot = name) entry.slots with
              | None -> true
              | Some index -> snd (List.nth entry.slots index) <> Edit.Required
                  || (match Option.bind (List.nth_opt entry.slot_types index) Flow.Ty.of_string with
                      | Some (Flow.Ty.Fn (Some _)) -> false
                      | Some ty when ty = Flow.Ty.image -> false
                      | _ -> true)) entry.keyword_inputs then
          Error (Flow.Diagnostic.error ~code:"E_CATALOG" ("Keyword inputs require distinct required fn/image slots in " ^ entry.qualified))
        else if context_of entry.qualified = None then Error (Flow.Diagnostic.error
          ~code:"E_CATALOG" ("Unknown context prefix in " ^ entry.qualified))
        else if Hashtbl.mem seen entry.qualified then Error (Flow.Diagnostic.error
          ~code:"E_CATALOG" ("Duplicate kind " ^ entry.qualified))
        else begin
          let types = if entry.slot_types = [] then List.map (fun _ -> None) entry.slots else
            List.map (fun name -> if name = "geometry" then None else Flow.Ty.of_string name) entry.slot_types in
          let inputs = List.map2 (fun (name, requirement) ty ->
            Flow.Check.{name; required = (requirement = Edit.Required || requirement = Edit.Rest);
              rest = (requirement = Edit.Rest || requirement = Edit.Optional_rest); ty}) entry.slots types in
          let keywords, slots = List.partition (fun (s : Flow.Check.slot) ->
            List.mem s.name entry.keyword_inputs) inputs in
          let keywords = List.map (fun (s : Flow.Check.slot) ->
            let ty = match s.ty with
              | Some (Flow.Ty.Fn (Some signature)) -> Flow.Port_type.Fn signature
              | Some ty when ty = Flow.Ty.image -> Flow.Port_type.Image
              | _ -> invalid_arg ("Typed keyword input must be fn or image: " ^ s.name) in
            Flow.Check.{name = s.name; label = s.name; ty = Some ty;
              fields = []; folder = []; primary = true; unit = None}) keywords in
          Hashtbl.add seen entry.qualified ();
          Result.bind (Port.parameters entry.fields) (fun ports ->
            if List.exists (fun p -> List.mem p.Port.path entry.keyword_inputs) ports then
              Error (Flow.Diagnostic.error ~code:"E_CATALOG" ("Keyword input clashes with a scalar parameter in " ^ entry.qualified))
            else
            let parameters = List.map (fun port ->
              let label = match port.Port.fields with
                | (field : Param.field_view) :: _ -> field.label
                | [] -> port.path in
              Flow.Check.{name = port.path; label; ty = port.ty;
                fields = List.map (fun (field : Param.field_view) ->
                  field.name, field.kind, field.default) port.fields;
                folder = (match port.Port.fields with (f : Param.field_view) :: _ -> f.folder | [] -> []);
                primary = (match port.Port.fields with (f : Param.field_view) :: _ -> f.primary | [] -> false);
                unit = (match port.Port.fields with [(f : Param.field_view)] -> f.unit | _ -> None)}) ports in
            let context = Option.get (context_of entry.qualified) in
            let outputs = if context = Flow.Context.sop
              then ["geo", Flow.Port_type.Geometry] else [] in
            build (Flow.Check.{qualified = entry.qualified; aliases = [];
              context; slots; parameters = parameters @ keywords; outputs;
              facts = Hashtbl.find_opt declarations entry.qualified} :: reversed) rest)
        end in
  build [] (List.map descriptor factories @ extra)
