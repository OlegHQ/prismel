type field =
  | Native_uint of string
  | Uint64 of string
  | Float64 of string
  | Nested of string * string

type t =
  { objc_type : string
  ; ocaml_type : string
  ; fields : field list
  }

let entries =
  [ { objc_type = "MTLSize"
    ; ocaml_type = "size"
    ; fields = [ Native_uint "width"; Native_uint "height"; Native_uint "depth" ]
    }
  ; { objc_type = "MTLOrigin"
    ; ocaml_type = "origin"
    ; fields = [ Native_uint "x"; Native_uint "y"; Native_uint "z" ]
    }
  ; { objc_type = "MTLRegion"
    ; ocaml_type = "region"
    ; fields = [ Nested ("origin", "MTLOrigin"); Nested ("size", "MTLSize") ]
    }
  ; { objc_type = "MTLScissorRect"
    ; ocaml_type = "scissor_rect"
    ; fields =
        [ Native_uint "x"
        ; Native_uint "y"
        ; Native_uint "width"
        ; Native_uint "height"
        ]
    }
  ; { objc_type = "MTLViewport"
    ; ocaml_type = "viewport"
    ; fields =
        [ Float64 "originX"
        ; Float64 "originY"
        ; Float64 "width"
        ; Float64 "height"
        ; Float64 "znear"
        ; Float64 "zfar"
        ]
    }
  ; { objc_type = "MTLSizeAndAlign"
    ; ocaml_type = "size_and_align"
    ; fields = [ Native_uint "size"; Native_uint "align" ]
    }
  ; { objc_type = "MTLResourceID"
    ; ocaml_type = "resource_id"
    ; fields = [ Uint64 "_impl" ]
    }
  ; { objc_type = "MTL4BufferRange"
    ; ocaml_type = "buffer_range4"
    ; fields = [ Uint64 "bufferAddress"; Uint64 "length" ]
    }
  ]

let objc_types = List.map (fun entry -> entry.objc_type) entries

let identifier_character = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
  | _ -> false

let contains_type signature objc_type =
  let signature_length = String.length signature in
  let type_length = String.length objc_type in
  let rec search offset =
    if offset + type_length > signature_length then false
    else if String.sub signature offset type_length <> objc_type then
      search (offset + 1)
    else
      let left_ok =
        offset = 0 || not (identifier_character signature.[offset - 1])
      in
      let right = offset + type_length in
      let right_ok =
        right = signature_length
        || not (identifier_character signature.[right])
      in
      (left_ok && right_ok) || search (offset + 1)
  in
  search 0

let contains substring value =
  let substring_length = String.length substring in
  let value_length = String.length value in
  let rec search offset =
    offset + substring_length <= value_length
    && (String.sub value offset substring_length = substring
        || search (offset + 1))
  in
  search 0

(* By-value records are mechanical. Pointer/array/object/block signatures are
   deliberately left for ownership- and cardinality-aware templates. *)
let mechanically_safe_signature signature =
  not
    (List.exists
       (fun marker -> contains marker signature)
       [ "*"; "id<"; "NSArray"; "instancetype"; "(^" ])

let validate () =
  let fail format = Printf.ksprintf invalid_arg format in
  let names = List.sort String.compare objc_types in
  let rec reject_duplicates = function
    | left :: right :: _ when String.equal left right ->
        fail "duplicate Metal struct ABI type: %s" left
    | _ :: rest -> reject_duplicates rest
    | [] -> ()
  in
  reject_duplicates names;
  List.iter
    (fun entry ->
      if entry.fields = [] then fail "Metal struct ABI type has no fields: %s" entry.objc_type;
      List.iter
        (function
          | Nested (_, nested) when not (List.mem nested objc_types) ->
              fail "Metal struct ABI type %s has unknown nested type %s"
                entry.objc_type nested
          | _ -> ())
        entry.fields)
    entries

let () = validate ()
