type nullability = Nonnull | Nullable

type getter_ownership = Copy_to_ocaml
type setter_ownership = Borrow_during_call

type receiver_status =
  | Qualified_direct of Binding_receiver_catalog.receiver
  | Qualified_polymorphic of Binding_receiver_catalog.polymorphic_receiver
  | Pending_receiver_catalog

type entry =
  { property_sdk_id : string
  ; getter_sdk_id : string
  ; setter_sdk_id : string option
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; macos_introduced : Binding_availability.version
  ; nullability : nullability
  ; getter_ownership : getter_ownership
  ; setter_ownership : setter_ownership option
  ; receiver_status : receiver_status
  }

let parse_version value =
  match String.split_on_char '.' value with
  | [ major; minor ] ->
      Binding_direct_spec.version (int_of_string major) (int_of_string minor)
  | [ major; minor; patch ] ->
      Binding_direct_spec.version ~patch:(int_of_string patch)
        (int_of_string major) (int_of_string minor)
  | _ -> invalid_arg ("Invalid Metal availability version: " ^ value)

let receiver_for owner =
  match
    List.find_opt
      (fun (receiver : Binding_receiver_catalog.receiver) ->
        String.equal receiver.sdk_owner owner)
      Binding_receiver_catalog.receivers
  with
  | Some receiver -> Qualified_direct receiver
  | None ->
      (match
         List.find_opt
           (fun (receiver : Binding_receiver_catalog.polymorphic_receiver) ->
             String.equal receiver.sdk_owner owner)
           Binding_receiver_catalog.polymorphic_receivers
       with
      | Some receiver -> Qualified_polymorphic receiver
      | None -> Pending_receiver_catalog)

let capitalize_first value =
  if String.equal value "" then invalid_arg "Empty Metal property name";
  String.init (String.length value) (fun index ->
      if index = 0 then Char.uppercase_ascii value.[index] else value.[index])

let entry ?(attributes = []) ?(setter = false) ~owner ~name ~header ~signature
    ~macos_introduced () =
  let nullability =
    if String.equal signature "NSString * _Nonnull" then Nonnull
    else if String.equal signature "NSString * _Nullable" then Nullable
    else invalid_arg ("Unsupported Metal NSString signature: " ^ signature)
  in
  let getter_sdk_id = "method:-[" ^ owner ^ " " ^ name ^ "]" in
  let setter_sdk_id =
    if setter then
      Some
        ("method:-[" ^ owner ^ " set" ^ capitalize_first name ^ ":]")
    else None
  in
  { property_sdk_id = "property:" ^ owner ^ ":" ^ name
  ; getter_sdk_id
  ; setter_sdk_id
  ; owner
  ; name
  ; header
  ; signature
  ; attributes
  ; macos_introduced = parse_version macos_introduced
  ; nullability
  ; getter_ownership = Copy_to_ocaml
  ; setter_ownership = Option.map (fun _ -> Borrow_during_call) setter_sdk_id
  ; receiver_status = receiver_for owner
  }

let inventory_ids entry =
  entry.property_sdk_id :: entry.getter_sdk_id
  :: Option.to_list entry.setter_sdk_id

let getter_ocaml_type entry =
  match entry.nullability with Nonnull -> "string" | Nullable -> "string option"

let setter_ocaml_type entry =
  Option.map
    (fun _ ->
      match entry.nullability with
      | Nonnull -> "string"
      | Nullable -> "string option")
    entry.setter_sdk_id

let getter_selector entry = entry.name

let setter_selector entry =
  Option.map (fun _ -> "set" ^ capitalize_first entry.name ^ ":")
    entry.setter_sdk_id

let receiver_or_reject entry =
  match entry.receiver_status with
  | Qualified_direct receiver -> receiver.local_name
  | Qualified_polymorphic receiver -> receiver.local_name
  | Pending_receiver_catalog ->
      invalid_arg
        ("Metal NSString receiver is not qualified: " ^ entry.owner)

let native_getter_expression entry =
  let receiver = receiver_or_reject entry in
  "NSString *result = [" ^ receiver ^ " " ^ getter_selector entry
  ^ "]; /* copy UTF-8 into OCaml before return */"

let native_setter_expression entry =
  Option.map
    (fun selector ->
      let receiver = receiver_or_reject entry in
      "[" ^ receiver ^ " " ^ selector
      ^ "value]; /* NSString borrowed for this call only */")
    (setter_selector entry)
