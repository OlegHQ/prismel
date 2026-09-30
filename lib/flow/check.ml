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

type checked = { term : term }
type state = { catalog : catalog }

let symbol form = match form.Sexp.node with
  | Sexp.Atom (Sexp.Symbol name) -> Some name | _ -> None
let list form = match form.Sexp.node with Sexp.List items -> Some items | _ -> None
let short qualified = match String.split_on_char '/' qualified with
  | [_; name] -> name | _ -> qualified

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
let kinds state = state.catalog.kinds @ builtin_kinds
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
             ("Unknown node " ^ head ^ "." ^ suggestion (short head) names));
      None

let resolve_kind catalog context head =
  let failure = ref None in
  let state = {catalog} in
  match resolve_report state context (fun code message -> failure := Some (code, message)) head with
  | Some kind -> Ok kind
  | None -> Error (Option.value !failure ~default:("E_UNKNOWN_KIND", "Unknown node " ^ head))

let numeric_value = function
  | Param.Int_value n -> Some (float_of_int n)
  | Float_value n -> Some n
  | Bool_value n -> Some (if n then 1. else 0.)
  | Text_value _ | Choice_value _ -> None
let checked term = {term}

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

let validate_parameter report parameter term =
  validate_parameter report parameter (checked term)
