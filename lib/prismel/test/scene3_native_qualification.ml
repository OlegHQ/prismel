module P = Prismel
module Lower = Prismel__Scene3_raster2_lowering
module Description = Prismel__Scene_description
module Native = Prismel__Scene_ogpu_renderer
module Resources = Prismel__Scene3_raster2_resources

let get = function Ok value -> value | Error _ -> failwith "Scene3 qualification error"
let resources : Lower.resources = { texture=(fun _->Error Lower.Texture_error);shadow=(fun _->Error Lower.Shadow_error) }
let camera=P.Camera.orthographic~height:2.~at:(P.Vec3.create 0. 0. 2.)~target:P.Vec3.zero()
let vertices=[P.Vec3.create(-0.75)(-0.75)0.;P.Vec3.create 0.75(-0.75)0.;P.Vec3.create 0.75 0.75 0.;P.Vec3.create(-0.75)0.75 0.]
let normals=List.init 4(fun _->P.Vec3.unit_z)
let reversed=List.init 4(fun _->P.Vec3.create 0. 0.(-1.))
let sources=P.Mesh.["points",Points,[0;1;2;3];"lines",Lines,[0;1;1;2;2;3];"line-strip",Line_strip,[0;1;2;3];"line-loop",Line_loop,[0;1;2;3];"triangles",Triangles,[0;1;2;0;2;3];"triangle-strip",Triangle_strip,[0;1;3;2];"triangle-fan",Triangle_fan,[0;1;2;3]]
let modes=P.Scene3.["faces",Faces;"wireframe",Wireframe;"vertices",Vertices]
let lower scene=get(Lower.lower_view3d~resources~default_viewport:(0,0,32,32)(Description.View3d(camera,scene,Some(0,0,32,32))))
let raster (prepared:Lower.prepared)=let color=get(Raster2.Surface.create~width:32~height:32())and depth=get(Raster2.Depth_stencil.create~width:32~height:32())in let target:Raster2.Scene3_consumer.target={color;depth=Some depth;multisample=None}in get(Raster2.Scene3_consumer.render~target~clear:0x000000ffl~clear_depth:prepared.Lower.clear_depth~clear_stencil:prepared.clear_stencil~draws:prepared.draws);Bytes.copy(Raster2.Surface.bytes color)
let native runtime (prepared:Lower.prepared)=let draws=Array.to_list prepared.Lower.draws|>List.mapi(fun index draw->let rendered,state=Native.draw3 draw in let rendered={rendered with Scene_execution.state={rendered.state with depth_clear=prepared.clear_depth;depth_load=(if index=0 then Ogpu.Render_pass.Clear else Load)}}in let family=match rendered.state.stencil_state with None->Scene_execution.Scene3|Some _->Scene3_stencil in family,Native.pipeline_blend state.blend,None,None,prepared.samples,rendered)in ignore(get(Runtime_next.render_sampled_resources~clear:(0.,0.,0.,1.) runtime draws));get(Runtime_next.read_pixels runtime~bytes_per_row:128)
let mismatch a b=let count=ref 0 in for index=0 to min(Bytes.length a)(Bytes.length b)-1 do if abs(Char.code(Bytes.get a index)-Char.code(Bytes.get b index))>3 then incr count done;!count
let expected_gap _topology _mode = 0
let ()=match Runtime_next.create~width:32~height:32 with Error _->print_endline"Scene3 native qualification: skipped (no M1/Metal)"|Ok runtime->let gaps=ref[]in let qualify label golden mesh mode shading=let material=P.Material.unlit P.Color.white in let scene=P.Scene3.create[P.Scene3.with_raster(P.Scene3.raster_state~line_width:3.~point_size:5.())[P.Scene3.mesh~material~mode~cull:P.Scene3.Cull_none~shading mesh]]in let prepared=lower scene and terminal=ref None in let expected=raster prepared in for frame=1 to 600 do let actual=native runtime prepared in if List.mem frame[1;2;60;600]then let differences=mismatch expected actual in if differences<>golden then failwith(Printf.sprintf"%s frame %d parity golden changed: %d <> %d"label frame differences golden);if differences<>0 then gaps:=(label,frame,differences)::!gaps;terminal:=Some actual done;ignore!terminal in List.iter(fun(name,topology,indices)->List.iter(fun(mode_name,mode)->let mesh=P.Mesh.create_exn~mode:topology~indices~normals vertices and golden=expected_gap name mode_name in qualify(name^"/"^mode_name^"/smooth")golden mesh mode P.Scene3.Smooth;qualify(name^"/"^mode_name^"/flat")golden mesh mode P.Scene3.Flat)modes)sources;let reversed_mesh=P.Mesh.create_exn~mode:P.Mesh.Triangles~indices:[0;1;2;0;2;3]~normals:reversed vertices in qualify"triangles/faces/reversed-authored-normals"0 reversed_mesh P.Scene3.Faces P.Scene3.Smooth;get(Runtime_next.destroy runtime);if!gaps=[]then print_endline"Scene3 native qualification: all topology/mode/shading pixels match Raster2"else(List.rev!gaps|>List.iter(fun(label,frame,count)->Printf.eprintf"GAP %s frame=%d differing_channels=%d\n"label frame count);Printf.printf"Scene3 native qualification: %d stable explicit parity gaps\n"(List.length!gaps))

let shadow_native runtime (prepared : Lower.prepared) =
  let draws =
    Array.to_list prepared.draws
    |> List.mapi (fun index draw ->
      let rendered, state = Native.draw3 draw in
      let auxiliary =
        match Native.auxiliary_shadow_atlas draw.shadows with
        | Ok (Some value) -> value
        | Ok None -> failwith "missing multi-shadow atlas"
        | Error _ -> failwith "multi-shadow atlas construction failed"
      in
      let rendered =
        { rendered with
          Scene_execution.state =
            { rendered.state with
              depth_clear = prepared.clear_depth;
              depth_load = if index = 0 then Ogpu.Render_pass.Clear else Load;
              stencil_clear = prepared.clear_stencil;
              stencil_load = if index = 0 then Clear else Load } }
      in
      let family =
        match rendered.state.stencil_state with
        | None -> Scene_execution.Scene3_shadow
        | Some _ -> Scene3_shadow_stencil
      in
      (family, Native.pipeline_blend state.blend, Some Native.white_texture,
       Some auxiliary, prepared.samples, rendered))
  in
  (match
     Runtime_next.render_sampled_resources ~clear:(0., 0., 0., 1.) runtime draws
   with
  | Ok _ -> ()
  | Error error ->
      failwith
        ("multi-shadow native render failed: " ^ Ogpu.Error.to_string error));
  match Runtime_next.read_pixels runtime ~bytes_per_row:128 with
  | Ok pixels -> pixels
  | Error error ->
      failwith
        ("multi-shadow native readback failed: " ^ Ogpu.Error.to_string error)

let shadow_scene depths1 depths2 depths3 =
  let direction x y = P.Vec3.create x y (-1.) in
  let light1 = P.Light.directional ~direction:(direction 0.2 0.1) ()
  and light2 = P.Light.directional ~direction:(direction (-0.25) 0.15) ()
  and light3 = P.Light.directional ~direction:(direction 0.1 (-0.3)) ()
  and fill = P.Light.directional ~intensity:0.2 ~direction:(direction 0. 0.) () in
  let shadow filter strength bias normal_bias light width height depths =
    P.Shadow3.create ~filter ~strength ~bias ~normal_bias ~light ~camera
      ~width ~height ~depths ()
  in
  let shadows =
    [ shadow P.Shadow3.Hard 0.35 0.001 0.002 light1 2 1 depths1;
      shadow P.Shadow3.Pcf_3x3 0.65 0.003 0.004 light2 3 2 depths2;
      shadow P.Shadow3.Pcf_5x5 0.9 0.005 0.008 light3 2 3 depths3 ]
  in
  let mesh =
    P.Mesh.create_exn ~mode:P.Mesh.Triangles ~indices:[ 0; 1; 2; 0; 2; 3 ]
      ~normals vertices
  in
  let material =
    P.Material.create ~diffuse:P.Color.white ~ambient:(P.Color.gray 26)
      ~specular:P.Color.white ~shininess:16. ()
  in
  let stencil =
    P.Scene3.stencil_state ~comparison:P.Scene3.Always ~reference:3
      ~on_pass:P.Scene3.Replace ()
  in
  P.Scene3.create ~lights:[ light1; fill; light2; light3 ] ~shadows
    ~separate_specular:true
    ~fog:(P.Fog3.linear ~color:(P.Color.gray 51) ~start:0.5 ~end_:4.)
    [ P.Scene3.with_stencil stencil
        [ P.Scene3.mesh ~material ~cull:P.Scene3.Cull_none mesh ] ]

let () =
  match Runtime_next.create ~width:32 ~height:32 with
  | Error _ -> print_endline "Scene3 multi-shadow qualification: skipped"
  | Ok runtime ->
      let owned = Resources.create () in
      let shadow_resources = Resources.callbacks owned in
      let qualify scene =
        let prepared =
          match
            Lower.lower_view3d ~resources:shadow_resources
              ~default_viewport:(0, 0, 32, 32)
              (Description.View3d (camera, scene, Some (0, 0, 32, 32)))
          with
          | Ok value -> value
          | Error _ -> failwith "multi-shadow lowering failed"
        in
        let expected =
          try raster prepared
          with Failure _ -> failwith "multi-shadow Raster2 render failed"
        in
        let before = (Runtime_next.stats runtime).uploaded_bytes in
        List.iter
          (fun frame ->
            let actual = shadow_native runtime prepared in
            let differences = mismatch expected actual in
            if differences <> 0 then
              let sample bytes =
                let offset = ((16 * 32) + 16) * 4 in
                ( Char.code (Bytes.get bytes offset),
                  Char.code (Bytes.get bytes (offset + 1)),
                  Char.code (Bytes.get bytes (offset + 2)),
                  Char.code (Bytes.get bytes (offset + 3)) )
              in
              let er, eg, eb, ea = sample expected
              and ar, ag, ab, aa = sample actual in
              failwith
                (Printf.sprintf
                   "multi-shadow frame %d differs by %d channels; center expected=%d,%d,%d,%d actual=%d,%d,%d,%d"
                   frame differences er eg eb ea ar ag ab aa))
          [ 1; 2; 60; 600 ];
        let uploaded = (Runtime_next.stats runtime).uploaded_bytes in
        if uploaded <= before then failwith "multi-shadow resources not uploaded";
        ignore (shadow_native runtime prepared);
        if (Runtime_next.stats runtime).uploaded_bytes <> uploaded then
          failwith "stable multi-shadow frame reuploaded"
      in
      qualify
        (shadow_scene [| 0.2; 0.8 |]
           [| 0.1; 0.4; 0.9; 0.3; 0.7; 0.5 |]
           [| 0.2; 0.6; 0.4; 0.8; 0.3; 0.7 |]);
      qualify
        (shadow_scene [| 0.25; 0.75 |]
           [| 0.15; 0.45; 0.85; 0.35; 0.65; 0.55 |]
           [| 0.3; 0.5; 0.45; 0.75; 0.35; 0.65 |]);
      Resources.destroy owned;
      (match Runtime_next.destroy runtime with
      | Ok () -> ()
      | Error error ->
          failwith
            ("multi-shadow runtime destroy failed: " ^ Ogpu.Error.to_string error));
      print_endline
        "Scene3 multi-shadow qualification: atlas/filter/bias/reload parity"
