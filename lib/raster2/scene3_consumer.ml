type vertex={position:Scene3_lighting.vec3;normal:Scene3_lighting.vec3;color:int32;u:float;v:float}
type shading=Flat|Smooth
type mode=Faces|Wireframe|Vertices
type draw={matrix:float array;model_matrix:float array;camera_position:Scene3_lighting.vec3;viewport:Scene3.viewport;scissor:Triangle.clip;topology:Scene3.topology;vertices:vertex array;indices:int array;lighting:Scene3_lighting.descriptor;shadows:Shadow_map.prepared option array;shading:shading;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend;depth_stencil:Depth_stencil.state;mode:mode;line_width:float;point_size:float;program:Scene3_program.program option}
type target={color:Surface.t;depth:Depth_stencil.t option;multisample:Multisample.t option}
type error=Invalid_target|Invalid_vertex|Lighting_error of Scene3_lighting.error|Geometry_error of Scene3.error|Program_error of Scene3_program.error
type hdr_vertex={x:float;y:float;depth:float;inv_w:float;color:Scene3_lighting.color;u:float;v:float}
type fixed={geometry:Scene3.prepared;hdr_triangles:(hdr_vertex*hdr_vertex*hdr_vertex)array;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend;depth_stencil:Depth_stencil.state;mode:mode;line_width:float;point_size:float}
type prepared=Fixed of fixed|Program of draw*Scene3_program.program
let finite x=Float.is_finite x
let channel value shift=float Int32.(to_int(logand(shift_right_logical value shift)0xffl))/.255.
let modulate_color (value:Scene3_lighting.color) packed=
  {Scene3_lighting.r=value.r*.channel packed 24;g=value.g*.channel packed 16;
   b=value.b*.channel packed 8;a=value.a*.channel packed 0}
let world_position matrix (value:Scene3_lighting.vec3)=
  let x=matrix.(0)*.value.x+.matrix.(1)*.value.y+.matrix.(2)*.value.z+.matrix.(3)
  and y=matrix.(4)*.value.x+.matrix.(5)*.value.y+.matrix.(6)*.value.z+.matrix.(7)
  and z=matrix.(8)*.value.x+.matrix.(9)*.value.y+.matrix.(10)*.value.z+.matrix.(11)
  and w=matrix.(12)*.value.x+.matrix.(13)*.value.y+.matrix.(14)*.value.z+.matrix.(15)in
  if abs_float w<=1e-18 then{Scene3_lighting.x=x;y;z}
  else{Scene3_lighting.x=x/.w;y=y/.w;z=z/.w}
let world_normal matrix (value:Scene3_lighting.vec3)=
  let a=matrix.(0)and b=matrix.(1)and c=matrix.(2)
  and d=matrix.(4)and e=matrix.(5)and f=matrix.(6)
  and g=matrix.(8)and h=matrix.(9)and i=matrix.(10)in
  let determinant=a*.(e*.i-.f*.h)-.b*.(d*.i-.f*.g)+.c*.(d*.h-.e*.g)in
  if abs_float determinant<=1e-18 then value else
  let inverse=1./.determinant in
  {Scene3_lighting.x=((e*.i-.f*.h)*.value.x+.(f*.g-.d*.i)*.value.y+.(d*.h-.e*.g)*.value.z)*.inverse;
   y=((c*.h-.b*.i)*.value.x+.(a*.i-.c*.g)*.value.y+.(b*.g-.a*.h)*.value.z)*.inverse;
   z=((b*.f-.c*.e)*.value.x+.(c*.d-.a*.f)*.value.y+.(a*.e-.b*.d)*.value.z)*.inverse}
type hdr_clip={cx:float;cy:float;cz:float;cw:float;color:Scene3_lighting.color;tu:float;tv:float}
let interpolate_hdr a b t=
  let mix x y=x+.t*.(y-.x)in
  {cx=mix a.cx b.cx;cy=mix a.cy b.cy;cz=mix a.cz b.cz;cw=mix a.cw b.cw;
   color={Scene3_lighting.r=mix a.color.r b.color.r;g=mix a.color.g b.color.g;
     b=mix a.color.b b.color.b;a=mix a.color.a b.color.a};
   tu=mix a.tu b.tu;tv=mix a.tv b.tv}
let clip_hdr plane polygon=match polygon with[]->[]|_->
  let output=ref[]and previous=ref(List.hd(List.rev polygon))in
  List.iter(fun current->
    let before=plane !previous and here=plane current in
    if here>=0. then begin
      if before<0. then output:=interpolate_hdr !previous current(before/.(before-.here))::!output;
      output:=current::!output
    end else if before>=0. then
      output:=interpolate_hdr !previous current(before/.(before-.here))::!output;
    previous:=current)polygon;
  List.rev !output
let prepare_hdr ~matrix ~(viewport:Scene3.viewport) topology vertices indices colors=
  let transform index=
    let vertex=vertices.(index)in
    let f row=vertex.position.x*.matrix.(row*4)+.vertex.position.y*.matrix.(row*4+1)+.vertex.position.z*.matrix.(row*4+2)+.matrix.(row*4+3)in
    {cx=f 0;cy=f 1;cz=f 2;cw=f 3;color=colors.(index);tu=vertex.u;tv=vertex.v}in
  let transformed=Array.init(Array.length vertices)transform in
  let planes=[|(fun p->p.cx+.p.cw);(fun p->p.cw-.p.cx);(fun p->p.cy+.p.cw);
    (fun p->p.cw-.p.cy);(fun p->p.cz);(fun p->p.cw-.p.cz)|]in
  let project p=let inv=1./.p.cw in
    {x=viewport.x+.(p.cx*.inv+.1.)*.0.5*.viewport.width;
     y=viewport.y+.(1.-.(p.cy*.inv+.1.)*.0.5)*.viewport.height;
     depth=viewport.min_depth+.p.cz*.inv*.(viewport.max_depth-.viewport.min_depth);
     inv_w=inv;color=p.color;u=p.tu;v=p.tv}in
  let result=ref[]in
  let emit ia ib ic=
    let polygon=Array.fold_left(fun value plane->clip_hdr plane value)
      [transformed.(ia);transformed.(ib);transformed.(ic)]planes in
    match polygon with a::b::rest->
      let a=project a and previous=ref(project b)in
      List.iter(fun value->let current=project value in
        result:=(a,!previous,current)::!result;previous:=current)rest
    |_->()in
  let count=match topology with Scene3.Triangle_list->Array.length indices/3
    |Triangle_strip|Triangle_fan->max 0(Array.length indices-2)|_->0 in
  for index=0 to count-1 do
    match topology with
    |Scene3.Triangle_list->emit indices.(3*index)indices.(3*index+1)indices.(3*index+2)
    |Triangle_strip->if index land 1=0 then emit indices.(index)indices.(index+1)indices.(index+2)
      else emit indices.(index+1)indices.(index)indices.(index+2)
    |Triangle_fan->emit indices.(0)indices.(index+1)indices.(index+2)
    |_->()
  done;
  Array.of_list(List.rev !result)
let pack_color (value:Scene3_lighting.color)=
  let byte value=int_of_float(max 0.(min 1. value)*.255.+.0.5)in
  Int32.(logor(shift_left(of_int(byte value.r))24)
    (logor(shift_left(of_int(byte value.g))16)
      (logor(shift_left(of_int(byte value.b))8)(of_int(byte value.a)))))
let draw_hdr ~hdr ~surface ~depth ~depth_state ~blend ~cull ~clip ~texture
    (a:hdr_vertex)(b:hdr_vertex)(c:hdr_vertex)=
  let area=(c.x-.a.x)*.(b.y-.a.y)-.(c.y-.a.y)*.(b.x-.a.x)in
  let rejected=area=0.||match cull with Triangle.Back->area<=0.|Front->area>=0.|Cull_none->false in
  if not rejected then begin
    let a,b,area=if area<0. then b,a,-.area else a,b,area in
    let texture_coordinates=match texture with None->None|Some _->Some[|0.;0.;0.;0.;0.;0.|]in
    let xmin=max clip.Triangle.x(max 0(int_of_float(floor(min a.x(min b.x c.x)))))
    and ymin=max clip.y(max 0(int_of_float(floor(min a.y(min b.y c.y)))))
    and xmax=min(clip.x+clip.width-1)(min(Surface.width surface-1)(int_of_float(ceil(max a.x(max b.x c.x)))))
    and ymax=min(clip.y+clip.height-1)(min(Surface.height surface-1)(int_of_float(ceil(max a.y(max b.y c.y)))))in
    for y=ymin to ymax do for x=xmin to xmax do
      let px=float x+.0.5 and py=float y+.0.5 in
      let w0=(px-.b.x)*.(c.y-.b.y)-.(py-.b.y)*.(c.x-.b.x)
      and w1=(px-.c.x)*.(a.y-.c.y)-.(py-.c.y)*.(a.x-.c.x)
      and w2=(px-.a.x)*.(b.y-.a.y)-.(py-.a.y)*.(b.x-.a.x)in
      if w0>=(-1e-9)&&w1>=(-1e-9)&&w2>=(-1e-9) then begin
        let w0=w0/.area and w1=w1/.area and w2=w2/.area in
        let z=w0*.a.depth+.w1*.b.depth+.w2*.c.depth in
        let pass=match depth with None->true|Some value->
          Depth_stencil.Private.test_and_update_unchecked value depth_state~x~y~depth:z in
        if pass then begin
          let denominator=w0*.a.inv_w+.w1*.b.inv_w+.w2*.c.inv_w in
          let affine=abs_float denominator<=1e-12 in
          let p0=if affine then w0 else w0*.a.inv_w/.denominator
          and p1=if affine then w1 else w1*.b.inv_w/.denominator
          and p2=if affine then w2 else w2*.c.inv_w/.denominator in
          let red=p0*.a.color.r+.p1*.b.color.r+.p2*.c.color.r
          and green=p0*.a.color.g+.p1*.b.color.g+.p2*.c.color.g
          and blue=p0*.a.color.b+.p1*.b.color.b+.p2*.c.color.b
          and alpha=p0*.a.color.a+.p1*.b.color.a+.p2*.c.color.a in
          let sampled=match texture,texture_coordinates with
          |None,None->0
          |Some value,Some coordinates->
            let u=(w0*.a.u*.a.inv_w+.w1*.b.u*.b.inv_w+.w2*.c.u*.c.inv_w)/.denominator
            and v=(w0*.a.v*.a.inv_w+.w1*.b.v*.b.inv_w+.w2*.c.v*.c.inv_w)/.denominator in
            Array.unsafe_set coordinates 0 u;Array.unsafe_set coordinates 1 v;
            Texture.Private.sample_int_unchecked value.Triangle.texture
              ~address_u:value.address_u~address_v:value.address_v~filter:value.filter coordinates
          |_->assert false in
          let red=match texture with None->red|Some _->red*.float((sampled lsr 24)land 255)/.255.
          and green=match texture with None->green|Some _->green*.float((sampled lsr 16)land 255)/.255.
          and blue=match texture with None->blue|Some _->blue*.float((sampled lsr 8)land 255)/.255.
          and alpha=match texture with None->alpha|Some _->alpha*.float(sampled land 255)/.255. in
          match hdr with
          |None->
            let byte value=int_of_float(max 0.(min 1. value)*.255.+.0.5)in
            Composite.pixel_int surface~blend~x~y
              ((byte red lsl 24)lor(byte green lsl 16)lor(byte blue lsl 8)lor byte alpha)
          |Some values->
            let offset=(y*Surface.width surface+x)*4 in
            if blend=Composite.Copy||blend=Replace||alpha>=1. then begin
              values.(offset)<-red;values.(offset+1)<-green;
              values.(offset+2)<-blue;values.(offset+3)<-alpha
            end else begin
              let destination_alpha=values.(offset+3)in
              let output_alpha=alpha+.destination_alpha*.(1.-.alpha)in
              if output_alpha=0. then begin
                values.(offset)<-0.;values.(offset+1)<-0.;values.(offset+2)<-0.
              end else begin
                let retained=destination_alpha*.(1.-.alpha)in
                values.(offset)<-(red*.alpha+.values.(offset)*.retained)/.output_alpha;
                values.(offset+1)<-(green*.alpha+.values.(offset+1)*.retained)/.output_alpha;
                values.(offset+2)<-(blue*.alpha+.values.(offset+2)*.retained)/.output_alpha
              end;
              values.(offset+3)<-output_alpha
            end
        end
      end
    done done
  end
let rec render_offset ~hdr ~sample_offset ~(target:target) ~clear ~clear_depth ~clear_stencil ~draws=
 let width=Surface.width target.color and height=Surface.height target.color in
 let valid_depth=match target.depth with None->true|Some d->Depth_stencil.width d=width&&Depth_stencil.height d=height in
 let valid_msaa=match target.multisample with None->true|Some m->Multisample.width m=width&&Multisample.height m=height in
 if not valid_depth||not valid_msaa||not(finite clear_depth)||clear_depth<0.||clear_depth>1.||clear_stencil<0||clear_stencil>255 then Error Invalid_target else
 match target.multisample with
 | Some destination->
   let samples=Multisample.samples destination in
   begin match Multisample.create~width~height~samples()with Error _->Error Invalid_target|Ok staged->
   let failure=ref None and first_depth=ref None in
   let staged_bytes=Multisample.bytes staged and staged_pitch=Multisample.pitch staged
   and clear_bits=Int32.bits_of_float clear_depth in
   for y=0 to height-1 do for x=0 to width-1 do for sample=0 to samples-1 do
     let offset=y*staged_pitch+(x*samples+sample)*8 in
     Bytes.set_int32_le staged_bytes offset clear;
     Bytes.set_int32_le staged_bytes(offset+4)clear_bits
   done done done;
   for sample=0 to samples-1 do if !failure=None then
     match Multisample.sample_position~samples sample with Error _->failure:=Some Invalid_target|Ok(sample_x,sample_y)->
     match Surface.create~width~height()with Error _->failure:=Some Invalid_target|Ok sample_color->
     let sample_depth=match target.depth with None->Ok None|Some _->Result.map Option.some(Depth_stencil.create~width~height())in
     match sample_depth with Error _->failure:=Some Invalid_target|Ok sample_depth->
     begin match render_offset~hdr:None~sample_offset:(0.5-.sample_x,0.5-.sample_y)~target:{color=sample_color;depth=sample_depth;multisample=None}~clear~clear_depth~clear_stencil~draws with
     | Error error->failure:=Some error
     | Ok()->
       if sample=0 then first_depth:=Option.map(fun value->Bytes.copy(Depth_stencil.bytes value))sample_depth;
       let sample_pitch=Surface.pitch sample_color in
       for y=0 to height-1 do for x=0 to width-1 do
         let color=Surface.Private.get_rgba_int_at_unchecked sample_color
           (y*sample_pitch+x*4)in
         let destination=y*staged_pitch+(x*samples+sample)*8 in
         Bytes.set_int32_le staged_bytes destination(Int32.of_int color);
         (match sample_depth with
          |None->Bytes.set_int32_le staged_bytes(destination+4)(Int32.bits_of_float clear_depth)
          |Some value->Bytes.blit(Depth_stencil.bytes value)
             (y*Depth_stencil.pitch value+x*8)staged_bytes(destination+4)4)
       done done
     end
   done;
   match !failure with Some error->Error error|None->
     begin
       let half=samples/2 and target_pitch=Surface.pitch target.color
       and sums=Array.make 4 0 in
       for y=0 to height-1 do for x=0 to width-1 do
         Array.fill sums 0 4 0;
         for sample=0 to samples-1 do
           let packed=Int32.to_int(Bytes.get_int32_le staged_bytes
             (y*staged_pitch+(x*samples+sample)*8))in
           sums.(0)<-sums.(0)+((packed lsr 24)land 255);
           sums.(1)<-sums.(1)+((packed lsr 16)land 255);
           sums.(2)<-sums.(2)+((packed lsr 8)land 255);
           sums.(3)<-sums.(3)+(packed land 255)
         done;
         Surface.Private.set_rgba_int_at_unchecked target.color(y*target_pitch+x*4)
           ((((sums.(0)+half)/samples)lsl 24)lor(((sums.(1)+half)/samples)lsl 16)
             lor(((sums.(2)+half)/samples)lsl 8)lor((sums.(3)+half)/samples))
       done done;
       Bytes.blit(Multisample.bytes staged)0(Multisample.bytes destination)0(Bytes.length(Multisample.bytes staged));
       begin match target.depth,!first_depth with Some depth,Some bytes->Bytes.blit bytes 0(Depth_stencil.bytes depth)0(Bytes.length bytes)|_->()end;
       Ok()
     end
   end
 | None->
 let failure=ref None and prepared=ref[]in let fail e=if !failure=None then failure:=Some e in
 Array.iter(fun draw->match draw.program with
  | Some program->prepared:=Program(draw,program)::!prepared
  | None->match Scene3_lighting.prepare_with_shadows draw.lighting draw.shadows with Error e->fail(Lighting_error e)|Ok lighting->
  if Array.exists(fun v->let p=v.position and n=v.normal in not(finite p.x&&finite p.y&&finite p.z&&finite n.x&&finite n.y&&finite n.z&&finite v.u&&finite v.v))draw.vertices then fail Invalid_vertex else
  let invalid_index=Array.find_opt(fun index->index<0||index>=Array.length draw.vertices)draw.indices in
  if invalid_index<>None then fail(Geometry_error(Scene3.Invalid_index(Option.get invalid_index)))else
  if draw.topology=Scene3.Triangle_list&&Array.length draw.indices mod 3<>0 then fail(Geometry_error Scene3.Invalid_cardinality)else
  let flat_normal a b c=let a=draw.vertices.(a).position and b=draw.vertices.(b).position and c=draw.vertices.(c).position in let ux=b.x-.a.x and uy=b.y-.a.y and uz=b.z-.a.z and vx=c.x-.a.x and vy=c.y-.a.y and vz=c.z-.a.z in let x=uy*.vz-.uz*.vy and y=uz*.vx-.ux*.vz and z=ux*.vy-.uy*.vx in let length=sqrt(x*.x+.y*.y+.z*.z)in if length=0. then {Scene3_lighting.x=0.;y=0.;z=1.}else{x=x/.length;y=y/.length;z=z/.length}in
  let source_vertices,source_indices,source_topology=match draw.shading,draw.topology with
  | Flat,(Scene3.Triangle_list|Triangle_strip|Triangle_fan as topology)->
    let count=match topology with Triangle_list->Array.length draw.indices/3|Triangle_strip|Triangle_fan->max 0(Array.length draw.indices-2)|_->assert false in
    let vertices=if count=0 then[||]else Array.make(count*3)draw.vertices.(0)in
    for i=0 to count-1 do let a,b,c=match topology with Triangle_list->draw.indices.(3*i),draw.indices.(3*i+1),draw.indices.(3*i+2)|Triangle_strip->if i land 1=0 then draw.indices.(i),draw.indices.(i+1),draw.indices.(i+2)else draw.indices.(i+1),draw.indices.(i),draw.indices.(i+2)|Triangle_fan->draw.indices.(0),draw.indices.(i+1),draw.indices.(i+2)|_->assert false in let normal=flat_normal a b c in vertices.(3*i)<-{draw.vertices.(a)with normal};vertices.(3*i+1)<-{draw.vertices.(b)with normal};vertices.(3*i+2)<-{draw.vertices.(c)with normal}done;
    vertices,Array.init(count*3)(fun i->i),Scene3.Triangle_list
  | _->draw.vertices,draw.indices,draw.topology in
  let hdr_colors=Array.map(fun v->
    let position=world_position draw.model_matrix v.position
    and normal=world_normal draw.model_matrix v.normal in
    let view={Scene3_lighting.x=draw.camera_position.x-.position.x;
      y=draw.camera_position.y-.position.y;z=draw.camera_position.z-.position.z}in
    let fog_distance=sqrt(view.x*.view.x+.view.y*.view.y+.view.z*.view.z)in
    Scene3_lighting.shade_color lighting~position~normal~view
      ~front_facing:true~texture:None~fog_distance
      |>fun shaded->modulate_color shaded v.color)source_vertices in
  let vertices=Array.mapi(fun index v->
    {Scene3.x=v.position.x;y=v.position.y;z=v.position.z;
     color=pack_color hdr_colors.(index);u=v.u;v=v.v})source_vertices in
  let offset_x,offset_y=sample_offset in
  let viewport={draw.viewport with Scene3.x=draw.viewport.x+.offset_x;y=draw.viewport.y+.offset_y}in
  match Scene3.prepare~matrix:draw.matrix~viewport~scissor:draw.scissor~topology:source_topology~vertices~indices:source_indices with Error e->fail(Geometry_error e)|Ok geometry->
    let hdr_triangles=prepare_hdr~matrix:draw.matrix~viewport source_topology source_vertices source_indices hdr_colors in
    prepared:=Fixed{geometry;hdr_triangles;texture=draw.texture;cull=draw.cull;blend=draw.blend;depth_stencil=draw.depth_stencil;mode=draw.mode;line_width=draw.line_width;point_size=draw.point_size}::!prepared)draws;
 match !failure with Some e->Error e|None->
 let color_bytes=Bytes.copy(Surface.bytes target.color)in match Surface.of_bytes~width~height~pitch:(Surface.pitch target.color)color_bytes with Error _->Error Invalid_target|Ok color->
 let depth=match target.depth with None->None|Some source->let bytes=Bytes.copy(Depth_stencil.bytes source)in(match Depth_stencil.of_bytes~width~height~pitch:(Depth_stencil.pitch source)bytes with Ok value->Some(source,value)|Error _->None)in
 Surface.clear color clear;(match hdr with None->()|Some values->
   let r=channel clear 24 and g=channel clear 16 and b=channel clear 8 and a=channel clear 0 in
   for index=0 to Surface.width color*Surface.height color-1 do let offset=index*4 in
     values.(offset)<-r;values.(offset+1)<-g;values.(offset+2)<-b;values.(offset+3)<-a done);
 (match depth with None->()|Some(_,d)->ignore(Depth_stencil.clear d~depth:clear_depth~stencil:clear_stencil));
 let raster_depth=Option.map snd depth in
 let vertex_key(v:Triangle.vertex)=Int64.bits_of_float v.x,Int64.bits_of_float v.y,Int64.bits_of_float v.depth in
 let draw_line (draw:fixed) a b=Triangle.draw_line~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~clip:draw.geometry.clip~texture:draw.texture~width:draw.line_width a b in
 let draw_point (draw:fixed) v=Triangle.draw_point~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~clip:draw.geometry.clip~texture:draw.texture~size:draw.point_size v in
 let program_failure=ref None in
 List.iter(function
  | Program(draw,program)->
    if !program_failure=None then
      (match Scene3_program.render~sample_offset~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~cull:draw.cull~clip:draw.scissor~point_size:draw.point_size~line_width:draw.line_width~varying_count:program.varying_count~fragment:program.fragment program.primitives with Ok()->()|Error error->program_failure:=Some(Program_error error))
  | Fixed draw->match draw.mode with
  | Faces->Array.iter(fun(a,b,c)->draw_hdr~hdr~surface:color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~cull:draw.cull~clip:draw.geometry.clip~texture:draw.texture a b c)draw.hdr_triangles;Array.iter(fun(a,b)->draw_line draw a b)draw.geometry.lines;Array.iter(draw_point draw)draw.geometry.points
  | Wireframe->let seen=Hashtbl.create(Array.length draw.geometry.triangles*3+Array.length draw.geometry.lines)in let unique_line u v=let a=vertex_key u and b=vertex_key v in let key=if compare a b<=0 then a,b else b,a in if not(Hashtbl.mem seen key)then(Hashtbl.add seen key();draw_line draw u v)in Array.iter(fun(a,b,c)->if Triangle.visible~cull:draw.cull a b c then List.iter(fun(u,v)->unique_line u v)[a,b;b,c;c,a])draw.geometry.triangles;Array.iter(fun(a,b)->unique_line a b)draw.geometry.lines;Array.iter(draw_point draw)draw.geometry.points
  | Vertices->let seen=Hashtbl.create(Array.length draw.geometry.triangles*3+Array.length draw.geometry.lines*2+Array.length draw.geometry.points)in let unique_point v=let key=vertex_key v in if not(Hashtbl.mem seen key)then(Hashtbl.add seen key();draw_point draw v)in Array.iter(fun(a,b,c)->if Triangle.visible~cull:draw.cull a b c then List.iter unique_point[a;b;c])draw.geometry.triangles;Array.iter(fun(a,b)->unique_point a;unique_point b)draw.geometry.lines;Array.iter unique_point draw.geometry.points)(List.rev !prepared);
 match !program_failure with Some error->Error error|None->
 Bytes.blit color_bytes 0(Surface.bytes target.color)0(Bytes.length color_bytes);(match target.depth,depth with Some destination,Some(_,source)->Bytes.blit(Depth_stencil.bytes source)0(Depth_stencil.bytes destination)0(Bytes.length(Depth_stencil.bytes source))|_->());
 Ok()

let render ~target ~clear ~clear_depth ~clear_stencil ~draws=
  render_offset~hdr:None~sample_offset:(0.,0.)~target~clear~clear_depth~clear_stencil~draws
let render_float ~target ~clear ~clear_depth ~clear_stencil ~draws=
  if target.multisample<>None||Array.exists(fun draw->draw.program<>None||draw.mode<>Faces||
      draw.texture<>None||draw.lighting.material.diffuse.a<>1.||
      match draw.blend with Composite.Copy|Replace|Source_over|Alpha->false|_->true)draws
  then Error Invalid_target else
  let values=Array.make(Surface.width target.color*Surface.height target.color*4)0. in
  match render_offset~hdr:(Some values)~sample_offset:(0.,0.)~target~clear~clear_depth~clear_stencil~draws with
  |Error _ as error->error|Ok()->Ok values
