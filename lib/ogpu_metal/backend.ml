type resource = Buffer of Buffer.t | Texture of Texture.t

module Native_metal = Metal

module Metal = Native_metal

type icb_entry = {
  icb : Metal.Indirect_command_buffer.t;
  icb_commands : Metal.Indirect_command_buffer.Render_command.t option array;
}

type active_queue = { presentations : Surface.Private.pending_presentation array }

type table_entry = {
  table : [ `Intersection of Metal.Intersection_function_table.t | `Visible of Metal.Visible_function_table.t ];
  mutable table_handles : Metal.Function_handle.t list;
  mutable table_uses : int;
  mutable table_destroy_requested : bool;
}

(* Plan G6 objects retained by in-flight commands: destruction while used is
   deferred to the last release. *)
type 'a sync_entry = {
  native : 'a;
  mutable uses : int;
  mutable destroy_requested : bool;
  mutable dead : bool;
  finish : unit -> (unit, Ogpu_core.Error.t) result;
}

type control = {
  resources : (int64, resource) Hashtbl.t;
  heaps : (int64, Metal.Heap.t sync_entry) Hashtbl.t;
  residency : (int64, Metal.Residency_set.t sync_entry) Hashtbl.t;
  fences : (int64, Metal.Fence.t sync_entry) Hashtbl.t;
  events : (int64, Metal.Shared_event.t sync_entry) Hashtbl.t;
  samples : (int64, Metal.Resource100.Sample_buffer.t sync_entry) Hashtbl.t;
  dynamics : (int64, (Metal.Dynamic_library.t * Metal.Library.t) sync_entry) Hashtbl.t;
  archives : (int64, Metal.Binary_archive.t sync_entry) Hashtbl.t;
  upscalers : (int64, Metal.Fx.Spatial_scaler.t sync_entry) Hashtbl.t;
  pipeline_tokens : (int64, Pipeline.t) Hashtbl.t;
  tables : (int64, table_entry) Hashtbl.t;
  active_queues : (int64, active_queue) Hashtbl.t;
  libraries : (int64, Library.t) Hashtbl.t;
  accels : (int64, Acceleration.t) Hashtbl.t;
  sampler_tokens : (int64, Sampler.t) Hashtbl.t;
  icbs : (int64, icb_entry) Hashtbl.t;
  arguments : (int64, Metal.Shader_argument_encoder.t) Hashtbl.t;
  depth_states : (Ogpu_core.Backend.depth_state, Metal.Depth_stencil.t) Hashtbl.t;
  acquired_frames : (int64, Surface.t * Surface.frame) Hashtbl.t;
  mutable cleanup_error : Ogpu_core.Error.t option;
  mutable device_live : bool;
  mutable device_id : int64 option;
  mutable next : int64;
}

let error op kind text = Error (Ogpu_core.Error.make op kind text)

let token c =
  let x = c.next in
  c.next <- Int64.succ x;
  x

let pending_presentation_capacity = 3

let metal_compare = function
  | Ogpu_core.Render_pass.Never -> Metal.Depth_stencil.Never
  | Less -> Less | Equal -> Equal | Less_equal -> Less_equal | Greater -> Greater
  | Not_equal -> Not_equal | Greater_equal -> Greater_equal | Always -> Always

let metal_cull = function
  | Ogpu_core.Render_pass.Cull_none -> Metal.Render_encoder.No_cull
  | Cull_front -> Cull_front
  | Cull_back -> Cull_back

let metal_operation = function
  | Ogpu_core.Render_pass.Keep -> Metal.Depth_stencil.Keep
  | Zero -> Zero | Replace -> Replace | Increment_clamp -> Increment_clamp
  | Decrement_clamp -> Decrement_clamp | Invert -> Invert
  | Increment_wrap -> Increment_wrap | Decrement_wrap -> Decrement_wrap

let metal_stage = function
  | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.Vertex
  | Fragment -> Fragment
  | Object -> Object
  | Mesh -> Mesh
  | Tile -> Tile

let native_texture control texture =
  let device_id, token = Ogpu_core.Backend.Private.texture_driver_token texture in
  if control.device_id <> Some device_id then
    error "Ogpu_metal.Backend.native_texture" Ogpu_core.Error.Cross_device
      "texture belongs to another renderer"
  else
    match Hashtbl.find_opt control.resources token with
    | Some (Texture texture) when not (Texture.destroyed texture) ->
        Ok (Texture.Private.metal texture)
    | _ ->
        error "Ogpu_metal.Backend.native_texture" Ogpu_core.Error.Stale_handle
          "texture is unavailable"

module Private = struct
  let native_texture = native_texture
end

let create () =
  let c =
    {
      resources = Hashtbl.create 32;
      heaps = Hashtbl.create 4;
      residency = Hashtbl.create 4;
      fences = Hashtbl.create 4;
      events = Hashtbl.create 4;
      samples = Hashtbl.create 4;
      dynamics = Hashtbl.create 4;
      archives = Hashtbl.create 4;
      upscalers = Hashtbl.create 2;
      pipeline_tokens = Hashtbl.create 16;
      tables = Hashtbl.create 4;
      active_queues = Hashtbl.create 4;
      libraries = Hashtbl.create 4;
      accels = Hashtbl.create 8;
      sampler_tokens = Hashtbl.create 8;
      icbs = Hashtbl.create 8;
      arguments = Hashtbl.create 4;
      depth_states = Hashtbl.create 8;
      acquired_frames = Hashtbl.create 4;
      cleanup_error = None;
      device_live = false;
      device_id = None;
      next = 1L;
    }
  in
  let record_ogpu_cleanup error =
    if Option.is_none c.cleanup_error then c.cleanup_error <- Some error
  in
  let record_cleanup failure =
    Option.iter
      (fun error ->
        record_ogpu_cleanup (Device.of_metal_error ~operation:"Ogpu_metal.Backend.cleanup" error))
      failure
  in
  let take_cleanup_error () =
    let failure = c.cleanup_error in
    c.cleanup_error <- None;
    failure
  in
  let create_device () =
    if c.device_live then
      error "Ogpu_metal.Backend.create_device" Ogpu_core.Error.Invalid_state
        "adapter already owns a live device"
    else
      match Device.system_default () with
      | Error _ as e -> e
      | Ok device ->
          c.device_live <- true;
          c.device_id <- Some (Ogpu_core.Handle.device_id (Device.Private.handle device));
          let device_token = token c in
          let buffer_memory = function
            | Ogpu_core.Types.Shared -> Buffer.Shared
            | Ogpu_core.Types.Device_local -> Buffer.Device_local
          in
          let register_buffer created =
            match created with
            | Error _ as e -> e
            | Ok buffer ->
                let id = token c in
                Hashtbl.add c.resources id (Buffer buffer);
                let read offset length = Buffer.read_bytes device buffer ~offset ~length in
                Ok
                  {
                    Ogpu_core.Backend.token = id;
                    write =
                      (fun offset bytes ->
                        Buffer.write_bytes device buffer ~dst_offset:offset bytes);
                    read;
                    read_into =
                      (fun offset destination destination_offset length ->
                        match read offset length with
                        | Error _ as e -> e
                        | Ok bytes ->
                            if
                              destination_offset < 0
                              || length > Bytes.length destination - destination_offset
                            then
                              error "Ogpu_metal.Backend.buffer.read_into"
                                Ogpu_core.Error.Invalid_argument "destination range is invalid"
                            else (
                              Bytes.blit bytes 0 destination destination_offset length;
                              Ok ()));
                    destroy =
                      (fun () ->
                        match Buffer.destroy buffer with
                        | Error _ as e -> e
                        | Ok () ->
                            Hashtbl.remove c.resources id;
                            Ok ());
                  }
          in
          let create_buffer memory descriptor =
            register_buffer (Buffer.create device ~memory:(buffer_memory memory) descriptor)
          in
          let texture_memory ~host_read (descriptor : Ogpu_core.Types.texture_descriptor) =
            if descriptor.sample_count = 1 && host_read then Texture.Shared else Device_local
          in
          let register_texture ~host_read (descriptor : Ogpu_core.Types.texture_descriptor) created =
            match created with
            | Error _ as e -> e
            | Ok texture ->
                let id = token c in
                Hashtbl.add c.resources id (Texture texture);
                let read offset length =
                  if not host_read then
                    error "Ogpu_metal.Backend.depth.read" Ogpu_core.Error.Unsupported
                      "depth textures are not host readable"
                  else if
                    offset <> 0L || descriptor.height <= 0 || length mod descriptor.height <> 0
                  then
                    error "Ogpu_metal.Backend.texture.read" Ogpu_core.Error.Invalid_argument
                      "texture read range is invalid"
                  else
                    Texture.read_bytes device texture ~mip_level:0
                      ~bytes_per_row:(length / descriptor.height)
                in
                let read_into offset destination destination_offset length =
                  if not host_read then
                    error "Ogpu_metal.Backend.depth.read_into" Ogpu_core.Error.Unsupported
                      "depth textures are not host readable"
                  else if
                    offset <> 0L || destination_offset <> 0
                    || length <> Bytes.length destination
                    || descriptor.height <= 0
                    || length mod descriptor.height <> 0
                  then
                    error "Ogpu_metal.Backend.texture.read_into" Ogpu_core.Error.Invalid_argument
                      "destination must exactly match the texture read range"
                  else
                    Texture.read_bytes_into device texture ~mip_level:0
                      ~bytes_per_row:(length / descriptor.height) ~destination
                in
                Ok
                  {
                    Ogpu_core.Backend.token = id;
                    write =
                      (fun _ _ ->
                        error "Ogpu_metal.Backend.texture.write" Ogpu_core.Error.Unsupported
                          "use a transfer pass for textures");
                    read;
                    read_into;
                    destroy =
                      (fun () ->
                        match Texture.destroy texture with
                        | Error _ as e -> e
                        | Ok () ->
                            Hashtbl.remove c.resources id;
                            Ok ());
                  }
          in
          let create_texture_format ~format ~host_read descriptor =
            register_texture ~host_read descriptor
              (Texture.create device ~memory:(texture_memory ~host_read descriptor) ~format descriptor)
          in
          let create_texture descriptor =
            create_texture_format ~format:Texture.Rgba8_unorm ~host_read:true descriptor
          in
          let create_depth_texture descriptor =
            create_texture_format ~format:Texture.Depth32_float ~host_read:false descriptor
          in
          let create_stencil_texture descriptor =
            create_texture_format ~format:Texture.Stencil8 ~host_read:false descriptor
          in
          let native_resource token = Hashtbl.find_opt c.resources token in
          let register_sync table native native_destroy operation =
            let id = token c in
            let rec entry =
              { native; uses = 0; destroy_requested = false; dead = false; finish = (fun () -> finish ()) }
            and finish () =
              if entry.dead then Ok ()
              else
                match native_destroy native with
                | Error e -> Error (Device.of_metal_error ~operation e)
                | Ok () ->
                    entry.dead <- true;
                    Hashtbl.remove table id;
                    Ok ()
            in
            Hashtbl.add table id entry;
            (id, entry)
          in
          let sync_destroy (entry : _ sync_entry) () =
            if entry.dead then Ok ()
            else if entry.uses > 0 then begin
              entry.destroy_requested <- true;
              Ok ()
            end
            else entry.finish ()
          in
          let find_sync operation table what token =
            match Hashtbl.find_opt table token with
            | Some (entry : _ sync_entry) when not entry.dead -> Ok entry
            | _ -> error operation Ogpu_core.Error.Invalid_argument (what ^ " graph is incomplete")
          in
          let of_metal operation = function
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok x -> Ok x
          in
          let metal_device = Device.Private.metal device in
          let create_heap (descriptor : Ogpu_core.Backend.heap_descriptor) =
            let operation = "Ogpu_metal.Backend.create_heap" in
            let storage =
              match descriptor.heap_memory with
              | Ogpu_core.Types.Shared -> Metal.Buffer.Shared
              | Ogpu_core.Types.Device_local -> Metal.Buffer.Private
            in
            if descriptor.heap_sparse && descriptor.heap_memory <> Ogpu_core.Types.Device_local then
              error operation Ogpu_core.Error.Invalid_argument "sparse heaps are device-local"
            else
            let created =
              if descriptor.heap_sparse then
                  Metal.Heap.create ~device:metal_device
                    (Metal.Heap.make_descriptor ~storage ~hazard_tracking:Metal.Heap.Tracked ~kind:Metal.Heap.Sparse
                       ~sparse_page_size:Metal.Sparse_page_size.Page_16_kib ?label:descriptor.heap_label
                       ~size:descriptor.heap_size ())
              else
                Metal.Heap.create ~device:metal_device
                  (Metal.Heap.make_descriptor ~storage
                     ~hazard_tracking:(if descriptor.heap_tracked then Metal.Heap.Tracked else Metal.Heap.Untracked)
                     ~kind:Metal.Heap.Placement ?label:descriptor.heap_label ~size:descriptor.heap_size ())
            in
            match created with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok heap ->
                let id, entry = register_sync c.heaps heap Metal.Heap.destroy "Ogpu_metal.Backend.destroy_heap" in
                Ok
                  {
                    Ogpu_core.Backend.heap_token = id;
                    heap_buffer =
                      (fun ~offset buffer_descriptor ->
                        register_buffer
                          (Buffer.create_in_heap device ~memory:(buffer_memory descriptor.heap_memory) heap ~offset
                             buffer_descriptor));
                    heap_texture =
                      (fun ~offset texture_descriptor ->
                        register_texture ~host_read:(descriptor.heap_memory = Ogpu_core.Types.Shared) texture_descriptor
                          (Texture.create_in_heap device
                             ~memory:(match descriptor.heap_memory with Shared -> Texture.Shared | Device_local -> Device_local)
                             heap ~offset ~format:Texture.Rgba8_unorm texture_descriptor));
                    heap_alias =
                      (fun token ->
                        let operation = "Ogpu_metal.Backend.make_aliasable" in
                        match native_resource token with
                        | Some (Buffer buffer) -> of_metal operation (Metal.Buffer.make_aliasable (Buffer.Private.metal buffer))
                        | Some (Texture texture) -> of_metal operation (Metal.Texture.make_aliasable (Texture.Private.metal texture))
                        | None -> error operation Ogpu_core.Error.Invalid_argument "resource graph is incomplete");
                    destroy_heap = sync_destroy entry;
                  }
          in
          let heap_placement = function
            | Ogpu_core.Backend.Buffer_placement (memory, length) -> (
                let storage =
                  match memory with
                  | Ogpu_core.Types.Shared -> Metal.Buffer.Shared
                  | Ogpu_core.Types.Device_local -> Metal.Buffer.Private
                in
                match Metal.Heap.buffer_size_and_align ~device:metal_device ~length ~storage () with
                | Error e -> Error (Device.of_metal_error ~operation:"Ogpu_metal.Backend.buffer_placement" e)
                | Ok sizes -> Ok { Ogpu_core.Backend.placement_size = sizes.size; placement_alignment = sizes.alignment })
            | Texture_placement descriptor -> (
                match Texture.placement device ~memory:Texture.Device_local ~format:Texture.Rgba8_unorm descriptor with
                | Error _ as e -> e
                | Ok (size, alignment) -> Ok { Ogpu_core.Backend.placement_size = size; placement_alignment = alignment })
          in
          let residency_allocation operation = function
            | Ogpu_core.Backend.Resident_buffer token -> (
                match native_resource token with
                | Some (Buffer buffer) -> Ok (Metal.Residency_set.Buffer (Buffer.Private.metal buffer))
                | _ -> error operation Ogpu_core.Error.Invalid_argument "buffer graph is incomplete")
            | Resident_texture token -> (
                match native_resource token with
                | Some (Texture texture) -> Ok (Metal.Residency_set.Texture (Texture.Private.metal texture))
                | _ -> error operation Ogpu_core.Error.Invalid_argument "texture graph is incomplete")
            | Resident_heap token ->
                Result.map (fun (entry : _ sync_entry) -> Metal.Residency_set.Heap entry.native)
                  (find_sync operation c.heaps "heap" token)
          in
          let create_residency ~capacity ~label =
            let operation = "Ogpu_metal.Backend.create_residency_set" in
            match
              Metal.Residency_set.create ~device:metal_device
                (Metal.Residency_set.make_descriptor ?label ~initial_capacity:capacity ())
            with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok set ->
                let id, entry =
                  register_sync c.residency set Metal.Residency_set.destroy "Ogpu_metal.Backend.destroy_residency_set"
                in
                let change operation apply item =
                  match residency_allocation operation item with
                  | Error _ as e -> e
                  | Ok allocation -> of_metal operation (apply set allocation)
                in
                Ok
                  {
                    Ogpu_core.Backend.residency_token = id;
                    residency_add = change "Ogpu_metal.Backend.residency_add" Metal.Residency_set.add_allocation;
                    residency_remove = change "Ogpu_metal.Backend.residency_remove" Metal.Residency_set.remove_allocation;
                    residency_commit =
                      (fun () -> of_metal "Ogpu_metal.Backend.residency_commit" (Metal.Residency_set.commit set));
                    residency_size =
                      (fun () -> of_metal "Ogpu_metal.Backend.residency_size" (Metal.Residency_set.allocated_size set));
                    destroy_residency = sync_destroy entry;
                  }
          in
          let create_fence () =
            match Metal.Fence.create metal_device with
            | Error e -> Error (Device.of_metal_error ~operation:"Ogpu_metal.Backend.create_fence" e)
            | Ok fence ->
                let id, entry = register_sync c.fences fence Metal.Fence.destroy "Ogpu_metal.Backend.destroy_fence" in
                Ok { Ogpu_core.Backend.fence_token = id; destroy_fence = sync_destroy entry }
          in
          let create_event () =
            match Metal.Device.new_shared_event metal_device with
            | Error e -> Error (Device.of_metal_error ~operation:"Ogpu_metal.Backend.create_event" e)
            | Ok event ->
                let id, entry =
                  register_sync c.events event Metal.Shared_event.destroy "Ogpu_metal.Backend.destroy_event"
                in
                Ok
                  {
                    Ogpu_core.Backend.event_token = id;
                    event_value =
                      (fun () -> of_metal "Ogpu_metal.Backend.event_value" (Metal.Shared_event.signaled_value event));
                    event_signal =
                      (fun value ->
                        of_metal "Ogpu_metal.Backend.signal_event" (Metal.Shared_event.set_signaled_value event value));
                    event_wait =
                      (fun value ~timeout_ms ->
                        of_metal "Ogpu_metal.Backend.wait_event"
                          (Metal.Shared_event.wait_until_signaled event ~value ~timeout_ms:(Int64.of_int timeout_ms)));
                    destroy_event = sync_destroy entry;
                  }
          in
          let create_timestamps ~count =
            let operation = "Ogpu_metal.Backend.create_timestamps" in
            match Metal.Resource100.Sample_buffer.create metal_device ~sample_count:(Int64.of_int count) () with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok samples ->
                let id, entry =
                  register_sync c.samples samples Metal.Resource100.Sample_buffer.destroy
                    "Ogpu_metal.Backend.destroy_timestamps"
                in
                Ok
                  {
                    Ogpu_core.Backend.timestamps_token = id;
                    timestamps_read =
                      (fun ~first ~count ->
                        let operation = "Ogpu_metal.Backend.read_timestamps" in
                        match Metal.Counters.resolve samples ~first:(Int64.of_int first) ~count:(Int64.of_int count) with
                        | Error e -> Error (Device.of_metal_error ~operation e)
                        | Ok bytes ->
                            if Bytes.length bytes <> 8 * count then
                              error operation Ogpu_core.Error.Invalid_state
                                "resolved timestamp bytes do not match the sample count"
                            else Ok (Array.init count (fun i -> Bytes.get_int64_le bytes (i * 8))));
                    destroy_timestamps = sync_destroy entry;
                  }
          in
          let timestamp_reference () =
            let operation = "Ogpu_metal.Backend.timestamp_reference" in
            match Metal.Device.sample_timestamps metal_device with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok (cpu_nanoseconds, gpu_timestamp) -> (
                match Metal.Device.timestamp_frequency metal_device with
                | Error e -> Error (Device.of_metal_error ~operation e)
                | Ok gpu_frequency -> Ok { Ogpu_core.Backend.cpu_nanoseconds; gpu_timestamp; gpu_frequency })
          in
          let finish_table_destroy entry =
            let operation = "Ogpu_metal.Backend.destroy_table" in
            (* The table holds a dependent on every function handle it binds,
               so it goes first and releases them for destruction. *)
            let destroyed =
              match entry.table with
              | `Intersection table -> Metal.Intersection_function_table.destroy table
              | `Visible table -> Metal.Visible_function_table.destroy table
            in
            let handles = entry.table_handles in
            entry.table_handles <- [];
            let released =
              List.fold_left
                (fun result handle ->
                  match (result, Metal.Function_handle.destroy handle) with
                  | Ok (), Error e -> Error (Device.of_metal_error ~operation e)
                  | result, _ -> result)
                (Ok ()) handles
            in
            match (destroyed, released) with
            | Error e, _ -> Error (Device.of_metal_error ~operation e)
            | Ok (), (Error _ as e) -> e
            | Ok (), Ok () -> Ok ()
          in
          let create_table pipeline ~intersection ~capacity =
            let operation = "Ogpu_metal.Backend.create_table" in
            match Pipeline.Private.native pipeline with
            | Render _ ->
                error operation Ogpu_core.Error.Invalid_argument
                  "function tables belong to compute pipelines"
            | Compute compute -> (
                let created =
                  if intersection then
                    Result.map (fun t -> `Intersection t)
                      (Metal.Intersection_function_table.create ~pipeline:compute ~capacity)
                  else
                    Result.map (fun t -> `Visible t)
                      (Metal.Visible_function_table.create ~pipeline:compute ~capacity)
                in
                match created with
                | Error e -> Error (Device.of_metal_error ~operation e)
                | Ok table ->
                    let id = token c in
                    let entry =
                      { table; table_handles = []; table_uses = 0
                      ; table_destroy_requested = false }
                    in
                    Hashtbl.add c.tables id entry;
                    let handle_of name =
                      match Pipeline.Private.linked_function pipeline name with
                      | None ->
                          error operation Ogpu_core.Error.Invalid_argument
                            "function is not linked into the table's pipeline"
                      | Some function_ -> (
                          match Metal.Function_handle.create ~pipeline:compute ~function_ with
                          | Error e -> Error (Device.of_metal_error ~operation e)
                          | Ok handle ->
                              entry.table_handles <- handle :: entry.table_handles;
                              Ok handle)
                    in
                    Ok
                      {
                        Ogpu_core.Backend.table_token = id;
                        table_set_function =
                          (fun ~index name ->
                            match handle_of name with
                            | Error _ as e -> e
                            | Ok handle ->
                                let set =
                                  match table with
                                  | `Intersection t ->
                                      Metal.Intersection_function_table.set_function t ~index (Some handle)
                                  | `Visible t ->
                                      Metal.Visible_function_table.set_function t ~index (Some handle)
                                in
                                Result.map_error (Device.of_metal_error ~operation) set);
                        table_set_buffer =
                          (fun ~index buffer_token ~offset ->
                            match (table, native_resource buffer_token) with
                            | `Intersection t, Some (Buffer buffer) ->
                                Result.map_error (Device.of_metal_error ~operation)
                                  (Metal.Intersection_function_table.set_buffer t ~index ~offset
                                     (Some (Buffer.Private.metal buffer)))
                            | `Visible _, _ ->
                                error operation Ogpu_core.Error.Invalid_argument
                                  "visible function tables bind no buffers"
                            | _, _ ->
                                error operation Ogpu_core.Error.Invalid_argument
                                  "table buffer graph is incomplete");
                        destroy_table =
                          (fun () ->
                            if entry.table_uses > 0 then begin
                              entry.table_destroy_requested <- true;
                              Hashtbl.remove c.tables id;
                              Ok ()
                            end
                            else
                              match finish_table_destroy entry with
                              | Error _ as e -> e
                              | Ok () ->
                                  Hashtbl.remove c.tables id;
                                  Ok ());
                      })
          in
          let own_pipeline pipeline =
            let id = token c in
            Hashtbl.add c.pipeline_tokens id pipeline;
            Ok
              {
                Ogpu_core.Backend.pipeline_token = id;
                create_table = create_table pipeline;
                destroy_pipeline =
                  (fun () ->
                    match Pipeline.destroy pipeline with
                    | Error _ as failure -> failure
                    | Ok () ->
                        Hashtbl.remove c.pipeline_tokens id;
                        Ok ());
              }
          in
          let archive_list operation tokens =
            List.fold_left
              (fun result token ->
                match result with
                | Error _ as failure -> failure
                | Ok acc ->
                    Result.map (fun (entry : _ sync_entry) -> entry.native :: acc)
                      (find_sync operation c.archives "archive" token))
              (Ok []) tokens
            |> Result.map List.rev
          in
          let create_library shader ~dynamic =
            let operation = "Ogpu_metal.Backend.create_library" in
            let dynamic =
              List.fold_left
                (fun result token ->
                  match result with
                  | Error _ as failure -> failure
                  | Ok acc ->
                      Result.map (fun (entry : _ sync_entry) -> fst entry.native :: acc)
                        (find_sync operation c.dynamics "dynamic library" token))
                (Ok []) dynamic
              |> Result.map List.rev
            in
            match dynamic with
            | Error _ as failure -> failure
            | Ok dynamic -> (
            match Library.create ~dynamic device shader with
            | Error _ as failure -> failure
            | Ok library ->
                let id = token c in
                Hashtbl.add c.libraries id library;
                Ok
                  {
                    Ogpu_core.Backend.library_token = id;
                    create_compute_pipeline_in =
                      (fun ~entry ~constants ~interface ~linked ~archives ~archive_only ->
                        match archive_list "Ogpu_metal.Backend.create_compute_pipeline" archives with
                        | Error _ as failure -> failure
                        | Ok archives -> (
                        match
                          Pipeline.create_compute_from_library ~linked ~archives ~archive_only device library ~entry ~constants
                            ~interface
                        with
                        | Error _ as failure -> failure
                        | Ok pipeline -> own_pipeline pipeline));
                    destroy_library =
                      (fun () ->
                        match Library.destroy library with
                        | Error _ as failure -> failure
                        | Ok () ->
                            Hashtbl.remove c.libraries id;
                            Ok ());
                  })
          in
          let find_library operation token =
            match Hashtbl.find_opt c.libraries token with
            | Some library -> Ok library
            | None -> error operation Ogpu_core.Error.Invalid_argument "library graph is incomplete"
          in
          let create_mesh_pipeline (o : Ogpu_core.Backend.driver_mesh_options) =
            let operation = "Ogpu_metal.Backend.create_mesh_pipeline" in
            match (find_library operation o.mesh_library, archive_list operation o.mesh_archives) with
            | Error e, _ | _, Error e -> Error e
            | Ok library, Ok archives -> (
                match
                  Pipeline.create_mesh ?label:o.mesh_label ~blend:o.mesh_blend ~archives ~archive_only:o.mesh_archive_only device library
                    ~object_entry:o.mesh_object_entry ~mesh_entry:o.mesh_entry ~fragment_entry:o.mesh_fragment_entry
                    ~color:o.mesh_color ~mesh_threads:o.mesh_threads ~object_threads:o.object_threads
                with
                | Error _ as failure -> failure
                | Ok pipeline -> own_pipeline pipeline)
          in
          let create_tile_pipeline (o : Ogpu_core.Backend.driver_tile_options) =
            let operation = "Ogpu_metal.Backend.create_tile_pipeline" in
            match (find_library operation o.tile_library, archive_list operation o.tile_archives) with
            | Error e, _ | _, Error e -> Error e
            | Ok library, Ok archives -> (
                match
                  Pipeline.create_tile ?label:o.tile_label ~archives ~archive_only:o.tile_archive_only device library
                    ~tile_entry:o.tile_entry ~color:o.tile_color ~tile_threads:o.tile_threads
                with
                | Error _ as failure -> failure
                | Ok pipeline -> own_pipeline pipeline)
          in
          let create_dynamic_library ~install_name shader =
            let operation = "Ogpu_metal.Backend.create_dynamic_library" in
            if Ogpu_core.Shader.backend shader <> "metal" || Ogpu_core.Shader.format shader <> Ogpu_core.Shader.Msl_source then
              error operation Ogpu_core.Error.Invalid_argument "dynamic libraries compile from MSL source"
            else
              match
                Metal.Library.compile_dynamic_source ?label:(Ogpu_core.Shader.label shader) ~device:metal_device ~install_name
                  (Bytes.to_string (Ogpu_core.Shader.bytes shader))
              with
              | Error e -> Error (Device.of_metal_error ~operation e)
              | Ok source -> (
                  (* Metal resolves a pipeline's dynamic symbols from a library
                     loaded by its install name, so the compiled library is
                     serialized there (or to a temporary file for an
                     @rpath-style name) and loaded back. *)
                  let path =
                    if Filename.is_relative install_name then Filename.temp_file "prismel-dynamic" ".metallib"
                    else install_name
                  in
                  let loaded =
                    match Metal.Dynamic_library.create ?label:(Ogpu_core.Shader.label shader) source with
                    | Error _ as failure -> failure
                    | Ok compiled -> (
                        let serialized = Metal.Dynamic_library.serialize compiled path in
                        ignore (Metal.Dynamic_library.destroy compiled);
                        match serialized with
                        | Error _ as failure -> failure
                        | Ok () -> Metal.Dynamic_library.load_file ?label:(Ogpu_core.Shader.label shader) ~device:metal_device path)
                  in
                  match loaded with
                  | Error e ->
                      ignore (Metal.Library.destroy source);
                      Error (Device.of_metal_error ~operation e)
                  | Ok dynamic ->
                      let id, entry =
                        register_sync c.dynamics (dynamic, source)
                          (fun (dynamic, source) ->
                            match Metal.Dynamic_library.destroy dynamic with
                            | Error _ as failure -> failure
                            | Ok () ->
                                (try Sys.remove path with Sys_error _ -> ());
                                Metal.Library.destroy source)
                          "Ogpu_metal.Backend.destroy_dynamic_library"
                      in
                      Ok { Ogpu_core.Backend.dynamic_token = id; destroy_dynamic = sync_destroy entry })
          in
          let create_archive ~path =
            let operation = "Ogpu_metal.Backend.create_archive" in
            match Metal.Binary_archive.create ?path metal_device with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok archive ->
                let id, entry =
                  register_sync c.archives archive Metal.Binary_archive.destroy "Ogpu_metal.Backend.destroy_archive"
                in
                Ok
                  {
                    Ogpu_core.Backend.archive_token = id;
                    archive_add =
                      (fun token ->
                        let operation = "Ogpu_metal.Backend.archive_add" in
                        match Hashtbl.find_opt c.pipeline_tokens token with
                        | None -> error operation Ogpu_core.Error.Invalid_argument "pipeline graph is incomplete"
                        | Some pipeline -> (
                            let functions = Pipeline.Private.functions pipeline in
                            match (Pipeline.Private.native pipeline, functions) with
                            | Compute _, entry :: _ ->
                                of_metal operation (Metal.Binary_archive.add_compute_functions archive entry)
                            | Render native, functions -> (
                                match (Metal.Render_pipeline.kind native, Metal.Render_pipeline.color_formats native, functions) with
                                | Mesh, color_format :: _, mesh :: fragment :: _ ->
                                    of_metal operation
                                      (Metal.Binary_archive.add_mesh_render_pipeline archive ~mesh ~fragment ~color_format ())
                                | Tile, color_format :: _, tile :: _ ->
                                    of_metal operation (Metal.Binary_archive.add_tile_render_pipeline archive ~tile ~color_format)
                                | _ ->
                                    error operation Ogpu_core.Error.Unsupported
                                      "vertex/fragment render pipelines are compiled by the Metal 4 compiler and are not archived")
                            | Compute _, [] ->
                                error operation Ogpu_core.Error.Invalid_state "compute pipeline lost its entry function"));
                    archive_serialize =
                      (fun path -> of_metal "Ogpu_metal.Backend.archive_serialize" (Metal.Binary_archive.serialize archive path));
                    destroy_archive = sync_destroy entry;
                  }
          in
          let create_sparse_texture ~heap descriptor =
            let operation = "Ogpu_metal.Backend.create_sparse_texture" in
            match find_sync operation c.heaps "heap" heap with
            | Error _ as failure -> failure
            | Ok entry ->
                register_texture ~host_read:false descriptor
                  (Texture.create_sparse device entry.native ~format:Texture.Rgba8_unorm descriptor)
          in
          let texture_tile token =
            let operation = "Ogpu_metal.Backend.texture_tile" in
            match native_resource token with
            | Some (Texture texture) -> (
                match Metal.Texture.sparse_info (Texture.Private.metal texture) with
                | Error e -> Error (Device.of_metal_error ~operation e)
                | Ok None -> error operation Ogpu_core.Error.Invalid_argument "texture is not sparse"
                | Ok (Some info) -> Ok (info.tile_width, info.tile_height))
            | _ -> error operation Ogpu_core.Error.Invalid_argument "texture graph is incomplete"
          in
          let create_upscaler ~input ~output =
            let operation = "Ogpu_metal.Backend.create_upscaler" in
            match
              Metal.Fx.Spatial_scaler.create metal_device ~input ~output ~color_format:Metal.Texture.Rgba8_unorm
                ~output_format:Metal.Texture.Rgba8_unorm
            with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok scaler ->
                let id, entry =
                  register_sync c.upscalers scaler Metal.Fx.Spatial_scaler.destroy "Ogpu_metal.Backend.destroy_upscaler"
                in
                Ok { Ogpu_core.Backend.upscaler_token = id; destroy_upscaler = sync_destroy entry }
          in
          let create_accel descriptor =
            let operation = "Ogpu_metal.Backend.create_accel" in
            let resolve_buffer token =
              match native_resource token with
              | Some (Buffer buffer) -> Ok buffer
              | _ ->
                  error operation Ogpu_core.Error.Invalid_argument
                    "acceleration buffer graph is incomplete"
            in
            let resolve_structure token =
              match Hashtbl.find_opt c.accels token with
              | Some structure -> Ok structure
              | None ->
                  error operation Ogpu_core.Error.Invalid_argument
                    "acceleration structure graph is incomplete"
            in
            match Acceleration.create device descriptor ~resolve_buffer ~resolve_structure with
            | Error _ as failure -> failure
            | Ok structure ->
                let id = token c in
                Hashtbl.add c.accels id structure;
                let sizes = Acceleration.sizes structure in
                Ok
                  {
                    Ogpu_core.Backend.accel_token = id;
                    accel_sizes =
                      {
                        structure_size = sizes.acceleration_structure_size;
                        build_scratch_size = sizes.build_scratch_buffer_size;
                        refit_scratch_size = sizes.refit_scratch_buffer_size;
                      };
                    destroy_accel =
                      (fun () ->
                        match Acceleration.destroy structure with
                        | Error _ as failure -> failure
                        | Ok () ->
                            Hashtbl.remove c.accels id;
                            Ok ());
                  }
          in
          let instance_layout kind =
            let layout =
              Metal.Acceleration_structure.Build.instance_layout
                (match kind with
                 | Ogpu_core.Backend.Default_instances -> Metal.Acceleration_structure.Build.Default_instances
                 | User_id_instances -> User_id_instances
                 | Motion_instances -> Motion_instances)
            in
            [| layout.size; layout.transform; layout.options; layout.mask; layout.table_offset
             ; layout.structure_index; layout.user_id; layout.transforms_start; layout.transforms_count
             ; layout.start_border_offset; layout.end_border_offset; layout.start_time_offset
             ; layout.end_time_offset |]
          in
          let create_sampler descriptor =
            match Sampler.create device descriptor with
            | Error _ as failure -> failure
            | Ok sampler ->
                let id = token c in
                Hashtbl.add c.sampler_tokens id sampler;
                Ok
                  {
                    Ogpu_core.Backend.sampler_token = id;
                    destroy_sampler =
                      (fun () ->
                        match Sampler.destroy sampler with
                        | Error _ as failure -> failure
                        | Ok () ->
                            Hashtbl.remove c.sampler_tokens id;
                            Ok ());
                  }
          in
          let create_render_pipeline (options : Ogpu_core.Backend.render_pipeline_options)
              descriptor =
            if options.archives <> [] then
              error "Ogpu_metal.Backend.create_render_pipeline" Ogpu_core.Error.Unsupported
                "vertex/fragment render pipelines are compiled by the Metal 4 compiler and are not archived"
            else
            let primitive_topology =
              match options.topology with
              | Ogpu_core.Render_pass.Point_list -> Metal.Render_pipeline.Point
              | _ -> Metal.Render_pipeline.Triangle
            in
            match
              Pipeline.create_render_owned ~indirect:options.indirect ~primitive_topology
                ~blend:options.blend device descriptor
            with
            | Error _ as failure -> failure
            | Ok pipeline -> own_pipeline pipeline
          in
          let create_icb ~max_commands =
            let operation = "Ogpu_metal.Backend.create_icb" in
            let descriptor =
              Metal.Indirect_command_buffer.descriptor ~inherit_buffers:false
                ~inherit_pipeline_state:false ~max_vertex_buffer_bind_count:8
                ~max_fragment_buffer_bind_count:8
                ~command_types:
                  [ Metal.Indirect_command_buffer.Indirect_draw; Indirect_draw_indexed ]
                ()
            in
            match
              Metal.Indirect_command_buffer.create ~device:(Device.Private.metal device)
                ~max_command_count:max_commands descriptor
            with
            | Error e -> Error (Device.of_metal_error ~operation e)
            | Ok icb ->
                let id = token c in
                let entry = { icb; icb_commands = Array.make max_commands None } in
                Hashtbl.add c.icbs id entry;
                let native_of = function
                  | Error e -> Error (Device.of_metal_error ~operation e)
                  | Ok x -> Ok x
                in
                let command index =
                  match entry.icb_commands.(index) with
                  | Some command -> Ok command
                  | None -> (
                      match Metal.Indirect_command_buffer.Render_command.at icb index with
                      | Error e -> Error (Device.of_metal_error ~operation e)
                      | Ok command ->
                          entry.icb_commands.(index) <- Some command;
                          Ok command)
                in
                let buffer token =
                  match native_resource token with
                  | Some (Buffer buffer) -> Ok buffer
                  | _ ->
                      error operation Ogpu_core.Error.Invalid_argument
                        "buffer graph is incomplete"
                in
                let primitive = function
                  | Ogpu_core.Render_pass.Point_list ->
                      Metal.Indirect_command_buffer.Render_command.Point
                  | Line_list -> Line
                  | Triangle_list -> Triangle
                  | Triangle_strip -> Triangle_strip
                in
                Ok
                  {
                    Ogpu_core.Backend.icb_token = id;
                    icb_reset =
                      (fun ~location ~length ->
                        native_of (Metal.Indirect_command_buffer.reset icb ~location ~length));
                    icb_set_pipeline =
                      (fun ~index token ->
                        match Hashtbl.find_opt c.pipeline_tokens token with
                        | None ->
                            error operation Ogpu_core.Error.Invalid_argument
                              "pipeline graph is incomplete"
                        | Some pipeline -> (
                            match Pipeline.Private.native pipeline with
                            | Compute _ ->
                                error operation Ogpu_core.Error.Invalid_argument
                                  "compute pipeline cannot draw"
                            | Render native -> (
                                match command index with
                                | Error _ as failure -> failure
                                | Ok command ->
                                    native_of
                                      (Metal.Indirect_command_buffer.Render_command.set_pipeline
                                         command native))));
                    icb_set_buffer =
                      (fun ~index stage ~slot ~offset token ->
                        match (command index, buffer token) with
                        | Error e, _ | _, Error e -> Error e
                        | Ok command, Ok buffer ->
                            (match stage with
                             | Ogpu_core.Backend.Vertex ->
                                 native_of (Metal.Indirect_command_buffer.Render_command.set_vertex_buffer command ~index:slot ~offset (Buffer.Private.metal buffer))
                             | Fragment ->
                                 native_of (Metal.Indirect_command_buffer.Render_command.set_fragment_buffer command ~index:slot ~offset (Buffer.Private.metal buffer))
                             | Object | Mesh | Tile ->
                                 error operation Ogpu_core.Error.Unsupported "indirect commands bind vertex and fragment buffers only"));
                    icb_draw =
                      (fun ~index ~primitive:kind ~first ~count ~instances ->
                        match command index with
                        | Error _ as failure -> failure
                        | Ok command ->
                            native_of
                              (Metal.Indirect_command_buffer.Render_command.draw_primitives
                                 command ~primitive:(primitive kind) ~vertex_start:first
                                 ~vertex_count:count ~instance_count:instances ()));
                    icb_draw_indexed =
                      (fun ~index ~primitive:kind ~index_type token ~offset ~count ~instances ->
                        match (command index, buffer token) with
                        | Error e, _ | _, Error e -> Error e
                        | Ok command, Ok index_buffer ->
                            native_of
                              (Metal.Indirect_command_buffer.Render_command.draw_indexed command
                                 ~primitive:(primitive kind)
                                 ~index_type:
                                   (match index_type with
                                   | Ogpu_core.Render_pass.Uint16 -> Uint16
                                   | Uint32 -> Uint32)
                                 ~index_buffer:(Buffer.Private.metal index_buffer)
                                 ~index_offset:offset ~index_count:count
                                 ~instance_count:(Int64.of_int instances) ()));
                    destroy_icb =
                      (fun () ->
                        Array.iteri
                          (fun index command ->
                            Option.iter
                              (fun command ->
                                ignore
                                  (Metal.Indirect_command_buffer.Render_command.destroy command);
                                entry.icb_commands.(index) <- None)
                              command)
                          entry.icb_commands;
                        match Metal.Indirect_command_buffer.destroy icb with
                        | Error e -> Error (Device.of_metal_error ~operation e)
                        | Ok () ->
                            Hashtbl.remove c.icbs id;
                            Ok ());
                  }
          in
          let create_argument ~pipeline stage ~index =
            let operation = "Ogpu_metal.Backend.create_argument" in
            match Hashtbl.find_opt c.pipeline_tokens pipeline with
            | None ->
                error operation Ogpu_core.Error.Invalid_argument "pipeline graph is incomplete"
            | Some pipeline -> (
                match stage with
                | Ogpu_core.Backend.Vertex | Object | Mesh | Tile ->
                    error operation Ogpu_core.Error.Unsupported
                      "argument encoders are exposed for fragment functions"
                | Fragment -> (
                    match Pipeline.Private.argument_encoder pipeline ~buffer_index:(Int64.of_int index) with
                    | Error _ as failure -> failure
                    | Ok encoder ->
                        let id = token c in
                        Hashtbl.add c.arguments id encoder;
                        let native_of = function
                          | Error e -> Error (Device.of_metal_error ~operation e)
                          | Ok x -> Ok x
                        in
                        (* A Metal argument encoder keeps its last-set resources
                           alive; encode each slice through a short-lived
                           encoder so evicted textures can be released. *)
                        let encode buffer offset resource =
                          match native_resource buffer with
                          | Some (Buffer buffer) -> (
                              match
                                Pipeline.Private.argument_encoder pipeline
                                  ~buffer_index:(Int64.of_int index)
                              with
                              | Error _ as failure -> failure
                              | Ok scratch ->
                                  let finish result =
                                    ignore (Metal.Shader_argument_encoder.destroy scratch);
                                    native_of result
                                  in
                                  (match
                                     Metal.Shader_argument_encoder.set_argument_buffer scratch
                                       (Buffer.Private.metal buffer) ~offset ()
                                   with
                                  | Error _ as failure -> finish failure
                                  | Ok () -> finish (resource scratch)))
                          | _ ->
                              error operation Ogpu_core.Error.Invalid_argument
                                "buffer graph is incomplete"
                        in
                        Ok
                          {
                            Ogpu_core.Backend.argument_token = id;
                            argument_length =
                              Int64.to_int (Metal.Shader_argument_encoder.encoded_length encoder);
                            argument_alignment =
                              Int64.to_int (Metal.Shader_argument_encoder.alignment encoder);
                            argument_texture =
                              (fun ~buffer ~offset ~slot texture ->
                                match native_resource texture with
                                | Some (Texture texture) ->
                                    encode buffer offset (fun scratch ->
                                        Metal.Shader_argument_encoder.set scratch
                                          ~index:(Int64.of_int slot)
                                          (Metal.Shader_argument_encoder.Texture
                                             (Texture.Private.metal texture)))
                                | _ ->
                                    error operation Ogpu_core.Error.Invalid_argument
                                      "texture graph is incomplete");
                            argument_sampler =
                              (fun ~buffer ~offset ~slot sampler ->
                                match Hashtbl.find_opt c.sampler_tokens sampler with
                                | Some sampler ->
                                    encode buffer offset (fun scratch ->
                                        Metal.Shader_argument_encoder.set scratch
                                          ~index:(Int64.of_int slot)
                                          (Metal.Shader_argument_encoder.Sampler
                                             (Sampler.Private.metal sampler)))
                                | None ->
                                    error operation Ogpu_core.Error.Invalid_argument
                                      "sampler graph is incomplete");
                            destroy_argument =
                              (fun () ->
                                match Metal.Shader_argument_encoder.destroy encoder with
                                | Error e -> Error (Device.of_metal_error ~operation e)
                                | Ok () ->
                                    Hashtbl.remove c.arguments id;
                                    Ok ());
                          }))
          in
          let depth_state_for (state : Ogpu_core.Backend.depth_state) =
            let operation = "Ogpu_metal.Backend.depth_state" in
            match Hashtbl.find_opt c.depth_states state with
            | Some native -> Ok native
            | None ->
                if Hashtbl.length c.depth_states >= 64 then begin
                  Hashtbl.iter (fun _ native -> ignore (Metal.Depth_stencil.destroy native)) c.depth_states;
                  Hashtbl.reset c.depth_states
                end;
                let face (f : Ogpu_core.Render_pass.stencil_face) =
                  Metal.Depth_stencil.face ~compare:(metal_compare f.compare)
                    ~stencil_fail:(metal_operation f.stencil_fail)
                    ~depth_fail:(metal_operation f.depth_fail)
                    ~pass:(metal_operation f.pass) ~read_mask:f.read_mask
                    ~write_mask:f.write_mask ()
                in
                (match
                   Metal.Depth_stencil.create ~label:"ogpu-metal-depth-state"
                     ~depth_compare:(metal_compare state.depth_compare)
                     ~depth_write:state.depth_write
                     ?front_face:(Option.map (fun (s : Ogpu_core.Render_pass.stencil_state) -> face s.front) state.stencil)
                     ?back_face:(Option.map (fun (s : Ogpu_core.Render_pass.stencil_state) -> face s.back) state.stencil)
                     (Device.Private.metal device) ()
                 with
                 | Error e -> Error (Device.of_metal_error ~operation e)
                 | Ok native ->
                     Hashtbl.add c.depth_states state native;
                     Ok native)
          in
          let create_queue () =
            match Queue.create device with
            | Error _ as e -> e
            | Ok queue ->
                let queue_token = token c in
                let active =
                  {
                    presentations =
                      Array.init pending_presentation_capacity (fun _ ->
                          Surface.Private.create_pending_presentation ());
                  }
                in
                Hashtbl.add c.active_queues queue_token active;
                let commit_completed_epoch _epoch completion =
                  let cleanup = take_cleanup_error () in
                  match (completion, cleanup) with
                  | (Error _ as e), _ -> e
                  | Ok (), Some error -> Error error
                  | Ok (), None -> Ok ()
                in
                let complete_through epoch =
                  let waited = Queue.wait_through queue epoch in
                  let completed = Queue.completed_epoch queue in
                  Surface.Private.complete_presentations_through active.presentations completed;
                  commit_completed_epoch epoch waited
                in
                let poll_through epoch =
                  let polled = Queue.poll_through queue epoch in
                  let completed = Queue.completed_epoch queue in
                  if epoch > 0L && completed >= epoch then begin
                    Surface.Private.complete_presentations_through active.presentations completed;
                    Result.map
                      (fun () -> true)
                      (commit_completed_epoch completed (Result.map (fun _ -> ()) polled))
                  end
                  else polled
                in
                let begin_commands () =
                  let operation = "Ogpu_metal.Backend.begin_commands" in
                  let native_of = function
                    | Error e -> Error (Device.of_metal_error ~operation e)
                    | Ok x -> Ok x
                  in
                  match Metal.Command_buffer.create (Queue.Private.metal queue) () with
                  | Error e -> Error (Device.of_metal_error ~operation e)
                  | Ok native ->
                      let commands_token = token c in
                      let retained = ref [] in
                      let open_encoder : (unit -> unit) option ref = ref None in
                      let finished = ref false in
                      let keep retain release =
                        match retain () with
                        | Error _ as failure -> failure
                        | Ok () ->
                            retained := release :: !retained;
                            Ok ()
                      in
                      let keep_buffer buffer =
                        keep
                          (fun () -> Buffer.Private.retain_submission buffer)
                          (fun () -> Buffer.Private.release_submission buffer)
                      in
                      let keep_sync (entry : _ sync_entry) =
                        entry.uses <- entry.uses + 1;
                        retained :=
                          (fun () ->
                            entry.uses <- entry.uses - 1;
                            if entry.uses = 0 && entry.destroy_requested then
                              match entry.finish () with
                              | Ok () -> ()
                              | Error error -> record_ogpu_cleanup error)
                          :: !retained
                      in
                      let sampled (sampling : Ogpu_core.Backend.driver_sampling) =
                        Result.map
                          (fun (entry : _ sync_entry) ->
                            keep_sync entry;
                            (entry.native, Int64.of_int sampling.sampling_start, Int64.of_int sampling.sampling_end))
                          (find_sync operation c.samples "timestamps" sampling.sampling_token)
                      in
                      let release_later destroy =
                        retained :=
                          (fun () -> match destroy () with Ok () -> () | Error e -> record_cleanup (Some e)) :: !retained
                      in
                      let fence_call kind token call =
                        match find_sync operation c.fences "fence" token with
                        | Error _ as e -> e
                        | Ok entry ->
                            keep_sync entry;
                            native_of (call entry.native)
                        |> fun result -> ignore kind; result
                      in
                      let heap_call token call =
                        match find_sync operation c.heaps "heap" token with
                        | Error _ as e -> e
                        | Ok entry ->
                            keep_sync entry;
                            native_of (call entry.native)
                      in
                      let find_buffer token =
                        match native_resource token with
                        | Some (Buffer buffer) -> Ok buffer
                        | _ ->
                            error operation Ogpu_core.Error.Invalid_argument
                              "buffer graph is incomplete"
                      in
                      let find_accel token =
                        match Hashtbl.find_opt c.accels token with
                        | Some structure -> Ok structure
                        | None ->
                            error operation Ogpu_core.Error.Invalid_argument
                              "acceleration structure graph is incomplete"
                      in
                      let keep_accel structure =
                        match Acceleration.Private.retain_submission structure with
                        | Error _ as failure -> failure
                        | Ok release ->
                            retained := release :: !retained;
                            Ok ()
                      in
                      let recording () =
                        if !finished then
                          error operation Ogpu_core.Error.Invalid_state "commands are finished"
                        else Ok ()
                      in
                      let compute_encoder sampling =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            let created =
                              match sampling with
                              | None -> native_of (Metal.Compute_encoder.create native)
                              | Some sampling -> (
                                  match sampled sampling with
                                  | Error _ as e -> e
                                  | Ok (sample_buffer, start_index, end_index) -> (
                                      match
                                        Metal.Compute_pass.create metal_device
                                          ~attachments:[| Some { Metal.Compute_pass.sample_buffer; start_index; end_index } |] ()
                                      with
                                      | Error e -> Error (Device.of_metal_error ~operation e)
                                      | Ok pass -> (
                                          match Metal.Compute_pass.create_encoder native pass with
                                          | Error e ->
                                              ignore (Metal.Compute_pass.destroy pass);
                                              Error (Device.of_metal_error ~operation e)
                                          | Ok encoder ->
                                              release_later (fun () -> Metal.Compute_pass.destroy pass);
                                              Ok encoder)))
                            in
                            match created with
                            | Error _ as failure -> failure
                            | Ok encoder ->
                                open_encoder :=
                                  Some (fun () -> ignore (Metal.Compute_encoder.end_encoding encoder));
                                Ok
                                  {
                                    Ogpu_core.Backend.set_pipeline =
                                      (fun token ->
                                        match Hashtbl.find_opt c.pipeline_tokens token with
                                        | None ->
                                            error operation Ogpu_core.Error.Invalid_argument
                                              "pipeline graph is incomplete"
                                        | Some pipeline -> (
                                            match Pipeline.Private.native pipeline with
                                            | Render _ ->
                                                error operation Ogpu_core.Error.Invalid_argument
                                                  "render pipeline cannot execute compute"
                                            | Compute compute -> (
                                                match
                                                  keep
                                                    (fun () ->
                                                      Pipeline.Private.retain_submission pipeline)
                                                    (fun () ->
                                                      Pipeline.Private.release_submission pipeline)
                                                with
                                                | Error _ as failure -> failure
                                                | Ok () ->
                                                    native_of
                                                      (Metal.Compute_encoder.set_pipeline encoder
                                                         compute))));
                                    set_buffer =
                                      (fun ~index ~offset token ->
                                        match find_buffer token with
                                        | Error _ as failure -> failure
                                        | Ok buffer -> (
                                            match keep_buffer buffer with
                                            | Error _ as failure -> failure
                                            | Ok () ->
                                                native_of
                                                  (Metal.Compute_encoder.set_buffer encoder ~index
                                                     ~offset (Buffer.Private.metal buffer))));
                                    set_bytes =
                                      (fun ~index bytes ->
                                        native_of (Metal.Compute_encoder.set_bytes encoder ~index bytes));
                                    set_texture =
                                      (fun ~index token ->
                                        match native_resource token with
                                        | Some (Texture texture) -> (
                                            match
                                              keep
                                                (fun () -> Texture.Private.retain_submission texture)
                                                (fun () -> Texture.Private.release_submission texture)
                                            with
                                            | Error _ as failure -> failure
                                            | Ok () ->
                                                native_of
                                                  (Metal.Compute_encoder.set_texture encoder ~index
                                                     (Texture.Private.metal texture)))
                                        | _ ->
                                            error operation Ogpu_core.Error.Invalid_argument
                                              "texture graph is incomplete");
                                    set_accel =
                                      (fun ~index token ->
                                        match find_accel token with
                                        | Error _ as failure -> failure
                                        | Ok structure -> (
                                            match keep_accel structure with
                                            | Error _ as failure -> failure
                                            | Ok () ->
                                                native_of
                                                  (Metal.Compute_encoder.set_acceleration_structure
                                                     encoder ~index
                                                     (Some (Acceleration.Private.metal structure)))));
                                    set_table =
                                      (fun ~index token ->
                                        match Hashtbl.find_opt c.tables token with
                                        | None ->
                                            error operation Ogpu_core.Error.Invalid_argument
                                              "function table graph is incomplete"
                                        | Some entry -> (
                                            match
                                              keep
                                                (fun () ->
                                                  entry.table_uses <- entry.table_uses + 1;
                                                  Ok ())
                                                (fun () ->
                                                  entry.table_uses <- entry.table_uses - 1;
                                                  if entry.table_uses = 0 && entry.table_destroy_requested
                                                  then ignore (finish_table_destroy entry))
                                            with
                                            | Error _ as failure -> failure
                                            | Ok () ->
                                                native_of
                                                  (match entry.table with
                                                   | `Intersection t ->
                                                       Metal.Compute_encoder.set_intersection_function_table
                                                         encoder ~index (Some t)
                                                   | `Visible t ->
                                                       Metal.Compute_encoder.set_visible_function_table
                                                         encoder ~index (Some t))));
                                    dispatch_threads =
                                      (fun ~threads ~threadgroup ->
                                        native_of
                                          (Metal.Compute_encoder.dispatch_threads encoder ~threads
                                             ~threadgroup));
                                    dispatch_threadgroups =
                                      (fun ~threadgroups ~threadgroup ->
                                        native_of
                                          (Metal.Compute_encoder.dispatch_threadgroups encoder
                                             ~threadgroups ~threadgroup));
                                    compute_use_heap =
                                      (fun token -> heap_call token (fun heap -> Metal.Compute_encoder.use_heaps encoder [ heap ]));
                                    compute_update_fence =
                                      (fun token -> fence_call `Update token (Metal.Compute_encoder.update_fence encoder));
                                    compute_wait_fence =
                                      (fun token -> fence_call `Wait token (Metal.Compute_encoder.wait_for_fence encoder));
                                    end_compute =
                                      (fun () ->
                                        open_encoder := None;
                                        native_of (Metal.Compute_encoder.end_encoding encoder));
                                  })
                      in
                      let accel_encoder () =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match Metal.Acceleration_encoder.create native with
                            | Error e -> Error (Device.of_metal_error ~operation e)
                            | Ok encoder ->
                                open_encoder :=
                                  Some
                                    (fun () ->
                                      ignore (Metal.Acceleration_encoder.end_encoding encoder));
                                let operate encode token ~scratch ~scratch_offset =
                                  match find_accel token with
                                  | Error _ as failure -> failure
                                  | Ok structure -> (
                                      match find_buffer scratch with
                                      | Error _ as failure -> failure
                                      | Ok scratch -> (
                                          match keep_accel structure with
                                          | Error _ as failure -> failure
                                          | Ok () -> (
                                              match keep_buffer scratch with
                                              | Error _ as failure -> failure
                                              | Ok () ->
                                                  encode encoder device structure ~scratch
                                                    ~scratch_offset)))
                                in
                                let pair encode ~src ~dst =
                                  match (find_accel src, find_accel dst) with
                                  | Error e, _ | _, Error e -> Error e
                                  | Ok src, Ok dst -> (
                                      match (keep_accel src, keep_accel dst) with
                                      | Error e, _ | _, Error e -> Error e
                                      | Ok (), Ok () -> encode encoder device ~src ~dst)
                                in
                                Ok
                                  {
                                    Ogpu_core.Backend.build = operate Acceleration.encode_build;
                                    refit = operate Acceleration.encode_refit;
                                    copy = pair Acceleration.encode_copy;
                                    compact = pair Acceleration.encode_compact;
                                    write_compacted_size =
                                      (fun token ~dst ~offset ->
                                        match (find_accel token, find_buffer dst) with
                                        | Error e, _ | _, Error e -> Error e
                                        | Ok structure, Ok destination -> (
                                            match (keep_accel structure, keep_buffer destination) with
                                            | Error e, _ | _, Error e -> Error e
                                            | Ok (), Ok () ->
                                                Acceleration.encode_compacted_size encoder device
                                                  structure ~destination ~offset));
                                    end_accel =
                                      (fun () ->
                                        open_encoder := None;
                                        native_of (Metal.Acceleration_encoder.end_encoding encoder));
                                  })
                      in
                      let find_texture token =
                        match native_resource token with
                        | Some (Texture texture) -> Ok texture
                        | _ ->
                            error operation Ogpu_core.Error.Invalid_argument
                              "texture graph is incomplete"
                      in
                      let keep_texture texture =
                        keep
                          (fun () -> Texture.Private.retain_submission texture)
                          (fun () -> Texture.Private.release_submission texture)
                      in
                      let region (o : Ogpu_core.Types.origin)
                          (e : Ogpu_core.Types.extent) : Metal.Texture.region =
                        { x = o.x; y = o.y; z = o.z; width = e.width; height = e.height; depth = e.depth }
                      in
                      let blit_encoder sampling =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            let created =
                              match sampling with
                              | None -> native_of (Metal.Blit_encoder.create native)
                              | Some sampling -> (
                                  match sampled sampling with
                                  | Error _ as e -> e
                                  | Ok (sample_buffer, start_index, end_index) -> (
                                      match Metal.Blit_pass_descriptor.create metal_device with
                                      | Error e -> Error (Device.of_metal_error ~operation e)
                                      | Ok pass -> (
                                          let configured =
                                            match Metal.Blit_pass_descriptor.attachments pass with
                                            | Error _ as e -> e
                                            | Ok attachments -> (
                                                match Metal.Blit_pass_attachments.get attachments ~index:0 with
                                                | Error _ as e -> e
                                                | Ok None -> Ok None
                                                | Ok (Some attachment) ->
                                                    Result.map
                                                      (fun () -> Some (attachments, attachment))
                                                      (Metal.Blit_pass_attachment.configure attachment
                                                         ~sample_buffer:(Some sample_buffer)
                                                         ~start:(Metal.Blit_pass_attachment.Index start_index)
                                                         ~finish:(Metal.Blit_pass_attachment.Index end_index)))
                                          in
                                          let cleanup children =
                                            release_later (fun () ->
                                                let first =
                                                  match children with
                                                  | None -> Ok ()
                                                  | Some (attachments, attachment) -> (
                                                      match Metal.Blit_pass_attachment.destroy attachment with
                                                      | Error _ as e -> e
                                                      | Ok () -> Metal.Blit_pass_attachments.destroy attachments)
                                                in
                                                match first with
                                                | Error _ as e -> e
                                                | Ok () -> Metal.Blit_pass_descriptor.destroy pass)
                                          in
                                          match configured with
                                          | Error e ->
                                              ignore (Metal.Blit_pass_descriptor.destroy pass);
                                              Error (Device.of_metal_error ~operation e)
                                          | Ok None ->
                                              ignore (Metal.Blit_pass_descriptor.destroy pass);
                                              error operation Ogpu_core.Error.Invalid_state
                                                "blit pass has no sample attachment slot"
                                          | Ok children -> (
                                              match Metal.Blit_pass_descriptor.create_encoder native pass with
                                              | Error e ->
                                                  cleanup children;
                                                  Error (Device.of_metal_error ~operation e)
                                              | Ok encoder ->
                                                  cleanup children;
                                                  Ok encoder))))
                            in
                            match created with
                            | Error _ as failure -> failure
                            | Ok encoder ->
                                open_encoder :=
                                  Some (fun () -> ignore (Metal.Blit_encoder.end_encoding encoder));
                                let two_buffers src dst k =
                                  match (find_buffer src, find_buffer dst) with
                                  | Error e, _ | _, Error e -> Error e
                                  | Ok source, Ok destination -> (
                                      match (keep_buffer source, keep_buffer destination) with
                                      | Error e, _ | _, Error e -> Error e
                                      | Ok (), Ok () -> native_of (k source destination))
                                in
                                Ok
                                  {
                                    Ogpu_core.Backend.copy_buffer =
                                      (fun ~src ~src_offset ~dst ~dst_offset ~length ->
                                        two_buffers src dst (fun source destination ->
                                            Metal.Blit_encoder.copy_buffer encoder
                                              ~source:(Buffer.Private.metal source)
                                              ~source_offset:src_offset
                                              ~destination:(Buffer.Private.metal destination)
                                              ~destination_offset:dst_offset ~length));
                                    fill_buffer =
                                      (fun token ~offset ~length ~value ->
                                        match find_buffer token with
                                        | Error _ as failure -> failure
                                        | Ok buffer -> (
                                            match keep_buffer buffer with
                                            | Error _ as failure -> failure
                                            | Ok () ->
                                                native_of
                                                  (Metal.Blit_encoder.fill_buffer encoder
                                                     (Buffer.Private.metal buffer) ~offset ~length
                                                     ~byte:value)));
                                    buffer_to_texture =
                                      (fun ~src ~offset ~bytes_per_row ~bytes_per_image ~dst ~mip
                                           ~origin ~extent ->
                                        match (find_buffer src, find_texture dst) with
                                        | Error e, _ | _, Error e -> Error e
                                        | Ok source, Ok destination -> (
                                            match (keep_buffer source, keep_texture destination) with
                                            | Error e, _ | _, Error e -> Error e
                                            | Ok (), Ok () ->
                                                native_of
                                                  (Metal.Blit_encoder.copy_buffer_to_texture encoder
                                                     ~source:(Buffer.Private.metal source)
                                                     ~source_offset:offset
                                                     ~source_bytes_per_row:(Int64.to_int bytes_per_row)
                                                     ~source_bytes_per_image:
                                                       (Int64.to_int bytes_per_image)
                                                     ~destination:(Texture.Private.metal destination)
                                                     ~destination_slice:0 ~destination_level:mip
                                                     ~destination_region:(region origin extent))));
                                    texture_to_buffer =
                                      (fun ~src ~mip ~origin ~extent ~dst ~offset ~bytes_per_row
                                           ~bytes_per_image ->
                                        match (find_texture src, find_buffer dst) with
                                        | Error e, _ | _, Error e -> Error e
                                        | Ok source, Ok destination -> (
                                            match (keep_texture source, keep_buffer destination) with
                                            | Error e, _ | _, Error e -> Error e
                                            | Ok (), Ok () ->
                                                native_of
                                                  (Metal.Blit_encoder.copy_texture_to_buffer encoder
                                                     ~source:(Texture.Private.metal source)
                                                     ~source_slice:0 ~source_level:mip
                                                     ~source_region:(region origin extent)
                                                     ~destination:(Buffer.Private.metal destination)
                                                     ~destination_offset:offset
                                                     ~destination_bytes_per_row:bytes_per_row
                                                     ~destination_bytes_per_image:bytes_per_image ())));
                                    copy_texture =
                                      (fun ~src ~src_mip ~src_origin ~dst ~dst_mip ~dst_origin ~extent ->
                                        match (find_texture src, find_texture dst) with
                                        | Error e, _ | _, Error e -> Error e
                                        | Ok source, Ok destination -> (
                                            match (keep_texture source, keep_texture destination) with
                                            | Error e, _ | _, Error e -> Error e
                                            | Ok (), Ok () ->
                                                native_of
                                                  (Metal.Blit_encoder.copy_texture_region encoder
                                                     ~source:(Texture.Private.metal source)
                                                     ~source_slice:0 ~source_level:src_mip
                                                     ~source_region:(region src_origin extent)
                                                     ~destination:(Texture.Private.metal destination)
                                                     ~destination_slice:0 ~destination_level:dst_mip
                                                     ~destination_origin:
                                                       (dst_origin.x, dst_origin.y, dst_origin.z))));
                                    blit_update_fence =
                                      (fun token -> fence_call `Update token (Metal.Blit_encoder.update_fence encoder));
                                    blit_wait_fence =
                                      (fun token -> fence_call `Wait token (Metal.Blit_encoder.wait_for_fence encoder));
                                    resolve_timestamps =
                                      (fun token ~first ~count ~dst ~offset ->
                                        match (find_sync operation c.samples "timestamps" token, find_buffer dst) with
                                        | Error e, _ | _, Error e -> Error e
                                        | Ok entry, Ok destination -> (
                                            match keep_buffer destination with
                                            | Error _ as e -> e
                                            | Ok () ->
                                                keep_sync entry;
                                                native_of
                                                  (Metal.Resource100.Sample_buffer.resolve encoder entry.native
                                                     ~first:(Int64.of_int first) ~count:(Int64.of_int count)
                                                     (Buffer.Private.metal destination) ~offset)));
                                    end_blit =
                                      (fun () ->
                                        open_encoder := None;
                                        native_of (Metal.Blit_encoder.end_encoding encoder));
                                  })
                      in
                      let render_encoder sampling (target : Ogpu_core.Backend.driver_render_target) =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            let color = target.target_colors.(0) in
                            let optional f = function
                              | None -> Ok None
                              | Some token -> Result.map Option.some (f token)
                            in
                            match
                              ( find_texture color.color,
                                optional find_texture color.color_resolve,
                                optional (fun (d : Ogpu_core.Backend.driver_depth_attachment) -> find_texture d.depth) target.target_depth,
                                optional (fun (s : Ogpu_core.Backend.driver_stencil_attachment) -> find_texture s.stencil) target.target_stencil )
                            with
                            | Error e, _, _, _ | _, Error e, _, _ | _, _, Error e, _ | _, _, _, Error e -> Error e
                            | Ok color_texture, Ok resolve, Ok depth, Ok stencil -> (
                                let retained_all =
                                  List.fold_left
                                    (fun result texture ->
                                      Result.bind result (fun () -> keep_texture texture))
                                    (Ok ())
                                    (color_texture
                                    :: List.filter_map Fun.id [ resolve; depth; stencil ])
                                in
                                match retained_all with
                                | Error _ as failure -> failure
                                | Ok () -> (
                                    match
                                      Metal.Render_pass_descriptor.create ~width:target.target_width
                                        ~height:target.target_height
                                        ~sample_count:target.target_samples ()
                                    with
                                    | Error e -> Error (Device.of_metal_error ~operation e)
                                    | Ok pass -> (
                                        let fail e =
                                          ignore (Metal.Render_pass_descriptor.destroy pass);
                                          Error (Device.of_metal_error ~operation e)
                                        in
                                        let sample =
                                          match sampling with
                                          | None -> Ok None
                                          | Some sampling -> Result.map Option.some (sampled sampling)
                                        in
                                        match sample with
                                        | Error e ->
                                            ignore (Metal.Render_pass_descriptor.destroy pass);
                                            Error e
                                        | Ok sample ->
                                        let load = function
                                          | Ogpu_core.Render_pass.Dont_care ->
                                              Metal.Render_pass_descriptor.Load_dont_care
                                          | Load -> Load
                                          | Clear -> Clear
                                        and store = function
                                          | Ogpu_core.Render_pass.Store | Resolve ->
                                              Metal.Render_pass_descriptor.Store
                                          | Discard -> Store_dont_care
                                        in
                                        let configured =
                                          let ( let* ) = Result.bind in
                                          let* () =
                                            Metal.Render_pass_descriptor.set_attachments pass
                                              ~color:(Texture.Private.metal color_texture)
                                              ~clear:color.color_clear
                                              ?depth:(Option.map Texture.Private.metal depth)
                                              ?stencil:(Option.map Texture.Private.metal stencil)
                                              ()
                                          in
                                          let* () =
                                            Metal.Render_pass_descriptor.set_color_load_action pass
                                              (load color.color_load)
                                          in
                                          let* () =
                                            match resolve with
                                            | None ->
                                                Metal.Render_pass_descriptor.set_color_store_action
                                                  pass ~resolve:false
                                            | Some resolve ->
                                                let* () =
                                                  Metal.Render_pass_descriptor.set_resolve_texture
                                                    pass (Some (Texture.Private.metal resolve))
                                                in
                                                Metal.Render_pass_descriptor.set_color_store_action
                                                  pass ~resolve:true
                                          in
                                          let depth_actions =
                                            match target.target_depth with
                                            | None -> (Metal.Render_pass_descriptor.Clear, Metal.Render_pass_descriptor.Store, 1.)
                                            | Some d -> (load d.depth_load, store d.depth_store, d.depth_clear)
                                          and stencil_actions =
                                            match target.target_stencil with
                                            | None -> (Metal.Render_pass_descriptor.Clear, Metal.Render_pass_descriptor.Store, 0)
                                            | Some s -> (load s.stencil_load, store s.stencil_store, s.stencil_clear)
                                          in
                                          match
                                            Metal.Render_pass_descriptor.set_depth_stencil_actions pass
                                              ~depth:depth_actions ~stencil:stencil_actions
                                          with
                                          | Error _ as e -> e
                                          | Ok () -> (
                                              match sample with
                                              | None -> Ok ()
                                              | Some (sample_buffer, start_index, end_index) ->
                                                  (* Vertex start and fragment end bracket the pass. *)
                                                  Metal.Counters.set_render_pass_attachment pass ~index:0 sample_buffer
                                                    ~start_vertex:start_index ~end_vertex:(-1L) ~start_fragment:(-1L)
                                                    ~end_fragment:end_index)
                                        in
                                        match configured with
                                        | Error e -> fail e
                                        | Ok () -> (
                                            match
                                              Metal.Render_encoder.Private.create_from_pass_scoped native pass
                                            with
                                            | Error e -> fail e
                                            | Ok encoder ->
                                                let finish () =
                                                  open_encoder := None;
                                                  let ended = Metal.Render_encoder.end_encoding encoder in
                                                  ignore (Metal.Render_pass_descriptor.destroy pass);
                                                  native_of ended
                                                in
                                                open_encoder := Some (fun () -> ignore (finish ()));
                                                let render_pipeline token =
                                                  match Hashtbl.find_opt c.pipeline_tokens token with
                                                  | None ->
                                                      error operation Ogpu_core.Error.Invalid_argument
                                                        "pipeline graph is incomplete"
                                                  | Some pipeline -> (
                                                      match Pipeline.Private.native pipeline with
                                                      | Compute _ ->
                                                          error operation Ogpu_core.Error.Invalid_argument
                                                            "compute pipeline cannot draw"
                                                      | Render native -> (
                                                          match
                                                            keep
                                                              (fun () -> Pipeline.Private.retain_submission pipeline)
                                                              (fun () -> Pipeline.Private.release_submission pipeline)
                                                          with
                                                          | Error _ as failure -> failure
                                                          | Ok () -> Ok native))
                                                in
                                                let metal_primitive = function
                                                  | Ogpu_core.Render_pass.Point_list -> Metal.Render_encoder.Point
                                                  | Line_list -> Line
                                                  | Triangle_list -> Triangle
                                                  | Triangle_strip -> Triangle_strip
                                                and metal_index = function
                                                  | Ogpu_core.Render_pass.Uint16 -> Metal.Render_encoder.Uint16
                                                  | Uint32 -> Uint32
                                                in
                                                Ok
                                                  {
                                                    Ogpu_core.Backend.render_set_pipeline =
                                                      (fun token ->
                                                        match render_pipeline token with
                                                        | Error _ as failure -> failure
                                                        | Ok native ->
                                                            native_of (Metal.Render_encoder.set_pipeline encoder native));
                                                    set_stage_buffer =
                                                      (fun stage ~index ~offset token ->
                                                        match find_buffer token with
                                                        | Error _ as failure -> failure
                                                        | Ok buffer -> (
                                                            match keep_buffer buffer with
                                                            | Error _ as failure -> failure
                                                            | Ok () ->
                                                                native_of
                                                                  (match stage with
                                                                   | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.set_vertex_buffer encoder ~index ~offset (Buffer.Private.metal buffer)
                                                                   | Fragment -> Metal.Render_encoder.set_fragment_buffer encoder ~index ~offset (Buffer.Private.metal buffer)
                                                                   | Object | Mesh | Tile ->
                                                                       Metal.Render_encoder.set_stage_buffer encoder ~stage:(metal_stage stage) ~index ~offset
                                                                         (Some (Buffer.Private.metal buffer)))));
                                                    set_stage_bytes =
                                                      (fun stage ~index bytes ->
                                                        native_of
                                                          (match stage with
                                                           | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.set_vertex_bytes encoder ~index bytes
                                                           | Fragment -> Metal.Render_encoder.set_fragment_bytes encoder ~index bytes
                                                           | Object | Mesh | Tile -> Metal.Render_encoder.set_stage_bytes encoder ~stage:(metal_stage stage) ~index bytes));
                                                    set_stage_texture =
                                                      (fun stage ~index token ->
                                                        match find_texture token with
                                                        | Error _ as failure -> failure
                                                        | Ok texture -> (
                                                            match keep_texture texture with
                                                            | Error _ as failure -> failure
                                                            | Ok () ->
                                                                native_of
                                                                  (match stage with
                                                                   | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.set_vertex_texture encoder ~index (Texture.Private.metal texture)
                                                                   | Fragment -> Metal.Render_encoder.set_fragment_texture encoder ~index (Texture.Private.metal texture)
                                                                   | Object | Mesh | Tile ->
                                                                       Metal.Render_encoder.set_stage_texture encoder ~stage:(metal_stage stage) ~index
                                                                         (Some (Texture.Private.metal texture)))));
                                                    set_stage_sampler =
                                                      (fun stage ~index token ->
                                                        match Hashtbl.find_opt c.sampler_tokens token with
                                                        | None ->
                                                            error operation Ogpu_core.Error.Invalid_argument
                                                              "sampler graph is incomplete"
                                                        | Some sampler -> (
                                                            match
                                                              keep
                                                                (fun () -> Sampler.Private.retain_submission sampler)
                                                                (fun () -> Sampler.Private.release_submission sampler)
                                                            with
                                                            | Error _ as failure -> failure
                                                            | Ok () ->
                                                                native_of
                                                                  (match stage with
                                                                   | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.set_vertex_sampler encoder ~index (Sampler.Private.metal sampler)
                                                                   | Fragment -> Metal.Render_encoder.set_fragment_sampler encoder ~index (Sampler.Private.metal sampler)
                                                                   | Object | Mesh | Tile ->
                                                                       Metal.Render_encoder.set_stage_sampler encoder ~stage:(metal_stage stage) ~index
                                                                         (Some (Sampler.Private.metal sampler)))));
                                                    set_viewport =
                                                      (fun (rect : Ogpu_core.Render_pass.rect) ->
                                                        native_of
                                                          (Metal.Render_encoder.set_viewport encoder
                                                             { x = float rect.x; y = float rect.y; width = float rect.width;
                                                               height = float rect.height; znear = 0.; zfar = 1. }));
                                                    set_scissor =
                                                      (fun (rect : Ogpu_core.Render_pass.rect) ->
                                                        native_of
                                                          (Metal.Render_encoder.set_scissor encoder
                                                             { x = rect.x; y = rect.y; width = rect.width; height = rect.height }));
                                                    set_cull =
                                                      (fun cull ->
                                                        native_of (Metal.Render_encoder.set_cull_mode encoder (metal_cull cull)));
                                                    set_winding =
                                                      (fun winding ->
                                                        native_of
                                                          (Metal.Render_encoder.set_front_facing_winding encoder
                                                             (match winding with
                                                              | Ogpu_core.Backend.Clockwise -> Metal.Render_encoder.Clockwise
                                                              | Counter_clockwise -> Counter_clockwise)));
                                                    set_depth_state =
                                                      (function
                                                        | None -> native_of (Metal.Render_encoder.set_depth_stencil_state encoder None)
                                                        | Some state -> (
                                                            match depth_state_for state with
                                                            | Error _ as failure -> failure
                                                            | Ok native ->
                                                                native_of (Metal.Render_encoder.set_depth_stencil_state encoder (Some native))));
                                                    set_stencil_reference =
                                                      (fun ~front ~back ->
                                                        native_of (Metal.Render_encoder.set_stencil_reference_values encoder ~front ~back));
                                                    draw =
                                                      (fun ~primitive ~first ~count ~instances ->
                                                        native_of
                                                          (Metal.Render_encoder.draw_primitives encoder
                                                             ~primitive:(metal_primitive primitive) ~first ~count ~instances ()));
                                                    draw_indexed =
                                                      (fun ~primitive ~index_type token ~offset ~count ~instances ->
                                                        match find_buffer token with
                                                        | Error _ as failure -> failure
                                                        | Ok buffer -> (
                                                            match keep_buffer buffer with
                                                            | Error _ as failure -> failure
                                                            | Ok () ->
                                                                let index_buffer = Buffer.Private.metal buffer in
                                                                native_of
                                                                  (if instances = 1 then
                                                                     Metal.Render_encoder.draw_indexed_basic encoder
                                                                       ~primitive:(metal_primitive primitive)
                                                                       ~index_type:(metal_index index_type) ~index_buffer
                                                                       ~index_offset:offset ~index_count:count
                                                                   else
                                                                     Metal.Render_encoder.draw_indexed_instances encoder
                                                                       ~primitive:(metal_primitive primitive)
                                                                       ~index_type:(metal_index index_type) ~index_buffer
                                                                       ~index_offset:offset ~index_count:count
                                                                       ~instances:(Int64.of_int instances))));
                                                    draw_batch =
                                                      (fun draws ->
                                                        (* Indexed single-instance draws run through the native
                                                           prepared-draw loop in one call; anything else encodes
                                                           draw by draw. *)
                                                        let all_indexed =
                                                          Array.for_all
                                                            (fun (d : Ogpu_core.Backend.driver_batch_draw) ->
                                                              Option.is_some d.batch_index && d.batch_instances = 1)
                                                            draws
                                                        in
                                                        let resolve (d : Ogpu_core.Backend.driver_batch_draw) =
                                                          match render_pipeline d.batch_pipeline with
                                                          | Error _ as failure -> failure
                                                          | Ok native -> (
                                                              let rec buffers acc index =
                                                                if index = Array.length d.batch_buffers then Ok (List.rev acc)
                                                                else
                                                                  let stage, slot, token, offset = d.batch_buffers.(index) in
                                                                  match find_buffer token with
                                                                  | Error _ as failure -> failure
                                                                  | Ok buffer -> (
                                                                      match keep_buffer buffer with
                                                                      | Error _ as failure -> failure
                                                                      | Ok () -> buffers ((stage, slot, buffer, offset) :: acc) (index + 1))
                                                              in
                                                              match buffers [] 0 with
                                                              | Error _ as failure -> failure
                                                              | Ok buffers -> (
                                                                  match d.batch_index with
                                                                  | None -> Ok (native, buffers, None)
                                                                  | Some (kind, token, offset, count) -> (
                                                                      match find_buffer token with
                                                                      | Error _ as failure -> failure
                                                                      | Ok index_buffer -> (
                                                                          match keep_buffer index_buffer with
                                                                          | Error _ as failure -> failure
                                                                          | Ok () -> Ok (native, buffers, Some (kind, index_buffer, offset, count))))))
                                                        in
                                                        let resolved = Array.map resolve draws in
                                                        match Array.find_opt Result.is_error resolved with
                                                        | Some (Error e) -> Error e
                                                        | Some (Ok _) -> assert false
                                                        | None ->
                                                            if all_indexed then begin
                                                              let prepared =
                                                                Array.map2
                                                                  (fun (d : Ogpu_core.Backend.driver_batch_draw) resolved ->
                                                                    let native, buffers, index = Result.get_ok resolved in
                                                                    let kind, index_buffer, offset, count = Option.get index in
                                                                    ({ Metal.Render_encoder.Private.prepared_pipeline = native;
                                                                       prepared_bindings =
                                                                         Array.of_list
                                                                           (List.map
                                                                              (fun (stage, slot, buffer, offset) ->
                                                                                { Metal.Render_encoder.Private.prepared_stage = metal_stage stage;
                                                                                  prepared_index = slot; prepared_offset = offset;
                                                                                  prepared_buffer = Buffer.Private.metal buffer })
                                                                              buffers);
                                                                       prepared_primitive = metal_primitive d.batch_primitive;
                                                                       prepared_index_type = metal_index kind;
                                                                       prepared_index_buffer = Buffer.Private.metal index_buffer;
                                                                       prepared_index_offset = offset; prepared_index_count = count }
                                                                     : Metal.Render_encoder.Private.prepared_indexed_draw))
                                                                  draws resolved
                                                              in
                                                              match
                                                                Metal.Render_encoder.Private.prepare_indexed_draws
                                                                  (Device.Private.metal device) prepared
                                                              with
                                                              | Error e -> Error (Device.of_metal_error ~operation e)
                                                              | Ok prepared ->
                                                                  native_of
                                                                    (Metal.Render_encoder.Private.execute_prepared_indexed_draws encoder prepared)
                                                            end
                                                            else
                                                              let rec each index =
                                                                if index = Array.length draws then Ok ()
                                                                else
                                                                  let d = draws.(index) in
                                                                  let native, buffers, indexed = Result.get_ok resolved.(index) in
                                                                  let ( let* ) = Result.bind in
                                                                  let* () = native_of (Metal.Render_encoder.set_pipeline encoder native) in
                                                                  let* () =
                                                                    List.fold_left
                                                                      (fun result (stage, slot, buffer, offset) ->
                                                                        let* () = result in
                                                                        native_of
                                                                          (match stage with
                                                                           | Ogpu_core.Backend.Vertex -> Metal.Render_encoder.set_vertex_buffer encoder ~index:slot ~offset (Buffer.Private.metal buffer)
                                                                           | Fragment -> Metal.Render_encoder.set_fragment_buffer encoder ~index:slot ~offset (Buffer.Private.metal buffer)
                                                                           | Object | Mesh | Tile ->
                                                                               Metal.Render_encoder.set_stage_buffer encoder ~stage:(metal_stage stage) ~index:slot ~offset
                                                                                 (Some (Buffer.Private.metal buffer))))
                                                                      (Ok ()) buffers
                                                                  in
                                                                  let* () =
                                                                    match indexed with
                                                                    | None ->
                                                                        native_of
                                                                          (Metal.Render_encoder.draw_primitives encoder
                                                                             ~primitive:(metal_primitive d.batch_primitive)
                                                                             ~first:d.batch_vertex_start ~count:d.batch_vertex_count
                                                                             ~instances:d.batch_instances ())
                                                                    | Some (kind, index_buffer, offset, count) ->
                                                                        native_of
                                                                          (Metal.Render_encoder.draw_indexed_instances encoder
                                                                             ~primitive:(metal_primitive d.batch_primitive)
                                                                             ~index_type:(metal_index kind)
                                                                             ~index_buffer:(Buffer.Private.metal index_buffer)
                                                                             ~index_offset:offset ~index_count:count
                                                                             ~instances:(Int64.of_int d.batch_instances))
                                                                  in
                                                                  each (index + 1)
                                                              in
                                                              each 0);
                                                    use_resources =
                                                      (fun tokens ->
                                                        let rec split buffers textures = function
                                                          | [] -> Ok (List.rev buffers, List.rev textures)
                                                          | token :: rest -> (
                                                              match native_resource token with
                                                              | Some (Buffer buffer) -> (
                                                                  match keep_buffer buffer with
                                                                  | Error _ as failure -> failure
                                                                  | Ok () ->
                                                                      split (Metal.Render_encoder.Buffer_resource (Buffer.Private.metal buffer) :: buffers) textures rest)
                                                              | Some (Texture texture) -> (
                                                                  match keep_texture texture with
                                                                  | Error _ as failure -> failure
                                                                  | Ok () ->
                                                                      split buffers (Metal.Render_encoder.Texture_resource (Texture.Private.metal texture) :: textures) rest)
                                                              | None ->
                                                                  error operation Ogpu_core.Error.Invalid_argument
                                                                    "resource graph is incomplete")
                                                        in
                                                        match split [] [] tokens with
                                                        | Error _ as failure -> failure
                                                        | Ok (buffers, textures) ->
                                                            let ( let* ) = Result.bind in
                                                            let* () =
                                                              if buffers = [] then Ok ()
                                                              else
                                                                native_of
                                                                  (Metal.Render_encoder.use_resources encoder buffers
                                                                     ~usage:[ Metal.Render_encoder.Read ]
                                                                     ~stages:[ Metal.Render_encoder.Vertex; Fragment ])
                                                            in
                                                            if textures = [] then Ok ()
                                                            else
                                                              native_of
                                                                (Metal.Render_encoder.use_resources encoder textures
                                                                   ~usage:[ Metal.Render_encoder.Sample ]
                                                                   ~stages:[ Metal.Render_encoder.Fragment ]));
                                                    execute_icb =
                                                      (fun token ~location ~length ->
                                                        match Hashtbl.find_opt c.icbs token with
                                                        | None ->
                                                            error operation Ogpu_core.Error.Invalid_argument
                                                              "indirect command buffer graph is incomplete"
                                                        | Some entry ->
                                                            native_of
                                                              (Metal.Render_encoder.execute_indirect_commands encoder entry.icb
                                                                 ~location ~length));
                                                    render_use_heap =
                                                      (fun token ->
                                                        heap_call token (fun heap ->
                                                            Metal.Render_encoder.use_heaps encoder [ heap ]
                                                              ~stages:[ Metal.Render_encoder.Vertex; Fragment ]));
                                                    render_update_fence =
                                                      (fun token ->
                                                        fence_call `Update token (fun fence ->
                                                            Metal.Render_encoder.update_fence encoder fence
                                                              ~after:[ Metal.Render_encoder.Fragment ]));
                                                    render_wait_fence =
                                                      (fun token ->
                                                        fence_call `Wait token (fun fence ->
                                                            Metal.Render_encoder.wait_for_fence encoder fence
                                                              ~before:[ Metal.Render_encoder.Vertex ]));
                                                    draw_mesh =
                                                      (fun ~threadgroups ~object_threadgroup ~mesh_threadgroup ->
                                                        native_of
                                                          (Metal.Render_encoder.draw_mesh_threadgroups encoder ~threadgroups
                                                             ?object_threadgroup ~mesh_threadgroup ()));
                                                    dispatch_tile =
                                                      (fun ~threads -> native_of (Metal.Render_encoder.dispatch_threads_per_tile encoder ~threads));
                                                    tile_size =
                                                      (fun () ->
                                                        match (Metal.Render_encoder.tile_width encoder, Metal.Render_encoder.tile_height encoder) with
                                                        | Ok width, Ok height -> Ok (width, height)
                                                        | Error e, _ | _, Error e -> Error (Device.of_metal_error ~operation e));
                                                    end_render = finish;
                                                  })))))
                      in
                      let commit_present ~source (frame : Ogpu_core.Backend.driver_frame) =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match (find_texture source, Hashtbl.find_opt c.acquired_frames frame.frame_token) with
                            | Error e, _ -> Error e
                            | _, None ->
                                error operation Ogpu_core.Error.Invalid_state "frame token is stale"
                            | Ok source, Some (surface, native_frame) -> (
                                match
                                  Array.find_opt Surface.Private.pending_presentation_available
                                    active.presentations
                                with
                                | None ->
                                    error operation Ogpu_core.Error.Capacity
                                      "bounded presentation slots are all in flight"
                                | Some pending -> (
                                    match Surface.Private.prepare_present pending surface native_frame ~source with
                                    | Error _ as failure -> failure
                                    | Ok () -> (
                                        match Surface.Private.presentation_encoder pending native with
                                        | Error _ as failure ->
                                            Surface.Private.rollback_present pending;
                                            failure
                                        | Ok () -> (
                                            match Queue.submit_native queue native ~retained:!retained with
                                            | Error _ as failure ->
                                                Surface.Private.rollback_present pending;
                                                failure
                                            | Ok (receipt : Queue.receipt) ->
                                                finished := true;
                                                retained := [];
                                                Surface.Private.commit_present pending ~epoch:receipt.epoch;
                                                Hashtbl.remove c.acquired_frames frame.frame_token;
                                                Ok { Ogpu_core.Backend.epoch = receipt.epoch })))))
                      in
                      let release_all () =
                        List.iter (fun release -> release ()) !retained;
                        retained := []
                      in
                      let commit () =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match Queue.submit_native queue native ~retained:!retained with
                            | Error _ as failure -> failure
                            | Ok (receipt : Queue.receipt) ->
                                finished := true;
                                retained := [];
                                Ok { Ogpu_core.Backend.epoch = receipt.epoch })
                      in
                      let abandon () =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () ->
                            Option.iter (fun end_open -> end_open ()) !open_encoder;
                            open_encoder := None;
                            finished := true;
                            release_all ();
                            native_of (Metal.Command_buffer.destroy native)
                      in
                      let commands_use_residency token =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match find_sync operation c.residency "residency set" token with
                            | Error _ as e -> e
                            | Ok entry ->
                                keep_sync entry;
                                native_of (Metal.Command_buffer.use_residency_set native entry.native))
                      in
                      let commands_event ~signal token value =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match find_sync operation c.events "event" token with
                            | Error _ as e -> e
                            | Ok entry ->
                                keep_sync entry;
                                native_of
                                  (if signal then Metal.Command_buffer.encode_signal_shared_event native entry.native ~value
                                   else Metal.Command_buffer.encode_wait_for_shared_event native entry.native ~value))
                      in
                      let map_tiles token ~mip ~region ~map =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match find_texture token with
                            | Error _ as failure -> failure
                            | Ok texture -> (
                                match keep_texture texture with
                                | Error _ as failure -> failure
                                | Ok () -> (
                                    match Metal.Resource_state_encoder.create native with
                                    | Error e -> Error (Device.of_metal_error ~operation e)
                                    | Ok encoder ->
                                        let x, y, width, height = region in
                                        let mapped =
                                          Metal.Resource_state_encoder.update_texture_mapping encoder
                                            ~mode:(if map then Metal.Resource_state_encoder.Map else Unmap)
                                            (Texture.Private.metal texture) ~mip_level:mip ~slice:0
                                            ~region:{ x; y; z = 0; width; height; depth = 1 }
                                        in
                                        let ended = Metal.Resource_state_encoder.end_encoding encoder in
                                        native_of (match mapped with Error _ as e -> e | Ok () -> ended))))
                      in
                      let upscale token ~src ~dst =
                        match recording () with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match (find_sync operation c.upscalers "upscaler" token, find_texture src, find_texture dst) with
                            | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e
                            | Ok entry, Ok source, Ok destination -> (
                                match (keep_texture source, keep_texture destination) with
                                | (Error _ as failure), _ | _, (Error _ as failure) -> failure
                                | Ok (), Ok () ->
                                    keep_sync entry;
                                    native_of
                                      (Metal.Fx.Spatial_scaler.encode entry.native native ~color:(Texture.Private.metal source)
                                         ~output:(Texture.Private.metal destination))))
                      in
                      Ok
                        {
                          Ogpu_core.Backend.commands_token;
                          compute_encoder;
                          accel_encoder;
                          blit_encoder;
                          render_encoder;
                          map_tiles;
                          upscale;
                          commands_use_residency;
                          commands_signal_event = commands_event ~signal:true;
                          commands_wait_event = commands_event ~signal:false;
                          commit;
                          commit_present;
                          abandon;
                        }
                in
                let gpu_duration epoch = Queue.gpu_duration queue epoch in
                let gpu_timing () =
                  let timing = Queue.gpu_timing_for_device device in
                  { Ogpu_core.Backend.timing_supported = timing.supported;
                    gpu_seconds = timing.duration_seconds; gpu_samples = timing.sample_count }
                in
                let destroy_queue () =
                  if
                    not
                      (Array.for_all Surface.Private.pending_presentation_available
                         active.presentations)
                  then
                    error "Ogpu_metal.Backend.destroy_queue" Ogpu_core.Error.Invalid_state
                      "queue has presentations in flight"
                  else
                    match Queue.destroy queue with
                    | Error _ as e -> e
                    | Ok () -> (
                        Surface.Private.clear_pending_presentations active.presentations;
                        Hashtbl.remove c.active_queues queue_token;
                        match take_cleanup_error () with None -> Ok () | Some error -> Error error)
                in
                Ok
                  {
                    Ogpu_core.Backend.queue_token;
                    complete_through;
                    poll_through;
                    completed_epoch = (fun () -> Queue.completed_epoch queue);
                    begin_commands;
                    queue_add_residency =
                      (fun token ->
                        let operation = "Ogpu_metal.Backend.queue_add_residency" in
                        match find_sync operation c.residency "residency set" token with
                        | Error _ as e -> e
                        | Ok entry -> of_metal operation (Metal.Command_queue.add_residency_set (Queue.Private.metal queue) entry.native));
                    queue_remove_residency =
                      (fun token ->
                        let operation = "Ogpu_metal.Backend.queue_remove_residency" in
                        match find_sync operation c.residency "residency set" token with
                        | Error _ as e -> e
                        | Ok entry -> of_metal operation (Metal.Command_queue.remove_residency_set (Queue.Private.metal queue) entry.native));
                    gpu_duration;
                    gpu_timing;
                    destroy_queue;
                  }
          in
          let create_surface (configuration : Ogpu_core.Surface.configuration) =
            let adopted =
              match configuration.layer with
              | Some token -> (
                  match
                    Metal.Metal_layer.adopt_borrowed (Device.Private.metal device) token
                      (Metal.Metal_layer.default ~width:configuration.physical_width
                         ~height:configuration.physical_height)
                  with
                  | Error e -> Error (Device.of_metal_error ~operation:"Ogpu_metal.Backend.create_surface" e)
                  | Ok layer -> Ok (Some layer))
              | None -> Ok None
            in
            match adopted with
            | Error _ as e -> e
            | Ok adopted -> (
            match adopted with
            | None ->
                error "Ogpu_metal.Backend.create_surface" Ogpu_core.Error.Unsupported
                  "surface needs a native layer token"
            | Some layer -> (
                let release_adopted () =
                  Option.iter (fun layer -> ignore (Metal.Metal_layer.destroy layer)) adopted
                in
                match Surface.create device ~layer configuration with
                | Error _ as e -> release_adopted (); e
                | Ok surface ->
                    let surface_token = token c in
                    let frames_of_surface () =
                      Hashtbl.fold
                        (fun _ (owner, _) count -> if owner == surface then count + 1 else count)
                        c.acquired_frames 0
                    in
                    let find_frame token =
                      Option.map snd (Hashtbl.find_opt c.acquired_frames token)
                    in
                    let acquire_with acquire =
                      match acquire surface with
                      | Error _ as e -> e
                      | Ok Surface.Timeout -> Ok `Timeout
                      | Ok Occluded -> Ok `Occluded
                      | Ok Device_lost -> Ok `Device_lost
                      | Ok (Acquired frame) ->
                          let frame_token = Surface.frame_id frame in
                          Hashtbl.add c.acquired_frames frame_token (surface, frame);
                          Ok (`Acquired { Ogpu_core.Backend.frame_token })
                    in
                    let acquire () = acquire_with Surface.acquire
                    and acquire_sync () = acquire_with Surface.Private.acquire_scoped in
                    let take f frame =
                      match find_frame frame.Ogpu_core.Backend.frame_token with
                      | None ->
                          error "Ogpu_metal.Backend.surface" Ogpu_core.Error.Invalid_state
                            "frame token is stale"
                      | Some native -> (
                          match f surface native with
                          | Error _ as e -> e
                          | Ok () ->
                              Hashtbl.remove c.acquired_frames frame.frame_token;
                              Ok ())
                    in
                    Ok
                      {
                        Ogpu_core.Backend.surface_token;
                        configure = (fun x -> Surface.configure surface x);
                        acquire;
                        acquire_sync;
                        discard = take Surface.discard;
                        destroy_surface =
                          (fun () ->
                            if frames_of_surface () <> 0 then
                              error "Ogpu_metal.Backend.destroy_surface"
                                Ogpu_core.Error.Invalid_state "surface has outstanding frames"
                            else if Surface.in_flight_presentations surface <> 0 then
                              error "Ogpu_metal.Backend.destroy_surface"
                                Ogpu_core.Error.Invalid_state "surface has presentations in flight"
                            else (
                              Surface.destroy surface;
                              release_adopted ();
                              Ok ()));
                      }))
          in
          let destroy_device () =
            if Hashtbl.length c.active_queues <> 0 then
              error "Ogpu_metal.Backend.destroy_device" Ogpu_core.Error.Invalid_state
                "device has active queues"
            else begin
              Hashtbl.iter
                (fun _ native ->
                  match Metal.Depth_stencil.destroy native with
                  | Ok () -> ()
                  | Error error -> record_cleanup (Some error))
                c.depth_states;
              Hashtbl.reset c.depth_states;
              let destroyed = if c.device_live then Device.destroy device else Ok () in
              (match destroyed with
              | Ok () ->
                  c.device_live <- false;
                  c.device_id <- None
              | Error _ -> ());
              let cleanup = take_cleanup_error () in
              match (destroyed, cleanup) with
              | (Error _ as failure), _ -> failure
              | Ok (), Some error -> Error error
              | Ok (), None -> Ok ()
            end
          in
          Ok
            {
              Ogpu_core.Backend.device_token;
              device_handle = Device.Private.handle device;
              capabilities = Device.capabilities device;
              create_buffer;
              create_texture;
              create_depth_texture;
              create_stencil_texture;
              create_library;
              create_accel;
              instance_layout;
              create_sampler;
              create_render_pipeline;
              create_icb;
              create_argument;
              create_queue;
              create_surface;
              create_heap;
              heap_placement;
              create_residency;
              create_fence;
              create_event;
              create_timestamps;
              timestamp_reference;
              create_mesh_pipeline;
              create_tile_pipeline;
              create_dynamic_library;
              create_archive;
              create_sparse_texture;
              texture_tile;
              create_upscaler;
              destroy_device;
            }
  in
  ({ Ogpu_core.Backend.create_device }, c)
