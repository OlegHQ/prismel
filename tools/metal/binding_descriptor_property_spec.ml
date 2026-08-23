type representation =
  | Bool
  | Nsuint
  | Enum of string

type entry =
  { owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string
  ; attributes : string list
  ; representation : representation
  }

let representation signature =
  match signature with
  | "BOOL" -> Bool
  | "NSUInteger" -> Nsuint
  | value when String.length value > 3 && String.sub value 0 3 = "MTL" ->
      Enum value
  | value -> invalid_arg ("unsupported descriptor property type: " ^ value)

let entry ?(attributes = []) ~owner ~name ~header ~signature ~introduced () =
  { owner; name; header; signature; macos_introduced = introduced; attributes
  ; representation = representation signature
  }

let property_sdk_id entry = "property:" ^ entry.owner ^ ":" ^ entry.name
let getter_sdk_id entry = "method:-[" ^ entry.owner ^ " " ^ entry.name ^ "]"

let capitalize value =
  if value = "" then invalid_arg "empty descriptor property name";
  String.init (String.length value) (fun index ->
      if index = 0 then Char.uppercase_ascii value.[index] else value.[index])

let setter_sdk_id entry =
  "method:-[" ^ entry.owner ^ " set" ^ capitalize entry.name ^ ":]"

let inventory_ids entry =
  [ property_sdk_id entry; getter_sdk_id entry; setter_sdk_id entry ]

let snake_case value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri
    (fun index character ->
      let uppercase = character >= 'A' && character <= 'Z' in
      if uppercase && index > 0 then begin
        let previous = value.[index - 1] in
        let next_lowercase =
          index + 1 < String.length value
          && value.[index + 1] >= 'a' && value.[index + 1] <= 'z'
        in
        if
          (previous >= 'a' && previous <= 'z')
          || (previous >= '0' && previous <= '9') || next_lowercase
        then Buffer.add_char output '_'
      end;
      Buffer.add_char output (Char.lowercase_ascii character))
    value;
  Buffer.contents output

let field_name entry = snake_case entry.name

let enum_module value =
  let value =
    if String.length value >= 3 && String.sub value 0 3 = "MTL" then
      String.sub value 3 (String.length value - 3)
    else value
  in
  snake_case value

let ocaml_type entry =
  match entry.representation with
  | Bool -> "bool"
  | Nsuint -> "int64"
  | Enum value -> "Metal.Enum." ^ enum_module value ^ ".t"

let fail format =
  Printf.ksprintf (fun message -> invalid_arg ("Metal descriptor property plan: " ^ message)) format

let validate entries =
  let ids = List.concat_map inventory_ids entries |> List.sort String.compare in
  let rec duplicates = function
    | left :: right :: _ when left = right -> fail "duplicate inventory ID %s" left
    | _ :: rest -> duplicates rest
    | [] -> ()
  in
  duplicates ids;
  List.iter
    (fun entry ->
      if entry.owner = "" || entry.name = "" || entry.header = "" then
        fail "empty identity field";
      if not (Filename.is_relative entry.header) then
        fail "absolute header %s" entry.header;
      if entry.macos_introduced = "" then fail "missing availability for %s" (property_sdk_id entry);
      match entry.representation with
      | Bool when entry.signature = "BOOL" -> ()
      | Nsuint when entry.signature = "NSUInteger" -> ()
      | Enum value when value = entry.signature -> ()
      | _ -> fail "representation/signature mismatch for %s" (property_sdk_id entry))
    entries
