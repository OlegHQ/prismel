type format=R8_unorm|Rgba8_unorm|Bgra8_unorm|Rgba16_float|Depth32_float
type storage=Device_local|Shared|Upload|Readback
type texture_usage=Binding|Attachment|Copy_src|Copy_dst
type texture_profile={format:format;storage:storage;width:int;height:int;depth:int;mip_levels:int;sample_count:int;usage:texture_usage list}
let invalid operation message=Error(Error.make operation Error.Invalid_argument message)
let validate_label ~operation=function None->Ok()|Some label when String.contains label '\000'->invalid operation"label contains NUL"|Some _->Ok()
let validate_buffer ~operation ~max_size ~size ~usage_count=
  if max_size<=0L||size<=0L||size>max_size then invalid operation"buffer size is outside device limits"
  else if usage_count<=0 then invalid operation"buffer usage is empty"else Ok()
let mul_overflows a b=a<>0L&&b>Int64.div Int64.max_int a
let validate_texture_shape ~operation ~max_dimension ~max_samples ~width ~height ~depth ~mip_levels ~sample_count ~usage_count=
  if max_dimension<=0||max_samples<=0||width<=0||height<=0||depth<=0||width>max_dimension||height>max_dimension then invalid operation"texture extent is outside device limits"
  else if mip_levels<=0||sample_count<=0||sample_count>max_samples||sample_count land(sample_count-1)<>0 then invalid operation"texture cardinality is invalid"
  else if usage_count<=0 then invalid operation"texture usage is empty"
  else let w=Int64.of_int width and h=Int64.of_int height and d=Int64.of_int depth in
    if mul_overflows w h||mul_overflows(Int64.mul w h)d then invalid operation"texture texel cardinality overflows"else
    let rec maximum_mips n levels=if n<=1 then levels else maximum_mips(n/2)(levels+1)in
    if mip_levels>maximum_mips(max width(max height depth))1 then invalid operation"texture mip cardinality exceeds its extent"else Ok()
let formats=[R8_unorm;Rgba8_unorm;Bgra8_unorm;Rgba16_float;Depth32_float]
let storages=[Device_local;Shared;Upload;Readback]
let storage_supported=function Device_local|Shared->true|Upload|Readback->false
let format_storage_table=Array.of_list(List.concat_map(fun format->List.map(fun storage->format,storage,storage_supported storage)storages)formats)
let unique values=List.sort_uniq compare values=values
let validate_texture_profile capabilities value=
  let operation="Ogpu.Validation.validate_texture_profile"in let limits=capabilities.Capabilities.limits in
  match validate_texture_shape~operation~max_dimension:limits.max_texture_dimension_2d~max_samples:limits.max_sample_count
    ~width:value.width~height:value.height~depth:value.depth~mip_levels:value.mip_levels~sample_count:value.sample_count~usage_count:(List.length value.usage)with
  |Error _ as failure->failure|Ok()->
  if not(List.mem value.format formats)||not(List.mem value.storage storages)then invalid operation"unknown format or storage"
  else if not(storage_supported value.storage)then Error(Error.make operation Error.Unsupported"texture storage profile is unsupported")
  else if not(unique value.usage)then invalid operation"texture usage must be sorted and unique"
  else if value.sample_count>1&&(value.mip_levels<>1||value.depth<>1||value.usage<>[Attachment])then invalid operation"multisample textures require one attachment-only mip and depth slice"
  else if value.storage=Shared&&value.sample_count>1 then invalid operation"shared multisample textures are unsupported"
  else Ok()
let power value=value>0L&&Int64.logand value(Int64.pred value)=0L
let validate_range ~operation ~size ~offset ~length ~alignment=
  if size<0L||offset<0L||length<=0L||not(power alignment)||Int64.rem offset alignment<>0L then invalid operation"range or alignment is invalid"
  else if offset>Int64.sub size length then invalid operation"range is out of bounds"else Ok()
let validate_layout ~operation entries=
  let entries=List.sort(fun(a,_)(b,_)->Int.compare a b)entries in
  let rec loop previous=function
    |[]->Ok()
    |(binding,_)::_ when binding<0->invalid operation"binding is negative"
    |(_,visibility)::_ when visibility=[]->invalid operation"visibility is empty"
    |(_,visibility)::_ when List.sort_uniq Int.compare visibility<>visibility->invalid operation"visibility must be sorted and unique"
    |(binding,_)::_ when previous=Some binding->invalid operation"duplicate binding"
    |(binding,_)::rest->loop(Some binding)rest
  in loop None entries
let validate_groups ~operation ~max_groups groups=
  let groups=List.sort Int.compare groups in
  if max_groups<0||List.length groups>max_groups then Error(Error.make operation Error.Capacity"bind-group limit exceeded")else
  let rec loop expected=function []->Ok()|group::_ when group<>expected->invalid operation"groups must be contiguous from zero"|_::rest->loop(expected+1)rest in loop 0 groups
