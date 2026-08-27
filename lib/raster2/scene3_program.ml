type vec2={x:float;y:float}
type vec3={x:float;y:float;z:float}
type vertex={clip_x:float;clip_y:float;clip_z:float;clip_w:float;world:vec3;normal:vec3;color:int32;tex_coord:vec2;varyings:float array}
type primitive=Point of vertex|Line of vertex*vertex|Triangle of vertex*vertex*vertex
type fragment_input={screen:vec2;depth:float;front_facing:bool;world:vec3;normal:vec3;color:int32;tex_coord:vec2;varyings:float array}
type fragment_output={color:int32;depth:float option}
type error=Non_finite|Varying_cardinality|Fragment_failure|Invalid_depth
type program={primitives:primitive array;varying_count:int;fragment:fragment_input->fragment_output option}
type projected={x:float;y:float;depth:float;inv_w:float;world:vec3;normal:vec3;color:int32;tex_coord:vec2;varyings:float array}
let finite=Float.is_finite
let valid varying_count (v:vertex)=List.for_all finite[v.clip_x;v.clip_y;v.clip_z;v.clip_w;v.world.x;v.world.y;v.world.z;v.normal.x;v.normal.y;v.normal.z;v.tex_coord.x;v.tex_coord.y]&&Array.length v.varyings=varying_count&&Array.for_all finite v.varyings
let channel c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let rgba r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let mix a b t=a+.t*.(b-.a)
let mix3 (a:vec3) (b:vec3) t:vec3={x=mix a.x b.x t;y=mix a.y b.y t;z=mix a.z b.z t}
let mix2 (a:vec2) (b:vec2) t:vec2={x=mix a.x b.x t;y=mix a.y b.y t}
let mix_color a b t=rgba(int_of_float(mix(float(channel a 24))(float(channel b 24))t+.0.5))(int_of_float(mix(float(channel a 16))(float(channel b 16))t+.0.5))(int_of_float(mix(float(channel a 8))(float(channel b 8))t+.0.5))(int_of_float(mix(float(channel a 0))(float(channel b 0))t+.0.5))
let interpolate a b t={clip_x=mix a.clip_x b.clip_x t;clip_y=mix a.clip_y b.clip_y t;clip_z=mix a.clip_z b.clip_z t;clip_w=mix a.clip_w b.clip_w t;world=mix3 a.world b.world t;normal=mix3 a.normal b.normal t;color=mix_color a.color b.color t;tex_coord=mix2 a.tex_coord b.tex_coord t;varyings=Array.mapi(fun i x->mix x b.varyings.(i)t)a.varyings}
let distance plane v=match plane with 0->v.clip_x+.v.clip_w|1->v.clip_w-.v.clip_x|2->v.clip_y+.v.clip_w|3->v.clip_w-.v.clip_y|4->v.clip_z+.v.clip_w|_->v.clip_w-.v.clip_z
let clip_plane plane polygon=match polygon with[]->[]|_->let output=ref[]and previous=ref(List.hd(List.rev polygon))in List.iter(fun current->let a=distance plane !previous and b=distance plane current in if b>=0. then(if a<0. then output:=interpolate !previous current(a/.(a-.b))::!output;output:=current::!output)else if a>=0. then output:=interpolate !previous current(a/.(a-.b))::!output;previous:=current)polygon;List.rev!output
let project clip v=let inv_w=1./.v.clip_w in{x=float clip.Triangle.x+.(v.clip_x*.inv_w+.1.)*.0.5*.float clip.width;y=float clip.y+.(1.-.(v.clip_y*.inv_w+.1.)*.0.5)*.float clip.height;depth=(v.clip_z*.inv_w+.1.)*.0.5;inv_w;world=v.world;normal=v.normal;color=v.color;tex_coord=v.tex_coord;varyings=v.varyings}
let edge a b x y=(x-.a.x)*.(b.y-.a.y)-.(y-.a.y)*.(b.x-.a.x)
let top a b=a.y<b.y||(a.y=b.y&&a.x>b.x)
let render ~color ~depth ~depth_state ~blend ~cull ~clip ~point_size ~line_width ~varying_count ~fragment primitives=
  let vertices=Array.to_list primitives|>List.concat_map(function Point a->[a]|Line(a,b)->[a;b]|Triangle(a,b,c)->[a;b;c])in
  if not(finite point_size&&finite line_width)||point_size<=0.||line_width<=0. then Error Non_finite else
  if List.exists(fun v->not(valid varying_count v))vertices then Error(if List.exists(fun(v:vertex)->Array.length v.varyings<>varying_count)vertices then Varying_cardinality else Non_finite)else
  let staged_color=Bytes.copy(Surface.bytes color)in match Surface.of_bytes~width:(Surface.width color)~height:(Surface.height color)~pitch:(Surface.pitch color)staged_color with Error _->Error Fragment_failure|Ok output->
  let staged_depth=match depth with None->Ok None|Some source->Result.map(fun copy->Some(source,copy))(Depth_stencil.of_bytes~width:(Depth_stencil.width source)~height:(Depth_stencil.height source)~pitch:(Depth_stencil.pitch source)(Bytes.copy(Depth_stencil.bytes source)))in match staged_depth with Error _->Error Fragment_failure|Ok staged_depth->
  let raster_depth=Option.map snd staged_depth and failure=ref None in
  let shade front x y a b c w0 w1 w2 =
    if !failure=None then
      let denominator=w0*.a.inv_w+.w1*.b.inv_w+.w2*.c.inv_w in
      if denominator<>0. then
        let weight w v=w*.v.inv_w/.denominator in
        let a0=weight w0 a and b0=weight w1 b and c0=weight w2 c in
        let vector (a:vec3)(b:vec3)(c:vec3):vec3=
          {x=a0*.a.x+.b0*.b.x+.c0*.c.x;y=a0*.a.y+.b0*.b.y+.c0*.c.y;z=a0*.a.z+.b0*.b.z+.c0*.c.z}in
        let world=vector a.world b.world c.world and normal=vector a.normal b.normal c.normal
        and tex_coord:vec2={x=a0*.a.tex_coord.x+.b0*.b.tex_coord.x+.c0*.c.tex_coord.x;y=a0*.a.tex_coord.y+.b0*.b.tex_coord.y+.c0*.c.tex_coord.y}
        and varyings=Array.init varying_count(fun i->a0*.a.varyings.(i)+.b0*.b.varyings.(i)+.c0*.c.varyings.(i))
        and base=rgba(int_of_float(a0*.float(channel a.color 24)+.b0*.float(channel b.color 24)+.c0*.float(channel c.color 24)+.0.5))(int_of_float(a0*.float(channel a.color 16)+.b0*.float(channel b.color 16)+.c0*.float(channel c.color 16)+.0.5))(int_of_float(a0*.float(channel a.color 8)+.b0*.float(channel b.color 8)+.c0*.float(channel c.color 8)+.0.5))(int_of_float(a0*.float(channel a.color 0)+.b0*.float(channel b.color 0)+.c0*.float(channel c.color 0)+.0.5))in
        let default_depth=w0*.a.depth+.w1*.b.depth+.w2*.c.depth in
        try match fragment{screen={x=float x+.0.5;y=float y+.0.5};depth=default_depth;front_facing=front;world;normal;color=base;tex_coord;varyings}with
        |None->()
        |Some(result:fragment_output)->
          let z=Option.value result.depth~default:default_depth in
          if not(finite z)||z<0.||z>1. then failure:=Some Invalid_depth else
          let pass=match raster_depth with None->true|Some buffer->(match Depth_stencil.test_and_update buffer depth_state~x~y~depth:z with Ok value->value|Error _->false)in
          if pass then Composite.pixel output~blend~x~y result.color
        with _->failure:=Some Fragment_failure
  in
  let triangle a b c=let polygon=Array.fold_left(fun values plane->clip_plane plane values)[a;b;c][|0;1;2;3;4;5|]in match polygon with first::second::rest->let first=project clip first and previous=ref(project clip second)in List.iter(fun value->let current=project clip value and signed_area=edge first !previous (project clip value).x (project clip value).y in let rejected=signed_area=0.||match cull with Triangle.Back->signed_area<=0.|Front->signed_area>=0.|Cull_none->false in if not rejected then let front=signed_area>0. in let a,b,area=if signed_area<0. then !previous,first,-.signed_area else first,!previous,signed_area in let xmin=max clip.x(max 0(int_of_float(floor(min a.x(min b.x current.x)))))and ymin=max clip.y(max 0(int_of_float(floor(min a.y(min b.y current.y)))))and xmax=min(clip.x+clip.width-1)(min(Surface.width output-1)(int_of_float(ceil(max a.x(max b.x current.x)))))and ymax=min(clip.y+clip.height-1)(min(Surface.height output-1)(int_of_float(ceil(max a.y(max b.y current.y)))))in for y=ymin to ymax do for x=xmin to xmax do let px=float x+.0.5 and py=float y+.0.5 in let w0=edge b current px py and w1=edge current a px py and w2=edge a b px py in if(w0>0.||w0=0.&&top b current)&&(w1>0.||w1=0.&&top current a)&&(w2>0.||w2=0.&&top a b)then shade front x y a b current(w0/.area)(w1/.area)(w2/.area)done done;previous:=current)rest|_->()
  in
  let point value=
    if Array.for_all(fun plane->distance plane value>=0.)[|0;1;2;3;4;5|]&&value.clip_w<>0. then
      let value=project clip value and half=point_size*.0.5 in
      let xmin=max clip.x(max 0(int_of_float(ceil(value.x-.half-.0.5))))and ymin=max clip.y(max 0(int_of_float(ceil(value.y-.half-.0.5))))and xmax=min(clip.x+clip.width-1)(min(Surface.width output-1)(int_of_float(floor(value.x+.half-.0.5))))and ymax=min(clip.y+clip.height-1)(min(Surface.height output-1)(int_of_float(floor(value.y+.half-.0.5))))in
      for y=ymin to ymax do for x=xmin to xmax do shade true x y value value value 1. 0. 0. done done
  in
  let clip_line a b=
    let a=ref a and b=ref b and visible=ref true in
    for plane=0 to 5 do
      let da=distance plane !a and db=distance plane !b in
      if da<0.&&db<0. then visible:=false
      else if da<0. then a:=interpolate !a !b (da/.(da-.db))
      else if db<0. then b:=interpolate !a !b (da/.(da-.db))
    done;
    if !visible then Some(!a,!b)else None
  in
  let line a b=match clip_line a b with None->()|Some(a,b)->
    let a=project clip a and b=project clip b in
    let half=line_width*.0.5 and dx=b.x-.a.x and dy=b.y-.a.y in
    let length2=dx*.dx+.dy*.dy in
    let xmin=max clip.x(max 0(int_of_float(floor(min a.x b.x-.half))))and ymin=max clip.y(max 0(int_of_float(floor(min a.y b.y-.half))))and xmax=min(clip.x+clip.width-1)(min(Surface.width output-1)(int_of_float(ceil(max a.x b.x+.half))))and ymax=min(clip.y+clip.height-1)(min(Surface.height output-1)(int_of_float(ceil(max a.y b.y+.half))))in
    for y=ymin to ymax do for x=xmin to xmax do
      let px=float x+.0.5 and py=float y+.0.5 in
      let t=if length2=0. then 0. else max 0.(min 1.(((px-.a.x)*.dx+.(py-.a.y)*.dy)/.length2))in
      let qx=a.x+.t*.dx and qy=a.y+.t*.dy in
      if(px-.qx)*.(px-.qx)+.(py-.qy)*.(py-.qy)<=half*.half then shade true x y a b b (1.-.t) t 0.
    done done
  in
  Array.iter(function Triangle(a,b,c)->triangle a b c|Point a->point a|Line(a,b)->line a b)primitives;
  match!failure with Some error->Error error|None->Bytes.blit staged_color 0(Surface.bytes color)0(Bytes.length staged_color);Option.iter(fun(destination,source)->Bytes.blit(Depth_stencil.bytes source)0(Depth_stencil.bytes destination)0(Bytes.length(Depth_stencil.bytes source)))staged_depth;Ok()
