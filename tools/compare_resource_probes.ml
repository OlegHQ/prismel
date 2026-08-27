let load path = Yojson.Safe.from_file path
let member name = Yojson.Safe.Util.member name
let () =
  if Array.length Sys.argv <> 3 then failwith "legacy.json next.json required";
  let legacy = load Sys.argv.(1) and next = load Sys.argv.(2) in
  let schema value = member "schema" value |> Yojson.Safe.Util.to_int in
  if schema legacy <> 1 || schema next <> 1 then failwith "probe schema mismatch";
  let report = `Assoc ["schema", `Int 1; "process_isolated", `Bool true;
    "legacy", legacy; "next", next;
    "classification", `Assoc [
      "exact_shared", `List [`String "owned image dimensions"; `String "canvas deterministic pixels";
        `String "glyph metrics"; `String "wrapped and empty text"; `String "audio lifecycle"];
      "legacy_raw_differences", `List [`String "watched image generation is not public";
        `String "encoded/PCM audio snapshots are not public"];
      "legacy_available", (match member "available" legacy with
        | `Bool value -> `Bool value | _ -> `Bool true)]] in
  Yojson.Safe.pretty_to_channel stdout report; output_char stdout '\n'
