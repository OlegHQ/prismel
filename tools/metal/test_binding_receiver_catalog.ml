open Support

module String_set = Set.Make (String)

let parse_options () =
  let inventory = ref "" in
  let bridge = ref "" in
  Arg.parse
    [ "--inventory", Arg.Set_string inventory, "Pinned Metal API inventory"
    ; "--bridge", Arg.Set_string bridge, "Handwritten Metal bridge"
    ]
    (fun value -> fail "unexpected receiver-catalog test argument: %s" value)
    "Test the audited Metal native-receiver catalog";
  if !inventory = "" then fail "missing receiver-catalog option --inventory";
  if !bridge = "" then fail "missing receiver-catalog option --bridge";
  !inventory, !bridge

let inventory_owners path =
  let value = read_file path |> Yojson.Safe.from_string in
  let symbols =
    match member_list "symbols" value with
    | Some symbols -> symbols
    | None -> fail "Metal inventory symbols field must be a list"
  in
  List.fold_left
    (fun owners symbol ->
      let owners =
        match member_string "owner" symbol with
        | Some owner -> String_set.add owner owners
        | None -> owners
      in
      match member_string "name" symbol with
      | Some name -> String_set.add name owners
      | None -> owners)
    String_set.empty symbols

let find_substring ~needle source =
  let needle_length = String.length needle in
  let source_length = String.length source in
  let rec search index =
    if index + needle_length > source_length then None
    else if String.sub source index needle_length = needle then Some index
    else search (index + 1)
  in
  if needle_length = 0 then Some 0 else search 0

let substring_between ~opening ~closing source =
  let opening_start =
    match find_substring ~needle:opening source with
    | Some index -> index + String.length opening
    | None -> fail "Metal bridge has no %s declaration" opening
  in
  let suffix =
    String.sub source opening_start (String.length source - opening_start)
  in
  let closing_start =
    match find_substring ~needle:closing suffix with
    | Some index -> index
    | None -> fail "Metal bridge %s declaration is unterminated" opening
  in
  String.sub suffix 0 closing_start

let handle_kinds bridge =
  substring_between ~opening:"enum class Handle_kind : std::uint32_t {"
    ~closing:"};" bridge
  |> String.split_on_char '\n'
  |> List.filter_map (fun line ->
    let line = String.trim line in
    if line = "" then None
    else
      let line =
        if String.ends_with ~suffix:"," line then
          String.sub line 0 (String.length line - 1)
        else line
      in
      let name =
        match String.index_opt line '=' with
        | Some index -> String.sub line 0 index |> String.trim
        | None -> line
      in
      if name = "" then fail "empty Metal Handle_kind enumerator";
      Some name)
  |> String_set.of_list

let require_bridge_evidence bridge
    (receiver : Binding_receiver_catalog.receiver) =
  let require needle description =
    if not (contains ~needle bridge) then
      fail "Metal receiver %s lacks %s evidence %S" receiver.sdk_owner
        description needle
  in
  match receiver.bridge_access with
  | Object_of_handle -> require "object_of_handle(" "direct object recovery"
  | Object_of_helper helper -> require (helper ^ "(") "helper recovery"
  | Wrapped_property { wrapper_type; property } ->
      require wrapper_type "wrapper type";
      require property "wrapper property"

let check_catalog inventory bridge =
  Binding_receiver_catalog.validate ();
  let owners = inventory_owners inventory in
  let bridge = read_file bridge in
  let actual_handle_kinds = handle_kinds bridge in
  let catalog_handle_kinds =
    List.map
      (fun (receiver : Binding_receiver_catalog.receiver) ->
        receiver.handle_kind)
      Binding_receiver_catalog.receivers
    @ List.map
        (fun (exclusion : Binding_receiver_catalog.exclusion) ->
          exclusion.handle_kind)
        Binding_receiver_catalog.exclusions
    |> String_set.of_list
  in
  (if String_set.equal actual_handle_kinds catalog_handle_kinds then () else
     let names values = String.concat ", " (String_set.elements values) in
     fail "Metal receiver catalog does not exactly partition Handle_kind (missing: %s; stale: %s)"
       (names (String_set.diff actual_handle_kinds catalog_handle_kinds))
       (names (String_set.diff catalog_handle_kinds actual_handle_kinds)));
  List.iter
    (fun (receiver : Binding_receiver_catalog.receiver) ->
      if not (String_set.mem receiver.sdk_owner owners) then
        fail "Metal receiver owner is absent from the pinned inventory: %s"
          receiver.sdk_owner;
      require_bridge_evidence bridge receiver)
    Binding_receiver_catalog.receivers;
  List.iter
    (fun (receiver : Binding_receiver_catalog.polymorphic_receiver) ->
      if not (String_set.mem receiver.sdk_owner owners) then
        fail
          "Metal polymorphic receiver owner is absent from the pinned inventory: %s"
          receiver.sdk_owner;
      if not (contains ~needle:(receiver.helper ^ "(") bridge) then
        fail "Metal polymorphic receiver %s lacks helper evidence"
          receiver.sdk_owner)
    Binding_receiver_catalog.polymorphic_receivers;
  Printf.printf
    "Metal receiver catalog accounts for %d Handle_kind values through %d generator mappings and %d exclusions\n%!"
    Binding_receiver_catalog.expected_handle_kind_count
    Binding_receiver_catalog.expected_catalog_count
    Binding_receiver_catalog.expected_exclusion_count

let main () =
  let inventory, bridge = parse_options () in
  check_catalog inventory bridge

let () = protect_main main
