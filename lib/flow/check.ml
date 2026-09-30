type parameter = {
  name : string; label : string; ty : Port_type.t option;
  fields : (string * Param.kind_view * Param.value) list;
}
type slot = { name : string; required : bool; rest : bool }
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
             gather ({name = group; label = field.label; ty = Some Port_type.Vec3;
               fields = List.map (fun (field : Param.field_view) ->
                 field.name, field.kind, field.default)
                 [field;y;z]} :: reversed) tail
         | _ -> gather ({name = field.name; label = field.label;
             ty = Port_type.of_field_kind field.kind;
             fields = [field.name, field.kind, field.default]} :: reversed) rest) in
  gather [] fields

exception Invalid_manifest of Diagnostic.t

let catalog_of_manifest source =
  match Sexp.parse source with
  | Error diagnostic -> Error diagnostic
  | Ok forms ->
      let bad form message = raise (Invalid_manifest (Diagnostic.error
        ~span:form.Sexp.span ~position:form.position ~code:"E_CATALOG" message)) in
      let tagged tag form = match list form with
        | Some (head :: fields) when symbol head = Some tag -> fields
        | _ -> bad form ("Expected (" ^ tag ^ " …) in Flow manifest") in
      let string form = match form.Sexp.node with
        | Sexp.Atom (Sexp.String text) -> text
        | _ -> bad form "Expected a quoted string in Flow manifest" in
      let word form = match form.Sexp.node with
        | Sexp.Atom (Sexp.Symbol text | Sexp.Number text) -> text
        | _ -> bad form "Expected an atom in Flow manifest" in
      let number parse form = match parse (word form) with
        | Some value -> value | None -> bad form "Invalid number in Flow manifest" in
      let integer = number int_of_string_opt in
      let floating form =
        let value = number float_of_string_opt form in
        if Float.is_finite value then value
        else bad form "Non-finite number in Flow manifest" in
      let bool form = match word form with
        | "true" -> true | "false" -> false
        | _ -> bad form "Expected true or false in Flow manifest" in
      let one tag form = match tagged tag form with
        | [value] -> value | _ -> bad form (tag ^ " needs one value") in
      let optional parse form = if word form = "nil" then None
        else Some (parse form) in
      let strings tag form = List.map string (tagged tag form) in
      let property tag fields parent = match List.find_opt (fun form ->
          match list form with Some (head :: _) -> symbol head = Some tag
          | _ -> false) fields with
        | Some form -> form | None -> bad parent ("Missing " ^ tag ^ " in Flow manifest") in
      let literal form = match list form with
        | Some [head; value] ->
            (match symbol head with
             | Some "bool" -> Param.Bool_value (bool value)
             | Some "int" -> Param.Int_value (integer value)
             | Some "float" -> Param.Float_value (floating value)
             | Some "text" -> Param.Text_value (string value)
             | Some "choice" -> Param.Choice_value (string value)
             | _ -> bad form "Unknown literal kind in Flow manifest")
        | _ -> bad form "Malformed literal in Flow manifest" in
      let kind_view form = match list form with
        | Some [head] when symbol head = Some "bool" -> Param.Toggle_view
        | Some [head] when symbol head = Some "text" -> Param.Text_view
        | Some [head; soft; hard] when symbol head = Some "int" ->
            (match tagged "soft" soft, tagged "hard" hard with
             | [low; high], [hard_low; hard_high] ->
                 Param.Integer_view {Param.soft_min = integer low;
                   soft_max = integer high;
                   hard_min = optional integer hard_low;
                   hard_max = optional integer hard_high}
             | _ -> bad form "Malformed integer range in Flow manifest")
        | Some [head; soft; hard] when symbol head = Some "float" ->
            (match tagged "soft" soft, tagged "hard" hard with
             | [low; high], [hard_low; hard_high] ->
                 Param.Floating_view {Param.soft_min = floating low;
                   soft_max = floating high;
                   hard_min = optional floating hard_low;
                   hard_max = optional floating hard_high}
             | _ -> bad form "Malformed float range in Flow manifest")
        | Some (head :: labels) when symbol head = Some "choice" ->
            Param.Choice_view (Array.of_list (List.map string labels))
        | _ -> bad form "Unknown field kind in Flow manifest" in
      let field form = match tagged "field" form with
        | [name; label; folder; kind; default; primary; vec3] ->
            let default = literal default in
            let vec3 = match tagged "vec3" vec3 with
              | [] -> None | [name; index] -> Some (string name, integer index)
              | _ -> bad vec3 "Malformed Vec3 group in Flow manifest" in
            {Param.name = string name; label = string label;
              description = None; folder = strings "folder" folder;
              impact = Param.Cook; primary = bool (one "primary" primary);
              vec3; kind = kind_view kind; default; current = default}
        | _ -> bad form "Malformed field in Flow manifest" in
      let port_type form = match word form with
        | "geometry" -> Port_type.Geometry | "float" -> Float
        | "int" -> Int | "bool" -> Bool | "vec3" -> Vec3
        | _ -> bad form "Unknown output type in Flow manifest" in
      let kind form = match tagged "kind" form with
        | qualified :: properties ->
            let qualified = string qualified in
            let get tag = property tag properties form in
            let key = string (one "key" (get "key")) in
            ignore (string (one "operation" (get "operation")));
            ignore (string (one "label" (get "label")));
            ignore (strings "category" (get "category"));
            let aliases = strings "aliases" (get "aliases") in
            let slots = tagged "slots" (get "slots") |> List.map (fun slot ->
              match tagged "slot" slot with
              | [name; required] ->
                  (match word required with
                    | "required" -> {name = string name; required = true; rest = false}
                    | "optional" -> {name = string name; required = false; rest = false}
                    | "rest" -> {name = string name; required = true; rest = true}
                    | _ -> bad required "Unknown slot requirement")
              | _ -> bad slot "Malformed slot in Flow manifest") in
            let fields = List.map field (tagged "fields" (get "fields")) in
            let outputs = tagged "outputs" (get "outputs") |> List.map (fun output ->
              match tagged "output" output with
              | [name; ty] -> string name, port_type ty
              | _ -> bad output "Malformed output in Flow manifest") in
            let context = if String.starts_with ~prefix:"value/" qualified then None
              else match List.find_opt (fun context ->
                  String.starts_with ~prefix:(Context.name context ^ "/") qualified)
                  Context.[Sop; Scene; World; Settings] with
                | Some context -> Some context
                | None -> bad form "Unknown kind namespace in Flow manifest" in
            if not (String.ends_with ~suffix:("/" ^ key) qualified)
              then bad form "Kind key differs from its qualified name";
            Option.map (fun context -> {qualified; aliases; context; slots;
              parameters = parameters_of_fields fields; outputs}) context
        | _ -> bad form "Malformed kind in Flow manifest" in
      try match forms with
      | [root] ->
          (match tagged "flow_manifest" root with
           | [version_form; digest_form; kinds_form] ->
               let version = integer (one "version" version_form)
               and digest = string (one "digest" digest_form) in
               if version < 0 then bad root "Negative Flow catalog version";
               if String.length digest <> 32 || not (String.for_all
                 (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) digest)
               then bad root "Flow manifest digest must be 32 lowercase hex digits";
               let kind_forms = tagged "kinds" kinds_form in
               let raw form = String.sub source form.Sexp.span.start
                 (form.Sexp.span.finish - form.Sexp.span.start) in
               (* the digest covers the sop and value kinds; scene, world and settings
                  kinds are generated by the editor document and follow them *)
               let linked = List.filter (fun form -> match tagged "kind" form with
                 | qualified :: _ -> let q = string qualified in
                     String.starts_with ~prefix:"sop/" q || String.starts_with ~prefix:"value/" q
                 | [] -> true) kind_forms in
               let payload = raw version_form ^ "\n(kinds" ^
                 (if linked = [] then "" else " " ^
                   String.concat " " (List.map raw linked)) ^ ")" in
               if Digest.to_hex (Digest.string payload) <> digest then
                 bad digest_form "Flow manifest digest does not match its contents";
               let kinds = List.filter_map kind kind_forms in
               Ok ({version; kinds}, digest)
           | _ -> bad root "Flow manifest needs version, digest and kinds")
      | _ -> Error (Diagnostic.error ~code:"E_CATALOG"
          "Flow manifest needs one top-level form")
      with Invalid_manifest diagnostic -> Error diagnostic
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
        if ty = Port_type.Geometry then Some {name; required = default = None; rest = false}
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
let resolve_report state context report head =
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
      report "E_WRONG_CONTEXT"
        (Printf.sprintf "%s is a %s node and cannot appear in a %s graph"
          kind.qualified (Context.name kind.context) (Context.name context)); None
  | _ :: _ :: _ ->
      report "E_AMBIGUOUS"
        (Printf.sprintf "%s is ambiguous: %s. Write the namespace to choose"
          head (String.concat " or " (List.map (fun kind -> kind.qualified) candidates)));
      None
  | [] ->
      (match String.split_on_char '/' head with
       | prefix :: _ :: _ when not (known_prefix state prefix) ->
           report "E_NAMESPACE"
             (Printf.sprintf "Unknown namespace %s. This file knows sop, value and user" prefix)
       | _ ->
           let names = List.map (fun kind -> short kind.qualified) all in
           report "E_UNKNOWN_KIND"
             ("Unknown node " ^ head ^ "." ^ suggestion head names));
      None

let resolve state context form head =
  resolve_report state context (error state form) head

let resolve_kind catalog context head =
  let failure = ref None in
  let state = {catalog; definitions = []; diagnostics = []} in
  match resolve_report state context (fun code message -> failure := Some (code, message)) head with
  | Some kind -> Ok kind
  | None -> Error (Option.value !failure ~default:("E_UNKNOWN_KIND", "Unknown node " ^ head))

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

let validate_range report (parameter : parameter) field value =
  match field, numeric_value value with
  | (_, Param.Integer_view range, _), Some number ->
      if Float.floor number <> number then ()
      else if Option.fold ~none:false ~some:(fun n -> number < float_of_int n) range.hard_min
           || Option.fold ~none:false ~some:(fun n -> number > float_of_int n) range.hard_max then
        report Diagnostic.Error "E_HARD_RANGE"
          (Printf.sprintf ":%s is outside its hard range" parameter.name)
      else if number < float_of_int range.soft_min || number > float_of_int range.soft_max then
        report Diagnostic.Warning "W_SOFT_RANGE"
          (Printf.sprintf ":%s %g is outside the slider range %d–%d. Allowed, but check it"
            parameter.name number range.soft_min range.soft_max)
  | (_, Param.Floating_view range, _), Some number ->
      if Option.fold ~none:false ~some:(fun n -> number < n) range.hard_min
           || Option.fold ~none:false ~some:(fun n -> number > n) range.hard_max then
        report Diagnostic.Error "E_HARD_RANGE"
          (Printf.sprintf ":%s is outside its hard range" parameter.name)
      else if number < range.soft_min || number > range.soft_max then
        report Diagnostic.Warning "W_SOFT_RANGE"
          (Printf.sprintf ":%s %g is outside the slider range %g–%g. Allowed, but check it"
            parameter.name number range.soft_min range.soft_max)
  | _ -> ()

let validate_parameter report (parameter : parameter) (value : checked) =
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
  if not good then report Diagnostic.Error "E_TYPE"
    (Printf.sprintf ":%s takes %s, but this is %s" parameter.name
      (Option.fold ~none:"text" ~some:Port_type.name parameter.ty)
      (Option.fold ~none:"nil or text" ~some:Port_type.name ty));
  (match parameter.ty, value.term.node with
   | Some Port_type.Int, Literal (Param.Float_value number)
       when Float.floor number <> number ->
       report Diagnostic.Error "E_INT_LITERAL"
         (Printf.sprintf ":%s is an integer, not %g" parameter.name number)
   | Some Port_type.Int, Literal (Param.Float_value number)
       when number >= float_of_int max_int || number < float_of_int min_int ->
       report Diagnostic.Error "E_HARD_RANGE"
         (Printf.sprintf ":%s is outside the integer range" parameter.name)
   | _ -> ());
  (match parameter.fields, value.term.node with
   | [(_, Param.Choice_view options, _)],
       Literal (Param.Text_value label | Param.Choice_value label)
       when not (Array.exists (( = ) label) options) ->
       report Diagnostic.Error "E_TYPE"
         (Printf.sprintf ":%s must be one of %s" parameter.name
           (String.concat ", " (Array.to_list options)))
   | _ -> ());
  if good then (match value.term.node, parameter.fields with
    | Literal literal, field :: _ -> validate_range report parameter field literal
    | Vector components, fields ->
        List.iter2 (fun component field -> match component.node with
          | Literal literal -> validate_range report parameter field literal
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

(* a rest slot named [n] also answers to [n_2], [n_3], ... *)
and rest_name n extra = if extra = 0 then n else n ^ "_" ^ string_of_int (extra + 1)

and is_slot (kind : kind) name = List.exists (fun (slot : slot) ->
    slot.name = name || slot.rest && String.starts_with ~prefix:(slot.name ^ "_") name
      && int_of_string_opt (String.sub name (String.length slot.name + 1)
        (String.length name - String.length slot.name - 1)) <> None) kind.slots

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
                 if is_slot kind name then
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
                             validate_parameter (emit state value_form) parameter value);
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
          let repeats = match List.rev kind.slots with
            | { rest = true; _ } :: _ -> true | _ -> false in
          if !positional >= Array.length slots && not repeats then
            error state item "E_EXTRA_POSITIONAL"
              (Printf.sprintf "%s takes %d geometry inputs; this one is extra"
                (short kind.qualified) (Array.length slots))
          else (
            let last = Array.length slots - 1 in
            let slot = if !positional <= last then slots.(!positional).name
              else rest_name slots.(last).name (!positional - last) in
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
  | Some ("scene" | "world" | "settings" | "shader" as name) ->
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
               else if Symbol.reserved name then Some "E_BINDING_NAME"
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
                 if Symbol.reserved name && name <> "t" then
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
                              else validate_parameter (emit state default)
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
                    state.definitions || List.exists (fun (kind : kind) ->
                      kind.qualified = "user/" ^ name) state.catalog.kinds then
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
                     && result.node <> Nil
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

let validate_parameter report parameter term =
  validate_parameter report parameter (checked term)
