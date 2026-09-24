let fail label format =
  Printf.ksprintf
    (fun message -> failwith ("Metal availability test " ^ label ^ ": " ^ message))
    format

let require label condition =
  if not condition then fail label "condition is false"

let version major minor patch : Binding_availability.version =
  { major; minor; patch }

let expect_version label expected source =
  match Binding_availability.parse_site source with
  | Ok (Some actual) when Binding_availability.equal expected actual -> ()
  | Ok (Some actual) ->
      fail label "expected %s, got %s"
        (Binding_availability.canonical expected)
        (Binding_availability.canonical actual)
  | Ok None ->
      fail label "expected %s, got no macOS availability"
        (Binding_availability.canonical expected)
  | Error error ->
      fail label "unexpected parse error at %d: %s" error.offset error.message

let expect_parse_error label source =
  match Binding_availability.parse_site source with
  | Error _ -> ()
  | Ok None -> fail label "malformed input was treated as absent"
  | Ok (Some actual) ->
      fail label "malformed input produced %s"
        (Binding_availability.canonical actual)

let expect_ast_error label declaration =
  match Binding_availability_ast.sites declaration with
  | exception Binding_availability_ast.Error _ -> ()
  | _ -> fail label "malformed AST location was accepted"

let location file line =
  `Assoc [ "file", `String file; "line", `Int line ]

let macro_location ~sdk_file ~sdk_line =
  `Assoc
    [ ( "spellingLoc"
      , location "/SDK/usr/include/AvailabilityInternal.h" 244 )
    ; "expansionLoc", location sdk_file sdk_line
    ]

let availability_attribute fields =
  `Assoc (("kind", `String "AvailabilityAttr") :: fields)

let declaration children = `Assoc [ "inner", `List children ]

let test_ast_extraction () =
  let first_file = "/SDK/Metal/MTLFirst.h" in
  let second_file = "/SDK/Metal/MTLSecond.h" in
  let first = macro_location ~sdk_file:first_file ~sdk_line:81 in
  let second = macro_location ~sdk_file:second_file ~sdk_line:17 in
  let ast =
    declaration
      [ availability_attribute
          [ "range", `Assoc [ "begin", second; "end", second ] ]
      ; availability_attribute [ "loc", first ]
      ; availability_attribute
          [ "range", `Assoc [ "begin", first; "end", first ] ]
      ; `Assoc
          [ "kind", `String "Wrapper"
          ; "inner",
            `List
              [ availability_attribute
                  [ "loc",
                    macro_location ~sdk_file:"/SDK/Metal/Nested.h"
                      ~sdk_line:999
                  ]
              ]
          ]
      ]
  in
  let expected : Binding_availability_ast.site list =
    [ { file = first_file; line = 81 }
    ; { file = second_file; line = 17 }
    ]
  in
  let actual = Binding_availability_ast.sites ast in
  require "AST expansion preference, direct traversal, dedupe, and sort"
    (actual = expected);
  expect_ast_error "AST expansion missing line"
    (declaration
       [ availability_attribute
           [ "range",
             `Assoc
               [ ( "begin"
                 , `Assoc
                     [ ( "spellingLoc"
                       , location
                           "/SDK/usr/include/AvailabilityInternal.h" 244 )
                     ; ( "expansionLoc"
                       , `Assoc
                           [ "file", `String "/SDK/Metal/MissingLine.h" ] )
                     ] )
               ]
           ]
       ]);
  expect_ast_error "AST internal spelling is not an expansion"
    (declaration
       [ availability_attribute
           [ "range",
             `Assoc
               [ ( "begin"
                 , `Assoc
                     [ ( "spellingLoc"
                       , location
                           "/SDK/usr/include/AvailabilityInternal.h" 244 )
                     ] )
               ]
           ]
       ])

let test_macro_parsing () =
  let v10_15_4 = version 10 15 4 in
  let v26 = version 26 0 0 in
  expect_version "patch introduction" v10_15_4
    "property API_AVAILABLE(ios(13.0), macos(10.15.4));";
  expect_version "current major introduction" v26
    "method API_AVAILABLE( macos ( 26.0 ), ios(26.0) );";
  expect_version "deprecated introduction" v10_15_4
    "method API_DEPRECATED(\"old\", macos(10.15.4, 26.0));";
  expect_parse_error "unavailable macOS"
    "method API_UNAVAILABLE(macos);";
  expect_parse_error "missing minor"
    "method API_AVAILABLE(macos(26));";
  expect_parse_error "duplicate macOS clause"
    "method API_AVAILABLE(macos(10.15.4), macos(26.0));";
  match
    Binding_availability.combine_sites
      [ "protocol API_AVAILABLE(macos(10.11));"
      ; "owner API_AVAILABLE(macos(10.15.4));"
      ; "category API_AVAILABLE(ios(17.0));"
      ; "method API_AVAILABLE(macos(26.0));"
      ]
  with
  | Ok (Some actual) ->
      require "inherited maximum introduction"
        (Binding_availability.equal actual v26)
  | Ok None -> fail "inherited maximum introduction" "got no version"
  | Error site_error ->
      fail "inherited maximum introduction" "site %d failed at %d: %s"
        site_error.site_index site_error.error.offset site_error.error.message

let main () =
  Binding_availability.validate ();
  Binding_availability_ast.self_test ();
  test_ast_extraction ();
  test_macro_parsing ();
  Printf.printf
    "Metal availability AST extraction and strict macro parsing passed\n%!"

let () = main ()
