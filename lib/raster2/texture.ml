type color_space=Linear|Srgb
type address=Clamp|Repeat|Mirror
type filter=Nearest|Bilinear|Trilinear
type t={levels:Surface.t array;color_space:color_space;storage_bytes:int}
type error=Invalid_size|Invalid_capacity|Capacity_exceeded|Invalid_lod of float|Invalid_coordinate
let channel c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let rgba r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let[@inline always] linear_of_srgb x=let x=float x/.255. in if x<=0.04045 then x/.12.92 else Float.pow((x+.0.055)/.1.055)2.4
let[@inline always] srgb_of_linear x=let x=max 0.(min 1. x)in let x=if x<=0.0031308 then 12.92*.x else 1.055*.Float.pow x(1./.2.4)-.0.055 in int_of_float(x*.255.+.0.5)
let create ~color_space ~hard_capacity source=
 let width=Surface.width source and height=Surface.height source in if width<=0||height<=0 then Error Invalid_size else if hard_capacity<0 then Error Invalid_capacity else
 let required=ref 0 and w=ref width and h=ref height in while !w>1 || !h>1 do if !w>max_int/4 || (!h<>0 && !w*4>max_int/ !h) then required:=max_int else required:=!required+ !w* !h*4;w:=max 1((!w+1)/2);h:=max 1((!h+1)/2)done;if !required<>max_int then required:=!required+4;
 if !required>hard_capacity then Error Capacity_exceeded else
 let first=match Surface.create~width~height()with Ok s->s|Error _->assert false in Bytes.blit(Surface.bytes source)0(Surface.bytes first)0(width*height*4);
 let levels=ref[first]and current=ref first in while Surface.width !current>1||Surface.height !current>1 do let nw=max 1((Surface.width !current+1)/2)and nh=max 1((Surface.height !current+1)/2)in let next=match Surface.create~width:nw~height:nh()with Ok s->s|Error _->assert false in for y=0 to nh-1 do for x=0 to nw-1 do let count=ref 0 and sums=Array.make 4 0. in for oy=0 to 1 do for ox=0 to 1 do let sx=x*2+ox and sy=y*2+oy in if sx<Surface.width !current&&sy<Surface.height !current then(match Surface.get_rgba !current~x:sx~y:sy with Ok c->incr count;for k=0 to 3 do let value=channel c(24-k*8)in sums.(k)<-sums.(k)+.(if color_space=Srgb&&k<3 then linear_of_srgb value else float value/.255.)done|_->())done done;let out k=if color_space=Srgb&&k<3 then srgb_of_linear(sums.(k)/.float !count)else int_of_float(sums.(k)/.float !count*.255.+.0.5)in ignore(Surface.set_rgba next~x~y(rgba(out 0)(out 1)(out 2)(out 3)))done done;levels:=next::!levels;current:=next done;Ok{levels=Array.of_list(List.rev !levels);color_space;storage_bytes= !required}
let create_levels ~color_space ~hard_capacity sources=
  if Array.length sources=0 then Error Invalid_size else
  let required=ref 0 and valid=ref true in
  Array.iteri(fun index surface->let expected_w=max 1((Surface.width sources.(0)+(1 lsl index)-1)asr index)and expected_h=max 1((Surface.height sources.(0)+(1 lsl index)-1)asr index)in if Surface.width surface<>expected_w||Surface.height surface<>expected_h then valid:=false else required:=!required+Bytes.length(Surface.bytes surface))sources;
  if not !valid then Error Invalid_size else if hard_capacity<0 then Error Invalid_capacity else if !required>hard_capacity then Error Capacity_exceeded else
  let levels=Array.map(fun source->match Surface.create~width:(Surface.width source)~height:(Surface.height source)()with Error _->assert false|Ok copy->Bytes.blit(Surface.bytes source)0(Surface.bytes copy)0(Bytes.length(Surface.bytes source));copy)sources in Ok{levels;color_space;storage_bytes= !required}
let width t=Surface.width t.levels.(0)and height t=Surface.height t.levels.(0)and levels t=Array.length t.levels and storage_bytes t=t.storage_bytes
let level t index=if index<0||index>=Array.length t.levels then Error(Invalid_lod(float index))else Ok t.levels.(index)
let[@inline always] chi c n=(c lsr n)land 255
let[@inline always] rgbai r g b a=(r lsl 24)lor(g lsl 16)lor(b lsl 8)lor a
let[@inline always] index mode size value=match mode with Clamp->max 0(min(size-1)value)|Repeat->let value=value mod size in if value<0 then value+size else value|Mirror->let period=size*2 in let value=value mod period in let value=if value<0 then value+period else value in if value<size then value else period-1-value
let[@inline always] blend_int color_space a b scratch weight=
 let t=Float.Array.unsafe_get scratch weight in
 let inverse=1.-.t in match color_space with
 |Linear->
  rgbai(int_of_float(inverse*.float(chi a 24)+.t*.float(chi b 24)+.0.5))
   (int_of_float(inverse*.float(chi a 16)+.t*.float(chi b 16)+.0.5))
   (int_of_float(inverse*.float(chi a 8)+.t*.float(chi b 8)+.0.5))
   (int_of_float(inverse*.float(chi a 0)+.t*.float(chi b 0)+.0.5))
 |Srgb->
  rgbai(srgb_of_linear(inverse*.linear_of_srgb(chi a 24)+.t*.linear_of_srgb(chi b 24)))
   (srgb_of_linear(inverse*.linear_of_srgb(chi a 16)+.t*.linear_of_srgb(chi b 16)))
   (srgb_of_linear(inverse*.linear_of_srgb(chi a 8)+.t*.linear_of_srgb(chi b 8)))
   (int_of_float(inverse*.float(chi a 0)+.t*.float(chi b 0)+.0.5))
let[@inline always] texel_int_unchecked t ~level ~address_u ~address_v ~x ~y=let surface=t.levels.(level)in Surface.Private.get_rgba_int_unchecked surface~x:(index address_u(Surface.width surface)x)~y:(index address_v(Surface.height surface)y)
let[@inline always] sample_level_int t level ~address_u ~address_v ~filter scratch=let surface=t.levels.(level)in let u=Float.Array.unsafe_get scratch 0 and v=Float.Array.unsafe_get scratch 1 and w=Surface.width surface and h=Surface.height surface in match filter with Nearest->texel_int_unchecked t~level~address_u~address_v~x:(int_of_float(u*.float w))~y:(int_of_float(v*.float h))|Bilinear|Trilinear->let x=u*.float w-.0.5 and y=v*.float h-.0.5 in let x0=if x<0. then -1 else int_of_float x and y0=if y<0. then -1 else int_of_float y in Float.Array.unsafe_set scratch 3(x-.float x0);Float.Array.unsafe_set scratch 4(y-.float y0);let a=blend_int t.color_space(texel_int_unchecked t~level~address_u~address_v~x:x0~y:y0)(texel_int_unchecked t~level~address_u~address_v~x:(x0+1)~y:y0)scratch 3 and b=blend_int t.color_space(texel_int_unchecked t~level~address_u~address_v~x:x0~y:(y0+1))(texel_int_unchecked t~level~address_u~address_v~x:(x0+1)~y:(y0+1))scratch 3 in blend_int t.color_space a b scratch 4
let[@inline always] sample_int_unchecked t ~address_u ~address_v ~filter scratch=
 let raw_u=Float.Array.unsafe_get scratch 0 and raw_v=Float.Array.unsafe_get scratch 1 in
 let u=match address_u with Clamp->max 0.(min 1. raw_u)|Repeat->let truncated=int_of_float raw_u in let base=if raw_u<float truncated then truncated-1 else truncated in raw_u-.float base|Mirror->let truncated=int_of_float raw_u in let base=if raw_u<float truncated then truncated-1 else truncated in let fraction=raw_u-.float base in if abs base land 1=0 then fraction else 1.-.fraction
 and v=match address_v with Clamp->max 0.(min 1. raw_v)|Repeat->let truncated=int_of_float raw_v in let base=if raw_v<float truncated then truncated-1 else truncated in raw_v-.float base|Mirror->let truncated=int_of_float raw_v in let base=if raw_v<float truncated then truncated-1 else truncated in let fraction=raw_v-.float base in if abs base land 1=0 then fraction else 1.-.fraction in
 Float.Array.unsafe_set scratch 0 u;Float.Array.unsafe_set scratch 1 v;
 let lod=Float.Array.unsafe_get scratch 2 in let maximum=Array.length t.levels-1 in let lod_floor=int_of_float lod in let low=min maximum lod_floor in match filter with Trilinear->let high=min maximum(low+1)in let a=sample_level_int t low~address_u~address_v~filter:Bilinear scratch and b=sample_level_int t high~address_u~address_v~filter:Bilinear scratch in Float.Array.unsafe_set scratch 5(lod-.float lod_floor);blend_int t.color_space a b scratch 5|Nearest|Bilinear->sample_level_int t low~address_u~address_v~filter scratch
let sample t ~address_u ~address_v ~filter ~u ~v ~lod=if not(Float.is_finite u&&Float.is_finite v)then Error Invalid_coordinate else if not(Float.is_finite lod)||lod<0. then Error(Invalid_lod lod)else let scratch=Float.Array.of_list[u;v;lod;0.;0.;0.]in Ok(Int32.of_int(sample_int_unchecked t~address_u~address_v~filter scratch))
module Private=struct
  let sample_int_unchecked t ~address_u ~address_v ~filter coordinates=
    sample_int_unchecked t~address_u~address_v~filter coordinates
  let texel_int_unchecked=texel_int_unchecked
end
