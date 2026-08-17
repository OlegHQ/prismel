open Ppxlib
open Ast_builder.Default

let expression_attribute name =
  Attribute.declare name Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload __) Fun.id

let default_attribute = expression_attribute "sop.default"
let label_attribute = expression_attribute "sop.label"
let name_attribute = expression_attribute "sop.name"
let description_attribute = expression_attribute "sop.description"
let folder_attribute = expression_attribute "sop.folder"
let impact_attribute = expression_attribute "sop.impact"
let soft_min_attribute = expression_attribute "sop.min"
let soft_max_attribute = expression_attribute "sop.max"
let hard_min_attribute = expression_attribute "sop.hard_min"
let hard_max_attribute = expression_attribute "sop.hard_max"
let kind_attribute = expression_attribute "sop.kind"
let ignore_attribute =
  Attribute.declare_flag "sop.ignore" Attribute.Context.label_declaration

let type_expression_attribute name =
  Attribute.declare name Attribute.Context.type_declaration
    Ast_pattern.(single_expr_payload __) Fun.id

let node_key_attribute = type_expression_attribute "sop.node_key"
let node_operation_attribute = type_expression_attribute "sop.node_operation"
let node_label_attribute = type_expression_attribute "sop.node_label"
let node_category_attribute = type_expression_attribute "sop.node_category"
let node_inputs_attribute = type_expression_attribute "sop.node_inputs"
let node_optional_attribute = type_expression_attribute "sop.node_optional"
let register_attribute =
  Attribute.declare_flag "sop.register" Attribute.Context.module_binding

let located_lident ~loc value = { loc; txt = Longident.Lident value }

let longident_of_list = function
  | [] -> invalid_arg "longident_of_list"
  | head :: tail ->
      List.fold_left (fun path item -> Longident.Ldot (path, item))
        (Longident.Lident head) tail

let located_path ~loc values = { loc; txt = longident_of_list values }
let ident ~loc values = pexp_ident ~loc (located_path ~loc values)

let string_constant expression what = match expression.pexp_desc with
  | Pexp_constant (Pconst_string (value, _, _)) -> value
  | _ -> Location.raise_errorf ~loc:expression.pexp_loc
      "%s expects a string literal" what

let int_constant expression what = match expression.pexp_desc with
  | Pexp_constant (Pconst_integer (value, None)) ->
      (match int_of_string_opt value with
       | Some value -> value
       | None -> Location.raise_errorf ~loc:expression.pexp_loc
           "%s integer literal is outside the supported range" what)
  | _ -> Location.raise_errorf ~loc:expression.pexp_loc
      "%s expects an integer literal" what

let optional_string attribute declaration what =
  Option.map (fun expression -> string_constant expression what)
    (Attribute.get attribute declaration)

let required attribute declaration what =
  match Attribute.get attribute declaration with
  | Some expression -> expression
  | None -> Location.raise_errorf ~loc:declaration.pld_loc
      "%s requires [@sop.%s ...]" declaration.pld_name.txt what

let type_name = function
  | { ptyp_desc = Ptyp_constr ({ txt = Longident.Lident name; _ }, []); _ } ->
      Some name
  | _ -> None

let parameter_constructor ~loc name =
  pexp_construct ~loc
    (located_path ~loc ["Procedural"; "Parameter"; name]) None

let apply ~loc function_ arguments = pexp_apply ~loc function_ arguments

let numeric_kind declaration integer =
  let loc = declaration.pld_loc in
  let minimum = required soft_min_attribute declaration "min"
  and maximum = required soft_max_attribute declaration "max" in
  let arguments = ref [Labelled "min", minimum; Labelled "max", maximum] in
  Option.iter (fun value -> arguments := (Labelled "hard_min", value) :: !arguments)
    (Attribute.get hard_min_attribute declaration);
  Option.iter (fun value -> arguments := (Labelled "hard_max", value) :: !arguments)
    (Attribute.get hard_max_attribute declaration);
  arguments := List.rev_append !arguments [Nolabel, eunit ~loc];
  apply ~loc (ident ~loc ["Procedural"; "Parameter";
    if integer then "integer" else "floating"]) !arguments

let kind_expression declaration =
  match Attribute.get kind_attribute declaration with
  | Some expression -> expression
  | None ->
      let loc = declaration.pld_loc in
      match type_name declaration.pld_type with
      | Some "bool" -> parameter_constructor ~loc "Toggle"
      | Some "string" -> parameter_constructor ~loc "Text"
      | Some "int" -> numeric_kind declaration true
      | Some "float" -> numeric_kind declaration false
      | Some name -> Location.raise_errorf ~loc
          "sop_params cannot infer parameter kind for %s; add [@sop.kind ...]"
          name
      | None -> Location.raise_errorf ~loc
          "sop_params requires [@sop.kind ...] for this field type"

let impact_expression declaration =
  let loc = declaration.pld_loc in
  match optional_string impact_attribute declaration "sop.impact" with
  | None | Some "cook" -> parameter_constructor ~loc "Cook"
  | Some "view" -> parameter_constructor ~loc "View"
  | Some "export" -> parameter_constructor ~loc "Export"
  | Some value -> Location.raise_errorf ~loc
      "sop.impact must be \"cook\", \"view\", or \"export\", not %S" value

let folder_expression declaration =
  let loc = declaration.pld_loc in
  let parts = match optional_string folder_attribute declaration "sop.folder" with
    | None -> []
    | Some value -> String.split_on_char '/' value
        |> List.filter (fun item -> String.trim item <> "")
  in
  elist ~loc (List.map (estring ~loc) parts)

let optional_labelled ~loc label = function
  | None -> []
  | Some value -> [Labelled label, estring ~loc value]

let field_expression type_declaration declaration =
  let loc = declaration.pld_loc in
  let field_name = declaration.pld_name.txt in
  let record_type = ptyp_constr ~loc
      (located_lident ~loc type_declaration.ptype_name.txt) [] in
  let record_pattern = ppat_constraint ~loc
      (ppat_var ~loc { loc; txt = "record" }) record_type in
  let record = evar ~loc "record" and field_value = evar ~loc "field_value" in
  let field_path = located_lident ~loc field_name in
  let get = pexp_fun ~loc Nolabel None record_pattern
      (pexp_field ~loc record field_path) in
  let record_base = match type_declaration.ptype_kind with
    | Ptype_record [_] -> None
    | Ptype_record _ | Ptype_abstract | Ptype_variant _ | Ptype_open ->
        Some record
  in
  let set_record_pattern = match record_base with
    | None -> ppat_constraint ~loc
        (ppat_var ~loc { loc; txt = "_record" }) record_type
    | Some _ -> record_pattern
  in
  let set = pexp_fun ~loc Nolabel None (ppat_var ~loc { loc; txt = "field_value" })
      (pexp_fun ~loc Nolabel None set_record_pattern
        (pexp_record ~loc [field_path, field_value] record_base)) in
  let public_name = Option.value ~default:field_name
      (optional_string name_attribute declaration "sop.name") in
  let arguments =
    [ Labelled "name", estring ~loc public_name ]
    @ optional_labelled ~loc "label"
        (optional_string label_attribute declaration "sop.label")
    @ optional_labelled ~loc "description"
        (optional_string description_attribute declaration "sop.description")
    @ [ Labelled "folder", folder_expression declaration;
        Labelled "impact", impact_expression declaration;
        Labelled "kind", kind_expression declaration;
        Labelled "default", required default_attribute declaration "default";
        Labelled "get", get;
        Labelled "set", set;
        Nolabel, eunit ~loc ]
  in
  apply ~loc (ident ~loc ["Procedural"; "Parameter"; "field"]) arguments

let value_binding ~loc name expression =
  pstr_value ~loc Nonrecursive [value_binding ~loc
    ~pat:(ppat_var ~loc { loc; txt = name }) ~expr:expression]

let ensure_monomorphic type_declaration =
  if type_declaration.ptype_params <> [] then
    Location.raise_errorf ~loc:type_declaration.ptype_loc
      "sop_params requires a monomorphic record type"

let generate_type type_declaration =
  ensure_monomorphic type_declaration;
  let loc = type_declaration.ptype_loc in
  match type_declaration.ptype_kind with
  | Ptype_record declarations ->
      let default_name = type_declaration.ptype_name.txt ^ "_default"
      and schema_name = type_declaration.ptype_name.txt ^ "_schema" in
      let defaults = List.map (fun declaration ->
        located_lident ~loc:declaration.pld_loc declaration.pld_name.txt,
        required default_attribute declaration "default") declarations in
      let default_expression = pexp_constraint ~loc
          (pexp_record ~loc defaults None)
          (ptyp_constr ~loc (located_lident ~loc type_declaration.ptype_name.txt) [])
      in
      let fields = declarations
        |> List.filter (fun declaration ->
          not (Attribute.has_flag ignore_attribute declaration))
        |> List.map (field_expression type_declaration) in
      let schema_expression = apply ~loc
          (ident ~loc ["Procedural"; "Parameter"; "schema"])
          [ Labelled "name", estring ~loc type_declaration.ptype_name.txt;
            Labelled "default", evar ~loc default_name;
            Nolabel, elist ~loc fields ] in
      [ value_binding ~loc default_name default_expression;
        value_binding ~loc schema_name schema_expression ]
  | Ptype_abstract | Ptype_variant _ | Ptype_open ->
      let extension = Location.error_extensionf ~loc
          "sop_params can only derive record types" in
      [pstr_extension ~loc extension []]

let generate_impl ~ctxt (_recursive, declarations) =
  let _loc = Expansion_context.Deriver.derived_item_loc ctxt in
  List.concat_map generate_type declarations

let signature_type ~loc type_declaration =
  ptyp_constr ~loc (located_lident ~loc type_declaration.ptype_name.txt) []

let generate_signature type_declaration =
  ensure_monomorphic type_declaration;
  let loc = type_declaration.ptype_loc in
  let type_ = signature_type ~loc type_declaration in
  let default_name = type_declaration.ptype_name.txt ^ "_default"
  and schema_name = type_declaration.ptype_name.txt ^ "_schema" in
  [ psig_value ~loc (value_description ~loc
      ~name:{ loc; txt = default_name } ~type_ ~prim:[]);
    psig_value ~loc (value_description ~loc
      ~name:{ loc; txt = schema_name }
      ~type_:(ptyp_constr ~loc
        (located_path ~loc ["Procedural"; "Parameter"; "schema"]) [type_])
      ~prim:[]) ]

let generate_intf ~ctxt (_recursive, declarations) =
  let _loc = Expansion_context.Deriver.derived_item_loc ctxt in
  List.concat_map generate_signature declarations

let required_type attribute declaration what =
  match Attribute.get attribute declaration with
  | Some expression -> expression
  | None -> Location.raise_errorf ~loc:declaration.ptype_loc
      "sop_node requires [@@%s ...]" what

let node_metadata declaration =
  let key = string_constant
      (required_type node_key_attribute declaration "sop.node_key")
      "sop.node_key"
  and label = string_constant
      (required_type node_label_attribute declaration "sop.node_label")
      "sop.node_label"
  and category = string_constant
      (required_type node_category_attribute declaration "sop.node_category")
      "sop.node_category"
  and inputs = int_constant
      (required_type node_inputs_attribute declaration "sop.node_inputs")
      "sop.node_inputs" in
  let operation = match Attribute.get node_operation_attribute declaration with
    | None -> key
    | Some expression -> string_constant expression "sop.node_operation" in
  let category = String.split_on_char '/' category
      |> List.map String.trim
      |> List.filter (fun item -> item <> "") in
  if String.trim key = "" || String.trim operation = ""
      || String.trim label = "" || category = [] then
    Location.raise_errorf ~loc:declaration.ptype_loc
      "sop_node key, label, and category must not be blank";
  if inputs < 0 then Location.raise_errorf ~loc:declaration.ptype_loc
      "sop.node_inputs must be non-negative";
  let optional = match Attribute.get node_optional_attribute declaration with
    | None -> []
    | Some expression ->
        let value = string_constant expression "sop.node_optional" in
        String.split_on_char ',' value |> List.filter_map (fun item ->
          let item = String.trim item in
          if item = "" then None
          else match int_of_string_opt item with
            | Some index when index >= 0 && index < inputs -> Some index
            | _ -> Location.raise_errorf ~loc:expression.pexp_loc
                "sop.node_optional contains invalid slot %S for %d inputs"
                item inputs)
        |> List.sort_uniq Int.compare in
  key, operation, label, category, inputs, optional

let generate_node_type declaration =
  ensure_monomorphic declaration;
  let loc = declaration.ptype_loc in
  let key, operation, label, category, inputs, optional =
    node_metadata declaration in
  let build = evar ~loc "build" and input_nodes = evar ~loc "input_nodes" in
  let construct = apply ~loc build
      [ Labelled "label", estring ~loc key;
        Labelled "inputs", input_nodes;
        Nolabel, evar ~loc (declaration.ptype_name.txt ^ "_default") ] in
  let constructor = pexp_fun ~loc Nolabel None
      (ppat_var ~loc { loc; txt = "input_nodes" }) construct in
  let common = [
    Labelled "key", estring ~loc key;
    Labelled "operation", estring ~loc operation;
    Labelled "label", estring ~loc label;
    Labelled "category", elist ~loc (List.map (estring ~loc) category) ] in
  let factory = if optional = [] then
      apply ~loc (ident ~loc ["Procedural"; "Edit_graph"; "factory"])
        (common @ [Labelled "arity", eint ~loc inputs; Nolabel, constructor])
    else
      let requirements = List.init inputs (fun index ->
        pexp_construct ~loc (located_path ~loc ["Procedural"; "Edit_graph";
          if List.mem index optional then "Optional" else "Required"]) None) in
      apply ~loc (ident ~loc ["Procedural"; "Edit_graph"; "factory_slots"])
        (common @ [Labelled "inputs", elist ~loc requirements;
          Nolabel, constructor]) in
  [value_binding ~loc (declaration.ptype_name.txt ^ "_factory")
     (pexp_fun ~loc Nolabel None
       (ppat_var ~loc { loc; txt = "build" }) factory)]

let generate_node_impl ~ctxt (_recursive, declarations) =
  let _loc = Expansion_context.Deriver.derived_item_loc ctxt in
  List.concat_map generate_node_type declarations

let registered_module = function
  | { pstr_desc = Pstr_module binding; _ }
      when Attribute.has_flag register_attribute binding -> binding.pmb_name.txt
  | _ -> None

let manifest structure =
  let names = List.filter_map registered_module structure in
  match names with
  | [] -> structure
  | names ->
      let loc = (List.hd structure).pstr_loc in
      let factories = List.map (fun name ->
        ident ~loc [name; "factory"]) names in
      let editor = pmod_structure ~loc
          [value_binding ~loc "factories" (elist ~loc factories)] in
      structure @ [pstr_module ~loc (module_binding ~loc
        ~name:{ loc; txt = Some "Editor" } ~expr:editor)]

let attributes = List.map (fun attribute -> Attribute.T attribute)
    [ default_attribute; label_attribute; name_attribute; description_attribute;
      folder_attribute; impact_attribute; soft_min_attribute; soft_max_attribute;
      hard_min_attribute; hard_max_attribute; kind_attribute ]
  @ [Attribute.T ignore_attribute]

let node_attributes = List.map (fun attribute -> Attribute.T attribute)
    [node_key_attribute; node_operation_attribute; node_label_attribute;
     node_inputs_attribute; node_optional_attribute]

let () =
  let structure = Deriving.Generator.V2.make_noarg ~attributes generate_impl
  and signature = Deriving.Generator.V2.make_noarg ~attributes generate_intf in
  Deriving.add "sop_params" ~str_type_decl:structure ~sig_type_decl:signature
  |> Deriving.ignore;
  let node_structure = Deriving.Generator.V2.make_noarg
      ~attributes:node_attributes generate_node_impl in
  Deriving.add "sop_node" ~str_type_decl:node_structure |> Deriving.ignore;
  Driver.register_transformation "sop_manifest" ~impl:manifest
