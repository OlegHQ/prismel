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
let vec3_attribute = expression_attribute "sop.vec3"
let primary_attribute =
  Attribute.declare_flag "sop.primary" Attribute.Context.label_declaration
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
let node_slots_attribute = type_expression_attribute "sop.node_slots"
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

let folder_parts declaration =
  match optional_string folder_attribute declaration "sop.folder" with
    | None -> []
    | Some value -> String.split_on_char '/' value
        |> List.filter (fun item -> String.trim item <> "")

let folder_expression declaration =
  let loc = declaration.pld_loc in
  elist ~loc (List.map (estring ~loc) (folder_parts declaration))

let public_name declaration = Option.value ~default:declaration.pld_name.txt
    (optional_string name_attribute declaration "sop.name")

let vec3_components declarations =
  let groups = List.filter_map (fun (index, declaration) ->
    Option.map (fun name -> name, index, declaration)
      (optional_string vec3_attribute declaration "sop.vec3"))
      (List.mapi (fun index declaration -> index, declaration) declarations) in
  let names = List.map public_name declarations in
  List.concat_map (fun name ->
    let fields = List.filter (fun (group, _, _) -> group = name) groups in
    let _, _, first = List.hd fields in
    let fail message = Location.raise_errorf ~loc:first.pld_loc
        "sop.vec3 %S %s" name message in
    if String.trim name = "" then fail "must not be blank";
    if List.mem name names then fail "clashes with a parameter name";
    (match fields with
     | [(_, a, _); (_, b, _); (_, c, _)] when b = a + 1 && c = b + 1 -> ()
     | _ -> fail "requires exactly three consecutive float fields in one folder");
    List.mapi (fun component (_, _, declaration) ->
      if type_name declaration.pld_type <> Some "float"
          || Attribute.has_flag ignore_attribute declaration
          || folder_parts declaration <> folder_parts first then
        fail "requires exactly three consecutive float fields in one folder";
      declaration.pld_name.txt, (name, component)) fields)
    (List.sort_uniq String.compare (List.map (fun (name, _, _) -> name) groups))

let optional_labelled ~loc label = function
  | None -> []
  | Some value -> [Labelled label, estring ~loc value]

let field_expression components type_declaration declaration =
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
  let arguments =
    [ Labelled "name", estring ~loc (public_name declaration);
      Labelled "primary", ebool ~loc (Attribute.has_flag primary_attribute declaration) ]
    @ (match List.assoc_opt field_name components with
       | None -> []
       | Some (name, index) ->
           [Labelled "vec3", pexp_tuple ~loc [estring ~loc name; eint ~loc index]])
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
      let components = vec3_components declarations in
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
        |> List.map (field_expression components type_declaration) in
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
  (match type_declaration.ptype_kind with
   | Ptype_record declarations -> ignore (vec3_components declarations)
   | _ -> ());
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
  if not (Flow.Symbol.valid_name key) then Location.raise_errorf ~loc:declaration.ptype_loc
      "sop.node_key must match [a-z][a-z0-9_]*, not %S" key;
  let slots = match Attribute.get node_slots_attribute declaration with
    | None -> List.init inputs (fun index -> "in" ^ string_of_int index)
    | Some expression ->
        let names = string_constant expression "sop.node_slots"
            |> String.split_on_char ',' |> List.map String.trim in
        if List.length names <> inputs || List.exists (fun name -> not (Flow.Symbol.valid_name name)) names
            || List.length (List.sort_uniq String.compare names) <> inputs then
          Location.raise_errorf ~loc:expression.pexp_loc
            "sop.node_slots requires %d distinct names matching [a-z][a-z0-9_]*" inputs;
        names in
  let field_names = match declaration.ptype_kind with
    | Ptype_record fields -> List.concat_map (fun field ->
        if Attribute.has_flag ignore_attribute field then [] else
        public_name field :: Option.to_list
          (optional_string vec3_attribute field "sop.vec3")) fields
    | _ -> [] in
  List.iter (fun slot -> if List.mem slot field_names then
    Location.raise_errorf ~loc:declaration.ptype_loc
      "sop.node_slots name %S clashes with a parameter name" slot) slots;
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
  key, operation, label, category, inputs, optional, slots

(* [<t>_build operator] is the recursive, arity-checked node constructor that
   [<t>_factory] consumes. [operator ~label parameters input0 ...] receives one
   [Node.t] per required slot and one [Node.t option] per optional slot and
   returns the unparameterized operator; the generated code checks the input
   shape, attaches the schema through [Node.parameterize] (which derives the
   cache identity from every cook field), and rebuilds itself after edits.
   Optional slots rebuild from the physical input list using the presence
   captured when the node was built, so sparse connections keep their slot. *)
let build_expression ~loc type_name label inputs optional =
  let var name = evar ~loc name and pvar name = ppat_var ~loc { loc; txt = name } in
  let slot index = Printf.sprintf "input%d" index in
  let slots = List.init inputs Fun.id in
  let plural = if inputs = 1 then "" else "s" in
  let fail message = apply ~loc (ident ~loc ["Stdlib"; "invalid_arg"])
      [Nolabel, estring ~loc message] in
  let fun_ label pattern body = pexp_fun ~loc label None pattern body in
  let operator_call = apply ~loc (var "operator")
      ((Labelled "label", var "label") :: (Nolabel, var "parameters")
       :: List.map (fun index -> Nolabel, var (slot index)) slots) in
  let parameterize rebuild = apply ~loc
      (ident ~loc ["Procedural"; "Node"; "parameterize"])
      [ Labelled "schema", var (type_name ^ "_schema");
        Labelled "values", var "parameters";
        Labelled "rebuild", rebuild;
        Nolabel, operator_call ] in
  let build_body shape rebuild message = pexp_match ~loc (var "inputs")
      [ case ~lhs:shape ~guard:None ~rhs:(parameterize rebuild);
        case ~lhs:(ppat_any ~loc) ~guard:None ~rhs:(fail message) ] in
  let build_fun body = fun_ (Labelled "label") (pvar "label")
      (fun_ (Labelled "inputs") (pvar "inputs")
        (fun_ Nolabel (pvar "parameters") body)) in
  let rec_build bindings = pexp_let ~loc Recursive
      (List.map (fun (name, expr) ->
        Ast_builder.Default.value_binding ~loc ~pat:(pvar name) ~expr) bindings) (var "build") in
  let body =
    if optional = [] then
      let shape = plist ~loc (List.map (fun index -> pvar (slot index)) slots) in
      rec_build ["build", build_fun (build_body shape (var "build")
        (Printf.sprintf "%s expects %d input%s" label inputs plural))]
    else
      let is_optional index = List.mem index optional in
      let present index = "present" ^ string_of_int index in
      let shape = plist ~loc (List.map (fun index ->
        if is_optional index then pvar (slot index)
        else ppat_construct ~loc (located_lident ~loc "Some")
          (Some (pvar (slot index)))) slots) in
      let rebuild = apply ~loc (var "rebuild") (List.map (fun index ->
        Nolabel, apply ~loc (ident ~loc ["Stdlib"; "Option"; "is_some"])
          [Nolabel, var (slot index)]) optional) in
      let lost = fail (Printf.sprintf
        "%s lost a connected input while rebuilding" label) in
      let take = pexp_match ~loc (var "rest")
          [ case ~lhs:(ppat_construct ~loc (located_lident ~loc "::")
                (Some (ppat_tuple ~loc [pvar "input"; pvar "rest"])))
              ~guard:None
              ~rhs:(pexp_tuple ~loc [pexp_construct ~loc
                (located_lident ~loc "Some") (Some (var "input"));
                var "rest"]);
            case ~lhs:(ppat_construct ~loc (located_lident ~loc "[]") None)
              ~guard:None ~rhs:lost ] in
      let decode = List.fold_right (fun index body ->
        let value = if is_optional index then
            pexp_ifthenelse ~loc (var (present index)) take
              (Some (pexp_tuple ~loc [pexp_construct ~loc
                (located_lident ~loc "None") None; var "rest"]))
          else take in
        pexp_let ~loc Nonrecursive [Ast_builder.Default.value_binding ~loc
          ~pat:(ppat_tuple ~loc [pvar (slot index); pvar "rest"]) ~expr:value]
          body) slots
        (pexp_match ~loc (var "rest")
          [ case ~lhs:(ppat_construct ~loc (located_lident ~loc "[]") None)
              ~guard:None
              ~rhs:(apply ~loc (var "build")
                [ Labelled "label", var "label";
                  Labelled "inputs", elist ~loc
                    (List.map (fun index -> var (slot index)) slots);
                  Nolabel, var "parameters" ]);
            case ~lhs:(ppat_any ~loc) ~guard:None ~rhs:(fail (Printf.sprintf
              "%s received extra inputs while rebuilding" label)) ]) in
      let rebuild_fun = List.fold_right (fun index body ->
        fun_ Nolabel (pvar (present index)) body) optional
        (build_fun (pexp_let ~loc Nonrecursive
          [Ast_builder.Default.value_binding ~loc ~pat:(pvar "rest") ~expr:(var "inputs")]
          decode)) in
      rec_build [
        "build", build_fun (build_body shape rebuild (Printf.sprintf
          "%s expects %d input slot%s with every required input connected"
          label inputs plural));
        "rebuild", rebuild_fun ] in
  fun_ Nolabel (pvar "operator") body

let generate_node_type declaration =
  ensure_monomorphic declaration;
  let loc = declaration.ptype_loc in
  let key, operation, label, category, inputs, optional, slots =
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
    Labelled "slots", elist ~loc (List.map (estring ~loc) slots);
    Labelled "fields", apply ~loc
      (ident ~loc ["Procedural"; "Parameter"; "view"])
      [Nolabel, evar ~loc (declaration.ptype_name.txt ^ "_schema");
       Nolabel, evar ~loc (declaration.ptype_name.txt ^ "_default")];
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
       (ppat_var ~loc { loc; txt = "build" }) factory);
   value_binding ~loc (declaration.ptype_name.txt ^ "_build")
     (build_expression ~loc declaration.ptype_name.txt label inputs optional)]

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
      hard_min_attribute; hard_max_attribute; kind_attribute; vec3_attribute ]
  @ [Attribute.T ignore_attribute; Attribute.T primary_attribute]

let node_attributes = List.map (fun attribute -> Attribute.T attribute)
    [node_key_attribute; node_operation_attribute; node_label_attribute;
     node_inputs_attribute; node_optional_attribute; node_slots_attribute]

let flow_manifest_path = ref None

let flow_position ~start source offset =
  let relative = Flow.Sexp.position_of_offset source offset in
  let pos_cnum = start.Lexing.pos_cnum + offset in
  let pos_lnum = start.pos_lnum + relative.line - 1 in
  let pos_bol = if relative.line = 1 then start.pos_bol
    else pos_cnum - relative.col + 1 in
  {start with Lexing.pos_cnum; pos_lnum; pos_bol}

let flow_location ~start source (diagnostic : Flow.Diagnostic.t) =
  let first, last = match diagnostic.span with
    | Some span -> span.start, span.finish | None -> 0, 0 in
  {Location.loc_start = flow_position ~start source first;
   loc_end = flow_position ~start source last; loc_ghost = false}

let flow_construct ~loc path = function
  | None -> pexp_construct ~loc (located_path ~loc path) None
  | Some argument -> pexp_construct ~loc (located_path ~loc path) (Some argument)
let flow_pair ~loc a b = pexp_tuple ~loc [a; b]
let flow_record ~loc path fields =
  pexp_constraint ~loc
    (pexp_record ~loc (List.map (fun (name, value) ->
      located_lident ~loc name, value) fields) None)
    (ptyp_constr ~loc (located_path ~loc path) [])
let flow_option ~loc f = function
  | None -> flow_construct ~loc ["None"] None
  | Some value -> flow_construct ~loc ["Some"] (Some (f value))
let flow_type ~loc = function
  | ty ->
      let name = match ty with
        | Flow.Port_type.Geometry -> "Geometry" | Float -> "Float"
        | Int -> "Int" | Bool -> "Bool" | Vec3 -> "Vec3" in
      flow_construct ~loc ["Flow"; "Port_type"; name] None
let flow_context ~loc = function
  | Flow.Context.Sop -> flow_construct ~loc ["Flow"; "Context"; "Sop"] None
  | Value -> flow_construct ~loc ["Flow"; "Context"; "Value"] None
  | Scene -> flow_construct ~loc ["Flow"; "Context"; "Scene"] None
  | World -> flow_construct ~loc ["Flow"; "Context"; "World"] None
let flow_literal ~loc = function
  | Param.Bool_value value -> flow_construct ~loc ["Param"; "Bool_value"]
      (Some (ebool ~loc value))
  | Int_value value -> flow_construct ~loc ["Param"; "Int_value"]
      (Some (eint ~loc value))
  | Float_value value -> flow_construct ~loc ["Param"; "Float_value"]
      (Some (efloat ~loc (Flow.Expr.sexp_number value)))
  | Text_value value -> flow_construct ~loc ["Param"; "Text_value"]
      (Some (estring ~loc value))
  | Choice_value value -> flow_construct ~loc ["Param"; "Choice_value"]
      (Some (estring ~loc value))

let rec flow_term ~loc (term : Flow.Check.term) =
  let list = elist ~loc in
  let node = match term.node with
    | Literal literal -> flow_construct ~loc ["Flow"; "Check"; "Literal"]
        (Some (flow_literal ~loc literal))
    | Nil -> flow_construct ~loc ["Flow"; "Check"; "Nil"] None
    | Vector terms -> flow_construct ~loc ["Flow"; "Check"; "Vector"]
        (Some (list (List.map (flow_term ~loc) terms)))
    | Expression expression ->
        let parsed = apply ~loc (ident ~loc ["Flow"; "Expr"; "parse_sexp"])
          [Nolabel, estring ~loc (Flow.Expr.sexp expression)] in
        let expression = apply ~loc (ident ~loc ["Result"; "get_ok"])
          [Nolabel, parsed] in
        flow_construct ~loc ["Flow"; "Check"; "Expression"]
          (Some expression)
    | Reference (name, path) ->
        flow_construct ~loc ["Flow"; "Check"; "Reference"]
          (Some (flow_pair ~loc (estring ~loc name) (estring ~loc path)))
    | Call call ->
        let call = flow_record ~loc ["Flow"; "Check"; "call"] [
          "kind", estring ~loc call.kind;
          "arguments", list (List.map (fun (name, term) ->
            flow_pair ~loc (estring ~loc name) (flow_term ~loc term))
            call.arguments);
          "bypass", ebool ~loc call.bypass] in
        flow_construct ~loc ["Flow"; "Check"; "Call"] (Some call) in
  flow_record ~loc ["Flow"; "Check"; "term"] [
    "node", node;
    "ty", flow_option ~loc (flow_type ~loc) term.ty]

let flow_ports ~loc ports = elist ~loc (List.map (fun (name, ty) ->
  flow_pair ~loc (estring ~loc name) (flow_type ~loc ty)) ports)
let flow_graph ~loc (graph : Flow.Check.graph) =
  flow_record ~loc ["Flow"; "Check"; "graph"] [
    "name", estring ~loc graph.name;
    "context", flow_context ~loc graph.context;
    "bindings", elist ~loc (List.map (fun (binding : Flow.Check.binding) ->
      flow_record ~loc ["Flow"; "Check"; "binding"] [
        "name", estring ~loc binding.name;
        "term", flow_term ~loc binding.term;
        "outputs", flow_ports ~loc binding.outputs]) graph.bindings);
    "results", elist ~loc (List.map (flow_term ~loc) graph.results)]
let flow_program ~loc (program : Flow.Check.program) =
  flow_record ~loc ["Flow"; "Check"; "program"] [
    "graph", flow_graph ~loc program.graph;
    "definitions", elist ~loc (List.map (fun (definition : Flow.Check.definition) ->
      flow_record ~loc ["Flow"; "Check"; "definition"] [
        "graph", flow_graph ~loc definition.graph;
        "inputs", elist ~loc (List.map (fun (name, ty, default) ->
          pexp_tuple ~loc [estring ~loc name; flow_type ~loc ty;
            flow_option ~loc (flow_term ~loc) default]) definition.inputs);
        "outputs", flow_ports ~loc definition.outputs]) program.definitions)]

let expand_flow ~loc payload =
  let source, start = match payload.pexp_desc with
    | Pexp_constant (Pconst_string (source, _, Some delimiter)) ->
        let start = payload.pexp_loc.loc_start in
        source, {start with pos_cnum = start.pos_cnum + 2 + String.length delimiter}
    | _ -> Location.raise_errorf ~loc:payload.pexp_loc
        "flow expects a quoted string such as {| (graph demo ...) |}" in
  let manifest_path = match !flow_manifest_path with
    | Some path -> path
    | None -> Location.raise_errorf ~loc
        "flow needs -flow-manifest <path> in the dune pps flags" in
  let manifest = try In_channel.with_open_text manifest_path In_channel.input_all
    with Sys_error message -> Location.raise_errorf ~loc
      "cannot read Flow manifest %s: %s" manifest_path message in
  let catalog, digest = match Flow.Check.catalog_of_manifest manifest with
    | Ok result -> result
    | Error diagnostic -> Location.raise_errorf ~loc
        "invalid Flow manifest %s: %s" manifest_path
        (Flow.Diagnostic.to_string diagnostic) in
  let program, diagnostics = Flow.Check.check catalog source in
  List.iter (fun (diagnostic : Flow.Diagnostic.t) ->
    if diagnostic.severity = Warning then
      Ocaml_common.Location.prerr_warning
        (flow_location ~start source diagnostic)
        (Ocaml_common.Warnings.Preprocessor
          (diagnostic.code ^ ": " ^ diagnostic.message)))
    diagnostics;
  let errors = List.filter (fun (diagnostic : Flow.Diagnostic.t) ->
    diagnostic.severity = Error) diagnostics in
  (match errors with
   | first :: rest ->
       let primary = flow_location ~start source first in
       let sub = List.map (fun diagnostic ->
         flow_location ~start source diagnostic,
         diagnostic.code ^ ": " ^ diagnostic.message) rest in
       let error = Location.Error.make ~loc:primary
         (first.code ^ ": " ^ first.message) ~sub in
       pexp_extension ~loc (Location.Error.to_extension error)
   | [] ->
       let program = Option.get program in
       apply ~loc (ident ~loc ["Flow_sop"; "Build"; "program"])
         [Labelled "factories", ident ~loc ["Sop_catalog"; "Editor"; "factories"];
          Labelled "manifest_digest", estring ~loc digest;
          Nolabel, flow_program ~loc program])

let flow_extension = Extension.declare "flow" Extension.Context.expression
    Ast_pattern.(single_expr_payload __)
    (fun ~loc ~path:_ payload -> expand_flow ~loc payload)

let () =
  Driver.add_arg "-flow-manifest"
    (Arg.String (fun path -> flow_manifest_path := Some path))
    ~doc:"Path to the generated Flow SOP catalog manifest";
  let structure = Deriving.Generator.V2.make_noarg ~attributes generate_impl
  and signature = Deriving.Generator.V2.make_noarg ~attributes generate_intf in
  Deriving.add "sop_params" ~str_type_decl:structure ~sig_type_decl:signature
  |> Deriving.ignore;
  let node_structure = Deriving.Generator.V2.make_noarg
      ~attributes:node_attributes generate_node_impl in
  Deriving.add "sop_node" ~str_type_decl:node_structure |> Deriving.ignore;
  Driver.register_transformation "sop_manifest" ~impl:manifest;
  Driver.register_transformation "flow"
    ~rules:[Context_free.Rule.extension flow_extension]
