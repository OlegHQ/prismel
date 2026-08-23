module type RAW = sig
  type handle
  val mesh_descriptor : function_:handle option -> mesh_function:handle ->
    fragment_function:handle option -> archives:handle list -> linked:handle list ->
    (handle,string) result
  val tile_descriptor : tile_function:handle -> archives:handle list ->
    libraries:handle list -> linked:handle list -> (handle,string) result
  val set_buffer : handle -> index:int -> handle option -> (unit,string) result
  val set_attachment : handle -> index:int -> handle option -> (unit,string) result
  val release : handle -> unit
end

module type EXTERNALS = sig
  type handle
  external mesh_pipeline_descriptor : 'a -> (handle,string) result
    = "caml_prismel_mesh_pipeline_descriptor"
  external tile_pipeline_descriptor : 'a -> (handle,string) result
    = "caml_prismel_tile_pipeline_descriptor"
end

module Make(R:RAW)=struct
  let with_unwind build retained =
    match build() with Ok value->Ok value | Error _ as e->List.iter R.release retained;e
  let mesh ~object_function ~mesh_function ~fragment_function ~archives ~linked =
    let retained=mesh_function::archives@linked@
      Option.to_list object_function@Option.to_list fragment_function in
    with_unwind(fun()->R.mesh_descriptor ~function_:object_function ~mesh_function
      ~fragment_function ~archives ~linked)retained
  let tile ~tile_function ~archives ~libraries ~linked =
    let retained=tile_function::archives@libraries@linked in
    with_unwind(fun()->R.tile_descriptor ~tile_function ~archives ~libraries ~linked)retained
end
