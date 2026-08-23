type integer_width =
  | Native
  | Bits32
  | Bits64

type scalar =
  | Bool
  | Signed of
      { objc_type : string
      ; width : integer_width
      }
  | Unsigned of
      { objc_type : string
      ; width : integer_width
      }
  | Float64 of
      { objc_type : string
      }

type semantics =
  | Query
  | Command
  | Blocking
  | Process_identity

type method_entry =
  { sdk_id : string
  ; owner : string
  ; selector : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; arguments : scalar list
  ; result : scalar option
  ; semantics : semantics
  ; ocaml_name : string
  ; c_symbol : string
  }

type property_entry =
  { sdk_id : string
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; getter : method_entry
  ; setter : method_entry option
  }

let version ?(patch = 0) major minor : Binding_availability.version =
  { major; minor; patch }

let bool = Bool
let nsuint = Unsigned { objc_type = "NSUInteger"; width = Native }
let nsint = Signed { objc_type = "NSInteger"; width = Native }
let uint32 = Unsigned { objc_type = "uint32_t"; width = Bits32 }
let uint64 = Unsigned { objc_type = "uint64_t"; width = Bits64 }
let double = Float64 { objc_type = "CFTimeInterval" }
let mach_port = Unsigned { objc_type = "task_id_token_t"; width = Bits32 }
let kern_return = Signed { objc_type = "kern_return_t"; width = Bits32 }

let named_nsuint objc_type = Unsigned { objc_type; width = Native }
let named_nsint objc_type = Signed { objc_type; width = Native }

let scalar_objc_type = function
  | Bool -> "BOOL"
  | Signed { objc_type; _ }
  | Unsigned { objc_type; _ }
  | Float64 { objc_type } -> objc_type

let scalar_ocaml_type = function
  | Bool -> "bool"
  | Signed _ | Unsigned _ -> "int64"
  | Float64 _ -> "float"

let valid_identifier_character = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | _ -> false

let snake_case value =
  let output = Buffer.create (String.length value + 8) in
  let add_separator () =
    if Buffer.length output > 0 then
      let contents = Buffer.contents output in
      if contents.[String.length contents - 1] <> '_' then Buffer.add_char output '_'
  in
  String.iteri
    (fun index character ->
      if not (valid_identifier_character character) then add_separator ()
      else begin
        let uppercase = character >= 'A' && character <= 'Z' in
        let previous = if index = 0 then None else Some value.[index - 1] in
        let next =
          if index + 1 >= String.length value then None else Some value.[index + 1]
        in
        let boundary =
          uppercase
          &&
          match previous, next with
          | Some ('a' .. 'z' | '0' .. '9'), _ -> true
          | Some ('A' .. 'Z'), Some ('a' .. 'z') -> true
          | _ -> false
        in
        if boundary then add_separator ();
        Buffer.add_char output (Char.lowercase_ascii character)
      end)
    value;
  let result = Buffer.contents output in
  let first = ref 0 in
  let last = ref (String.length result - 1) in
  while !first <= !last && result.[!first] = '_' do
    incr first
  done;
  while !last >= !first && result.[!last] = '_' do
    decr last
  done;
  if !last < !first then ""
  else String.sub result !first (!last - !first + 1)

let derived_name owner selector =
  "generated_" ^ snake_case owner ^ "_" ^ snake_case selector

let method_entry ?ocaml_name ?c_symbol ~sdk_id ~owner ~selector ~header
    ~signature ?(attributes = []) ~macos_introduced ~arguments ~result
    ~semantics () =
  let derived = derived_name owner selector in
  let ocaml_name = Option.value ~default:derived ocaml_name in
  let c_symbol =
    Option.value ~default:("caml_prismel_metal_" ^ derived) c_symbol
  in
  { sdk_id
  ; owner
  ; selector
  ; header
  ; signature
  ; attributes
  ; macos_introduced
  ; arguments
  ; result
  ; semantics
  ; ocaml_name
  ; c_symbol
  }

let property_entry ~sdk_id ~owner ~name ~header ~signature ?(attributes = [])
    ~macos_introduced ~getter ?setter () =
  { sdk_id
  ; owner
  ; name
  ; header
  ; signature
  ; attributes
  ; macos_introduced
  ; getter
  ; setter
  }

let method_inventory_ids (entry : method_entry) = [ entry.sdk_id ]

let property_inventory_ids (entry : property_entry) =
  entry.sdk_id :: entry.getter.sdk_id
  ::
  match entry.setter with
  | None -> []
  | Some setter -> [ setter.sdk_id ]
