type t={width:int;height:int;pitch:int;bytes:bytes}
type compare=Never|Less|Equal|Less_equal|Greater|Not_equal|Greater_equal|Always
type stencil_op=Keep|Zero|Replace|Increment_clamp|Decrement_clamp|Invert|Increment_wrap|Decrement_wrap
type stencil={compare:compare;fail:stencil_op;depth_fail:stencil_op;pass:stencil_op;read_mask:int;write_mask:int;reference:int}
type state={depth_compare:compare;depth_write:bool;stencil:stencil option}
type error=Invalid_size of{width:int;height:int}|Invalid_pitch of{minimum:int;actual:int}|Storage_too_small of{required:int;actual:int}|Coordinate_out_of_bounds of{x:int;y:int}|Invalid_depth of float|Invalid_stencil_value of int
let pixel_size=8
let checked ~width ~height ~pitch=if width<0||height<0||width>max_int/pixel_size then Error(Invalid_size{width;height})else let minimum=width*pixel_size in if pitch<minimum then Error(Invalid_pitch{minimum;actual=pitch})else if height<>0&&pitch>max_int/height then Error(Invalid_size{width;height})else Ok(pitch*height)
let create ?pitch ~width ~height ()=let pitch=Option.value pitch~default:(if width>max_int/pixel_size then 0 else width*pixel_size)in match checked~width~height~pitch with Error _ as e->e|Ok n->Ok{width;height;pitch;bytes=Bytes.make n '\000'}
let of_bytes ~width ~height ~pitch bytes=match checked~width~height~pitch with Error _ as e->e|Ok required when Bytes.length bytes<required->Error(Storage_too_small{required;actual=Bytes.length bytes})|Ok _->Ok{width;height;pitch;bytes}
let width t=t.width and height t=t.height and pitch t=t.pitch and bytes t=t.bytes
let offset t ~x ~y=if x<0||y<0||x>=t.width||y>=t.height then Error(Coordinate_out_of_bounds{x;y})else Ok(y*t.pitch+x*pixel_size)
let get_u32 b o=let byte n=Int32.of_int(Char.code(Bytes.get b(o+n)))in Int32.logor(byte 0)(Int32.logor(Int32.shift_left(byte 1)8)(Int32.logor(Int32.shift_left(byte 2)16)(Int32.shift_left(byte 3)24)))
let set_u32 b o v=for n=0 to 3 do Bytes.set b(o+n)(Char.chr Int32.(to_int(logand(shift_right_logical v(8*n))0xffl)))done
let valid_depth x=Float.is_finite x&&x>=0.&&x<=1.
let valid_stencil x=x>=0&&x<=255
let clear t ~depth ~stencil=if not(valid_depth depth)then Error(Invalid_depth depth)else if not(valid_stencil stencil)then Error(Invalid_stencil_value stencil)else(let bits=Int32.bits_of_float depth in for y=0 to t.height-1 do for x=0 to t.width-1 do let o=y*t.pitch+x*pixel_size in set_u32 t.bytes o bits;Bytes.set t.bytes(o+4)(Char.chr stencil);Bytes.set t.bytes(o+5)'\000';Bytes.set t.bytes(o+6)'\000';Bytes.set t.bytes(o+7)'\000' done done;Ok())
let get t ~x ~y=match offset t~x~y with Error _ as e->e|Ok o->Ok(Int32.float_of_bits(get_u32 t.bytes o),Char.code(Bytes.get t.bytes(o+4)))
let compare op incoming stored=match op with Never->false|Less->incoming<stored|Equal->incoming=stored|Less_equal->incoming<=stored|Greater->incoming>stored|Not_equal->incoming<>stored|Greater_equal->incoming>=stored|Always->true
let apply op ~reference stored=match op with Keep->stored|Zero->0|Replace->reference|Increment_clamp->min 255(stored+1)|Decrement_clamp->max 0(stored-1)|Invert->stored lxor 255|Increment_wrap->(stored+1)land 255|Decrement_wrap->(stored-1)land 255
let test_and_update t state ~x ~y ~depth=if not(valid_depth depth)then Error(Invalid_depth depth)else match offset t~x~y with Error _ as e->e|Ok o->let stored_depth=Int32.float_of_bits(get_u32 t.bytes o)and stored_stencil=Char.code(Bytes.get t.bytes(o+4))in let stencil_pass=match state.stencil with None->true|Some s->compare s.compare(s.reference land s.read_mask)(stored_stencil land s.read_mask)in let depth_pass=stencil_pass&&compare state.depth_compare depth stored_depth in(match state.stencil with None->()|Some s->let op=if not stencil_pass then s.fail else if not depth_pass then s.depth_fail else s.pass in let replacement=apply op~reference:s.reference stored_stencil and mask=s.write_mask land 255 in Bytes.set t.bytes(o+4)(Char.chr((stored_stencil land(lnot mask land 255))lor(replacement land mask))));if depth_pass&&state.depth_write then set_u32 t.bytes o(Int32.bits_of_float depth);Ok depth_pass
