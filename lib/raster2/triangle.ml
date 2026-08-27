type vertex={x:float;y:float;depth:float;color:int32;u:float;v:float} type cull=Cull_none|Back|Front type texture={texture:Texture.t;filter:Texture.filter;address_u:Texture.address;address_v:Texture.address} type clip={x:int;y:int;width:int;height:int}
let ch c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let rgba r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let sample ?(lod=0.) t u v=match Texture.sample t.texture~address_u:t.address_u~address_v:t.address_v~filter:t.filter~u~v~lod with Ok value->value|Error _->0xffffffffl
let edge (a:vertex) (b:vertex) x y=(x-.a.x)*.(b.y-.a.y)-.(y-.a.y)*.(b.x-.a.x)
let top (a:vertex) (b:vertex)=a.y<b.y||(a.y=b.y&&a.x>b.x)
let visible ~cull (a:vertex) (b:vertex) (c:vertex)=let area=edge a b c.x c.y in area<>0.&&match cull with Back->area>0.|Front->area<0.|Cull_none->true
let draw_general ~color ~depth ~depth_state ~blend ~cull ~clip ~texture (a:vertex) (b:vertex) (c:vertex)=let area=edge a b c.x c.y in let rejected=area=0.||match cull with Back->area<=0.|Front->area>=0.|Cull_none->false in if not rejected then let a,b,area=if area<0. then b,a,-.area else a,b,area in let lod=match texture with None->0.|Some t->let dx1=b.x-.a.x and dy1=b.y-.a.y and dx2=c.x-.a.x and dy2=c.y-.a.y in let du1=b.u-.a.u and dv1=b.v-.a.v and du2=c.u-.a.u and dv2=c.v-.a.v in let inv=1./.(dx1*.dy2-.dx2*.dy1)in let dudx=(du1*.dy2-.du2*.dy1)*.inv and dudy=(du2*.dx1-.du1*.dx2)*.inv and dvdx=(dv1*.dy2-.dv2*.dy1)*.inv and dvdy=(dv2*.dx1-.dv1*.dx2)*.inv in let tw=float(Texture.width t.texture)and th=float(Texture.height t.texture)in let rho=max(sqrt((dudx*.tw)**2.+.(dvdx*.th)**2.))(sqrt((dudy*.tw)**2.+.(dvdy*.th)**2.))in if rho<=1. then 0. else log rho/.log 2. in let ar=ch a.color 24 and ag=ch a.color 16 and ab=ch a.color 8 and aa=ch a.color 0 and br=ch b.color 24 and bg=ch b.color 16 and bb=ch b.color 8 and ba=ch b.color 0 and cr=ch c.color 24 and cg=ch c.color 16 and cb=ch c.color 8 and ca=ch c.color 0 in let xmin=max clip.x(max 0(int_of_float(floor(min a.x(min b.x c.x)))))and ymin=max clip.y(max 0(int_of_float(floor(min a.y(min b.y c.y)))))and xmax=min(clip.x+clip.width-1)(min(Surface.width color-1)(int_of_float(ceil(max a.x(max b.x c.x)))))and ymax=min(clip.y+clip.height-1)(min(Surface.height color-1)(int_of_float(ceil(max a.y(max b.y c.y)))))in for y=ymin to ymax do for x=xmin to xmax do let px=float x+.0.5 and py=float y+.0.5 in let w0=edge b c px py and w1=edge c a px py and w2=edge a b px py in if (w0>0.||w0=0.&&top b c)&&(w1>0.||w1=0.&&top c a)&&(w2>0.||w2=0.&&top a b)then let w0=w0/.area and w1=w1/.area and w2=w2/.area in let z=w0*.a.depth+.w1*.b.depth+.w2*.c.depth in let pass=match depth with None->true|Some d->(match Depth_stencil.test_and_update d depth_state~x~y~depth:z with Ok p->p|_->false)in if pass then let f av bv cv=int_of_float(w0*.float av+.w1*.float bv+.w2*.float cv+.0.5)in let r=f ar br cr and g=f ag bg cg and blue=f ab bb cb and alpha=f aa ba ca in match texture with
  |None->Composite.pixel_int color~blend~x~y((r lsl 24)lor(g lsl 16)lor(blue lsl 8)lor alpha)
  |Some t->let q=sample~lod t(w0*.a.u+.w1*.b.u+.w2*.c.u)(w0*.a.v+.w1*.b.v+.w2*.c.v)in Composite.pixel_int color~blend~x~y(((r*ch q 24/255)lsl 24)lor((g*ch q 16/255)lsl 16)lor((blue*ch q 8/255)lsl 8)lor(alpha*ch q 0/255)) done done
let draw_solid ~color ~blend ~cull ~clip (a:vertex)(b:vertex)(c:vertex)=
  let area=edge a b c.x c.y in
  let rejected=area=0.||match cull with Back->area<=0.|Front->area>=0.|Cull_none->false in
  if not rejected then begin
    let a,b=if area<0. then b,a else a,b in
    let xmin=max clip.x(max 0(int_of_float(floor(min a.x(min b.x c.x)))))
    and ymin=max clip.y(max 0(int_of_float(floor(min a.y(min b.y c.y)))))
    and xmax=min(clip.x+clip.width-1)(min(Surface.width color-1)(int_of_float(ceil(max a.x(max b.x c.x)))))
    and ymax=min(clip.y+clip.height-1)(min(Surface.height color-1)(int_of_float(ceil(max a.y(max b.y c.y)))))in
    let packed=Int32.to_int a.color in
    for y=ymin to ymax do for x=xmin to xmax do
      let px=float x+.0.5 and py=float y+.0.5 in
      let w0=edge b c px py and w1=edge c a px py and w2=edge a b px py in
      if(w0>0.||w0=0.&&top b c)&&(w1>0.||w1=0.&&top c a)&&(w2>0.||w2=0.&&top a b)
      then Composite.pixel_int color~blend~x~y packed
    done done
  end
let draw_textured_solid ~color ~blend ~cull ~clip (texture:texture)
    (a:vertex) (b:vertex) (c:vertex)=
  let area=edge a b c.x c.y in
  let rejected=area=0.||match cull with Back->area<=0.|Front->area>=0.|Cull_none->false in
  if not rejected then begin
    let a,b,area=if area<0. then b,a,-.area else a,b,area in
    let dx1=b.x-.a.x and dy1=b.y-.a.y and dx2=c.x-.a.x and dy2=c.y-.a.y in
    let du1=b.u-.a.u and dv1=b.v-.a.v and du2=c.u-.a.u and dv2=c.v-.a.v in
    let inv=1./.(dx1*.dy2-.dx2*.dy1)in
    let dudx=(du1*.dy2-.du2*.dy1)*.inv and dudy=(du2*.dx1-.du1*.dx2)*.inv
    and dvdx=(dv1*.dy2-.dv2*.dy1)*.inv and dvdy=(dv2*.dx1-.dv1*.dx2)*.inv in
    let tw=float(Texture.width texture.texture)and th=float(Texture.height texture.texture)in
    let rho=max(sqrt((dudx*.tw)**2.+.(dvdx*.th)**2.))(sqrt((dudy*.tw)**2.+.(dvdy*.th)**2.))in
    let lod=if rho<=1. then 0. else log rho/.log 2. in
    let coordinates=[|0.;0.;lod|]in
    let tint=Int32.to_int a.color in
    let tr=(tint lsr 24)land 255 and tg=(tint lsr 16)land 255
    and tb=(tint lsr 8)land 255 and ta=tint land 255 in
    let xmin=max clip.x(max 0(int_of_float(floor(min a.x(min b.x c.x)))))
    and ymin=max clip.y(max 0(int_of_float(floor(min a.y(min b.y c.y)))))
    and xmax=min(clip.x+clip.width-1)(min(Surface.width color-1)(int_of_float(ceil(max a.x(max b.x c.x)))))
    and ymax=min(clip.y+clip.height-1)(min(Surface.height color-1)(int_of_float(ceil(max a.y(max b.y c.y)))))in
    for y=ymin to ymax do for x=xmin to xmax do
      let px=float x+.0.5 and py=float y+.0.5 in
      let w0=(px-.b.x)*.(c.y-.b.y)-.(py-.b.y)*.(c.x-.b.x)
      and w1=(px-.c.x)*.(a.y-.c.y)-.(py-.c.y)*.(a.x-.c.x)
      and w2=(px-.a.x)*.(b.y-.a.y)-.(py-.a.y)*.(b.x-.a.x)in
      if(w0>0.||w0=0.&&top b c)&&(w1>0.||w1=0.&&top c a)&&(w2>0.||w2=0.&&top a b)then begin
        let w0=w0/.area and w1=w1/.area and w2=w2/.area in
        let u=w0*.a.u+.w1*.b.u+.w2*.c.u
        and v=w0*.a.v+.w1*.b.v+.w2*.c.v in
        let qi=match texture.filter with
        |Texture.Nearest->
          let level=min(Texture.levels texture.texture-1)(int_of_float(floor lod))in
          let divisor=1 lsl level in
          let width=max 1((Texture.width texture.texture+divisor-1)/divisor)
          and height=max 1((Texture.height texture.texture+divisor-1)/divisor)in
          Texture.Private.texel_int_unchecked texture.texture ~level
            ~address_u:texture.address_u ~address_v:texture.address_v
            ~x:(int_of_float(floor(u*.float width)))
            ~y:(int_of_float(floor(v*.float height)))
        |Texture.Bilinear|Trilinear->
          Array.unsafe_set coordinates 0 u;
          Array.unsafe_set coordinates 1 v;
          Texture.Private.sample_int_unchecked texture.texture
            ~address_u:texture.address_u ~address_v:texture.address_v
            ~filter:texture.filter coordinates in
        Composite.pixel_int color~blend~x~y
          ((((tr*((qi lsr 24)land 255)/255)lsl 24)
          lor((tg*((qi lsr 16)land 255)/255)lsl 16)
          lor((tb*((qi lsr 8)land 255)/255)lsl 8)
          lor(ta*(qi land 255)/255)))
      end
    done done
  end
let draw ~color ~depth ~depth_state ~blend ~cull ~clip ~texture a b c=
  match depth,texture with
  |None,None when a.color=b.color&&a.color=c.color->draw_solid~color~blend~cull~clip a b c
  |None,Some texture when a.color=b.color&&a.color=c.color->draw_textured_solid~color~blend~cull~clip texture a b c
  |_->draw_general~color~depth~depth_state~blend~cull~clip~texture a b c
let interpolate_vertex (a:vertex) (b:vertex) t=let f n=int_of_float(float(ch a.color n)+.t*.float(ch b.color n-ch a.color n)+.0.5)in{x=a.x+.t*.(b.x-.a.x);y=a.y+.t*.(b.y-.a.y);depth=a.depth+.t*.(b.depth-.a.depth);color=rgba(f 24)(f 16)(f 8)(f 0);u=a.u+.t*.(b.u-.a.u);v=a.v+.t*.(b.v-.a.v)}
let fragment ~color ~depth ~depth_state ~blend ~texture ~x ~y (v:vertex)=let pass=match depth with None->true|Some d->(match Depth_stencil.test_and_update d depth_state~x~y~depth:v.depth with Ok p->p|_->false)in if pass then let out=match texture with None->v.color|Some t->let q=sample t v.u v.v in rgba(ch v.color 24*ch q 24/255)(ch v.color 16*ch q 16/255)(ch v.color 8*ch q 8/255)(ch v.color 0*ch q 0/255)in Composite.pixel color~blend~x~y out
let draw_line ~color ~depth ~depth_state ~blend ~clip ~texture ~width (a:vertex) (b:vertex)=let half=width*.0.5 and dx=b.x-.a.x and dy=b.y-.a.y in let length2=dx*.dx+.dy*.dy in let xmin=max clip.x(max 0(int_of_float(floor(min a.x b.x-.half))))and ymin=max clip.y(max 0(int_of_float(floor(min a.y b.y-.half))))and xmax=min(clip.x+clip.width-1)(min(Surface.width color-1)(int_of_float(ceil(max a.x b.x+.half))))and ymax=min(clip.y+clip.height-1)(min(Surface.height color-1)(int_of_float(ceil(max a.y b.y+.half))))in
  match depth,texture with
  |None,None when a.color=b.color->
    let packed=Int32.to_int a.color and pitch=Surface.pitch color in
    for y=ymin to ymax do for x=xmin to xmax do
      let px=float x+.0.5 and py=float y+.0.5 in
      let t=if length2=0. then 0. else let value=((px-.a.x)*.dx+.(py-.a.y)*.dy)/.length2 in if value<0. then 0. else if value>1. then 1. else value in
      let delta_x=px-.(a.x+.t*.dx) and delta_y=py-.(a.y+.t*.dy) in
      if delta_x*.delta_x+.delta_y*.delta_y<=half*.half then let offset=(y*pitch)+(x*4)in let old=Surface.Private.get_rgba_int_at_unchecked color offset in Surface.Private.set_rgba_int_at_unchecked color offset(Composite.Private.blend_int blend packed old)
    done done
  |_->for y=ymin to ymax do for x=xmin to xmax do let px=float x+.0.5 and py=float y+.0.5 in let t=if length2=0. then 0. else max 0.(min 1.(((px-.a.x)*.dx+.(py-.a.y)*.dy)/.length2))in let qx=a.x+.t*.dx and qy=a.y+.t*.dy in if(px-.qx)*.(px-.qx)+.(py-.qy)*.(py-.qy)<=half*.half then fragment~color~depth~depth_state~blend~texture~x~y(interpolate_vertex a b t)done done
let draw_point ~color ~depth ~depth_state ~blend ~clip ~texture ~size (v:vertex)=let half=size*.0.5 in let xmin=max clip.x(max 0(int_of_float(ceil(v.x-.half-.0.5))))and ymin=max clip.y(max 0(int_of_float(ceil(v.y-.half-.0.5))))and xmax=min(clip.x+clip.width-1)(min(Surface.width color-1)(int_of_float(floor(v.x+.half-.0.5))))and ymax=min(clip.y+clip.height-1)(min(Surface.height color-1)(int_of_float(floor(v.y+.half-.0.5))))in for y=ymin to ymax do for x=xmin to xmax do fragment~color~depth~depth_state~blend~texture~x~y v done done
