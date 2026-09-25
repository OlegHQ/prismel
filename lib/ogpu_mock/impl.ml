let create_driver () =
  let driver, control = Ogpu_core.Backend_mock.create () in
  let live_handles () =
    let buffers, textures, pipelines, queues, surfaces =
      Ogpu_core.Backend_mock.live_counts control in
    buffers + textures + pipelines + queues + surfaces in
  driver, live_handles
