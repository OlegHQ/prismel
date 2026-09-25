type t =
  { metal : Metal.Device.t
  ; handle : Ogpu_core.Handle.device
  ; profile : Ogpu_core.Caps.t
  ; mutable generation : int64
  ; mutable live_resources : int
  }

let error operation kind message = Error (Ogpu_core.Error.make operation kind message)

let of_metal_error ~operation (value : Metal.error) =
  let kind = match value.kind with
    | Metal.Invalid_argument -> Ogpu_core.Error.Invalid_argument
    | Metal.Invalid_state | Metal.Parent_has_dependents -> Ogpu_core.Error.Invalid_state
    | Metal.Destroyed -> Ogpu_core.Error.Stale_handle
    | Metal.Device_mismatch -> Ogpu_core.Error.Cross_device
    | Metal.Unsupported -> Ogpu_core.Error.Unsupported
    | Metal.Native_error | Metal.Wrong_domain | Metal.Release_queue_overflow ->
        Ogpu_core.Error.Device_lost in
  Ogpu_core.Error.make operation kind value.message

let system_default () =
  let operation = "Ogpu_metal.Device.system_default" in
  match Metal.Device.system_default () with
  | Error value -> Error (of_metal_error ~operation value)
  | Ok metal ->
      (match Metal.Device.info metal with
       | Error value ->
           ignore (Metal.Device.destroy metal);
           Error (of_metal_error ~operation value)
       | Ok info ->
           let rec maximum_sample current=function
             |[]->Ok current
             |sample::rest->(match Metal.Device.supports_texture_sample_count metal sample with
               |Error value->Error(of_metal_error~operation value)
               |Ok true->maximum_sample sample rest|Ok false->maximum_sample current rest)in
           match maximum_sample 1[4;9;16]with Error _ as failure->ignore(Metal.Device.destroy metal);failure|Ok max_sample_count->
           (* Apple GPUs sample counters at encoder stage boundaries only. *)
           match Metal.Counters.supports metal Metal.Counters.Stage_boundary with Error value->ignore(Metal.Device.destroy metal);Error(of_metal_error~operation value)|Ok timestamp_boundary->
           match Metal.Counters.sets metal with Error value->ignore(Metal.Device.destroy metal);Error(of_metal_error~operation value)|Ok counter_sets->
           let timestamp_queries=timestamp_boundary&&List.exists(fun(set:Metal.Counters.set)->set.name="timestamp")counter_sets in
           match Metal.Device.supports_residency_sets metal with Error value->ignore(Metal.Device.destroy metal);Error(of_metal_error~operation value)|Ok residency_sets->
           match Metal.Device.supports_sparse_textures metal with Error value->ignore(Metal.Device.destroy metal);Error(of_metal_error~operation value)|Ok sparse_memory->
           match Metal.Fx.Spatial_scaler.supported metal with Error value->ignore(Metal.Device.destroy metal);Error(of_metal_error~operation value)|Ok metal_fx->
           (* Curve primitives intersect only on Apple GPU family 9 and later;
              mesh shaders need Apple7, tile shaders Apple4. *)
           let family f = match Metal.Device.supports_family metal f with Ok true -> true | _ -> false in
           let curves = family Metal.Device.Apple9 in
           let capabilities : Ogpu_core.Caps.t =
             { limits =
                 { max_buffer_size = info.max_buffer_length
                 ; max_texture_dimension_2d = 16_384
                 ; max_bind_groups = 4
                 ; max_sample_count }
             ; compute_pipeline = true
             ; render_pipeline = true
             ; ray_tracing = info.raytracing
             ; function_tables = info.raytracing
             ; ray_tracing_curves = info.raytracing && curves
             ; metal_fx
             ; timestamp_queries = false
             ; sparse_memory = false
             ; heaps = true
             ; residency_sets
             ; fences = true
             ; event_synchronization = true
             ; mesh_shaders = family Metal.Device.Apple7
             ; tile_shaders = family Metal.Device.Apple4
             ; dynamic_libraries = info.dynamic_libraries
             ; binary_archives = true
             ; conservative_limits = [] }
           in
           match Ogpu_core.Caps.create capabilities ~timestamp_queries ~sparse_memory
             ~conservative_limits:["max_texture_dimension_2d=16384";"max_bind_groups=4";"max_sample_count=probed(1/4/9/16)";"metal_fx=probed(MTLFXSpatialScaler)";"sparse_memory=probed(supportsSparseTextures)"] with
           | Error _ as failure -> ignore (Metal.Device.destroy metal); failure
           | Ok profile ->
               Ok { metal; handle = Ogpu_core.Handle.create_device (); profile;
                    generation = 1L; live_resources = 0 })

let id value = Ogpu_core.Handle.device_id value.handle
let generation value = value.generation
let capabilities value = value.profile
let capability_profile value=value.profile
let supports value feature=if Ogpu_core.Handle.device_destroyed value.handle then error"Ogpu_metal.Device.supports"Ogpu_core.Error.Stale_handle"device is destroyed"else Ogpu_core.Caps.require ~operation:"Ogpu_metal.Device.supports" value.profile feature
let destroyed value = Ogpu_core.Handle.device_destroyed value.handle

let destroy value =
  let operation = "Ogpu_metal.Device.destroy" in
  if destroyed value then Ok ()
  else if value.live_resources <> 0 then
    error operation Ogpu_core.Error.Invalid_state "device still owns live resources"
  else
    match Metal.Device.destroy value.metal with
    | Error metal -> Error (of_metal_error ~operation metal)
    | Ok () ->
        Ogpu_core.Handle.destroy_device value.handle;
        value.generation <- Int64.succ value.generation;
        Ok ()

module Private = struct
  let metal value = value.metal
  let handle value = value.handle
  let attach_resource value = value.live_resources <- value.live_resources + 1
  let detach_resource value = value.live_resources <- value.live_resources - 1
end
