open Support

let capture_commit = "aab2337b6aab57b453514b4171bcc44a3dcaef37"

let output_relative = "specification/evidence/gpu_migration/fixtures.json"

let environment_relative =
  "specification/evidence/gpu_migration/phase0_environment.json"

type artifact =
  { identifier : string
  ; path : string
  ; kind : string
  ; target : string
  ; comparison : string
  ; command : string
  ; expected : string
  ; ownership : string
  }

let artifacts =
  [ { identifier = "renderer-headless"
    ; path = "test/gpu_migration/golden/renderer_headless.png"
    ; kind = "png"
    ; target = "headless"
    ; comparison = "byte_exact"
    ; command =
        "PRISMEL_RENDER_TARGET=headless dune exec --profile release \
         test/gpu_baseline_renderer.exe -- <png> <trace>"
    ; expected = "640x480 RGBA8 non-interlaced PNG; exact digest"
    ; ownership =
        "Committed deterministic golden owned by renderer parity tests."
    }
  ; { identifier = "renderer-web"
    ; path = "test/gpu_migration/golden/renderer_web.png"
    ; kind = "png"
    ; target = "web"
    ; comparison = "byte_exact_and_equal_to_renderer-headless"
    ; command =
        "PRISMEL_RENDER_TARGET=web PRISMEL_WEB_PORT=0 dune exec --profile \
         release test/gpu_baseline_renderer.exe -- <png> <trace>"
    ; expected = "Exact authoritative software framebuffer shared with headless."
    ; ownership =
        "Committed deterministic golden owned by web target parity tests."
    }
  ; { identifier = "renderer-native-m1"
    ; path = "test/gpu_migration/golden/renderer_native_m1.png"
    ; kind = "png"
    ; target = "native"
    ; comparison = "frozen_native_tolerance"
    ; command =
        "PRISMEL_RENDER_TARGET=native dune exec --profile release \
         test/gpu_baseline_renderer.exe -- <png> <trace>"
    ; expected =
        "640x480 M1 SDL/OpenGL reference; repeated legacy captures are exact."
    ; ownership =
        "Committed M1 reference owned by native renderer parity tests."
    }
  ; { identifier = "renderer-headless-lifecycle"
    ; path = "test/gpu_migration/traces/renderer_headless.json"
    ; kind = "json"
    ; target = "headless"
    ; comparison = "byte_exact"
    ; command = "Emitted with renderer-headless."
    ; expected = "Ordered Canvas, capture, and Image teardown trace."
    ; ownership =
        "Committed lifecycle trace owned by renderer resource tests."
    }
  ; { identifier = "renderer-web-lifecycle"
    ; path = "test/gpu_migration/traces/renderer_web.json"
    ; kind = "json"
    ; target = "web"
    ; comparison = "byte_exact"
    ; command = "Emitted with renderer-web."
    ; expected = "Ordered Canvas, capture, and Image teardown trace."
    ; ownership = "Committed lifecycle trace owned by web resource tests."
    }
  ; { identifier = "renderer-native-m1-lifecycle"
    ; path = "test/gpu_migration/traces/renderer_native_m1.json"
    ; kind = "json"
    ; target = "native"
    ; comparison = "byte_exact"
    ; command = "Emitted with renderer-native-m1."
    ; expected = "Ordered Canvas, capture, and Image teardown trace."
    ; ownership = "Committed lifecycle trace owned by native resource tests."
    }
  ; { identifier = "audio-headless"
    ; path = "test/gpu_migration/traces/audio_headless.json"
    ; kind = "json"
    ; target = "headless"
    ; comparison = "byte_exact"
    ; command =
        "PRISMEL_RENDER_TARGET=headless dune exec --profile release \
         test/gpu_baseline_audio.exe -- <trace>"
    ; expected =
        "Sample/music play-pause-resume-stop and idempotent destruction pass."
    ; ownership =
        "Committed SDL_mixer dummy-device trace owned by audio parity tests."
    }
  ; { identifier = "web-runtime-events-audio-resources"
    ; path = "test/gpu_migration/traces/web_runtime.json"
    ; kind = "json"
    ; target = "web"
    ; comparison = "byte_exact"
    ; command =
        "PRISMEL_RENDER_TARGET=web PRISMEL_WEB_PORT=0 \
         PRISMEL_GPU_TRACE_OUTPUT=<trace> dune exec --profile release \
         test/web_runtime_smoke.exe"
    ; expected =
        "Ordered browser events, audio mirroring, and upload cleanup pass."
    ; ownership =
        "Committed transport trace owned jointly by Runtime and Wap tests."
    }
  ]

let expected_web_events =
  [ "MouseMoved(13, 17)"
  ; "MousePressed(LeftButton, (13, 17))"
  ; "MouseScrolled(0, 1)"
  ; "KeyPressed(KeyChar 'a')"
  ; "TextInput(\"A\")"
  ; "KeyReleased(KeyChar 'a')"
  ; "MouseReleased(LeftButton, (13, 17))"
  ; "WindowResized(80, 60)"
  ; "FileDropped(browser.txt)"
  ; "WindowFocusLost"
  ]

let native_tolerance =
  `Assoc
    [ "authority", `String "Frozen before any Metal-renderer output exists."
    ; "dimensions_must_match", `Bool true
    ; "pixel_format", `String "RGBA8"
    ; "mean_absolute_error_per_channel_max", `Float 1.5
    ; "pixels_with_any_rgb_error_over_16_fraction_max", `Float 0.02
    ; "alpha_mismatch_fraction_max", `Float 0.0
    ; "clear_and_axis_aligned_interior_regions", `String "exact"
    ; ( "rasterized_edges"
      , `String
          "measured by aggregate bounds above; thresholds may not be loosened" )
    ]

let string_list values = `List (List.map (fun value -> `String value) values)

let decode_rgba path =
  match Sdl3_image.load_file path with
  | Error error ->
      fail "%s: %s" path (Format.asprintf "%a" Sdl3_image.pp_error error)
  | Ok surface ->
      Fun.protect
        ~finally:(fun () -> ignore (Sdl3.Surface.destroy surface))
        (fun () ->
          match Sdl3.Surface.copy_rgba surface with
          | Error error ->
              fail "%s: %s" path (Format.asprintf "%a" Sdl3.pp_error error)
          | Ok rgba -> rgba.width, rgba.height, rgba.pixels)

let expect_boolean identifier field value =
  if member_bool field value <> Some true then
    fail "%s: %s did not pass" identifier field

let expect_last identifier field expected value message =
  let actual =
    Option.value (member_list field value) ~default:[] |> List.rev
  in
  match actual with
  | value :: _ when value = `String expected -> ()
  | _ -> fail "%s: %s" identifier message

let validate_trace identifier value =
  if member_int "schema" value <> Some 1 then
    fail "%s: invalid trace schema" identifier;
  match identifier with
  | "audio-headless" ->
      [ "sample_started"; "sample_stopped"; "music_started"; "music_stopped" ]
      |> List.iter (fun field -> expect_boolean identifier field value);
      expect_last identifier "operations" "temporary_wave.remove" value
        "temporary wave cleanup is missing"
  | "web-runtime-events-audio-resources" ->
      if member "event_order" value <> Some (string_list expected_web_events) then
        fail "%s: ordered event trace changed" identifier;
      if member "mouse_delta" value <> Some (`List [ `Int 13; `Int 17 ]) then
        fail "%s: accumulated mouse delta changed" identifier;
      expect_last identifier "resource_lifecycle" "runtime.remove_temp_file"
        value "upload cleanup trace changed"
  | identifier when has_prefix ~prefix:"renderer-" identifier ->
      if member "logical_size" value <> Some (`List [ `Int 640; `Int 480 ]) then
        fail "%s: logical size changed" identifier;
      expect_last identifier "lifecycle" "image.destroy" value
        "image teardown is missing"
  | _ -> ()

let artifact_json artifact dynamic =
  `Assoc
    ([ "id", `String artifact.identifier
     ; "path", `String artifact.path
     ; "kind", `String artifact.kind
     ; "target", `String artifact.target
     ; "comparison", `String artifact.comparison
     ; "command", `String artifact.command
     ; "expected", `String artifact.expected
     ; "ownership", `String artifact.ownership
     ]
     @ dynamic)

let required_string name value =
  match member_string name value with
  | Some value -> value
  | None -> fail "environment evidence lacks %s" name

let generate root =
  let environment =
    read_file (Filename.concat root environment_relative) |> Yojson.Safe.from_string
  in
  let hardware = member_exn "hardware" environment in
  let graphics = Option.value (member_list "graphics" hardware) ~default:[] in
  if not
       (List.exists
          (fun gpu -> member_string "model" gpu = Some "Apple M1")
          graphics)
  then fail "native reference environment is not the required M1 lane";
  let png_bytes = Hashtbl.create 3 in
  let entries =
    List.map
      (fun artifact ->
        let path = Filename.concat root artifact.path in
        if not (Sys.file_exists path) then fail "missing fixture artifact: %s" path;
        let contents = read_file path in
        let common =
          [ "bytes", `Int (String.length contents)
          ; "sha256", `String (sha256 contents)
          ]
        in
        if artifact.kind = "png" then begin
          let width, height, pixels = decode_rgba path in
          if width <> 640 || height <> 480 then
            fail "%s: expected 640x480 pixels" artifact.identifier;
          Hashtbl.replace png_bytes artifact.identifier contents;
          artifact_json artifact
            (common
             @ [ "width", `Int width
               ; "height", `Int height
               ; "pixel_sha256", `String (sha256 (Bytes.unsafe_to_string pixels))
               ])
        end
        else begin
          read_file path |> Yojson.Safe.from_string
          |> validate_trace artifact.identifier;
          artifact_json artifact common
        end)
      artifacts
  in
  if Hashtbl.find png_bytes "renderer-headless"
     <> Hashtbl.find png_bytes "renderer-web"
  then fail "headless and web authoritative PNGs are not byte-identical";
  let policy = member_exn "benchmark_policy" environment in
  `Assoc
    [ "schema", `Int 1
    ; "kind", `String "phase0_fixtures"
    ; "baseline_commit", member_exn "baseline_commit" environment
    ; "capture_commit", `String capture_commit
    ; "capture_dirty", `Bool false
    ; "profile", `String "release"
    ; "repeat_count", `Int 2
    ; "all_repeated_artifacts_byte_identical", `Bool true
    ; ( "native_environment"
      , `Assoc
          [ "machine_model", `String (required_string "machine_model" hardware)
          ; "gpu", `String "Apple M1"
          ; "os", member_exn "operating_system" environment
          ; "display", member_exn "display_scale" policy
          ] )
    ; "native_tolerance", native_tolerance
    ; "artifacts", `List entries
    ]

let main () =
  let root, mode = root_and_mode () in
  let value = generate root |> pretty_json in
  let output_path = Filename.concat root output_relative in
  match mode with
  | Write ->
      ensure_directory (Filename.dirname output_path);
      write_file output_path value;
      Printf.printf "wrote %d validated fixture records\n%!"
        (List.length artifacts)
  | Check ->
      if not (Sys.file_exists output_path) then
        fail "missing fixture manifest: %s" output_path;
      if read_file output_path <> value then
        fail
          "fixture manifest is stale; run dune exec \
           tools/gpu_migration/fixture_manifest.exe -- --write";
      print_endline "Phase 0 renderer/event/audio/resource fixtures passed"

let () = protect_main main
