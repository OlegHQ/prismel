type dispatch=Direct of{x:int;y:int;z:int}|Indirect of{buffer:unit Handle.t;buffer_size:int64;offset:int64}
type resource={id:int64;access:Command.access;stages:Command.stage list}
type description={pipeline_key:string;groups:(int*(int*Binding.kind)list)array;dispatch:dispatch;commands:Command.description array}
type t=description
let invalid text=Error(Error.make"Ogpu.Compute_pass.create"Error.Invalid_argument text)
let create device ~(limits:Capabilities.limits) ~pipeline ~layout ~groups ~resources ~dispatch=
  if Pipeline.kind pipeline<>Pipeline.Compute then invalid"pipeline is not compute"else
  let expected=Binding.pipeline_layouts layout|>List.map fst in let actual=Array.to_list groups|>List.map fst in if actual<>List.sort_uniq compare actual||actual<>expected then invalid"bind groups are duplicate, missing, or out of order"else
  let rec validate_groups i=if i=Array.length groups then Ok()else Result.bind(Binding.validate_group layout(snd groups.(i)))(fun()->validate_groups(i+1))in
  Result.bind(validate_groups 0)(fun()->
    let declared=Hashtbl.create(Array.length resources)in let failure=ref None in Array.iter(fun(resource:resource)->if resource.id<=0L||Hashtbl.mem declared resource.id then failure:=Some"resource declarations contain an invalid/duplicate id"else if resource.stages<>[Command.Compute_stage]then failure:=Some"compute resources require exactly the compute stage"else Hashtbl.add declared resource.id resource)resources;
    Array.iter(fun(_,group)->List.iter(fun(snapshot:Binding.resource_snapshot)->if not(Hashtbl.mem declared snapshot.id) && !failure=None then failure:=Some"bound resource is missing a declaration")(Binding.group_entries group))groups;
    match!failure with Some text->invalid text|None->
    let dispatch_result=match dispatch with Direct{x;y;z}->if x<=0||y<=0||z<=0||x>limits.max_texture_dimension_2d||y>limits.max_texture_dimension_2d||z>limits.max_texture_dimension_2d then invalid"direct dispatch dimensions exceed limits"else Ok()|Indirect{buffer;buffer_size;offset}->(match Handle.validate_for ~operation:"Ogpu.Compute_pass.create"device buffer with Error _ as e->e|Ok()when buffer_size<12L||offset<0L||Int64.rem offset 4L<>0L||offset>Int64.sub buffer_size 12L->invalid"indirect dispatch range/alignment is invalid"|Ok()->Ok())in
    Result.bind dispatch_result(fun()->let command=Command.begin_encoder()in Result.bind(Command.begin_pass command Command.Compute)(fun()->let declarations=Array.fold_left(fun result resource->Result.bind result(fun()->Command.declare_resource command ~resource_id:resource.id ~access:resource.access ~stages:resource.stages))(Ok())resources in Result.bind declarations(fun()->Result.bind(Command.end_pass command)(fun()->Result.map(fun()->{pipeline_key=Pipeline.cache_key pipeline;groups=Array.map(fun(index,group)->index,List.map(fun(snapshot:Binding.resource_snapshot)->snapshot.binding,snapshot.kind)(Binding.group_entries group))groups;dispatch;commands=Command.descriptions command})(Command.end_encoder command))))))
let describe value={value with groups=Array.map(fun(index,entries)->index,List.map(fun value->value)entries)value.groups;commands=Array.copy value.commands}
