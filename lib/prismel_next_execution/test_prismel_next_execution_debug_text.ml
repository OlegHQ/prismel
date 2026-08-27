open Prismel_next_execution

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let () =
  let configuration =
    { default_configuration with logical_width=32; logical_height=32;
      drawable_width=32; drawable_height=32 }
  in
  let runtime = get (create configuration) in
  Fun.protect
    ~finally:(fun () -> ignore (destroy runtime))
    (fun () ->
      let ir = Result.get_ok (Raster2.Render_ir.create [|
        Raster2.Render_ir.Push_transform
          {xx=2.;xy=0.;yx=0.;yy=2.;tx=3.;ty=0.};
        Debug_text {x=1.;y=2.;text="A\000ignored";color=0x4080bfffl};
        Pop_transform |]) in
      let draws = get (lower_scene2 runtime ~density:1
        ~resource:(fun _ -> None) ir) in
      if List.length draws <> 1 then
        failwith "debug text must be one packed backend draw";
      ignore (get (step runtime draws));
      let actual = get (capture runtime) in
      let expected = Result.get_ok (Raster2.Surface.create ~width:32 ~height:32 ()) in
      Raster2.Surface.clear expected 0l;
      ignore (Result.get_ok (Raster2.Debug_font.draw ~target:expected
        ~blend:Raster2.Composite.Copy ~x:5 ~y:4 ~color:0x4080bfffl "A"));
      if actual <> Raster2.Surface.bytes expected then
        failwith "debug text NUL/anchor-only fixed glyph pixels";
      print_endline "prismel_next_execution resource-free debug text passed")
