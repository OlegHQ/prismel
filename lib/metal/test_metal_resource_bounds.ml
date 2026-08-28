open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect_invalid name = function
  | Error { kind = Invalid_argument; _ } -> ()
  | Error error ->
      fail "%s returned %s, expected Invalid_argument" name
        (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "%s accepted a malformed range" name

let stats_equal name before after =
  if before.Release_queue.total_created <> after.Release_queue.total_created
     || before.total_released <> after.total_released
     || before.live_handles <> after.live_handles
  then
    fail
      "%s crossed the native boundary (created %Ld -> %Ld, released %Ld -> %Ld, live %d -> %d)"
      name before.total_created after.total_created before.total_released
      after.total_released before.live_handles after.live_handles

let reject_without_native_work name operation =
  ignore (get (Release_queue.drain ()));
  ignore (get (Release_queue.drain ()));
  let before = get (Release_queue.stats ()) in
  expect_invalid name (operation ());
  let after = get (Release_queue.stats ()) in
  stats_equal name before after

let () =
  match Device.system_default () with
  | Error _ -> print_endline "Metal resource bounds: skipped (no device)"
  | Ok device ->
      let info = get (Device.info device) in
      reject_without_native_work "negative buffer length" (fun () ->
        Buffer.create ~device ~length:(-1L) ~storage:Buffer.Shared ());
      reject_without_native_work "oversized buffer length" (fun () ->
        Buffer.create ~device ~length:(Int64.succ info.max_buffer_length)
          ~storage:Buffer.Shared ());
      let buffer =
        get (Buffer.create ~device ~length:32L ~storage:Buffer.Shared ())
      in
      let bytes = Bytes.make 16 '\001' in
      [ "buffer negative source", (fun () ->
          Buffer.write_bytes buffer ~src_offset:(-1) ~dst_offset:0L bytes)
      ; "buffer source beyond bytes", (fun () ->
          Buffer.write_bytes buffer ~src_offset:17 ~dst_offset:0L bytes)
      ; "buffer negative destination", (fun () ->
          Buffer.write_bytes buffer ~dst_offset:(-1L) bytes)
      ; "buffer destination overflow", (fun () ->
          Buffer.write_bytes buffer ~dst_offset:24L bytes)
      ; "buffer destination integer overflow", (fun () ->
          Buffer.write_bytes buffer ~dst_offset:Int64.max_int bytes)
      ; "buffer negative read", (fun () ->
          Result.map ignore (Buffer.read_bytes buffer ~offset:(-1L) ~length:1))
      ; "buffer oversized read", (fun () ->
          Result.map ignore (Buffer.read_bytes buffer ~offset:31L ~length:2))
      ; "buffer integer-overflow read", (fun () ->
          Result.map ignore
            (Buffer.read_bytes buffer ~offset:Int64.max_int ~length:max_int))
      ; "mapping negative offset", (fun () ->
          Buffer.with_mapping buffer ~offset:(-1L) ~length:1 ignore)
      ; "mapping negative length", (fun () ->
          Buffer.with_mapping buffer ~offset:0L ~length:(-1) ignore)
      ; "mapping oversized range", (fun () ->
          Buffer.with_mapping buffer ~offset:31L ~length:2 ignore)
      ; "mapping integer-overflow range", (fun () ->
          Buffer.with_mapping buffer ~offset:Int64.max_int ~length:max_int ignore)
      ]
      |> List.iter (fun (name, operation) ->
        reject_without_native_work name operation);
      let texture_buffer =
        get (Buffer.create ~device ~length:4096L ~storage:Buffer.Shared ())
      in
      let descriptor =
        Texture.descriptor_2d ~storage:Buffer.Shared
          ~usage:[ Texture.Shader_read ] ~format:Texture.Rgba8_unorm ~width:4
          ~height:4 ()
      in
      let alignment =
        get
          (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_2d
             ~format:Texture.Rgba8_unorm)
      in
      let aligned_pitch =
        let row = 16L in
        let remainder = Int64.rem row alignment in
        let value =
          if remainder = 0L then row
          else Int64.add row (Int64.sub alignment remainder)
        in
        Int64.to_int value
      in
      [ "texture-buffer negative offset", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer ~offset:(-1L)
               ~bytes_per_row:aligned_pitch descriptor))
      ; "texture-buffer misaligned offset", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer ~offset:1L
               ~bytes_per_row:aligned_pitch descriptor))
      ; "texture-buffer short row pitch", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer ~offset:0L
               ~bytes_per_row:15 descriptor))
      ; "texture-buffer unaligned row pitch", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer ~offset:0L
               ~bytes_per_row:(aligned_pitch + 1) descriptor))
      ; "texture-buffer row-pitch overflow", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer ~offset:0L
               ~bytes_per_row:max_int descriptor))
      ; "texture-buffer offset overflow", (fun () ->
          Result.map ignore
            (Texture.create_from_buffer ~buffer:texture_buffer
               ~offset:Int64.max_int ~bytes_per_row:aligned_pitch descriptor))
      ]
      |> List.iter (fun (name, operation) ->
        reject_without_native_work name operation);
      get
        (Buffer.with_mapping buffer ~offset:8L ~length:8 (fun mapping ->
           [ "mapped negative read", (fun () ->
               Result.map ignore
                 (Buffer.Mapping.read_bytes mapping ~offset:(-1) ~length:1))
           ; "mapped oversized read", (fun () ->
               Result.map ignore
                 (Buffer.Mapping.read_bytes mapping ~offset:7 ~length:2))
           ; "mapped negative source", (fun () ->
               Buffer.Mapping.write_bytes mapping ~src_offset:(-1)
                 ~dst_offset:0 bytes)
           ; "mapped source beyond bytes", (fun () ->
               Buffer.Mapping.write_bytes mapping ~src_offset:17 ~dst_offset:0
                 bytes)
           ; "mapped negative destination", (fun () ->
               Buffer.Mapping.write_bytes mapping ~dst_offset:(-1) bytes)
           ; "mapped oversized destination", (fun () ->
               Buffer.Mapping.write_bytes mapping ~dst_offset:7 bytes)
           ]
           |> List.iter (fun (name, operation) ->
             reject_without_native_work name operation)));
      let page_size = get (Buffer.External.page_size ()) in
      reject_without_native_work "negative external length" (fun () ->
        Buffer.External.create ~length:(-1L));
      reject_without_native_work "unaligned external length" (fun () ->
        Buffer.External.create ~length:(Int64.of_int (page_size - 1)));
      reject_without_native_work "overflow external length" (fun () ->
        Buffer.External.create ~length:Int64.max_int);
      let external_buffer =
        get (Buffer.External.create ~length:(Int64.of_int page_size))
      in
      [ "external negative source", (fun () ->
          Buffer.External.write_bytes external_buffer ~src_offset:(-1)
            ~dst_offset:0L bytes)
      ; "external source beyond bytes", (fun () ->
          Buffer.External.write_bytes external_buffer ~src_offset:17
            ~dst_offset:0L bytes)
      ; "external negative destination", (fun () ->
          Buffer.External.write_bytes external_buffer ~dst_offset:(-1L) bytes)
      ; "external destination overflow", (fun () ->
          Buffer.External.write_bytes external_buffer
            ~dst_offset:(Int64.of_int page_size) bytes)
      ; "external destination integer overflow", (fun () ->
          Buffer.External.write_bytes external_buffer ~dst_offset:Int64.max_int
            bytes)
      ; "external negative read", (fun () ->
          Result.map ignore
            (Buffer.External.read_bytes external_buffer ~offset:(-1L) ~length:1))
      ; "external oversized read", (fun () ->
          Result.map ignore
            (Buffer.External.read_bytes external_buffer
               ~offset:(Int64.of_int (page_size - 1)) ~length:2))
      ; "external integer-overflow read", (fun () ->
          Result.map ignore
            (Buffer.External.read_bytes external_buffer ~offset:Int64.max_int
               ~length:max_int))
      ]
      |> List.iter (fun (name, operation) ->
        reject_without_native_work name operation);
      get (Buffer.External.destroy external_buffer);
      get (Buffer.destroy texture_buffer);
      get (Buffer.destroy buffer);
      get (Device.destroy device);
      ignore (get (Release_queue.drain ()));
      ignore (get (Release_queue.drain ()));
      print_endline "Metal resource bounds: pre-native rejection table passed"
