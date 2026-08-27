open Ogpu.Validation
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let kind=function Ok()->"ok"|Error value->(match value.Ogpu.Error.kind with Invalid_argument->"invalid"|Unsupported->"unsupported"|Capacity->"capacity"|_->"other")
let ()=
  let capabilities=Ogpu.Capabilities.minimum_m1 in
  let formats=[R8_unorm;Rgba8_unorm;Bgra8_unorm;Rgba16_float;Depth32_float]and storages=[Device_local;Shared;Upload;Readback]
  and samples=[0;1;2;3;4;8]in
  let rec subsets=function []->[[]]|value::rest->let tail=subsets rest in tail@List.map(fun values->value::values)tail in
  let usages=subsets[Binding;Attachment;Copy_src;Copy_dst]in
  let matrix()=List.concat_map(fun format->List.concat_map(fun storage->List.concat_map(fun sample_count->List.map(fun usage->
    kind(validate_texture_profile capabilities{format;storage;width=64;height=64;depth=1;mip_levels=(if sample_count=1 then 7 else 1);sample_count;usage}))usages)samples)storages)formats in
  let sequential=matrix()in if List.length sequential<>1920 then failwith"validation matrix cardinality drift";
  let workers=Array.init 4(fun _->Domain.spawn matrix)in Array.iter(fun worker->if Domain.join worker<>sequential then failwith"validation result domain drift")workers;
  let table=Array.to_list format_storage_table in if List.length table<>20||List.length(List.filter(fun(_,_,supported)->supported)table)<>10 then failwith"format/storage table drift";
  get(validate_range~operation:"test"~size:1024L~offset:256L~length:512L~alignment:256L);
  (match validate_range~operation:"test"~size:Int64.max_int~offset:Int64.max_int~length:2L~alignment:1L with Error _->()|Ok()->failwith"range overflow accepted");
  let descriptor:Ogpu.Types.texture_descriptor={label=Some"unchanged";width=4;height=4;depth=1;mip_levels=3;sample_count=1;usage=[Texture_binding]}in
  get(Ogpu.Types.validate_texture capabilities descriptor);if descriptor.label<>Some"unchanged"then failwith"label mutated";
  print_endline"OGPU centralized validation: exhaustive1920, overflow/layout, 4-domain exact ok"
