let fail message = prerr_endline ("R10 adapter: " ^ message); exit 2

let () =
  let kind = ref "" and executable = ref "" and scenario = ref ""
  and target = ref "native" and profile = ref "release" and width = ref 64
  and height = ref 64 and warmup = ref 3. and seconds = ref 30. in
  Arg.parse [
    "--kind", Arg.Symbol (["native-next"; "legacy"], fun x -> kind := x), "adapter kind";
    "--executable", Arg.Set_string executable, "existing benchmark executable";
    "--scenario", Arg.Set_string scenario, "basic, pxui, canvas, or scene3";
    "--target", Arg.Symbol (["native"; "headless"; "web"], fun x -> target := x), "legacy target";
    "--profile", Arg.Set_string profile, "build profile recorded by child";
    "--width", Arg.Set_int width, "logical width";
    "--height", Arg.Set_int height, "logical height";
    "--warmup", Arg.Set_float warmup, "warmup seconds";
    "--seconds", Arg.Set_float seconds, "measurement seconds" ]
    (fun value -> fail ("unexpected argument " ^ value)) "R10 existing benchmark adapter";
  if !executable = "" || !scenario = "" || !warmup <= 0. || !seconds <= 0.
     || !width <= 0 || !height <= 0 then fail "invalid or missing arguments";
  let argv = match !kind with
    | "native-next" ->
        if !width <> 64 || !height <> 64 then
          fail "runtime-next native benchmark currently requires 64x64";
        [| !executable; !scenario; "--visibility"; "visible"; "--warmup"; "5";
           "--sample-seconds"; string_of_float !seconds |]
    | "legacy" ->
        Unix.putenv "PRISMEL_RENDER_TARGET" !target;
        Unix.putenv "PRISMEL_BENCH_PROFILE" !profile;
        Unix.putenv "PRISMEL_RENDERER_BENCH_WIDTH" (string_of_int !width);
        Unix.putenv "PRISMEL_RENDERER_BENCH_HEIGHT" (string_of_int !height);
        Unix.putenv "PRISMEL_RENDERER_BENCH_WARMUP" (string_of_float !warmup);
        Unix.putenv "PRISMEL_RENDERER_BENCH_SECONDS" (string_of_float !seconds);
        if !target = "web" then Unix.putenv "PRISMEL_WEB_PORT" "0";
        [| !executable; !scenario |]
    | _ -> fail "--kind is required" in
  Unix.execv !executable argv
