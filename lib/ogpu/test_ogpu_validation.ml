open Ogpu.Validation
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let kind=function Ok()->"ok"|Error value->(match value.Ogpu.Error.kind with Invalid_argument->"invalid"|Unsupported->"unsupported"|Capacity->"capacity"|_->"other")
let run () =
  let capabilities=Ogpu.Caps.minimum_m1 in
  let formats=[R8_unorm;Rgba8_unorm;Bgra8_unorm;Rgba16_float;Depth32_float]and storages=[Device_local;Shared;Upload;Readback]
  and samples=[0;1;2;3;4;8]in
  let rec subsets=function []->[[]]|value::rest->let tail=subsets rest in tail@List.map(fun values->value::values)tail in
  let usages=subsets[Binding;Attachment;Copy_src;Copy_dst]in
  let matrix()=List.concat_map(fun format->List.concat_map(fun storage->List.concat_map(fun sample_count->List.map(fun usage->
    kind(validate_texture_profile capabilities{format;storage;width=64;height=64;depth=1;mip_levels=(if sample_count=1 then 7 else 1);sample_count;usage}))usages)samples)storages)formats in
  let sequential=matrix()in if List.length sequential<>1920 then failwith"validation matrix cardinality drift";
  let workers=Array.init 4(fun _->Domain.spawn matrix)in Array.iter(fun worker->if Domain.join worker<>sequential then failwith"validation result domain drift")workers;
  let table=Array.to_list format_storage_table in if List.length table<>24||List.length(List.filter(fun(_,_,supported)->supported)table)<>12 then failwith"format/storage table drift";
  get(validate_range~operation:"test"~size:1024L~offset:256L~length:512L~alignment:256L);
  (match validate_range~operation:"test"~size:Int64.max_int~offset:Int64.max_int~length:2L~alignment:1L with Error _->()|Ok()->failwith"range overflow accepted");
  let descriptor:Ogpu.Types.texture_descriptor={label=Some"unchanged";width=4;height=4;depth=1;mip_levels=3;sample_count=1;format=Rgba8_unorm;usage=[Texture_binding]}in
  get(Ogpu.Types.validate_texture capabilities descriptor);if descriptor.label<>Some"unchanged"then failwith"label mutated";
  (match Ogpu.Types.validate_texture capabilities{descriptor with format=Rgba32_float;usage=[Texture_binding;Render_attachment]}with
   |Error{kind=Unsupported;_}->()|_->failwith"float render attachment accepted");
  get(Ogpu.Types.validate_texture capabilities{descriptor with format=Rgba16_float;usage=[Texture_binding;Storage_binding]});
  (* binary16: every non-NaN bit pattern round-trips; rounding is to nearest even. *)
  for bits=0 to 0xffff do
    let value=Ogpu.Types.float_of_half bits in
    if Float.is_nan value then(if not(Float.is_nan(Ogpu.Types.float_of_half(Ogpu.Types.half_of_float value)))then failwith"half NaN lost")
    else if Ogpu.Types.half_of_float value<>bits then failwith(Printf.sprintf"half round trip 0x%04x"bits)
  done;
  List.iter(fun(value,bits)->if Ogpu.Types.half_of_float value<>bits then failwith(Printf.sprintf"half_of_float %h"value))
    [1.,0x3c00;-2.,0xc000;65504.,0x7bff;65519.,0x7bff;65520.,0x7c00;1e9,0x7c00;Float.neg_infinity,0xfc00;
     1.+.0x1p-11,0x3c00;1.+.3.*.0x1p-11,0x3c02;0x1p-24,0x0001;0x1p-25,0x0000;3.*.0x1p-25,0x0002;0x1p-14-.0x1p-25,0x0400;-0.,0x8000];
  print_endline"OGPU centralized validation: exhaustive1920, overflow/layout, float formats, binary16 round trip, 4-domain exact ok"
