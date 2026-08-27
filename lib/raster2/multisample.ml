type t={width:int;height:int;samples:int;pitch:int;bytes:bytes}
type compare=Never|Less|Less_equal|Equal|Greater_equal|Greater|Not_equal|Always
type error=Invalid_sample_count of int|Invalid_size|Invalid_pitch|Storage_too_small|Out_of_bounds|Invalid_depth of float|Surface_error
let valid_samples=function 1|2|4|8|9|16->true|_->false
let checked ~width ~height ~samples ~pitch=if not(valid_samples samples)then Error(Invalid_sample_count samples)else if width<0||height<0||width>max_int/(samples*8)then Error Invalid_size else let minimum=width*samples*8 in if pitch<minimum then Error Invalid_pitch else if height<>0&&pitch>max_int/height then Error Invalid_size else Ok(pitch*height)
let create ?pitch ~width ~height ~samples ()=let pitch=Option.value pitch~default:(if valid_samples samples&&width>=0&&width<=max_int/(samples*8)then width*samples*8 else 0)in match checked~width~height~samples~pitch with Error _ as e->e|Ok length->Ok{width;height;samples;pitch;bytes=Bytes.make length '\000'}
let of_bytes ~width ~height ~samples ~pitch bytes=match checked~width~height~samples~pitch with Error _ as e->e|Ok required when Bytes.length bytes<required->Error Storage_too_small|Ok _->Ok{width;height;samples;pitch;bytes}
let width t=t.width and height t=t.height and samples t=t.samples and pitch t=t.pitch and bytes t=t.bytes
let grid side=Array.init(side*side)(fun index->
  (float(index mod side)+.0.5)/.float side,
  (float(index/side)+.0.5)/.float side)
let positions= function 1->[|(0.5,0.5)|]|2->[|(0.25,0.25);(0.75,0.75)|]|4->[|(0.375,0.125);(0.875,0.375);(0.125,0.625);(0.625,0.875)|]|8->[|(0.5625,0.3125);(0.4375,0.6875);(0.8125,0.5625);(0.3125,0.1875);(0.1875,0.8125);(0.0625,0.4375);(0.6875,0.9375);(0.9375,0.0625)|]|9->grid 3|16->grid 4|_->[||]
let sample_position ~samples index=if not(valid_samples samples)then Error(Invalid_sample_count samples)else if index<0||index>=samples then Error Out_of_bounds else Ok((positions samples).(index))
let set32 b o v=for n=0 to 3 do Bytes.set b(o+n)(Char.chr Int32.(to_int(logand(shift_right_logical v(8*n))0xffl)))done
let get32 b o=let byte n=Int32.of_int(Char.code(Bytes.get b(o+n)))in Int32.logor(byte 0)(Int32.logor(Int32.shift_left(byte 1)8)(Int32.logor(Int32.shift_left(byte 2)16)(Int32.shift_left(byte 3)24)))
let offset t x y sample=if x<0||y<0||sample<0||x>=t.width||y>=t.height||sample>=t.samples then Error Out_of_bounds else Ok(y*t.pitch+(x*t.samples+sample)*8)
let valid_depth d=Float.is_finite d&&d>=0.&&d<=1.
let clear t ~color ~depth=if not(valid_depth depth)then Error(Invalid_depth depth)else(let bits=Int32.bits_of_float depth in for y=0 to t.height-1 do for x=0 to t.width-1 do for sample=0 to t.samples-1 do let o=y*t.pitch+(x*t.samples+sample)*8 in set32 t.bytes o color;set32 t.bytes(o+4)bits done done done;Ok())
let compare op incoming stored=match op with Never->false|Less->incoming<stored|Less_equal->incoming<=stored|Equal->incoming=stored|Greater_equal->incoming>=stored|Greater->incoming>stored|Not_equal->incoming<>stored|Always->true
let test_and_write t ~compare:operation ~depth_write ~x ~y ~sample ~depth ~color=if not(valid_depth depth)then Error(Invalid_depth depth)else match offset t x y sample with Error _ as e->e|Ok o->let pass=compare operation depth(Int32.float_of_bits(get32 t.bytes(o+4)))in if pass then(set32 t.bytes o color;if depth_write then set32 t.bytes(o+4)(Int32.bits_of_float depth));Ok pass
let get t ~x ~y ~sample=match offset t x y sample with Error _ as e->e|Ok o->Ok(get32 t.bytes o,Int32.float_of_bits(get32 t.bytes(o+4)))
let resolve t target=if Surface.width target<>t.width||Surface.height target<>t.height then Error Surface_error else(let half=t.samples/2 in for y=0 to t.height-1 do for x=0 to t.width-1 do let r=ref 0 and g=ref 0 and b=ref 0 and a=ref 0 in for sample=0 to t.samples-1 do let color=get32 t.bytes(y*t.pitch+(x*t.samples+sample)*8)in r:=!r+Int32.(to_int(logand(shift_right_logical color 24)0xffl));g:=!g+Int32.(to_int(logand(shift_right_logical color 16)0xffl));b:=!b+Int32.(to_int(logand(shift_right_logical color 8)0xffl));a:=!a+Int32.(to_int(logand color 0xffl))done;let channel sum=Int32.of_int((sum+half)/t.samples)in let color=Int32.(logor(shift_left(channel !r)24)(logor(shift_left(channel !g)16)(logor(shift_left(channel !b)8)(channel !a))))in ignore(Surface.set_rgba target~x~y color)done done;Ok())
