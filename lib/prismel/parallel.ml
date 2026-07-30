module Task = Domainslib.Task

let active_pool : Task.pool option ref = ref None

let recommended_domains () = max 1 (Domain.recommended_domain_count ())

let run ?domains f =
  match !active_pool with
  | Some _ -> f ()
  | None ->
      let domains = Option.value ~default:(recommended_domains ()) domains in
      let num_domains = max 0 (domains - 1) in
      if num_domains = 0 then f ()
      else
        let pool = Task.setup_pool ~num_domains () in
        active_pool := Some pool;
        Fun.protect
          ~finally:(fun () ->
            active_pool := None;
            Task.teardown_pool pool)
          f

let rec map ?(grain = 64) f values =
  let source = Array.of_list values in
  let length = Array.length source in
  if length = 0 then []
  else
    match !active_pool with
    | None when length < grain -> Array.to_list (Array.map f source)
    | None -> run (fun () -> map ~grain f values)
    | Some pool ->
        Task.run pool (fun _ ->
          let output = Array.make length None in
          Task.parallel_for pool ~start:0 ~finish:(length - 1)
            ~chunk_size:(max 1 grain)
            ~body:(fun index -> output.(index) <- Some (f source.(index)));
          Array.to_list
            (Array.map
               (function Some value -> value | None -> assert false)
               output))

let rec for_ ?(chunk_size = 64) ~start ~finish body =
  if finish < start then ()
  else
    match !active_pool with
    | None when finish - start + 1 < chunk_size ->
        for index = start to finish do body index done
    | None -> run (fun () -> for_ ~chunk_size ~start ~finish body)
    | Some pool ->
        Task.run pool (fun _ ->
          Task.parallel_for pool ~start ~finish ~chunk_size:(max 1 chunk_size)
            ~body)

let rec both left right =
  match !active_pool with
  | None -> run (fun () -> both left right)
  | Some pool ->
      Task.run pool (fun _ ->
        let left_task = Task.async pool (fun _ -> left ()) in
        let right_value = right () in
        Task.await pool left_task, right_value)
