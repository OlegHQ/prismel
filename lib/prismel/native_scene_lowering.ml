type error =
  | Stage of string
  | Begin of Prismel_next_execution.error
  | Lower of Prismel_next_execution.error
  | Step of Prismel_next_execution.error

module Phase_profile = struct
  let enabled = Sys.getenv_opt "PRISMEL_RENDERER_PHASE_PROFILE" = Some "1"
  let calls = ref 0
  let stage = ref 0.
  let lower = ref 0.
  let step = ref 0.
  let release = ref 0.
  let before () = if enabled then Gc.allocated_bytes () else 0.
  let add target before = if enabled then
    target := !target +. Gc.allocated_bytes () -. before
  let () = at_exit (fun () -> if enabled && !calls > 0 then
    let count = float !calls in
    Printf.eprintf
      "phase-profile native-stage %.1f B/call lower %.1f B/call step %.1f B/call release %.1f B/call (%d calls)\n%!"
      (!stage /. count) (!lower /. count) (!step /. count) (!release /. count)
      !calls)
end

let pp_error formatter = function
  | Stage message -> Format.fprintf formatter "native Scene staging: %s" message
  | Begin error ->
      Format.fprintf formatter "native Scene submission setup: %a"
        Prismel_next_execution.pp_error error
  | Lower error ->
      Format.fprintf formatter "native Scene lowering: %a"
        Prismel_next_execution.pp_error error
  | Step error ->
      Format.fprintf formatter "native Scene submission: %a"
        Prismel_next_execution.pp_error error

let draw_of_scene3_entry (entry : Scene_execution.scene3_entry) =
  Prismel_next_execution.prepared_draw
    ~family:
      (match entry.family with
      | Scene3 -> Scene3
      | Scene3_textured -> Scene3_textured
      | Scene3_shadow -> Scene3_shadow
      | Scene3_stencil -> Scene3_stencil
      | Scene3_textured_stencil -> Scene3_textured_stencil
      | Scene3_shadow_stencil -> Scene3_shadow_stencil
      | Scene2 -> Scene2
      | Scene2_textured -> Scene2_textured)
    ~blend:
      (match entry.blend with
      | Replace -> Replace
      | Alpha -> Alpha
      | Add -> Add
      | Multiply -> Multiply
      | Screen -> Screen
      | Subtract -> Subtract)
    ?texture:entry.texture ?auxiliary:entry.auxiliary ~samples:entry.samples
    entry.draw

type retained_draws={staged:Scene.Private.staged_native;
  draws:Prismel_next_execution.draw list}
let retained_draw_capacity=16
let retained_draw_caches=Domain.DLS.new_key(fun()->ref[])
let draws_of_prepared (staged:Scene.Private.staged_native) prepared=
  match staged.retained with
  |None->Array.to_list prepared.Scene_execution.entries|>List.map draw_of_scene3_entry
  |Some _->
      let cache=Domain.DLS.get retained_draw_caches in
      match List.find_opt(fun cached->cached.staged==staged)!cache with
      |Some cached->cached.draws
      |None->
          let entries=prepared.Scene_execution.entries in
          let rec build index reversed=
            if index=Array.length entries then List.rev reversed
            else build(index+1)(draw_of_scene3_entry
              (Array.unsafe_get entries index)::reversed)in
          let draws=build 0[]in
          cache:={staged;draws}::!cache;
          if List.length!cache>retained_draw_capacity then
            cache:=List.filteri(fun index _->index<retained_draw_capacity)!cache;
          draws

let render ~execution ~density ~width ~height scene =
  let active_submission=ref None in
  let prepared = try
      let outcome=Fun.protect
        ~finally:(fun () ->
          let before=Phase_profile.before()in
          Scene.Private.release scene;
          Phase_profile.add Phase_profile.release before)
        (fun () ->
        let before=Phase_profile.before()in
        let staged=Scene.Private.stage_native_render ~density ~width ~height scene in
        Phase_profile.add Phase_profile.stage before;
        match staged with
        | Error message -> Error (Stage message)
        | Ok staged -> (
            let replayed=match staged.retained with
            |None->Ok None
            |Some(identity,version)->
                let before=Phase_profile.before()in
                let replayed=Prismel_next_execution.Private.replay
                    ~clear:staged.clear ~identity ~version execution in
                Phase_profile.add Phase_profile.step before;
                replayed in
            match replayed with
            |Error error->Error(Step error)
            |Ok(Some facts)->Ok(`Replayed facts)
            |Ok None->
            let before=Phase_profile.before()in
            match Prismel_next_execution.Private.begin_submission execution with
            | Error error ->
                Phase_profile.add Phase_profile.lower before;
                Error (Begin error)
            | Ok submission ->
                active_submission:=Some submission;
                    let rec lower reversed = function
                      | [] ->
                          Ok (`Prepared (submission, staged.retained, staged.clear,
                            List.rev reversed))
                      | Scene.Private.Scene2_layer (ir, resources) :: rest -> (
                          match
                            Prismel_next_execution.Private.lower_scene2 submission
                              ~density
                              ~resource:(fun id -> List.assoc_opt id resources)
                              ir
                          with
                          | Error error -> Error (Lower error)
                          | Ok batch -> lower (batch::reversed) rest)
                      | Scene.Private.Scene2_segment (segment, resources) :: rest -> (
                          match Prismel_next_execution.Private.lower_scene2
                            submission ~density
                            ~resource:(fun id -> List.assoc_opt id resources)
                            (Scene_command.Display_list.render_ir segment) with
                          | Error error -> Error (Lower error)
                          | Ok batch -> lower (batch :: reversed) rest)
                      | Scene.Private.Scene3_layer prepared :: rest ->
                          let draws = draws_of_prepared staged prepared in
                          (match Prismel_next_execution.Private.adopt_draws
                            submission draws with
                          |Error error->Error(Lower error)
                          |Ok batch->lower(batch::reversed)rest)
                    in
                    let outcome=lower [] staged.layers in
                    Phase_profile.add Phase_profile.lower before;
                    outcome)) in
      (match outcome with
      |Error _->Option.iter Prismel_next_execution.Private.cancel !active_submission
      |Ok _->());
      outcome
    with exn->
      Option.iter Prismel_next_execution.Private.cancel !active_submission;
      raise exn
  in
  match prepared with
  | Error _ as error -> error
  | Ok (`Replayed facts) ->
      if Phase_profile.enabled then incr Phase_profile.calls;
      Ok facts
  | Ok (`Prepared (submission, retained, clear, batches)) -> (
      let before=Phase_profile.before()in
      let stepped=match retained with
      |None->Prismel_next_execution.Private.step ~clear submission batches
      |Some(identity,version)->Prismel_next_execution.Private.step ~clear
          ~identity ~version submission batches in
      Phase_profile.add Phase_profile.step before;
      if Phase_profile.enabled then incr Phase_profile.calls;
      match stepped with
      | Ok facts -> Ok facts
      | Error error -> Error (Step error))
