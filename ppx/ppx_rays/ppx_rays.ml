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
let unit_attribute = expression_attribute "sop.unit"
let primary_attribute =
  Attribute.declare_flag "sop.primary" Attribute.Context.label_declaration
let ignore_attribute =
  Attribute.declare_flag "sop.ignore" Attribute.Context.label_declaration

(* Typed-function attributes ([sop.fn]): the default a typed optional argument
   takes when it differs from the editor default, the [invalid_arg] message a
   blank text raises, and the message a non-finite or out-of-hard-range number
   raises (the editor clamps instead). *)
let arg_default_attribute = expression_attribute "sop.arg_default"
let nonblank_attribute = expression_attribute "sop.nonblank"
let validate_attribute = expression_attribute "sop.validate"
(* The toggle field a typed optional argument sets: true when the argument is
   given ([sop.present "use_x"]) or when it is left out ([sop.absent
   "context_seed"]). *)
let present_attribute = expression_attribute "sop.present"
let absent_attribute = expression_attribute "sop.absent"

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
let fn_attribute = type_expression_attribute "sop.fn"
let args_attribute = type_expression_attribute "sop.args"
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
    @ optional_labelled ~loc "unit"
        (optional_string unit_attribute declaration "sop.unit")
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

(* [<t>_fn build ?label <args> inputs...] is the typed constructor of a node:
   [[@@sop.fn "name"]] names it and [[@@sop.args "?a ~b c ()"]] lists its
   arguments in order. Each argument is a field, a [sop.vec3] group (one
   [Vec3.t]) or an input slot; [?x] takes the field's editor default unless
   [[@sop.arg_default e]] overrides it, a blank [[@sop.nonblank "m"]] text or
   a non-finite/out-of-hard-range [[@sop.validate "m"]] number raises
   [Invalid_argument "Sop.name: m"]. Slots left out of the list follow as
   positional inputs; a trailing [()] adds the unit argument of a generator. *)
type argument = Arg_optional of string | Arg_labelled of string | Arg_positional of string | Arg_unit

let parse_arguments expression =
  string_constant expression "sop.args"
  |> String.split_on_char ' ' |> List.concat_map (String.split_on_char ',')
  |> List.filter_map (fun token ->
    let token = String.trim token in
    if token = "" then None
    else if token = "()" then Some Arg_unit
    else if token.[0] = '?' then Some (Arg_optional (String.sub token 1 (String.length token - 1)))
    else if token.[0] = '~' then Some (Arg_labelled (String.sub token 1 (String.length token - 1)))
    else Some (Arg_positional token))

let typed_function declaration ~key ~inputs ~optional ~slots ~name ~arguments =
  let loc = declaration.ptype_loc in
  let fields = match declaration.ptype_kind with
    | Ptype_record fields -> fields | _ -> [] in
  let components = vec3_components fields in
  let field name = List.find_opt (fun f -> f.pld_name.txt = name) fields in
  let group_fields group = List.filter_map (fun (name, (group_name, _)) ->
      if group_name = group then field name else None) components in
  let var name = evar ~loc name and pvar name = ppat_var ~loc { loc; txt = name } in
  let default field = pexp_field ~loc (var (declaration.ptype_name.txt ^ "_default"))
      (located_lident ~loc field) in
  let fail message = apply ~loc (ident ~loc ["Stdlib"; "invalid_arg"])
      [Nolabel, estring ~loc ("Sop." ^ name ^ ": " ^ message)] in
  let message attribute field what =
    Option.map (fun e -> string_constant e what) (Attribute.get attribute field) in
  let blank value = apply ~loc (ident ~loc ["Stdlib"; "String"; "trim"]) [Nolabel, value] in
  let is_blank value = pexp_apply ~loc (ident ~loc ["Stdlib"; "="])
      [Nolabel, blank value; Nolabel, estring ~loc ""] in
  let numeric_check field value =
    (* [not (Float.is_finite v) || v < hard_min || v > hard_max] *)
    let compare op bound = pexp_apply ~loc (ident ~loc ["Stdlib"; op]) [Nolabel, value; Nolabel, bound] in
    let bounds = List.filter_map Fun.id [
        Option.map (compare "<") (Attribute.get hard_min_attribute field);
        Option.map (compare ">") (Attribute.get hard_max_attribute field) ] in
    let finite = if type_name field.pld_type = Some "float" then
        [pexp_apply ~loc (ident ~loc ["Stdlib"; "not"]) [Nolabel,
           apply ~loc (ident ~loc ["Stdlib"; "Float"; "is_finite"]) [Nolabel, value]]]
      else [] in
    match finite @ bounds with
    | [] -> Location.raise_errorf ~loc:field.pld_loc
        "sop.validate on %s needs a float field or a hard range" field.pld_name.txt
    | first :: rest -> List.fold_left (fun left right ->
        pexp_apply ~loc (ident ~loc ["Stdlib"; "||"]) [Nolabel, left; Nolabel, right]) first rest in
  (* one typed argument: its pattern, the record fields it sets (name, value)
     and the checks it runs *)
  let checks = ref [] and sets = ref [] and params = ref [] and node_inputs = ref [] in
  (* A check on a [?x] argument runs on the value given, before the default
     resolves: [Option.iter (fun value -> if ... ) x]. [access] reads the
     checked number or text out of the argument (a vec3 component). *)
  let add_check ~name ~optional_value ~access condition message =
    let statement = if optional_value then
        apply ~loc (ident ~loc ["Stdlib"; "Option"; "iter"])
          [ Nolabel, pexp_fun ~loc Nolabel None (pvar "value")
              (pexp_ifthenelse ~loc (condition (access (var "value"))) (fail message) None);
            Nolabel, var name ]
      else pexp_ifthenelse ~loc (condition (access (var name))) (fail message) None in
    checks := (optional_value, statement) :: !checks in
  let settle ~name ~optional_value ~access field_name =
    match field field_name with
    | None -> Location.raise_errorf ~loc "sop.args names no field or slot %S" field_name
    | Some f ->
        sets := (field_name, access (var name)) :: !sets;
        Option.iter (add_check ~name ~optional_value ~access is_blank)
          (message nonblank_attribute f "sop.nonblank");
        Option.iter (add_check ~name ~optional_value ~access (numeric_check f))
          (message validate_attribute f "sop.validate") in
  let bind name value body = pexp_let ~loc Nonrecursive
      [Ast_builder.Default.value_binding ~loc ~pat:(pvar name) ~expr:value] body in
  let bindings = ref [] in
  let resolve name ~optional_value ~default_value =
    (* a [?x] argument becomes [let x = Option.value ~default x] *)
    if optional_value then bindings := (name, apply ~loc (ident ~loc ["Stdlib"; "Option"; "value"])
        [Labelled "default", default_value; Nolabel, var name]) :: !bindings in
  let vec3 group = match group_fields group with
    | [x; y; z] -> Some (x, y, z) | _ -> None in
  let component value axis = pexp_field ~loc value (located_path ~loc ["Rays_math"; "Vec3"; axis]) in
  let argument_default f = Option.value ~default:(default f.pld_name.txt)
      (Attribute.get arg_default_attribute f) in
  let slot_index name = let rec go index = function
      | [] -> None | slot :: rest -> if slot = name then Some index else go (index + 1) rest in
    go 0 slots in
  List.iter (fun argument ->
    let name, optional_value = match argument with
      | Arg_unit -> "()", false
      | Arg_optional name -> name, true
      | Arg_labelled name | Arg_positional name -> name, false in
    let label = match argument with
      | Arg_optional name -> Optional name
      | Arg_labelled name -> Labelled name
      | Arg_positional _ | Arg_unit -> Nolabel in
    match argument with
    | Arg_unit -> params := (Nolabel, punit ~loc) :: !params
    | _ ->
        params := (label, pvar name) :: !params;
        match slot_index name, vec3 name, field name with
        | Some index, _, _ -> node_inputs := (index, name) :: !node_inputs
        | None, Some (x, y, z), _ ->
            resolve name ~optional_value ~default_value:(apply ~loc
              (ident ~loc ["Rays_math"; "Vec3"; "create"])
              (List.map (fun f -> Nolabel, argument_default f) [x; y; z]));
            List.iter2 (fun f axis -> settle ~name ~optional_value
                ~access:(fun value -> component value axis) f.pld_name.txt)
              [x; y; z] ["x"; "y"; "z"]
        | None, None, Some f ->
            (* a toggle reads the argument's presence before its default resolves *)
            List.iter (fun (attribute, test) ->
              Option.iter (fun toggle ->
                if not optional_value then Location.raise_errorf ~loc:f.pld_loc
                    "sop.present/absent needs an optional argument for %s" name;
                let given = name ^ "_given" in
                bindings := (given, apply ~loc (ident ~loc ["Stdlib"; "Option"; test])
                    [Nolabel, var name]) :: !bindings;
                sets := (string_constant toggle "sop.present", var given) :: !sets)
                (Attribute.get attribute f))
              [present_attribute, "is_some"; absent_attribute, "is_none"];
            resolve name ~optional_value ~default_value:(argument_default f);
            settle ~name ~optional_value ~access:Fun.id name
        | None, None, None ->
            Location.raise_errorf ~loc "sop.args names no field, vec3 group or slot %S" name)
    arguments;
  (* slots not named in the list follow as positional inputs *)
  List.iteri (fun index slot -> if not (List.mem_assoc index !node_inputs) then begin
      params := (Nolabel, pvar slot) :: !params; node_inputs := (index, slot) :: !node_inputs end) slots;
  let inputs_list = elist ~loc (List.init inputs (fun index ->
    let slot = List.assoc index !node_inputs in
    if optional = [] || List.mem index optional then var slot
    else pexp_construct ~loc (located_lident ~loc "Some") (Some (var slot)))) in
  let record =
    let sets = List.rev !sets in
    let every = List.for_all (fun f -> List.mem_assoc f.pld_name.txt sets) fields in
    pexp_record ~loc (List.map (fun (f, v) -> located_lident ~loc f, v) sets)
      (if every then None else Some (var (declaration.ptype_name.txt ^ "_default"))) in
  let label = pexp_match ~loc (var "label")
      [ case ~lhs:(ppat_construct ~loc (located_lident ~loc "Some") (Some (pvar "value")))
          ~guard:None ~rhs:(var "value");
        case ~lhs:(ppat_construct ~loc (located_lident ~loc "None") None)
          ~guard:None ~rhs:(estring ~loc key) ] in
  let body = apply ~loc (var "build")
      [Labelled "label", label; Labelled "inputs", inputs_list; Nolabel, record] in
  let sequence body (_, statement) = pexp_sequence ~loc statement body in
  let body = List.fold_left sequence body (List.filter (fun (optional_value, _) -> not optional_value) !checks) in
  let body = List.fold_left (fun body (name, value) -> bind name value body) body !bindings in
  let body = List.fold_left sequence body (List.filter fst !checks) in
  let body = List.fold_left (fun body (label, pattern) -> pexp_fun ~loc label None pattern body)
      body !params in
  pexp_fun ~loc Nolabel None (pvar "build")
    (pexp_fun ~loc (Optional "label") None (pvar "label") body)

let generate_node_type declaration =
  ensure_monomorphic declaration;
  let loc = declaration.ptype_loc in
  let key, operation, label, category, inputs, optional, slots =
    node_metadata declaration in
  let typed = match Attribute.get fn_attribute declaration with
    | None -> []
    | Some expression ->
        let name = string_constant expression "sop.fn" in
        let arguments = match Attribute.get args_attribute declaration with
          | Some arguments -> parse_arguments arguments
          | None -> Location.raise_errorf ~loc "sop.fn requires [@@sop.args ...]" in
        [value_binding ~loc (declaration.ptype_name.txt ^ "_fn")
           (typed_function declaration ~key ~inputs ~optional ~slots ~name ~arguments)] in
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
  @ typed

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
          [value_binding ~loc "factories" (elist ~loc factories);
           pstr_value ~loc Nonrecursive [Ast_builder.Default.value_binding ~loc
             ~pat:(ppat_any ~loc) ~expr:(evar ~loc "factories")]] in
      structure @ [pstr_module ~loc (module_binding ~loc
        ~name:{ loc; txt = Some "Editor" } ~expr:editor)]

let attributes = List.map (fun attribute -> Attribute.T attribute)
    [ default_attribute; label_attribute; name_attribute; description_attribute;
      folder_attribute; impact_attribute; soft_min_attribute; soft_max_attribute;
      hard_min_attribute; hard_max_attribute; kind_attribute; vec3_attribute; unit_attribute;
      arg_default_attribute; nonblank_attribute; validate_attribute; present_attribute;
      absent_attribute ]
  @ [Attribute.T ignore_attribute; Attribute.T primary_attribute]

let node_attributes = List.map (fun attribute -> Attribute.T attribute)
    [node_key_attribute; node_operation_attribute; node_label_attribute;
     node_inputs_attribute; node_optional_attribute; node_slots_attribute;
     fn_attribute; args_attribute]
  @ List.map (fun attribute -> Attribute.T attribute)
    [arg_default_attribute; nonblank_attribute; validate_attribute; present_attribute;
     absent_attribute; hard_min_attribute;
     hard_max_attribute; vec3_attribute]

let () =
  let structure = Deriving.Generator.V2.make_noarg ~attributes generate_impl
  and signature = Deriving.Generator.V2.make_noarg ~attributes generate_intf in
  Deriving.add "sop_params" ~str_type_decl:structure ~sig_type_decl:signature
  |> Deriving.ignore;
  let node_structure = Deriving.Generator.V2.make_noarg
      ~attributes:node_attributes generate_node_impl in
  Deriving.add "sop_node" ~str_type_decl:node_structure |> Deriving.ignore;
  Driver.register_transformation "sop_manifest" ~impl:manifest
