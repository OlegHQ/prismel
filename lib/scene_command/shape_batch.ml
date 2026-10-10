type gpu_token = { identity:int; count:int; stamp:int64 }
type t = { bytes:bytes; count:int; gpu:gpu_token option }
let instance_bytes = 64
let count value = value.count
let instances value = value.bytes
let gpu value = value.gpu
module Private = struct
  let copy value = {value with bytes=Bytes.copy value.bytes}
  let valid value =
    match value.gpu with
    |Some token->value.count=token.count && Bytes.length value.bytes=0
    |None->
        Bytes.length value.bytes=value.count*instance_bytes &&
        let rec loop i = i=value.count ||
          let float word=Int32.float_of_bits(Bytes.get_int32_le value.bytes (i*instance_bytes+word*4))in
          let kind=Bytes.get_int32_le value.bytes (i*instance_bytes+40)in
          (kind=0l || kind=4l || kind=5l) &&
          Float.is_finite(float 0) && Float.is_finite(float 1) &&
          Float.is_finite(float 2) && Float.is_finite(float 3) &&
          Float.is_finite(float 11) && float 11>=0. &&
          Float.is_finite(float 12) && float 12>=0. &&
          Float.is_finite(float 13) && float 13>=0. &&
          (kind=5l || (float 2>=float 0 && float 3>=float 1)) && loop(i+1)
        in loop 0
  let gpu_token ~identity ~count ~stamp =
    if identity<=0 || count<0 || count>1_000_000 || stamp<0L then
      invalid_arg "Shape_batch.gpu_token: invalid identity, count or stamp";
    {identity; count; stamp}
  let gpu_identity value = value.identity
  let gpu_count (value:gpu_token) = value.count
  let gpu_stamp value = value.stamp
  let of_gpu (gpu:gpu_token) = {bytes=Bytes.empty; count=gpu.count; gpu=Some gpu}
end
module Builder = struct
  type batch = t
  type t = { mutable bytes:bytes; mutable count:int }
  let create ?(capacity=256) () =
    if capacity<0 || capacity>1_000_000 then invalid_arg "Shape_batch capacity";
    {bytes=Bytes.create (max 1 capacity * instance_bytes); count=0}
  let append builder kind x0 y0 x1 y1 fill stroke stroke_width =
    let finite value = Float.is_finite value && abs_float value <= 3.4028234663852886e38 in
    if not (finite x0 && finite y0 && finite x1 && finite y1 && finite stroke_width)
       || stroke_width<0. then invalid_arg "Shape_batch: invalid coordinates";
    if builder.count>=1_000_000 then invalid_arg "Shape_batch: instance limit";
    let offset=builder.count*instance_bytes in
    if offset+instance_bytes>Bytes.length builder.bytes then begin
      let grown=Bytes.create (min (1_000_000*instance_bytes) (2*Bytes.length builder.bytes)) in
      Bytes.blit builder.bytes 0 grown 0 offset; builder.bytes<-grown
    end;
    Bytes.fill builder.bytes offset instance_bytes '\000';
    let float word value = Bytes.set_int32_le builder.bytes (offset+4*word) (Int32.bits_of_float value) in
    float 0 x0; float 1 y0; float 2 x1; float 3 y1;
    Bytes.set_int32_le builder.bytes (offset+32) fill;
    Bytes.set_int32_le builder.bytes (offset+36) stroke;
    Bytes.set_int32_le builder.bytes (offset+40) kind;
    float 12 stroke_width; float 13 1.;
    builder.count<-builder.count+1
  let style fill stroke = match fill,stroke with None,None -> -1l,0l
    | _ -> Option.value ~default:0l fill,Option.value ~default:0l stroke
  let circle builder ~x ~y ~radius ?fill ?stroke ?(stroke_width=1.) () =
    if not (Float.is_finite radius) || radius<0. then invalid_arg "Shape_batch radius";
    let fill,stroke=style fill stroke in
    append builder 4l (x-.radius) (y-.radius) (x+.radius) (y+.radius) fill stroke
      (if stroke=0l then 0. else stroke_width)
  let rect builder ~x ~y ~width ~height ?fill ?stroke () =
    if not (Float.is_finite width && Float.is_finite height) || width<0. || height<0.
    then invalid_arg "Shape_batch extent";
    let fill,stroke=style fill stroke in
    append builder 0l x y (x+.width) (y+.height) fill stroke
      (if stroke=0l then 0. else 1.)
  let line builder ~x0 ~y0 ~x1 ~y1 ~color ~width =
    append builder 5l x0 y0 x1 y1 color 0l width
  let publish builder = {bytes=Bytes.sub builder.bytes 0 (builder.count*instance_bytes);
    count=builder.count; gpu=None}
end
