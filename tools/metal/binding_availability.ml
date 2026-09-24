type version =
  { major : int
  ; minor : int
  ; patch : int
  }

type error =
  { offset : int
  ; message : string
  }

type site_error =
  { site_index : int
  ; error : error
  }

let compare_component left right =
  if left < right then -1 else if left > right then 1 else 0

let compare left right =
  match compare_component left.major right.major with
  | 0 ->
      (match compare_component left.minor right.minor with
      | 0 -> compare_component left.patch right.patch
      | order -> order)
  | order -> order

let equal left right = compare left right = 0

let canonical version =
  if version.patch = 0 then
    Printf.sprintf "%d.%d" version.major version.minor
  else Printf.sprintf "%d.%d.%d" version.major version.minor version.patch

let error offset message = Error { offset; message }

let is_space = function
  | ' ' | '\t' | '\n' | '\r' | '\012' -> true
  | _ -> false

let is_identifier_start = function
  | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
  | _ -> false

let is_identifier_character = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
  | _ -> false

let skip_spaces text ~limit index =
  let rec loop index =
    if index < limit && is_space text.[index] then loop (index + 1)
    else index
  in
  loop index

let trim_bounds text start finish =
  let start = skip_spaces text ~limit:finish start in
  let rec trim_finish finish =
    if finish > start && is_space text.[finish - 1] then
      trim_finish (finish - 1)
    else finish
  in
  (start, trim_finish finish)

let identifier_end text ~limit start =
  let rec loop index =
    if index < limit && is_identifier_character text.[index] then
      loop (index + 1)
    else index
  in
  loop start

let skip_quoted text ~limit ~quote start =
  let rec loop escaped index =
    if index >= limit then None
    else if escaped then loop false (index + 1)
    else
      match text.[index] with
      | '\\' -> loop true (index + 1)
      | character when character = quote -> Some (index + 1)
      | _ -> loop false (index + 1)
  in
  loop false (start + 1)

let skip_block_comment text ~limit start =
  let rec loop index =
    if index + 1 >= limit then None
    else if text.[index] = '*' && text.[index + 1] = '/' then
      Some (index + 2)
    else loop (index + 1)
  in
  loop (start + 2)

let find_matching_paren text ~limit open_index =
  let rec loop depth index =
    if index >= limit then
      error open_index "unterminated availability macro parenthesis"
    else
      match text.[index] with
      | '"' | '\'' as quote ->
          (match skip_quoted text ~limit ~quote index with
          | Some next -> loop depth next
          | None -> error index "unterminated quote in availability macro")
      | '/' when index + 1 < limit && text.[index + 1] = '*' ->
          (match skip_block_comment text ~limit index with
          | Some next -> loop depth next
          | None ->
              error index "unterminated block comment in availability macro")
      | '/' when index + 1 < limit && text.[index + 1] = '/' ->
          error index "line comment terminates availability macro"
      | '(' -> loop (depth + 1) (index + 1)
      | ')' ->
          if depth = 1 then Ok index else loop (depth - 1) (index + 1)
      | _ -> loop depth (index + 1)
  in
  loop 1 (open_index + 1)

let split_top_level text start finish =
  let rec loop depth part_start parts index =
    if index = finish then Ok (List.rev ((part_start, finish) :: parts))
    else if index > finish then
      error finish "availability argument parser crossed its boundary"
    else
      match text.[index] with
      | '"' | '\'' as quote ->
          (match skip_quoted text ~limit:finish ~quote index with
          | Some next -> loop depth part_start parts next
          | None -> error index "unterminated quote in availability arguments")
      | '/' when index + 1 < finish && text.[index + 1] = '*' ->
          (match skip_block_comment text ~limit:finish index with
          | Some next -> loop depth part_start parts next
          | None ->
              error index
                "unterminated block comment in availability arguments")
      | '/' when index + 1 < finish && text.[index + 1] = '/' ->
          error index "line comment terminates availability arguments"
      | '(' -> loop (depth + 1) part_start parts (index + 1)
      | ')' ->
          if depth = 0 then
            error index "unmatched parenthesis in availability arguments"
          else loop (depth - 1) part_start parts (index + 1)
      | ',' when depth = 0 ->
          loop depth (index + 1) ((part_start, index) :: parts) (index + 1)
      | _ -> loop depth part_start parts (index + 1)
  in
  loop 0 start [] start

let contains_identifier text ~name start finish =
  let rec loop index =
    if index >= finish then false
    else
      match text.[index] with
      | '"' | '\'' as quote ->
          (match skip_quoted text ~limit:finish ~quote index with
          | Some next -> loop next
          | None -> false)
      | '/' when index + 1 < finish && text.[index + 1] = '*' ->
          (match skip_block_comment text ~limit:finish index with
          | Some next -> loop next
          | None -> false)
      | character when is_identifier_start character ->
          let next = identifier_end text ~limit:finish index in
          if
            next - index = String.length name
            && String.sub text index (next - index) = name
          then true
          else loop next
      | _ -> loop (index + 1)
  in
  loop start

let parse_decimal_component text start finish description =
  if start >= finish || not (Char.code text.[start] >= Char.code '0'
                              && Char.code text.[start] <= Char.code '9')
  then error start ("missing " ^ description ^ " version component")
  else
    let rec find_end index =
      if
        index < finish
        && Char.code text.[index] >= Char.code '0'
        && Char.code text.[index] <= Char.code '9'
      then find_end (index + 1)
      else index
    in
    let component_end = find_end start in
    if component_end - start > 1 && text.[start] = '0' then
      error start ("non-canonical leading zero in " ^ description)
    else
      let rec accumulate value index =
        if index = component_end then Ok (value, component_end)
        else
          let digit = Char.code text.[index] - Char.code '0' in
          if value > (max_int - digit) / 10 then
            error start (description ^ " version component overflows OCaml int")
          else accumulate ((value * 10) + digit) (index + 1)
      in
      accumulate 0 start

let parse_version text start finish =
  let start, finish = trim_bounds text start finish in
  match parse_decimal_component text start finish "major" with
  | Error _ as result -> result
  | Ok (major, after_major) ->
      if major = 0 then error start "macOS major version must be positive"
      else if after_major >= finish || text.[after_major] <> '.' then
        error after_major "macOS version requires major.minor"
      else
        let minor_start = after_major + 1 in
        (match parse_decimal_component text minor_start finish "minor" with
        | Error _ as result -> result
        | Ok (minor, after_minor) ->
            if after_minor = finish then Ok { major; minor; patch = 0 }
            else if text.[after_minor] <> '.' then
              error after_minor "unexpected character after macOS minor version"
            else
              let patch_start = after_minor + 1 in
              (match
                 parse_decimal_component text patch_start finish "patch"
               with
              | Error _ as result -> result
              | Ok (patch, after_patch) ->
                  if after_patch <> finish then
                    error after_patch
                      "unexpected character after macOS patch version"
                  else Ok { major; minor; patch }))

type macro_kind =
  | Available
  | Deprecated
  | Deprecated_with_replacement
  | Unavailable

let macro_name = function
  | Available -> "API_AVAILABLE"
  | Deprecated -> "API_DEPRECATED"
  | Deprecated_with_replacement -> "API_DEPRECATED_WITH_REPLACEMENT"
  | Unavailable -> "API_UNAVAILABLE"

let parse_macos_endpoints text kind start finish =
  match split_top_level text start finish with
  | Error _ as result -> result
  | Ok endpoints ->
      (match (kind, endpoints) with
      | Available, [ introduced ] ->
          let start, finish = introduced in
          parse_version text start finish
      | (Deprecated | Deprecated_with_replacement),
        [ introduced; deprecated ] ->
          let introduced_start, introduced_finish = introduced in
          let deprecated_start, deprecated_finish = deprecated in
          (match
             parse_version text introduced_start introduced_finish
           with
          | Error _ as result -> result
          | Ok introduced ->
              (match
                 parse_version text deprecated_start deprecated_finish
               with
              | Error _ as result -> result
              | Ok deprecated ->
                  if compare deprecated introduced < 0 then
                    error deprecated_start
                      "macOS deprecation precedes its introduction"
                  else Ok introduced))
      | Available, _ ->
          error start "API_AVAILABLE macos clause requires one version"
      | (Deprecated | Deprecated_with_replacement), _ ->
          error start
            ((macro_name kind)
            ^ " macos clause requires introduced and deprecated versions")
      | Unavailable, _ ->
          error start "API_UNAVAILABLE(macos) has no introduction version")

let parse_macos_clause text kind start finish =
  let start, finish = trim_bounds text start finish in
  if start = finish || not (is_identifier_start text.[start]) then
    if contains_identifier text ~name:"macos" start finish then
      error start "malformed macos availability clause"
    else Ok None
  else
    let name_end = identifier_end text ~limit:finish start in
    let name = String.sub text start (name_end - start) in
    if not (String.equal name "macos") then
      if contains_identifier text ~name:"macos" start finish then
        error start "macos availability clause must be a top-level argument"
      else Ok None
    else
      match kind with
      | Unavailable ->
          error start "API_UNAVAILABLE(macos) has no introduction version"
      | Available | Deprecated | Deprecated_with_replacement ->
          let open_index = skip_spaces text ~limit:finish name_end in
          if open_index >= finish || text.[open_index] <> '(' then
            error open_index "expected '(' after macos availability platform"
          else
            (match find_matching_paren text ~limit:finish open_index with
            | Error _ as result -> result
            | Ok close_index ->
                let trailing =
                  skip_spaces text ~limit:finish (close_index + 1)
                in
                if trailing <> finish then
                  error trailing "unexpected text after macos availability clause"
                else
                  match
                    parse_macos_endpoints text kind (open_index + 1)
                      close_index
                  with
                  | Error _ as result -> result
                  | Ok version -> Ok (Some (version, start)))

let parse_macro text kind name_end =
  let limit = String.length text in
  let open_index = skip_spaces text ~limit name_end in
  if open_index >= limit || text.[open_index] <> '(' then
    error name_end ("expected '(' after " ^ macro_name kind)
  else
    match find_matching_paren text ~limit open_index with
    | Error _ as result -> result
    | Ok close_index ->
        (match split_top_level text (open_index + 1) close_index with
        | Error _ as result -> result
        | Ok arguments ->
            let rec find found = function
              | [] -> Ok (found, close_index + 1)
              | (start, finish) :: rest ->
                  (match parse_macos_clause text kind start finish with
                  | Error _ as result -> result
                  | Ok None -> find found rest
                  | Ok (Some (version, clause_offset)) ->
                      (match found with
                      | None -> find (Some (version, clause_offset)) rest
                      | Some _ ->
                          error clause_offset
                            ("duplicate macos clause in " ^ macro_name kind)))
            in
            find None arguments)

let kind_of_macro = function
  | "API_AVAILABLE" -> Some Available
  | "API_DEPRECATED" -> Some Deprecated
  | "API_DEPRECATED_WITH_REPLACEMENT" ->
      Some Deprecated_with_replacement
  | "API_UNAVAILABLE" -> Some Unavailable
  | _ -> None

let parse_site text =
  let limit = String.length text in
  let rec loop found index =
    if index >= limit then Ok (Option.map fst found)
    else
      match text.[index] with
      | '"' | '\'' as quote ->
          (match skip_quoted text ~limit ~quote index with
          | Some next -> loop found next
          | None -> Ok (Option.map fst found))
      | '/' when index + 1 < limit && text.[index + 1] = '*' ->
          (match skip_block_comment text ~limit index with
          | Some next -> loop found next
          | None -> Ok (Option.map fst found))
      | '/' when index + 1 < limit && text.[index + 1] = '/' ->
          Ok (Option.map fst found)
      | character when is_identifier_start character ->
          let name_end = identifier_end text ~limit index in
          let name = String.sub text index (name_end - index) in
          (match kind_of_macro name with
          | Some kind ->
              (match parse_macro text kind name_end with
              | Error _ as result -> result
              | Ok (None, next) -> loop found next
              | Ok (Some (version, clause_offset), next) ->
                  (match found with
                  | None -> loop (Some (version, clause_offset)) next
                  | Some _ ->
                      error clause_offset
                        "ambiguous duplicate macos availability clauses"))
          | None ->
              if String.equal name "macos" then
                let after_name = skip_spaces text ~limit name_end in
                if after_name < limit && text.[after_name] = '(' then
                  error index
                    "macos availability clause is outside a supported API macro"
                else loop found name_end
              else loop found name_end)
      | _ -> loop found (index + 1)
  in
  loop None 0

let maximum versions =
  List.fold_left
    (fun maximum -> function
      | None -> maximum
      | Some candidate ->
          (match maximum with
          | None -> Some candidate
          | Some current ->
              if compare candidate current > 0 then Some candidate
              else maximum))
    None versions

let combine_sites sites =
  let rec loop site_index maximum_so_far = function
    | [] -> Ok maximum_so_far
    | site :: rest ->
        (match parse_site site with
        | Error error -> Error { site_index; error }
        | Ok None -> loop (site_index + 1) maximum_so_far rest
        | Ok (Some candidate) ->
            let maximum_so_far =
              match maximum_so_far with
              | None -> Some candidate
              | Some current ->
                  if compare candidate current > 0 then Some candidate
                  else maximum_so_far
            in
            loop (site_index + 1) maximum_so_far rest)
  in
  loop 0 None sites

let fail_fixture label format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal availability fixture " ^ label ^ ": " ^ message))
    format

let expect_version label expected source =
  match parse_site source with
  | Ok (Some actual) when equal expected actual -> ()
  | Ok (Some actual) ->
      fail_fixture label "expected %s, got %s" (canonical expected)
        (canonical actual)
  | Ok None -> fail_fixture label "expected %s, got no macOS clause" (canonical expected)
  | Error error ->
      fail_fixture label "unexpected parse error at %d: %s" error.offset
        error.message

let expect_none label source =
  match parse_site source with
  | Ok None -> ()
  | Ok (Some version) ->
      fail_fixture label "expected no clause, got %s" (canonical version)
  | Error error ->
      fail_fixture label "unexpected parse error at %d: %s" error.offset
        error.message

let expect_error label source =
  match parse_site source with
  | Error _ -> ()
  | Ok None -> fail_fixture label "malformed clause was treated as absent"
  | Ok (Some version) ->
      fail_fixture label "malformed clause produced %s" (canonical version)

let require label condition =
  if not condition then fail_fixture label "condition is false"

let validate () =
  let v10_11 = { major = 10; minor = 11; patch = 0 } in
  let v10_15_4 = { major = 10; minor = 15; patch = 4 } in
  let v26 = { major = 26; minor = 0; patch = 0 } in
  expect_version "available-10.11" v10_11
    "- (void)draw API_AVAILABLE(macos(10.11), ios(8.0));";
  expect_version "available-10.15.4" v10_15_4
    "value API_AVAILABLE(ios(13.0), macos(10.15.4), tvos(16.0));";
  expect_version "available-26.0" v26
    "value API_AVAILABLE( macos ( 26.0 ) , ios(26.0) );";
  expect_version "deprecated" v10_11
    "value API_DEPRECATED(\"message\", macos(10.11, 10.14), ios(8.0, 12.0));";
  expect_version "deprecated-with-replacement" v10_15_4
    "value API_DEPRECATED_WITH_REPLACEMENT(\"replacement, macos(99.0)\", macos(10.15.4, 26.0), ios(13.4, 26.0));";
  expect_none "other-platform-only"
    "value API_AVAILABLE(ios(17.0), tvos(17.0));";
  expect_none "macro-name-in-string"
    "const char *s = \"API_AVAILABLE(macos(99.0))\";";
  expect_error "duplicate-invocation"
    "value API_AVAILABLE(macos(10.11), macos(12.0));";
  expect_error "duplicate-site"
    "value API_AVAILABLE(macos(10.11)) API_DEPRECATED(\"x\", macos(10.11, 12.0));";
  expect_error "missing-minor" "value API_AVAILABLE(macos(10));";
  expect_error "too-many-components"
    "value API_AVAILABLE(macos(10.15.4.1));";
  expect_error "empty-component" "value API_AVAILABLE(macos(10..4));";
  expect_error "leading-zero" "value API_AVAILABLE(macos(010.11));";
  expect_error "overflow"
    "value API_AVAILABLE(macos(999999999999999999999999999999.0));";
  expect_error "missing-deprecation"
    "value API_DEPRECATED(\"message\", macos(10.11));";
  expect_error "backwards-deprecation"
    "value API_DEPRECATED(\"message\", macos(14.0, 13.0));";
  expect_error "unclosed-macro" "value API_AVAILABLE(macos(10.11);";
  expect_error "unavailable-macos" "value API_UNAVAILABLE(macos);";
  expect_error "orphan-clause" "value macos(10.11);";
  require "canonical-zero-patch" (String.equal (canonical v26) "26.0");
  require "canonical-patch"
    (String.equal (canonical v10_15_4) "10.15.4");
  require "patch-order"
    (compare v10_15_4 { major = 10; minor = 15; patch = 3 } > 0);
  require "major-order"
    (compare { major = 11; minor = 0; patch = 0 }
       { major = 10; minor = 99; patch = 99 }
    > 0);
  require "maximum-order"
    (match maximum [ Some v10_11; None; Some v26; Some v10_15_4 ] with
    | Some version -> equal version v26
    | None -> false);
  (match
     combine_sites
       [ "protocol API_AVAILABLE(macos(10.11));"
       ; "owner API_AVAILABLE(ios(17.0));"
       ; "method API_AVAILABLE(macos(10.15.4));"
       ; "category API_AVAILABLE(macos(10.13));"
       ]
   with
  | Ok (Some version) -> require "combined-sites" (equal version v10_15_4)
  | Ok None -> fail_fixture "combined-sites" "expected an effective version"
  | Error site_error ->
      fail_fixture "combined-sites" "site %d failed at %d: %s"
        site_error.site_index site_error.error.offset site_error.error.message);
  (match
     combine_sites
       [ "owner API_AVAILABLE(macos(10.11));"
       ; "method API_AVAILABLE(macos(10));"
       ]
   with
  | Error { site_index = 1; _ } -> ()
  | Error site_error ->
      fail_fixture "combined-error-index" "expected site 1, got site %d"
        site_error.site_index
  | Ok _ -> fail_fixture "combined-error-index" "malformed site was accepted")

let () = validate ()
