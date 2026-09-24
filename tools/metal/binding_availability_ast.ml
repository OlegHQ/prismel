type site =
  { file : string
  ; line : int
  }

exception Error of string

let fail format = Printf.ksprintf (fun message -> raise (Error message)) format

let object_member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let object_string name value =
  match object_member name value with
  | Some (`String value) -> Some value
  | Some _ | None -> None

let line_value = function
  | `Int value -> Some value
  | `Intlit value -> int_of_string_opt value
  | _ -> None

let object_line name value = Option.bind (object_member name value) line_value

let is_availability_internal file =
  String.equal file "AvailabilityInternal.h"
  || String.ends_with ~suffix:"/AvailabilityInternal.h" file
  || String.ends_with ~suffix:"\\AvailabilityInternal.h" file

let compare_site left right =
  let by_file = String.compare left.file right.file in
  if by_file <> 0 then by_file else Int.compare left.line right.line

let equal_site left right = compare_site left right = 0

let sort_uniq_sites values =
  List.sort_uniq compare_site values

type candidate_state =
  | Absent
  | Invalid
  | Usable of site

let candidate = function
  | `Assoc fields as value ->
      let has_file = List.mem_assoc "file" fields in
      let has_line = List.mem_assoc "line" fields in
      if not has_file && not has_line then Absent
      else
        begin
          match object_string "file" value, object_line "line" value with
          | Some file, Some line
            when not (String.equal (String.trim file) "") && line > 0 ->
              Usable { file; line }
          | _ -> Invalid
        end
  | _ -> Invalid

let nested_member names value =
  List.fold_left
    (fun current name -> Option.bind current (object_member name))
    (Some value) names

let anchor_locations attribute =
  [ "loc", object_member "loc" attribute
  ; "range.begin", nested_member [ "range"; "begin" ] attribute
  ; "range.end", nested_member [ "range"; "end" ] attribute
  ]

let select_unique ~attribute_index ~kind candidates =
  let usable =
    List.fold_left
      (fun sites (path, state) ->
        match state with
        | Absent -> sites
        | Invalid ->
            fail
              "AvailabilityAttr child %d has malformed %s location at %s"
              attribute_index kind path
        | Usable site -> site :: sites)
      [] candidates
    |> sort_uniq_sites
  in
  match usable with
  | [ site ] -> Some site
  | [] -> None
  | sites ->
      let locations =
        sites
        |> List.map (fun site -> Printf.sprintf "%s:%d" site.file site.line)
        |> String.concat ", "
      in
      fail "AvailabilityAttr child %d has conflicting %s locations: %s"
        attribute_index kind locations

let explicit_locations field anchors =
  anchors
  |> List.filter_map (fun (path, anchor) ->
    match anchor with
    | None -> None
    | Some anchor ->
        Option.map
          (fun location -> path ^ "." ^ field, candidate location)
          (object_member field anchor))

let direct_locations anchors =
  anchors
  |> List.filter_map (fun (path, anchor) ->
    match anchor with
    | None -> None
    | Some location ->
        begin
          match candidate location with
          | Absent -> None
          | Invalid -> Some (path, Invalid)
          | Usable site -> Some (path, Usable site)
        end)

let reject_internal ~attribute_index ~kind site =
  if is_availability_internal site.file then
    fail
      "AvailabilityAttr child %d resolves only to internal %s location %s:%d"
      attribute_index kind site.file site.line;
  site

let site_of_attribute attribute_index attribute =
  let anchors = anchor_locations attribute in
  let expansions = explicit_locations "expansionLoc" anchors in
  if expansions <> [] then
    begin
      match select_unique ~attribute_index ~kind:"expansion" expansions with
      | Some site -> reject_internal ~attribute_index ~kind:"expansion" site
      | None ->
          fail "AvailabilityAttr child %d has no usable expansion location"
            attribute_index
    end
  else
    let direct = direct_locations anchors in
    match select_unique ~attribute_index ~kind:"direct" direct with
    | Some site -> reject_internal ~attribute_index ~kind:"direct" site
    | None ->
        let spellings = explicit_locations "spellingLoc" anchors in
        begin
          match select_unique ~attribute_index ~kind:"spelling" spellings with
          | Some site -> reject_internal ~attribute_index ~kind:"spelling" site
          | None ->
              fail "AvailabilityAttr child %d has no usable expansion location"
                attribute_index
        end

let direct_children = function
  | `Assoc fields ->
      begin
        match List.assoc_opt "inner" fields with
        | None -> []
        | Some (`List children) -> children
        | Some _ -> fail "Clang declaration has a non-list inner member"
      end
  | _ -> fail "Clang declaration is not an object"

let sites declaration =
  direct_children declaration
  |> List.mapi (fun index child -> index, child)
  |> List.filter_map (fun (index, child) ->
    match object_string "kind" child with
    | Some "AvailabilityAttr" -> Some (site_of_attribute index child)
    | Some _ | None -> None)
  |> sort_uniq_sites

let self_test () =
  let location file line =
    `Assoc [ "file", `String file; "line", `Int line ]
  in
  let macro_anchor ~spelling_file ~spelling_line ~expansion_file
      ~expansion_line =
    `Assoc
      [ "spellingLoc", location spelling_file spelling_line
      ; "expansionLoc", location expansion_file expansion_line
      ]
  in
  let range ?begin_ ?end_ () =
    let fields =
      [ Option.map (fun value -> "begin", value) begin_
      ; Option.map (fun value -> "end", value) end_
      ]
      |> List.filter_map Fun.id
    in
    `Assoc fields
  in
  let attribute fields =
    `Assoc (("kind", `String "AvailabilityAttr") :: fields)
  in
  let declaration children = `Assoc [ "inner", `List children ] in
  let internal = "/SDK/usr/include/AvailabilityInternal.h" in
  let same_macro file line =
    macro_anchor ~spelling_file:internal ~spelling_line:244
      ~expansion_file:file ~expansion_line:line
  in
  let check label expected actual =
    if
      List.length expected <> List.length actual
      || not (List.for_all2 equal_site expected actual)
    then
      let show values =
        values
        |> List.map (fun value -> Printf.sprintf "%s:%d" value.file value.line)
        |> String.concat ", "
      in
      failwith
        (Printf.sprintf "%s: expected [%s], got [%s]" label (show expected)
           (show actual))
  in
  let expect_error label declaration =
    match sites declaration with
    | exception Error _ -> ()
    | _ -> failwith (label ^ ": expected Binding_availability_ast.Error")
  in
  let site_a = { file = "/SDK/Metal/A.h"; line = 11 } in
  let site_b = { file = "/SDK/Metal/B.h"; line = 7 } in
  let range_a = same_macro site_a.file site_a.line in
  let range_b = same_macro site_b.file site_b.line in
  let representative =
    declaration
      [ attribute [ "range", range ~begin_:range_b ~end_:range_b () ]
      ; attribute [ "loc", range_a ]
      ; attribute [ "range", range ~begin_:range_a ~end_:range_a () ]
      ; `Assoc
          [ "kind", `String "Wrapper"
          ; "inner",
            `List
              [ attribute
                  [ "range", range ~begin_:range_b ~end_:range_b () ]
              ]
          ]
      ]
  in
  check "representative expansion, direct-only traversal, dedupe, and sort"
    [ site_a; site_b ] (sites representative);
  let direct_site = { file = "/SDK/Metal/Direct.h"; line = 19 } in
  check "direct range location fallback" [ direct_site ]
    (sites
       (declaration
          [ attribute
              [ "range", range ~begin_:(location direct_site.file direct_site.line) ()
              ]
          ]));
  let spelling_site = { file = "/SDK/Metal/Spelling.h"; line = 23 } in
  check "non-internal spelling fallback" [ spelling_site ]
    (sites
       (declaration
          [ attribute
              [ "range",
                range
                  ~begin_:
                    (`Assoc
                      [ "spellingLoc",
                        location spelling_site.file spelling_site.line
                      ])
                  ()
              ]
          ]));
  expect_error "missing location" (declaration [ attribute [] ]);
  expect_error "missing expansion line"
    (declaration
       [ attribute
           [ "range",
             range
               ~begin_:
                 (`Assoc
                   [ "spellingLoc", location internal 244
                   ; "expansionLoc",
                     `Assoc [ "file", `String "/SDK/Metal/Missing.h" ]
                   ])
               ()
           ]
       ]);
  expect_error "non-positive expansion line"
    (declaration
       [ attribute
           [ "loc",
             `Assoc
               [ "expansionLoc", location "/SDK/Metal/Invalid.h" 0
               ; "spellingLoc", location internal 244
               ]
           ]
       ]);
  expect_error "conflicting expansion locations"
    (declaration
       [ attribute
           [ "range",
             range
               ~begin_:(same_macro "/SDK/Metal/First.h" 3)
               ~end_:(same_macro "/SDK/Metal/Second.h" 4) ()
           ]
       ]);
  expect_error "internal spelling is not an expansion site"
    (declaration
       [ attribute
           [ "range",
             range
               ~begin_:(`Assoc [ "spellingLoc", location internal 244 ])
               ()
           ]
       ])
