type representation =
  | Bool
  | Nsuint
  | Enum of string
  | Flags of string
  | Resource_options
  | Sample_index

type default =
  | Default_bool of bool
  | Default_int64 of int64

type entry =
  { owner : string
  ; name : string
  ; getter_name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string
  ; attributes : string list
  ; representation : representation
  ; default : default
  }

let representation signature =
  match signature with
  | "BOOL" -> Bool
  | "NSUInteger" -> Nsuint
  | "MTLIndirectCommandType" -> Flags "MTLIndirectCommandType"
  | "MTLResourceOptions" -> Resource_options
  | value when String.length value > 3 && String.sub value 0 3 = "MTL" ->
      Enum value
  | value -> invalid_arg ("unsupported descriptor property type: " ^ value)

let entry ?(attributes = []) ?(default_int64 = 0L) ?getter ~owner ~name ~header
    ~signature ~introduced () =
  let representation = if String.equal owner "MTLBlitPassSampleBufferAttachmentDescriptor" then Sample_index else representation signature in
  let default =
    match representation with
    | Bool -> Default_bool (default_int64 <> 0L)
    | Nsuint | Enum _ | Flags _ | Resource_options | Sample_index ->
        Default_int64 default_int64
  in
  let getter_name = Option.value ~default:name getter in
  { owner; name; getter_name; header; signature; macos_introduced = introduced; attributes
  ; representation
  ; default
  }

let property_sdk_id entry = "property:" ^ entry.owner ^ ":" ^ entry.name
let getter_sdk_id entry =
  "method:-[" ^ entry.owner ^ " " ^ entry.getter_name ^ "]"

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
  snake_case value

let ocaml_type entry =
  match entry.representation with
  | Bool -> "bool"
  | Nsuint -> "int64"
  | Enum value ->
      if String.equal value "MTLStorageMode" then "Storage_mode.t"
      else "Metal_enum_generated." ^ String.capitalize_ascii (enum_module value) ^ ".t"
  | Flags value ->
      "Metal_enum_generated." ^ String.capitalize_ascii (enum_module value)
      ^ ".t list"
  | Resource_options -> "Resource_options.t"
  | Sample_index -> "Sample_index.t"

let default_expression entry =
  match (entry.representation, entry.default) with
  | Bool, Default_bool value -> string_of_bool value
  | Nsuint, Default_int64 value -> Int64.to_string value ^ "L"
  | Enum name, Default_int64 value ->
      if String.equal name "MTLStorageMode" then
        Printf.sprintf "Storage_mode.of_int64_exn %LdL" value
      else
        Printf.sprintf
          "(match Metal_enum_generated.%s.of_int64 %LdL with Some value -> value | None -> invalid_arg %S)"
          (String.capitalize_ascii (enum_module name)) value
          ("Metal SDK default is absent from generated enum " ^ name)
  | Flags _, Default_int64 0L -> "[]"
  | Flags name, Default_int64 value ->
      invalid_arg
        (Printf.sprintf "nonzero flags default %Ld is unsupported for %s" value
           name)
  | Resource_options, Default_int64 value ->
      Printf.sprintf "Resource_options.of_bits_exn %LdL" value
  | Sample_index, Default_int64 value -> Printf.sprintf "Sample_index.of_int64_exn %LdL" value
  | _ -> failwith "descriptor property default/representation mismatch"

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
      if entry.owner = "" || entry.name = "" || entry.getter_name = ""
         || entry.header = ""
      then
        fail "empty identity field";
      if not (Filename.is_relative entry.header) then
        fail "absolute header %s" entry.header;
      if entry.macos_introduced = "" then fail "missing availability for %s" (property_sdk_id entry);
      match entry.representation with
      | Bool when entry.signature = "BOOL" -> ()
      | Nsuint when entry.signature = "NSUInteger" -> ()
      | Enum value when value = entry.signature -> ()
      | Flags value when value = entry.signature -> ()
      | Resource_options when entry.signature = "MTLResourceOptions" -> ()
      | Sample_index when entry.signature = "NSUInteger" -> ()
      | _ -> fail "representation/signature mismatch for %s" (property_sdk_id entry))
    entries
