type descriptor={pass:Command.pass;queries:Sync.query_set;first:int;count:int;destination:unit Handle.t;destination_resource_id:int64;destination_size:int64;destination_offset:int64;completion_epoch:int64}
type description={resolve:Sync.description;commands:Command.description array}
type t=description
let create device ~timestamp_queries descriptor=
  if not timestamp_queries then Error(Error.make"Ogpu.Query_pass.create"Error.Unsupported"timestamp/counter queries are unsupported")
  else if descriptor.destination_resource_id<=0L then Error(Error.make"Ogpu.Query_pass.create"Error.Invalid_argument"destination resource id must be positive")
  else Result.bind(Sync.resolve device descriptor.queries ~destination:descriptor.destination ~destination_size:descriptor.destination_size ~first:descriptor.first ~count:descriptor.count ~destination_offset:descriptor.destination_offset ~completion_epoch:descriptor.completion_epoch)(fun resolve->
    let command=Command.begin_encoder()in Result.bind(Command.begin_pass command descriptor.pass)(fun()->
      let stage=match descriptor.pass with Command.Transfer->Command.Transfer_stage|Render->Fragment|Compute->Compute_stage|Acceleration->Acceleration_stage in
      Result.bind(Command.declare_resource command ~resource_id:descriptor.destination_resource_id ~access:Command.Write ~stages:[stage])(fun()->Result.bind(Command.end_pass command)(fun()->Result.map(fun()->{resolve;commands=Command.descriptions command})(Command.end_encoder command)))))
let describe value={resolve=value.resolve;commands=Array.copy value.commands}
