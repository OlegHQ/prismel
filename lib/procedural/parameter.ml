type impact = Cook | View | Export

type effects = {
  cook : bool;
  view : bool;
  export : bool;
}

let no_effects = { cook = false; view = false; export = false }

let add_impact impact effects = match impact with
  | Cook -> { effects with cook = true }
  | View -> { effects with view = true }
  | Export -> { effects with export = true }

let union_effects left right = {
  cook = left.cook || right.cook;
  view = left.view || right.view;
  export = left.export || right.export;
}

let has_effects value = value.cook || value.view || value.export

type int_range = {
  soft_min : int;
  soft_max : int;
  hard_min : int option;
  hard_max : int option;
}

type float_range = {
  soft_min : float;
  soft_max : float;
  hard_min : float option;
  hard_max : float option;
}

type 'a choice = {
  options : (string * 'a) array;
  equal : 'a -> 'a -> bool;
}

type 'a encoding = {
  encode : 'a -> string;
  decode : string -> ('a, string) result;
  equal : 'a -> 'a -> bool;
}

type _ kind =
  | Toggle : bool kind
  | Integer : int_range -> int kind
  | Floating : float_range -> float kind
  | Text : string kind
  | Choice : 'a choice -> 'a kind
  | Encoded : 'a encoding -> 'a kind

type 'record field = Field : {
  name : string;
  label : string;
  description : string option;
  folder : string list;
  impact : impact;
  kind : 'value kind;
  default : 'value;
  get : 'record -> 'value;
  set : 'value -> 'record -> 'record;
} -> 'record field

type 'record schema = {
  name : string;
  default : 'record;
  fields : 'record field list;
  by_name : (string, 'record field) Hashtbl.t;
}

type value =
  | Bool_value of bool
  | Int_value of int
  | Float_value of float
  | Text_value of string
  | Choice_value of string

type kind_view =
  | Toggle_view
  | Integer_view of int_range
  | Floating_view of float_range
  | Text_view
  | Choice_view of string array

type field_view = {
  name : string;
  label : string;
  description : string option;
  folder : string list;
  impact : impact;
  kind : kind_view;
  default : value;
  current : value;
}

let nonblank what value =
  if String.trim value = "" then invalid_arg (what ^ " must not be blank")

let validate_int_range (range : int_range) =
  if range.soft_max <= range.soft_min then
    invalid_arg "Parameter.integer: soft max must be greater than soft min";
  (match range.hard_min, range.hard_max with
   | Some low, Some high when high < low ->
       invalid_arg "Parameter.integer: hard max must be at least hard min"
   | _ -> ());
  Option.iter (fun low ->
    if range.soft_min < low then invalid_arg
        "Parameter.integer: soft min must not be below hard min") range.hard_min;
  Option.iter (fun high ->
    if range.soft_max > high then invalid_arg
        "Parameter.integer: soft max must not exceed hard max") range.hard_max

let validate_float_range (range : float_range) =
  let finite = Float.is_finite in
  if not (finite range.soft_min && finite range.soft_max)
     || range.soft_max <= range.soft_min
  then invalid_arg
      "Parameter.floating: soft bounds must be finite and increasing";
  Option.iter (fun value -> if not (finite value) then invalid_arg
      "Parameter.floating: hard bounds must be finite") range.hard_min;
  Option.iter (fun value -> if not (finite value) then invalid_arg
      "Parameter.floating: hard bounds must be finite") range.hard_max;
  (match range.hard_min, range.hard_max with
   | Some low, Some high when high < low ->
       invalid_arg "Parameter.floating: hard max must be at least hard min"
   | _ -> ());
  Option.iter (fun low ->
    if range.soft_min < low then invalid_arg
        "Parameter.floating: soft min must not be below hard min") range.hard_min;
  Option.iter (fun high ->
    if range.soft_max > high then invalid_arg
        "Parameter.floating: soft max must not exceed hard max") range.hard_max

let integer ?hard_min ?hard_max ~min:soft_min ~max:soft_max () =
  let range : int_range = { soft_min; soft_max; hard_min; hard_max } in
  validate_int_range range;
  Integer range

let floating ?hard_min ?hard_max ~min:soft_min ~max:soft_max () =
  let range : float_range = { soft_min; soft_max; hard_min; hard_max } in
  validate_float_range range;
  Floating range

let choice ~equal values =
  if values = [] then invalid_arg "Parameter.choice: options must not be empty";
  let options = Array.of_list values in
  Array.iteri (fun index (label, _) ->
    nonblank "Parameter.choice label" label;
    for previous = 0 to index - 1 do
      if fst options.(previous) = label then invalid_arg
          (Printf.sprintf "Parameter.choice: duplicate label %S" label)
    done) options;
  Choice { options; equal }

let encoded ~equal ~encode ~decode = Encoded { encode; decode; equal }

let clamp_int (range : int_range) value =
  let value = match range.hard_min with
    | Some low -> max low value | None -> value in
  match range.hard_max with Some high -> min high value | None -> value

let clamp_float (range : float_range) value =
  if not (Float.is_finite value) then Error "float parameter must be finite"
  else
    let value = match range.hard_min with
      | Some low -> Float.max low value | None -> value in
    Ok (match range.hard_max with
      | Some high -> Float.min high value | None -> value)

let normalize_kind : type value. value kind -> value -> (value, string) result =
  fun kind value -> match kind with
  | Toggle | Text | Encoded _ -> Ok value
  | Integer range -> Ok (clamp_int range value)
  | Floating range -> clamp_float range value
  | Choice choice ->
      if Array.exists (fun (_, option) -> choice.equal option value)
          choice.options
      then Ok value else Error "choice parameter value is not an option"

let equal_kind : type value. value kind -> value -> value -> bool =
  fun kind left right -> match kind with
  | Toggle | Integer _ | Floating _ | Text -> left = right
  | Choice choice -> choice.equal left right
  | Encoded encoding -> encoding.equal left right

let default_label name =
  let value = Bytes.of_string name in
  Bytes.iteri (fun index character ->
    if character = '_' || character = '-' then Bytes.set value index ' ')
    value;
  let value = Bytes.to_string value in
  if value = "" then value
  else String.mapi (fun index character ->
    if index = 0 then Char.uppercase_ascii character else character) value

let field ~name ?label ?description ?(folder = []) ?(impact = Cook)
    ~kind ~default ~get ~set () =
  nonblank "Parameter.field name" name;
  List.iter (nonblank "Parameter.field folder") folder;
  let label = Option.value ~default:(default_label name) label in
  nonblank "Parameter.field label" label;
  let default = match normalize_kind kind default with
    | Ok value -> value
    | Error message -> invalid_arg ("Parameter.field " ^ name ^ ": " ^ message)
  in
  Field { name; label; description; folder; impact; kind; default; get; set }

let schema ~name ~default fields =
  nonblank "Parameter.schema name" name;
  let seen = Hashtbl.create (List.length fields) in
  List.iter (fun (Field field) ->
    if Hashtbl.mem seen field.name then invalid_arg
        (Printf.sprintf "Parameter.schema: duplicate field %S" field.name);
    Hashtbl.add seen field.name ()) fields;
  let by_name = Hashtbl.create (List.length fields) in
  List.iter (fun ((Field field) as packed) ->
    Hashtbl.add by_name field.name packed) fields;
  let schema = { name; default; fields; by_name } in
  let default = match
      List.fold_left (fun result (Field field) ->
        Result.bind result (fun record ->
          Result.map (fun value -> field.set value record)
            (normalize_kind field.kind (field.get record)))) (Ok default) fields
    with
    | Ok value -> value
    | Error message -> invalid_arg ("Parameter.schema " ^ name ^ ": " ^ message)
  in
  { schema with default }

let name (value : 'record schema) = value.name
let default (value : 'record schema) = value.default
let fields (value : 'record schema) = value.fields
let mem (value : 'record schema) name = Hashtbl.mem value.by_name name

let choice_label (choice : 'a choice) value =
  match Array.find_opt (fun (_, candidate) -> choice.equal candidate value)
      choice.options with
  | Some (label, _) -> label
  | None -> invalid_arg "Parameter.view: choice value is not an option"

let view_field : type record. record -> record field -> field_view =
  fun record (Field field) ->
    let kind, default, current = match field.kind with
      | Toggle -> Toggle_view, Bool_value field.default,
          Bool_value (field.get record)
      | Integer range -> Integer_view range, Int_value field.default,
          Int_value (field.get record)
      | Floating range -> Floating_view range, Float_value field.default,
          Float_value (field.get record)
      | Text -> Text_view, Text_value field.default,
          Text_value (field.get record)
      | Choice choice ->
          Choice_view (Array.map fst choice.options),
          Choice_value (choice_label choice field.default),
          Choice_value (choice_label choice (field.get record))
      | Encoded encoding -> Text_view,
          Text_value (encoding.encode field.default),
          Text_value (encoding.encode (field.get record))
    in
    { name = field.name; label = field.label;
      description = field.description; folder = field.folder;
      impact = field.impact; kind; default; current }

let view schema record = List.map (view_field record) schema.fields

let append_token buffer token =
  Printf.bprintf buffer "%d:%s" (String.length token) token

let key (schema : 'record schema) record =
  let buffer = Buffer.create 128 in
  append_token buffer schema.name;
  List.iter (fun (Field field) ->
    append_token buffer field.name;
    match field.kind with
    | Toggle -> Buffer.add_string buffer
        (if field.get record then "b1" else "b0")
    | Integer _ -> Printf.bprintf buffer "i%d;" (field.get record)
    | Floating _ -> Printf.bprintf buffer "f%.17g;" (field.get record)
    | Text -> Buffer.add_char buffer 's'; append_token buffer (field.get record)
    | Choice choice ->
        Buffer.add_char buffer 'c';
        append_token buffer (choice_label choice (field.get record))
    | Encoded encoding ->
        Buffer.add_char buffer 'e';
        append_token buffer (encoding.encode (field.get record)))
    schema.fields;
  Buffer.contents buffer

let apply_field : type record value.
    record -> value kind -> value -> (value -> record -> record) -> impact ->
    value -> (record * impact option, string) result =
  fun record kind old_value set impact candidate ->
    Result.map (fun value ->
      if equal_kind kind old_value value then record, None
      else set value record, Some impact) (normalize_kind kind candidate)

let apply schema record ~name value =
  match Hashtbl.find_opt schema.by_name name with
  | None -> Ok None
  | Some (Field field) ->
        let old_value = field.get record in
        let result = match field.kind, value with
          | Toggle, Bool_value value ->
              apply_field record field.kind old_value field.set field.impact value
          | Integer _, Int_value value ->
              apply_field record field.kind old_value field.set field.impact value
          | Floating _, Float_value value ->
              apply_field record field.kind old_value field.set field.impact value
          | Text, Text_value value ->
              apply_field record field.kind old_value field.set field.impact value
          | Choice choice, Choice_value label ->
              (match Array.find_opt (fun (candidate, _) -> candidate = label)
                  choice.options with
               | None -> Error (Printf.sprintf
                   "parameter %S has no choice %S" name label)
               | Some (_, value) -> apply_field record field.kind old_value
                   field.set field.impact value)
          | Encoded encoding, Text_value text ->
              Result.bind (encoding.decode text) (fun value ->
                apply_field record field.kind old_value field.set field.impact
                  value)
          | _ -> Error (Printf.sprintf "parameter %S received the wrong type" name)
        in
        Result.map Option.some result

let apply_all schema record changes =
  let step (record, effects) (name, value) =
    Result.bind (apply schema record ~name value) (function
      | None -> Ok (record, effects)
      | Some (record, None) -> Ok (record, effects)
      | Some (record, Some impact) ->
          Ok (record, add_impact impact effects))
  in
  List.fold_left (fun result change ->
    Result.bind result (fun state -> step state change))
    (Ok (record, no_effects)) changes

let normalize schema record =
  List.fold_left (fun result (Field field) ->
    Result.bind result (fun record ->
      Result.map (fun value -> field.set value record)
        (normalize_kind field.kind (field.get record)))) (Ok record) schema.fields
