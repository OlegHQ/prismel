open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok _ -> failwith "expected Metal 4 MSAA rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "Metal 4 MSAA render safe: skipped (no device)"
  | Ok device ->
      if not (get (Device.supports_texture_sample_count device 4)) then begin
        get (Device.destroy device);
        print_endline "Metal 4 MSAA render safe: skipped (no 4x support)"
      end else
        match Command4.Allocator.create device with
        | Error error when error.kind = Unsupported || error.kind = Native_error ->
            get (Device.destroy device);
            print_endline "Metal 4 MSAA render safe: skipped (Metal 4 unavailable)"
        | Error error -> failwith (Format.asprintf "%a" pp_error error)
        | Ok allocator ->
            let command = get (Command4.Command_buffer.create allocator ()) in
            let descriptor format width height =
              Texture.descriptor_2d ~storage:Buffer.Private
                ~usage:[ Texture.Render_target ] ~format ~width ~height ()
            in
            let multisample format width height =
              { (descriptor format width height) with
                kind = Texture.Texture_2d_multisample
              ; sample_count = 4
              }
            in
            let color = get (Texture.create ~device (multisample Texture.Rgba8_unorm 4 4)) in
            let resolve = get (Texture.create ~device (descriptor Texture.Rgba8_unorm 4 4)) in
            let wrong_size = get (Texture.create ~device (descriptor Texture.Rgba8_unorm 8 4)) in
            let single = get (Texture.create ~device (descriptor Texture.Rgba8_unorm 4 4)) in
            let depth = get (Texture.create ~device (multisample Texture.Depth32_float 4 4)) in
            let single_depth = get (Texture.create ~device (descriptor Texture.Depth32_float 4 4)) in
            let attachment ?(store_action = Command4.Render_encoder.Multisample_resolve)
                ?resolve_texture texture =
              Command4.Render_encoder.color_attachment ~store_action
                ?resolve_texture texture
            in
            let before = get (Release_queue.stats ()) in
            expect Invalid_argument
              (Command4.Render_encoder.create command
                 ~color_attachments:[ attachment color ]);
            expect Invalid_argument
              (Command4.Render_encoder.create command
                 ~color_attachments:
                   [ attachment ~store_action:Command4.Render_encoder.Store
                       ~resolve_texture:resolve color ]);
            expect Invalid_argument
              (Command4.Render_encoder.create command
                 ~color_attachments:[ attachment ~resolve_texture:resolve single ]);
            expect Invalid_argument
              (Command4.Render_encoder.create command
                 ~color_attachments:[ attachment ~resolve_texture:wrong_size color ]);
            expect Invalid_argument
              (Command4.Render_encoder.create command
                 ~depth_attachment:(Command4.Render_encoder.depth_attachment single_depth)
                 ~color_attachments:[ attachment ~resolve_texture:resolve color ]);
            let after = get (Release_queue.stats ()) in
            if after.total_created <> before.total_created then
              failwith "Metal 4 MSAA typed rejections allocated native handles";
            let encoder =
              get
                (Command4.Render_encoder.create command
                   ~depth_attachment:(Command4.Render_encoder.depth_attachment depth)
                   ~color_attachments:[ attachment ~resolve_texture:resolve color ])
            in
            expect Parent_has_dependents (Texture.destroy color);
            expect Parent_has_dependents (Texture.destroy resolve);
            expect Parent_has_dependents (Texture.destroy depth);
            get (Command4.Render_encoder.end_encoding encoder);
            let deferred =
              get
                (Command4.Render_encoder.create command
                   ~color_attachments:
                     [ attachment ~store_action:Command4.Render_encoder.Store_deferred
                         ~resolve_texture:resolve color ])
            in
            get
              (Command4.Render_encoder.set_color_store_action deferred ~index:0
                 Command4.Render_encoder.Multisample_resolve);
            get (Command4.Render_encoder.end_encoding deferred);
            get (Command4.Command_buffer.end_recording command);
            get (Command4.Command_buffer.destroy command);
            List.iter (fun texture -> get (Texture.destroy texture))
              [ single_depth; depth; single; wrong_size; resolve; color ];
            get (Command4.Allocator.destroy allocator);
            get (Device.destroy device);
            ignore (get (Release_queue.drain ()));
            print_endline
              "Metal 4 MSAA render safe: fixed/deferred resolve accepted; missing, unused, single-sample, size, and depth-count mismatches rejected"
