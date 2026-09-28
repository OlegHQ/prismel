type parameter = {
  name : string; label : string; ty : Port_type.t option;
  fields : (string * Param.kind_view * Param.value) list;
}
type slot = { name : string; required : bool }
type kind = {
  qualified : string; aliases : string list; context : Context.t;
  slots : slot list; parameters : parameter list;
  outputs : (string * Port_type.t) list;
}
type catalog = { version : int; kinds : kind list }
type term = { node : term_node; ty : Port_type.t option }
and term_node =
  | Literal of Param.value | Nil | Vector of term list | Expression of Expr.t
  | Reference of string * string | Call of call
and call = { kind : string; arguments : (string * term) list; bypass : bool }
type binding = { name : string; term : term; outputs : (string * Port_type.t) list }
type graph = {
  name : string; context : Context.t; bindings : binding list; results : term list;
}
type definition = {
  graph : graph; inputs : (string * Port_type.t * term option) list;
  outputs : (string * Port_type.t) list;
}
type program = { graph : graph; definitions : definition list }

module Names = Map.Make (String)
type checked = { term : term; outputs : (string * Port_type.t) list }
type env = (string * Port_type.t) list option Names.t
type state = { catalog : catalog; mutable definitions : definition list;
  mutable diagnostics : Diagnostic.t list }

let emit state form severity code message =
  let make = match severity with Diagnostic.Error -> Diagnostic.error
    | Warning -> Diagnostic.warning in
  state.diagnostics <- make ~span:form.Sexp.span ~position:form.position
    ~code message :: state.diagnostics
let error state form code message = emit state form Diagnostic.Error code message
let warning state form code message = emit state form Diagnostic.Warning code message
let symbol form = match form.Sexp.node with
  | Sexp.Atom (Sexp.Symbol name) -> Some name | _ -> None
let keyword form = match form.Sexp.node with
  | Sexp.Atom (Sexp.Keyword name) -> Some name | _ -> None
let list form = match form.Sexp.node with Sexp.List items -> Some items | _ -> None
let vector form = match form.Sexp.node with Sexp.Vector items -> Some items | _ -> None
let name form = match symbol form with
  | Some name when Symbol.valid_name name -> Some name | _ -> None
let short qualified = match String.split_on_char '/' qualified with
  | [_; name] -> name | _ -> qualified
let math_names = ["+", Expr.Add; "-", Expr.Sub; "*", Expr.Mul; "/", Expr.Div]
  @ List.filter (fun (name, _) ->
      not (List.mem name ["add"; "sub"; "mul"; "div"])) Expr.operators
let reserved = ["t"; "pi"; "nil"; "true"; "false"; "let*"; "values";
  "graph"; "defgraph"] @ List.map fst math_names

let distance a b =
  let rows = Array.init (String.length b + 1) Fun.id in
  for i = 1 to String.length a do
    let previous = ref rows.(0) in
    rows.(0) <- i;
    for j = 1 to String.length b do
      let old = rows.(j) in
      rows.(j) <- min (min (rows.(j) + 1) (rows.(j - 1) + 1))
        (!previous + if a.[i - 1] = b.[j - 1] then 0 else 1);
      previous := old
    done
  done;
  rows.(String.length b)
let suggestion word candidates =
  List.sort_uniq String.compare candidates
  |> List.filter_map (fun candidate ->
      let score = distance word candidate in
      if score <= 2 then Some (score, candidate) else None)
  |> List.sort compare |> function [] -> ""
    | (_, candidate) :: _ -> " Did you mean " ^ candidate ^ "?"

let parameters_of_fields fields =
  let rec gather reversed = function
    | [] -> List.rev reversed
    | (field : Param.field_view) :: rest ->
        (match field.vec3, rest with
         | Some (group, 0), (y : Param.field_view) :: (z : Param.field_view) :: tail
             when y.vec3 = Some (group, 1) && z.vec3 = Some (group, 2) ->
             gather ({name = group; label = group; ty = Some Port_type.Vec3;
               fields = List.map (fun (field : Param.field_view) ->
                 field.name, field.kind, field.default)
                 [field;y;z]} :: reversed) tail
         | _ -> gather ({name = field.name; label = field.label;
             ty = Port_type.of_field_kind field.kind;
             fields = [field.name, field.kind, field.default]} :: reversed) rest) in
  gather [] fields
let builtin_kinds = List.map (fun kind ->
  { qualified = "value/" ^ Value_kind.key kind; aliases = [];
    context = Context.Value; slots = [];
    parameters = parameters_of_fields (Value_kind.fields (Value_kind.make kind));
    outputs = Value_kind.outputs kind }) Value_kind.all
let kinds state = state.catalog.kinds @ builtin_kinds @
  List.map (fun (definition : definition) ->
    let graph = definition.graph in
    { qualified = "user/" ^ graph.name; aliases = [];
      context = graph.context;
      slots = List.filter_map (fun (name, ty, default) ->
        if ty = Port_type.Geometry then Some {name; required = default = None}
        else None) definition.inputs;
      parameters = List.filter_map (fun (name, ty, _) ->
        if ty = Port_type.Geometry then None else Some
          {name; label = name; ty = Some ty; fields = []}) definition.inputs;
      outputs = definition.outputs }) state.definitions
let known_prefix state name = List.mem name ["sop"; "value"; "user"] ||
  List.exists (fun kind -> String.starts_with ~prefix:(name ^ "/") kind.qualified)
    (kinds state)
let allowed context (kind : kind) =
  kind.context = Context.Value || kind.context = context
let resolve state context form head =
  let all = kinds state in
  let matches name = List.filter (fun kind ->
    kind.qualified = name || List.mem name kind.aliases) all in
  let candidates = if String.contains head '/' then matches head else
    List.filter (fun kind -> short kind.qualified = head ||
      List.exists (fun alias -> short alias = head) kind.aliases) all in
  let candidates = List.sort_uniq (fun a b ->
    String.compare a.qualified b.qualified) candidates in
  match candidates with
  | [kind] when allowed context kind -> Some kind
  | [kind] ->
      error state form "E_WRONG_CONTEXT"
        (Printf.sprintf "%s is a %s node and cannot appear in a %s graph"
          kind.qualified (Context.name kind.context) (Context.name context)); None
  | _ :: _ :: _ ->
      error state form "E_AMBIGUOUS"
        (Printf.sprintf "%s is ambiguous: %s. Write the namespace to choose"
          head (String.concat " or " (List.map (fun kind -> kind.qualified) candidates)));
      None
  | [] ->
      (match String.split_on_char '/' head with
       | prefix :: _ :: _ when not (known_prefix state prefix) ->
           error state form "E_NAMESPACE"
             (Printf.sprintf "Unknown namespace %s. This file knows sop, value and user" prefix)
       | _ ->
           let names = List.map (fun kind -> short kind.qualified) all in
           error state form "E_UNKNOWN_KIND"
             ("Unknown node " ^ head ^ "." ^ suggestion head names));
      None

let term ?ty node = {node; ty}
let numeric_value = function
  | Param.Int_value n -> Some (float_of_int n)
  | Float_value n -> Some n
  | Bool_value n -> Some (if n then 1. else 0.)
  | Text_value _ | Choice_value _ -> None
let number_term text =
  let number = float_of_string text in
  if not (Float.is_finite number) then None else
  match if String.contains text '.' then None else int_of_string_opt text with
  | Some number -> Some (term ~ty:Port_type.Int
      (Literal (Param.Int_value number)))
  | None -> Some (term ~ty:Port_type.Float (Literal (Param.Float_value number)))
let expr_of_term term = match term.node with
  | Literal value -> Option.bind (numeric_value value) (fun value ->
      Result.to_option (Expr.num value))
  | Expression expr -> Some expr
  | _ -> None
let output term = match term.ty with Some ty -> ["out", ty] | None -> []
let checked term = {term; outputs = output term}
let new_error state before =
  let rec loop diagnostics =
    if diagnostics == before then false else match diagnostics with
    | [] -> false
    | diagnostic :: rest ->
        diagnostic.Diagnostic.severity = Diagnostic.Error || loop rest in
  loop state.diagnostics

let validate_range state form (parameter : parameter) field value =
  match field, numeric_value value with
  | (_, Param.Integer_view range, _), Some number ->
      if Float.floor number <> number then ()
      else if Option.fold ~none:false ~some:(fun n -> number < float_of_int n) range.hard_min
           || Option.fold ~none:false ~some:(fun n -> number > float_of_int n) range.hard_max then
        error state form "E_HARD_RANGE"
          (Printf.sprintf ":%s is outside its hard range" parameter.name)
      else if number < float_of_int range.soft_min || number > float_of_int range.soft_max then
        warning state form "W_SOFT_RANGE"
          (Printf.sprintf ":%s %g is outside the slider range %d–%d. Allowed, but check it"
            parameter.name number range.soft_min range.soft_max)
  | (_, Param.Floating_view range, _), Some number ->
      if Option.fold ~none:false ~some:(fun n -> number < n) range.hard_min
           || Option.fold ~none:false ~some:(fun n -> number > n) range.hard_max then
        error state form "E_HARD_RANGE"
          (Printf.sprintf ":%s is outside its hard range" parameter.name)
      else if number < range.soft_min || number > range.soft_max then
        warning state form "W_SOFT_RANGE"
          (Printf.sprintf ":%s %g is outside the slider range %g–%g. Allowed, but check it"
            parameter.name number range.soft_min range.soft_max)
  | _ -> ()

let validate_parameter state form (parameter : parameter) (value : checked) =
  let ty = value.term.ty in
  let good = match parameter.ty, value.term.node with
    | None, Literal (Param.Text_value _ | Param.Choice_value _) -> true
    | None, _ -> false
    | Some Port_type.Vec3, Vector components ->
        List.for_all (fun component -> match component.ty with
          | Some source -> Port_type.can_connect ~source ~target:Port_type.Float
          | None -> false) components
    | Some Port_type.Vec3, Literal _ -> false
    | Some target, _ -> (match ty with
        | Some source -> Port_type.can_connect ~source ~target
        | None -> false) in
  if not good then error state form "E_TYPE"
    (Printf.sprintf ":%s takes %s, but this is %s" parameter.name
      (Option.fold ~none:"text" ~some:Port_type.name parameter.ty)
      (Option.fold ~none:"nil or text" ~some:Port_type.name ty));
  (match parameter.ty, value.term.node with
   | Some Port_type.Int, Literal (Param.Float_value number)
       when Float.floor number <> number ->
       error state form "E_INT_LITERAL"
         (Printf.sprintf ":%s is an integer, not %g" parameter.name number)
   | Some Port_type.Int, Literal (Param.Float_value number)
       when number >= float_of_int max_int || number < float_of_int min_int ->
       error state form "E_HARD_RANGE"
         (Printf.sprintf ":%s is outside the integer range" parameter.name)
   | _ -> ());
  (match parameter.fields, value.term.node with
   | [(_, Param.Choice_view options, _)],
       Literal (Param.Text_value label | Param.Choice_value label)
       when not (Array.exists (( = ) label) options) ->
       error state form "E_TYPE"
         (Printf.sprintf ":%s must be one of %s" parameter.name
           (String.concat ", " (Array.to_list options)))
   | _ -> ());
  if good then (match value.term.node, parameter.fields with
    | Literal literal, field :: _ -> validate_range state form parameter field literal
    | Vector components, fields ->
        List.iter2 (fun component field -> match component.node with
          | Literal literal -> validate_range state form parameter field literal
          | _ -> ()) components
          (if List.length fields = 3 then fields else List.init 3 (fun _ ->
            "", Param.Text_view, Param.Text_value ""))
    | _ -> ())

let normalize_parameter (parameter : parameter) term =
  let numeric target value = match numeric_value value with
    | None -> Literal value
    | Some number -> (match target with
        | Port_type.Float -> Literal (Param.Float_value number)
        | Port_type.Int when Float.floor number = number
            && number < float_of_int max_int
            && number >= float_of_int min_int ->
            Literal (Param.Int_value (int_of_float number))
        | Port_type.Bool -> Literal (Param.Bool_value (number <> 0.))
        | _ -> Literal value) in
  match parameter.ty, term.node with
  | Some target, Literal value -> {term with node = numeric target value}
  | Some Port_type.Vec3, Vector components ->
      {term with node = Vector (List.map (fun component ->
        match component.node with
        | Literal value -> {component with node = numeric Port_type.Float value}
        | _ -> component) components)}
  | None, Literal (Param.Text_value label) ->
      (match parameter.fields with
       | [(_, Param.Choice_view _, _)] ->
           {term with node = Literal (Param.Choice_value label)}
       | _ -> term)
  | _ -> term

let rec expression state context (env : env) form =
  match form.Sexp.node with
  | Sexp.Atom (Sexp.Number text) ->
      (match number_term text with Some term -> Some (checked term)
       | None -> error state form "E_TYPE" "This number is not finite"; None)
  | Sexp.Atom (Sexp.String text) ->
      Some (checked (term (Literal (Param.Text_value text))))
  | Sexp.Atom (Sexp.Keyword _) ->
      error state form "E_TYPE" "A keyword names an argument inside a node call"; None
  | Sexp.Atom (Sexp.Symbol "nil") -> Some (checked (term Nil))
  | Sexp.Atom (Sexp.Symbol "true") ->
      Some (checked (term ~ty:Port_type.Bool (Literal (Param.Bool_value true))))
  | Sexp.Atom (Sexp.Symbol "false") ->
      Some (checked (term ~ty:Port_type.Bool (Literal (Param.Bool_value false))))
  | Sexp.Atom (Sexp.Symbol "t") ->
      Some (checked (term ~ty:Port_type.Float (Expression Expr.time)))
  | Sexp.Atom (Sexp.Symbol "pi") ->
      Some (checked (term ~ty:Port_type.Float
        (Expression (Result.get_ok (Expr.num Float.pi)))))
  | Sexp.Atom (Sexp.Symbol name) -> reference state context env form name
  | Sexp.Vector components ->
      if List.length components <> 3 then (
        error state form "E_VECTOR_ARITY"
          (Printf.sprintf "A vector has 3 components [x y z]; this one has %d"
            (List.length components)); None)
      else let values = List.map (expression state context env) components in
        if List.exists Option.is_none values then None else
        let values = List.map Option.get values in
        if List.exists (fun value -> match value.term.ty with
          | Some (Port_type.Float | Int | Bool) -> false | _ -> true) values then (
          error state form "E_TYPE" "Vector components must be numbers"; None)
        else Some (checked (term ~ty:Port_type.Vec3
          (Vector (List.map (fun value -> value.term) values))))
  | Sexp.Meta (meta, inner) ->
      if meta <> "bypass" then warning state form "W_UNKNOWN_META"
        (Printf.sprintf "Unknown metadata ^:%s; only ^:bypass is defined" meta);
      (match expression state context env inner with
       | Some ({term = {node = Call call; ty}; _} as value) ->
           Some {value with term = {node = Call {call with bypass = meta = "bypass"}; ty}}
       | Some _ when meta = "bypass" ->
           error state form "E_TYPE" "^:bypass belongs before a node call"; None
       | result -> result)
  | Sexp.List items -> call state context env form items

and reference state _context env form word =
  let binding, requested = match String.split_on_char '.' word with
    | [binding; port] -> binding, Some port | _ -> word, None in
  match Names.find_opt binding env with
  | Some None -> None
  | Some (Some outputs) ->
      let choice = match requested, outputs with
        | None, [port] -> Some port
        | Some requested, _ -> List.find_opt (fun (port, _) -> port = requested) outputs
        | None, _ -> None in
      (match choice with
       | Some (port, ty) -> Some (checked
           (term ~ty (Reference (binding, port))))
       | None ->
           error state form "E_OUTPUT_UNKNOWN"
             (Printf.sprintf "%s has no output %s. Outputs: %s" binding
               (Option.value ~default:"(choose one)" requested)
               (String.concat ", " (List.map fst outputs))); None)
  | None ->
      let kind_names = List.concat_map (fun kind ->
        [short kind.qualified; kind.qualified] @ kind.aliases) (kinds state) in
      if List.mem word kind_names then error state form "E_KIND_AS_VALUE"
        (word ^ " is a node kind; call it as (" ^ word ^ " …) or bind it in let*")
      else error state form "E_UNBOUND"
        (word ^ " is not bound." ^ suggestion word (List.map fst (Names.bindings env)));
      None

and call state context env form items = match items with
  | [] -> error state form "E_UNKNOWN_KIND" "A call needs a node name first"; None
  | head :: args ->
      (match symbol head with
       | None -> error state head "E_UNKNOWN_KIND" "A call needs a node name first"; None
       | Some ("let*" | "values") ->
           error state head "E_VALUES_PLACE" "let* and values belong in a graph body"; None
       | Some head_name ->
           let math_name = if String.starts_with ~prefix:"value/" head_name then
             String.sub head_name 6 (String.length head_name - 6)
             else head_name in
           match List.assoc_opt math_name math_names with
           | Some op -> math state context env head op args
           | None -> match resolve state context head head_name with
             | None -> None
             | Some kind -> kind_call state context env form kind args)

and math state context env head op args =
  let values = List.map (expression state context env) args in
  if List.exists Option.is_none values then None else
  let values = List.map Option.get values in
  let values = if op = Expr.Sub && List.length values = 1 then
      checked (term ~ty:Port_type.Int (Literal (Param.Int_value 0))) :: values
    else values in
  let arity = Expr.arity op in
  if List.length values <> arity then (
    error state head "E_ARITY"
      (Printf.sprintf "%s takes %d argument%s, got %d"
        (Option.get (symbol head)) arity (if arity = 1 then "" else "s")
        (List.length values)); None)
  else if List.exists (fun value -> match value.term.ty with
    | Some (Port_type.Float | Int | Bool) -> false | _ -> true) values then (
    error state head "E_TYPE" "Math operators need scalar numbers"; None)
  else match List.map (fun value -> expr_of_term value.term) values with
    | expressions when List.for_all Option.is_some expressions ->
        (match Expr.op op (List.map Option.get expressions) with
         | Ok expr -> Some (checked (term ~ty:Port_type.Float (Expression expr)))
         | Error diagnostic -> error state head diagnostic.code diagnostic.message; None)
    | _ ->
        let arguments = List.mapi (fun index value ->
          (if index = 0 then "a" else "b"), value.term) values in
        let op_name = List.find (fun (_, candidate) -> candidate = op)
          Expr.operators |> fst in
        Some (checked (term ~ty:Port_type.Float
          (Call {kind = "value/math";
            arguments = ("op", term (Literal (Param.Choice_value op_name))) :: arguments;
            bypass = false})))

and kind_call state context env _form (kind : kind) args =
  let before = state.diagnostics in
  let slots = Array.of_list kind.slots in
  let seen = Hashtbl.create 8 and positional = ref 0 and keyword_seen = ref false in
  let failed = ref false in
  let arguments = ref [] in
  let rec loop = function
    | [] -> ()
    | item :: rest -> match keyword item with
      | Some name ->
          keyword_seen := true;
          (match rest with
           | [] -> error state item "E_MISSING_VALUE" (":" ^ name ^ " has no value")
           | value_form :: tail ->
               let descriptor =
                 if List.exists (fun (slot : slot) -> slot.name = name) kind.slots then
                   Some (`Slot name)
                 else Option.map (fun p -> `Parameter p)
                   (List.find_opt (fun (p : parameter) -> p.name = name) kind.parameters) in
               (match descriptor with
                | None ->
                    let names = List.map (fun (slot : slot) -> slot.name) kind.slots @
                      List.map (fun (p : parameter) -> p.name) kind.parameters in
                    error state item "E_UNKNOWN_PARAM"
                      (short kind.qualified ^ " has no parameter :" ^ name ^ "." ^
                       suggestion name names)
                | Some descriptor ->
                    if Hashtbl.mem seen name then
                      error state item "E_DUPLICATE_PARAM" (":" ^ name ^ " is given twice")
                    else (Hashtbl.add seen name ();
                      let checked = expression state context env value_form in
                      if checked = None then failed := true;
                      Option.iter (fun value ->
                        (match descriptor with
                         | `Slot _ -> if value.term.ty <> Some Port_type.Geometry
                               && value.term.node <> Nil then
                               error state value_form "E_TYPE"
                                 (":" ^ name ^ " takes geometry")
                         | `Parameter parameter ->
                             validate_parameter state value_form parameter value);
                        let term = match descriptor with
                          | `Parameter parameter ->
                              normalize_parameter parameter value.term
                          | `Slot _ -> value.term in
                        arguments := (name, term) :: !arguments)
                        checked));
               loop tail)
      | None ->
          if !keyword_seen then
            error state item "E_POSITIONAL_AFTER_KEYWORD"
              "Geometry inputs come before keyword arguments";
          if !positional >= Array.length slots then
            error state item "E_EXTRA_POSITIONAL"
              (Printf.sprintf "%s takes %d geometry inputs; this one is extra"
                (short kind.qualified) (Array.length slots))
          else (
            let slot = slots.(!positional).name in
            Hashtbl.replace seen slot ();
            let checked = expression state context env item in
            if checked = None then failed := true;
            Option.iter (fun value ->
              if value.term.ty <> Some Port_type.Geometry && value.term.node <> Nil then
                error state item "E_TYPE" ("Input " ^ slot ^ " takes geometry");
              arguments := (slot, value.term) :: !arguments)
              checked);
          incr positional; loop rest in
  loop args;
  let outputs = kind.outputs in
  let ty = match outputs with [(_, ty)] -> Some ty | _ -> None in
  if !failed || new_error state before then None else
  Some {term = {node = Call {kind = kind.qualified;
    arguments = List.rev !arguments; bypass = false}; ty}; outputs}

let context_of_form state form = match symbol form with
  | Some "sop" -> Some Context.Sop
  | Some "value" -> Some Context.Value
  | Some ("scene" | "world" | "shader" as name) ->
      error state form "E_CONTEXT_PLANNED"
        ("The " ^ name ^ " context is planned; use sop or value"); None
  | Some name ->
      error state form "E_CONTEXT_UNKNOWN"
        ("Unknown context " ^ name ^ ". Known contexts: sop, value"); None
  | None -> error state form "E_CONTEXT_UNKNOWN" ":context needs a name"; None

let header state ~definition form items = match items with
  | _head :: name_form :: tail ->
      (match name name_form with
       | None -> error state name_form "E_BINDING_NAME" "A graph needs a valid name"; None
       | Some name ->
           let rec options context = function
             | key :: value :: rest when keyword key = Some "context" ->
                 (match context_of_form state value with
                  | Some context -> options context rest | None -> None)
             | key :: value :: rest when not definition && keyword key = Some "catalog" ->
                 (match value.Sexp.node with
                  | Sexp.Atom (Sexp.Number number) ->
                      (match int_of_string_opt number with
                       | Some version when version <= state.catalog.version ->
                           options context rest
                       | Some version ->
                           error state value "E_CATALOG"
                             (Printf.sprintf "This file needs catalog %d; the build has %d"
                               version state.catalog.version); None
                       | None -> error state value "E_CATALOG"
                           ":catalog takes an integer version"; None)
                  | _ -> error state value "E_CATALOG"
                      ":catalog takes an integer version"; None)
             | rest -> Some (name, context, rest) in
           options Context.Sop tail)
  | _ -> error state form "E_TOPLEVEL" "A graph needs a name and body"; None

let body state context env form ~definition =
  let bindings, result_form = match list form with
    | Some ({Sexp.node = Sexp.Atom (Sexp.Symbol "let*"); _} ::
        bindings_form :: result :: []) ->
        (match vector bindings_form with
         | Some pairs -> pairs, result
         | None -> error state bindings_form "E_BINDING_NAME"
             "let* needs a [name form …] vector"; [], result)
    | _ -> [], form in
  let env = ref env and checked_bindings = ref [] in
  let rec check_pairs = function
    | [] -> ()
    | [item] -> error state item "E_BINDING_NAME"
        "let* bindings come in pairs: name then form"
    | name_form :: form :: rest ->
        (match name name_form with
         | None -> error state name_form "E_BINDING_NAME"
             "Binding names match [a-z][a-z0-9_]*"
         | Some name ->
             let code = if name = "t" then Some "E_BINDING_T"
               else if List.mem name reserved then Some "E_BINDING_NAME"
               else if Names.mem name !env then Some "E_DUPLICATE_BINDING"
               else None in
             (match code with
              | Some code -> error state name_form code
                  (if name = "t" then "t is the context time; pick another binding name"
                   else if code = "E_DUPLICATE_BINDING" then name ^ " is bound twice"
                   else name ^ " is reserved; pick another binding name")
              | None ->
                  let checked = expression state context !env form in
                  env := Names.add name (Option.map (fun value -> value.outputs) checked) !env;
                  Option.iter (fun value -> checked_bindings :=
                    {name; term = value.term; outputs = value.outputs} :: !checked_bindings)
                    checked));
        check_pairs rest in
  check_pairs bindings;
  let result_forms = if definition then match list result_form with
    | Some ({Sexp.node = Sexp.Atom (Sexp.Symbol "values"); _} :: rest) ->
        let rec entries reversed = function
          | [] -> List.rev reversed
          | key :: value :: tail when keyword key <> None ->
              let name = Option.get (keyword key) in
              if not (Symbol.valid_name name) then
                error state key "E_INTERFACE_ENTRY"
                  "An output name must match [a-z][a-z0-9_]*";
              entries ((Some name, value) :: reversed) tail
          | key :: [] when keyword key <> None ->
              error state key "E_INTERFACE_ENTRY"
                (":" ^ Option.get (keyword key) ^ " needs an output value");
              List.rev reversed
          | value :: tail -> entries ((None, value) :: reversed) tail in
        if rest = [] then error state result_form "E_RESULT_TYPE"
          "values needs at least one output";
        entries [] rest
    | _ -> [None, result_form]
  else (match list result_form with
    | Some ({Sexp.node = Sexp.Atom (Sexp.Symbol "values"); _} :: _) ->
        error state result_form "E_VALUES_PLACE"
          "values is for defgraph results; a graph returns one output"; []
    | _ -> [None, result_form]) in
  let results = List.filter_map (fun (name, form) ->
    Option.map (fun value -> name, value.term)
      (expression state context !env form))
    result_forms in
  List.rev !checked_bindings, results

let interface state form = match vector form with
  | None -> error state form "E_INTERFACE_ENTRY"
      "defgraph needs an interface vector"; [], Names.empty
  | Some entries ->
      List.fold_left (fun (inputs, env) entry ->
        match list entry with
        | Some [name_form; type_form]
        | Some [name_form; type_form; _] as items ->
            let items = Option.get items in
            (match name name_form, keyword type_form with
             | Some name, Some ty_name ->
                 if name = "t" then error state name_form "E_BINDING_T"
                   "t is the context time; pick another interface name";
                 if List.mem name reserved && name <> "t" then
                   error state name_form "E_BINDING_NAME"
                     (name ^ " is reserved; pick another interface name");
                 let ty = match ty_name with
                   | "geometry" -> Some Port_type.Geometry
                   | "float" -> Some Port_type.Float | "int" -> Some Port_type.Int
                   | "bool" -> Some Port_type.Bool | "vec3" -> Some Port_type.Vec3
                   | _ -> error state type_form "E_UNKNOWN_TYPE"
                       ("Unknown interface type :" ^ ty_name); None in
                 (match ty with
                  | None -> inputs, env
                  | Some ty ->
                      if Names.mem name env then
                        error state name_form "E_DUPLICATE_BINDING"
                          (name ^ " is an interface input twice");
                      let default = match items with
                        | [_;_;default] ->
                            Option.map (fun value ->
                              let rec literal term = match term.node with
                                | Literal _ | Nil -> true
                                | Vector components -> List.for_all literal components
                                | Expression _ | Reference _ | Call _ -> false in
                              if not (literal value.term) then
                                error state default "E_TYPE"
                                  "An interface default must be a literal";
                              if ty = Port_type.Geometry then (
                                if value.term.node <> Nil then
                                  error state default "E_TYPE"
                                    "A geometry input defaults to nil")
                              else validate_parameter state default
                                {name; label = name; ty = Some ty; fields = []} value;
                              normalize_parameter
                                {name; label = name; ty = Some ty; fields = []}
                                value.term)
                              (expression state Context.Value Names.empty default)
                        | _ -> warning state entry "W_NO_DEFAULT"
                            ("Interface input " ^ name ^ " has no default"); None in
                      (name, ty, default) :: inputs,
                      Names.add name (Some ["out", ty]) env)
             | _ -> error state entry "E_INTERFACE_ENTRY"
                 "Each interface entry is (name :type default)"; inputs, env)
        | _ -> error state entry "E_INTERFACE_ENTRY"
            "Each interface entry is (name :type default)"; inputs, env)
        ([], Names.empty) entries
      |> fun (inputs, env) -> List.rev inputs, env

let check catalog source = match Sexp.parse source with
  | Error diagnostic -> None, [diagnostic]
  | Ok forms ->
      let state = {catalog; definitions = []; diagnostics = []} in
      let main = ref None and graphs_seen = ref 0 in
      List.iter (fun form -> match list form with
        | Some ({Sexp.node = Sexp.Atom (Sexp.Symbol "defgraph"); _} :: _ as items) ->
            (match header state ~definition:true form items with
             | Some (name, context, [interface_form; body_form]) ->
                 if List.exists (fun (definition : definition) -> definition.graph.name = name)
                    state.definitions then
                   error state form "E_DUPLICATE_DEF"
                     ("defgraph " ^ name ^ " is defined twice")
                 else let inputs, env = interface state interface_form in
                   let bindings, results = body state context env body_form
                     ~definition:true in
                   let geometry = ref 0 and values = ref 0 in
                   let outputs = List.map (fun (explicit, result) ->
                     let ty = Option.value ~default:Port_type.Float result.ty in
                     if ty = Port_type.Geometry then (
                       incr geometry;
                       (Option.value explicit ~default:(if !geometry = 1 then "geo"
                         else "geo" ^ string_of_int !geometry)), ty)
                     else (incr values;
                       (Option.value explicit ~default:(if !values = 1 then "out"
                         else "out" ^ string_of_int !values)), ty))
                     results in
                   let seen = Hashtbl.create 8 in
                   List.iter (fun (output, _) ->
                     if Hashtbl.mem seen output then
                       error state body_form "E_INTERFACE_ENTRY"
                         ("Output " ^ output ^ " is named twice")
                     else Hashtbl.add seen output ()) outputs;
                   state.definitions <- state.definitions @
                     [{graph = {name; context; bindings;
                       results = List.map snd results}; inputs; outputs}]
             | Some _ -> error state form "E_INTERFACE_ENTRY"
                 "defgraph needs an interface vector and body"
             | None -> ())
        | Some ({Sexp.node = Sexp.Atom (Sexp.Symbol "graph"); _} :: _ as items) ->
            incr graphs_seen;
            if !graphs_seen > 1 then error state form "E_ONE_GRAPH"
              "One graph per file";
            (match header state ~definition:false form items with
             | Some (name, context, [body_form]) when !graphs_seen = 1 ->
                 let bindings, results = body state context Names.empty
                   body_form ~definition:false in
                   List.iter (fun (_, result) -> if result.ty <> Some Port_type.Geometry
                     then error state body_form "E_RESULT_TYPE"
                       ("A " ^ Context.name context ^ " graph returns geometry")) results;
                   main := Some {name; context; bindings;
                     results = List.map snd results}
             | Some (_, _, [_]) | None -> ()
             | Some _ -> error state form "E_TOPLEVEL"
                 "graph needs one body")
        | _ -> error state form "E_TOPLEVEL"
            "Top-level forms are graph and defgraph") forms;
      if !graphs_seen = 0 then state.diagnostics <- Diagnostic.error
        ~span:{start = 0; finish = 0} ~position:{line = 1; col = 1}
        ~code:"E_NO_GRAPH" "No (graph …) form found" :: state.diagnostics;
      let diagnostics = List.rev state.diagnostics in
      let has_errors = List.exists (fun diagnostic ->
        diagnostic.Diagnostic.severity = Diagnostic.Error) diagnostics in
      (match !main with
       | Some graph when not has_errors ->
           Some {graph; definitions = state.definitions}, diagnostics
       | _ -> None, diagnostics)
