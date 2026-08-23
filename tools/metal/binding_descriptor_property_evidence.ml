open Binding_descriptor_property_spec

type inventory_symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

let expected_promotion_count = 153
let promotion_ids =
  List.concat_map inventory_ids Binding_descriptor_property_plan.entries

let fail format = Printf.ksprintf (fun message -> invalid_arg ("Metal descriptor evidence: " ^ message)) format

let validate_inventory symbols =
  let table = Hashtbl.create (List.length symbols) in
  List.iter (fun symbol -> Hashtbl.replace table symbol.id symbol) symbols;
  List.iter
    (fun (entry : Binding_descriptor_property_spec.entry) ->
      let check id kind name signature =
        let symbol =
          match Hashtbl.find_opt table id with
          | Some value -> value
          | None -> fail "missing %s" id
        in
        if symbol.kind <> kind || symbol.owner <> Some entry.owner
           || symbol.name <> name || symbol.header <> entry.header
           || symbol.signature <> signature
           || symbol.macos_introduced <> Some entry.macos_introduced
           || symbol.attributes <> entry.attributes
        then fail "inventory drift for %s" id;
        if symbol.classification <> "unreviewed" then
          fail "expected pending declaration %s, got %s" id symbol.classification
      in
      check (property_sdk_id entry) "property" entry.name entry.signature;
      check (getter_sdk_id entry) "method" entry.name
        ("instance () -> " ^ entry.signature);
      let setter_name = "set" ^ String.init (String.length entry.name) (fun i -> if i = 0 then Char.uppercase_ascii entry.name.[i] else entry.name.[i]) ^ ":" in
      check (setter_sdk_id entry) "method" setter_name
        ("instance (" ^ entry.signature ^ ") -> void"))
    Binding_descriptor_property_plan.entries;
  if List.length promotion_ids <> expected_promotion_count then
    fail "expected %d promotion IDs, got %d" expected_promotion_count (List.length promotion_ids)
