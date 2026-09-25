open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let expect kind=function Error(e:error)when e.kind=kind->()|Error e->fail "%s"(Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"

(* A constant 2x2 image upscaled to 4x4 stays constant; mismatched sizes,
   missing usage, and destroyed scalers are rejected. *)
let run () =
  match Device.system_default () with
  | Error _ -> print_endline "metal fx safe: skipped (no device)"
  | Ok device ->
      if not (get (Fx.Spatial_scaler.supported device)) then print_endline "metal fx safe: unsupported"
      else begin
        expect Invalid_argument (Fx.Spatial_scaler.create device ~input:(4,4) ~output:(2,2)
          ~color_format:Texture.Rgba8_unorm ~output_format:Texture.Rgba8_unorm);
        let scaler=get(Fx.Spatial_scaler.create device ~input:(2,2) ~output:(4,4)
          ~color_format:Texture.Rgba8_unorm ~output_format:Texture.Rgba8_unorm)in
        if Fx.Spatial_scaler.input scaler<>(2,2)||Fx.Spatial_scaler.output scaler<>(4,4) then fail "scaler size drift";
        let color=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
          ~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:2~height:2()))in
        let output=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
          ~usage:[Texture.Shader_read;Texture.Render_target]~format:Texture.Rgba8_unorm~width:4~height:4()))in
        let unusable=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
          ~usage:[Texture.Shader_write]~format:Texture.Rgba8_unorm~width:4~height:4()))in
        let wrong=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
          ~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:3~height:2()))in
        get(Texture.write_bytes color~region:{x=0;y=0;z=0;width=2;height=2;depth=1}~mip_level:0~slice:0~bytes_per_row:8~bytes_per_image:16
          (Bytes.of_string(String.concat""(List.init 4(fun _->"\x40\x80\xc0\xff")))));
        let queue=get(Command_queue.create device)in
        let command=get(Command_buffer.create queue())in
        expect Invalid_argument(Fx.Spatial_scaler.encode scaler command~color:wrong~output);
        expect Native_error(Fx.Spatial_scaler.encode scaler command~color~output:unusable);
        let blit=get(Blit_encoder.create command)in
        expect Invalid_state(Fx.Spatial_scaler.encode scaler command~color~output);
        get(Blit_encoder.end_encoding blit);
        get(Fx.Spatial_scaler.encode scaler command~color~output);
        expect Parent_has_dependents(Fx.Spatial_scaler.destroy scaler);
        get(Command_buffer.commit command);
        get(Command_buffer.wait_until_completed command);
        let pixels=get(Texture.read_bytes output~region:{x=0;y=0;z=0;width=4;height=4;depth=1}~mip_level:0~slice:0~bytes_per_row:16~bytes_per_image:64)in
        for i=0 to 15 do
          let r=Char.code(Bytes.get pixels(i*4))and g=Char.code(Bytes.get pixels(i*4+1))and b=Char.code(Bytes.get pixels(i*4+2))in
          if abs(r-0x40)>2||abs(g-0x80)>2||abs(b-0xc0)>2 then fail "upscaled constant image drifted at pixel %d (%d %d %d)"i r g b
        done;
        get(Command_buffer.destroy command);
        get(Fx.Spatial_scaler.destroy scaler);
        expect Destroyed(Fx.Spatial_scaler.encode scaler command~color~output);
        List.iter(fun t->get(Texture.destroy t))[color;output;unusable;wrong];
        get(Command_queue.destroy queue);
        get(Device.destroy device);
        print_endline "metal fx safe: spatial upscale exact, rejections ok"
      end
