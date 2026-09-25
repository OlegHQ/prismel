type error =
  | Stage of string
  | Begin of Prismel_next_execution.error
  | Lower of Prismel_next_execution.error
  | Step of Prismel_next_execution.error

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
    ~family:entry.family ~blend:entry.blend
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
        ~finally:(fun () -> Scene.Private.release scene)
        (fun () ->
        let staged=Scene.Private.stage_native_render ~density ~width ~height scene in
        match staged with
        | Error message -> Error (Stage message)
        | Ok staged -> (
            let replayed=match staged.retained with
            |None->Ok None
            |Some(identity,version)->
                Prismel_next_execution.Private.replay
                    ~clear:staged.clear ~identity ~version execution in
            match replayed with
            |Error error->Error(Step error)
            |Ok(Some ())->Ok `Replayed
            |Ok None->
            match Prismel_next_execution.Private.begin_submission execution with
            | Error error -> Error (Begin error)
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
                          let cacheable=List.for_all(function
                            |_,Prismel_next_execution.Text _->true
                            |_,Prismel_next_execution.Image _
                            |_,Prismel_next_execution.Canvas _->false)resources in
                          let version=Scene.Private.native_segment_version
                            segment resources in
                          match Prismel_next_execution.Private.lower_scene2_segment
                            submission
                            ~identity:(Scene_command.Display_list.id segment)
                            ~version
                            ~cacheable ~density
                            ~resource:(fun id -> List.assoc_opt id resources)
                            (Scene_command.Display_list.render_ir segment) with
                          | Error error -> Error (Lower error)
                          | Ok batch -> lower (batch :: reversed) rest)
                      | Scene.Private.Ui_layer (ui, resources) :: rest -> (
                          match Prismel_next_execution.Private.lower_ui submission
                            ~density ~resource:(fun id -> List.assoc_opt id resources)
                            ui with
                          | Error error -> Error (Lower error)
                          | Ok batch -> lower (batch :: reversed) rest)
                      | Scene.Private.Scene3_layer prepared :: rest ->
                          let draws = draws_of_prepared staged prepared in
                          (match Prismel_next_execution.Private.adopt_draws
                            submission draws with
                          |Error error->Error(Lower error)
                          |Ok batch->lower(batch::reversed)rest)
                    in
                    lower [] staged.layers)) in
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
  | Ok `Replayed -> Ok ()
  | Ok (`Prepared (submission, retained, clear, batches)) -> (
      let stepped=match retained with
      |None->Prismel_next_execution.Private.step ~clear submission batches
      |Some(identity,version)->Prismel_next_execution.Private.step ~clear
          ~identity ~version submission batches in
      match stepped with
      | Ok () -> Ok ()
      | Error error -> Error (Step error))
