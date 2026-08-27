type vertex={x:float;y:float;z:float;color:int32;u:float;v:float}
type topology=Point_list|Line_list|Line_strip|Line_loop|Triangle_list|Triangle_strip|Triangle_fan
type viewport={x:float;y:float;width:float;height:float;min_depth:float;max_depth:float}
type prepared={points:Triangle.vertex array;lines:(Triangle.vertex*Triangle.vertex)array;triangles:(Triangle.vertex*Triangle.vertex*Triangle.vertex)array;clip:Triangle.clip}
type error=Invalid_matrix|Non_finite|Invalid_cardinality|Invalid_index of int|Invalid_viewport|Invalid_scissor|Complexity_limit
type clip_vertex={x:float;y:float;z:float;w:float;color:int32;u:float;v:float}
let finite=Float.is_finite
let finite_vertex (p:vertex)=finite p.x&&finite p.y&&finite p.z&&finite p.u&&finite p.v
let channel c n=Int32.(to_int(logand(shift_right_logical c n)0xffl))
let rgba r g b a=Int32.(logor(shift_left(of_int r)24)(logor(shift_left(of_int g)16)(logor(shift_left(of_int b)8)(of_int a))))
let interpolate a b t=let f n=int_of_float(float(channel a.color n)+.t*.float(channel b.color n-channel a.color n)+.0.5)in{x=a.x+.t*.(b.x-.a.x);y=a.y+.t*.(b.y-.a.y);z=a.z+.t*.(b.z-.a.z);w=a.w+.t*.(b.w-.a.w);color=rgba(f 24)(f 16)(f 8)(f 0);u=a.u+.t*.(b.u-.a.u);v=a.v+.t*.(b.v-.a.v)}
let clip_plane distance polygon=match polygon with[]->[]|_->let output=ref[]and previous=ref(List.hd(List.rev polygon))in List.iter(fun current->let dp=distance !previous and dc=distance current in if dc>=0. then(if dp<0. then output:=interpolate !previous current(dp/.(dp-.dc))::!output;output:=current::!output)else if dp>=0. then output:=interpolate !previous current(dp/.(dp-.dc))::!output;previous:=current)polygon;List.rev !output
let prepare ~matrix ~(viewport:viewport) ~(scissor:Triangle.clip) ~topology ~(vertices:vertex array) ~indices=
 if Array.length matrix<>16 then Error Invalid_matrix else if not(Array.for_all finite matrix)then Error Non_finite else if not(finite viewport.x&&finite viewport.y&&finite viewport.width&&finite viewport.height&&finite viewport.min_depth&&finite viewport.max_depth)then Error Non_finite else if viewport.width<=0.||viewport.height<=0.||viewport.min_depth<0.||viewport.max_depth>1.||viewport.min_depth>viewport.max_depth then Error Invalid_viewport else if scissor.x<0||scissor.y<0||scissor.width<0||scissor.height<0 then Error Invalid_scissor else if not(Array.for_all finite_vertex vertices)then Error Non_finite else
 let triangle_count=match topology with Triangle_list->if Array.length indices mod 3<>0 then -1 else Array.length indices/3|Triangle_strip|Triangle_fan->max 0(Array.length indices-2)|Point_list|Line_list|Line_strip|Line_loop->0 in
 let cardinality_valid=match topology with Line_list->Array.length indices mod 2=0|Point_list|Line_strip|Line_loop|Triangle_list|Triangle_strip|Triangle_fan->triangle_count>=0 in
 if not cardinality_valid then Error Invalid_cardinality else if Array.length indices>1_048_575||triangle_count>349_525 then Error Complexity_limit else
 let bad=Array.find_opt(fun i->i<0||i>=Array.length vertices)indices in match bad with Some i->Error(Invalid_index i)|None->
 let transform (p:vertex)=let f row=p.x*.matrix.(row*4)+.p.y*.matrix.(row*4+1)+.p.z*.matrix.(row*4+2)+.matrix.(row*4+3)in{x=f 0;y=f 1;z=f 2;w=f 3;color=p.color;u=p.u;v=p.v}in
 let transformed=Array.map transform vertices and result=ref[]in
 let planes=[|(fun p->p.x+.p.w);(fun p->p.w-.p.x);(fun p->p.y+.p.w);(fun p->p.w-.p.y);(fun p->p.z);(fun p->p.w-.p.z)|]in
 let convert p=let inv=1./.p.w in let ndcx=p.x*.inv and ndcy=p.y*.inv and ndcz=p.z*.inv in{Triangle.x=viewport.x+.(ndcx+.1.)*.0.5*.viewport.width;y=viewport.y+.(1.-.(ndcy+.1.)*.0.5)*.viewport.height;depth=viewport.min_depth+.ndcz*.(viewport.max_depth-.viewport.min_depth);color=p.color;u=p.u*.inv;v=p.v*.inv}in
 let emit ia ib ic=let polygon=[transformed.(ia);transformed.(ib);transformed.(ic)]in let clipped=Array.fold_left(fun p plane->clip_plane plane p)polygon planes in match clipped with a::b::rest->let a=convert a and previous=ref(convert b)in List.iter(fun c->let c=convert c in result:=(a,!previous,c)::!result;previous:=c)rest|_->()in
 for i=0 to triangle_count-1 do match topology with Triangle_list->emit indices.(3*i)indices.(3*i+1)indices.(3*i+2)|Triangle_strip->if i land 1=0 then emit indices.(i)indices.(i+1)indices.(i+2)else emit indices.(i+1)indices.(i)indices.(i+2)|Triangle_fan->emit indices.(0)indices.(i+1)indices.(i+2)|Point_list|Line_list|Line_strip|Line_loop->()done;
 let inside p=Array.for_all(fun plane->plane p>=0.)planes&&p.w<>0. in
 let point_indices=match topology with Point_list->Array.to_list indices|_->[] in
 let points=point_indices|>List.filter_map(fun i->let p=transformed.(i)in if inside p then Some(convert p)else None)|>Array.of_list in
 let clip_segment a b=let lo=ref 0. and hi=ref 1. and valid=ref true in Array.iter(fun plane->let da=plane a and db=plane b in if da<0.&&db<0. then valid:=false else if da<0. then lo:=max !lo(da/.(da-.db))else if db<0. then hi:=min !hi(da/.(da-.db)))planes;if !valid&& !lo<= !hi then Some(convert(interpolate a b !lo),convert(interpolate a b !hi))else None in
 let line_indices=match topology with Line_list->List.init(Array.length indices/2)(fun i->indices.(2*i),indices.(2*i+1))|Line_strip->List.init(max 0(Array.length indices-1))(fun i->indices.(i),indices.(i+1))|Line_loop when Array.length indices>1->List.init(Array.length indices)(fun i->indices.(i),indices.((i+1)mod Array.length indices))|Point_list|Line_loop|Triangle_list|Triangle_strip|Triangle_fan->[] in
 let lines=List.filter_map(fun(a,b)->clip_segment transformed.(a)transformed.(b))line_indices|>Array.of_list in
 Ok{points;lines;triangles=Array.of_list(List.rev !result);clip=scissor}
