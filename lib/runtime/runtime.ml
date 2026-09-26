type stats = {
  frames : int64;
  presented : int64;
  logical_draws : int64;
  logical_passes : int64;
  logical_submissions : int64;
  pipeline_cache_entries : int;
  mesh_cache_entries : int;
  uploaded_bytes : int64;
  gpu_timing_supported : bool;
  gpu_duration_seconds : float;
  gpu_sample_count : int64;
  retained_plan_builds : int64;
  retained_plan_hits : int64;
  retained_plan_misses : int64;
  retained_plan_evictions : int64;
  retained_plan_executions : int64;
  retained_plan_entries : int;
  retained_plan_capacity : int;
  sun_shadow_passes : int64;
}

type frame_facts = {
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  pixel_scale_x : float;
  pixel_scale_y : float;
}

(* The last Retina-scaled draw list, keyed by the physical identity of its
   input list and facts. A retained scene hands the runtime the same list
   every frame, so the scaled copy is built once instead of per frame. *)
type scaled_cache = {
  mutable scaled_input : Scene_execution.sampled_draw list;
  mutable scaled_facts : frame_facts option;
  mutable scaled_output : Scene_execution.sampled_draw list;
}

let new_scaled_cache () = { scaled_input = []; scaled_facts = None; scaled_output = [] }

(* Frame accounting shared by window and offscreen targets: one successful
   render or replay is one frame, pass and submission. *)
type counters = {
  mutable frames : int64;
  mutable presented : int64;
  mutable logical_draws : int64;
  mutable logical_passes : int64;
  mutable logical_submissions : int64;
}

let new_counters () =
  { frames = 0L; presented = 0L; logical_draws = 0L; logical_passes = 0L; logical_submissions = 0L }

let count counters draw_count ~presented =
  counters.frames <- Int64.succ counters.frames;
  if presented then counters.presented <- Int64.succ counters.presented;
  counters.logical_draws <- Int64.add counters.logical_draws (Int64.of_int draw_count);
  counters.logical_passes <- Int64.succ counters.logical_passes;
  counters.logical_submissions <- Int64.succ counters.logical_submissions

type presentation_facts = {
  title : string;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  position : (int * int) option;
  pixel_density : float;
  display_scale : float;
  refresh_rate : float option;
  vsync : bool;
}

type window = {
  handle : Sdl3.Window.t;
  view : Sdl3.Metal_view.t;
  vsync : bool;
  mutable cursors : ([ `Default | `Horizontal_resize | `Vertical_resize ] * Sdl3.Cursor.t) list;
  mutable cursor_shape : [ `Default | `Horizontal_resize | `Vertical_resize ] option;
}

(* One render target: a presenting window, or ([window = None]) an owned
   offscreen texture. *)
type t = {
  renderer : Scene_execution.t;
  window : window option;
  title : string;
  mutable facts : frame_facts;
  mutable presentation : presentation_facts option;
  counters : counters;
  scaled : scaled_cache;
  mutable dead : bool;
}

let stale operation = Error (Ogpu.Error.make operation Ogpu.Error.Stale_handle "runtime is destroyed")

let device value =
  if value.dead then stale "Runtime.device" else Ok (Scene_execution.device value.renderer)

let target value =
  if value.dead then stale "Runtime.target" else Ok (Scene_execution.target value.renderer)

let error op text = Error (Ogpu.Error.make op Ogpu.Error.Invalid_state text)
let sdl op = function Ok x -> Ok x | Error e -> error op (Format.asprintf "%a" Sdl3.pp_error e)
let clipboard_set_text text = sdl "Runtime.clipboard_set_text" (Sdl3.Clipboard.set_text text)
let clipboard_get_text () = sdl "Runtime.clipboard_get_text" (Sdl3.Clipboard.get_text ())

let facts window =
  match (Sdl3.Window.size window, Sdl3.Window.size_in_pixels window) with
  | Ok (lw, lh), Ok (dw, dh) when lw > 0 && lh > 0 && dw > 0 && dh > 0 ->
      Ok
        {
          logical_width = lw;
          logical_height = lh;
          drawable_width = dw;
          drawable_height = dh;
          pixel_scale_x = float dw /. float lw;
          pixel_scale_y = float dh /. float lh;
        }
  | Error e, _ -> sdl "Runtime.facts" (Error e)
  | _, Error e -> sdl "Runtime.facts" (Error e)
  | _ -> error "Runtime.facts" "window dimensions are invalid"

let source_scene3_header =
  {|#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]];
#ifdef PRISMEL_POINTS
float point_size [[point_size]];
#endif
float4 color; float2 uv; float3 world; float3 normal; };
inline float scene_double(const device uchar *p){uint lo=*reinterpret_cast<const device uint*>(p);uint hi=*reinterpret_cast<const device uint*>(p+4);ulong bits=(ulong(hi)<<32)|ulong(lo);float sign=(hi>>31)==0?1.:-1.;int exponent=int((bits>>52)&0x7fful);ulong fraction=bits&0xffffffffffffful;if(exponent==0)return sign*ldexp(float(fraction)/4503599627370496.,-1022);return sign*ldexp(1.+float(fraction)/4503599627370496.,exponent-1023);}
inline float4 scene_mul(const device float *m,float4 v){return float4(dot(v,float4(m[0],m[1],m[2],m[3])),dot(v,float4(m[4],m[5],m[6],m[7])),dot(v,float4(m[8],m[9],m[10],m[11])),dot(v,float4(m[12],m[13],m[14],m[15])));}
vertex Out scene_vertex(uint i [[vertex_id]],uint instance_id [[instance_id]],const device uchar *input [[buffer(0)]],const device float *surface [[buffer(6)]],const device float *instances [[buffer(7)]]){const device uchar*p=input+i*68;const device float*transform=surface[83]>.5?instances+instance_id*48:surface;Out v;float4 local=float4(scene_double(p),scene_double(p+8),scene_double(p+16),1.);float4 normal=float4(scene_double(p+24),scene_double(p+32),scene_double(p+40),0.);v.world=scene_mul(transform+16,local).xyz;v.normal=normalize(scene_mul(transform+32,normal).xyz);v.position=scene_mul(transform,local);
#ifdef PRISMEL_POINTS
v.point_size=1.;
#endif
v.color=unpack_unorm4x8_to_float(*reinterpret_cast<const device uint*>(p+48)).abgr;v.uv=float2(scene_double(p+52),scene_double(p+60));return v;}
inline void scene_light(Out v,const device float*l,thread float3&direction,thread float&strength){strength=l[8];if(l[0]<.5){direction=normalize(-float3(l[1],l[2],l[3]));}else if(l[0]<2.5){float3 delta=float3(l[1],l[2],l[3])-v.world;float distance=length(delta);direction=distance>0.?delta/distance:float3(0.);float attenuation=l[0]<1.5?l[9]+l[10]*distance+l[11]*distance*distance:l[15]+l[16]*distance+l[17]*distance*distance;strength=attenuation>0.?strength/attenuation:0.;if(l[0]>=1.5){float cosine=dot(-direction,normalize(float3(l[9],l[10],l[11])));strength*=cosine<l[13]?0.:pow(max(cosine,0.),l[14]);}}else{float3 axis=normalize(float3(l[9],l[10],l[11]));float3 reference=abs(axis.z)<.999?float3(0.,0.,1.):float3(0.,1.,0.);float3 u=normalize(cross(reference,axis));float3 w=cross(axis,u);int side=max(1,int(round(sqrt(l[14]))));float3 weighted=float3(0.);float total=0.;for(int row=0;row<side;row++)for(int column=0;column<side;column++){float a=(float(column)+.5)/float(side)-.5,b=(float(row)+.5)/float(side)-.5;float3 delta=float3(l[1],l[2],l[3])+a*l[12]*u+b*l[13]*w-v.world;float distance=length(delta);if(distance>0.){float3 ray=delta/distance;float facing=max(dot(axis,-ray),0.);float attenuation=l[15]+l[16]*distance+l[17]*distance*distance;float weight=attenuation>0.?l[8]*facing/(float(side*side)*attenuation):0.;weighted+=ray*weight;total+=weight;}}direction=length(weighted)>0.?normalize(weighted):float3(0.);strength=total;}}
inline float4 scene_surface(Out v,const device float*p,float4 tex,bool front,thread const float*visibility,bool shadowed){float3 n=normalize(v.normal);if(p[74]>.5&&!front)n=-n;float3 view=normalize(float3(p[48],p[49],p[50])-v.world);float3 primary=float3(p[64],p[65],p[66])+float3(p[52],p[53],p[54])*float3(p[69],p[70],p[71]);float3 spec=float3(0.);int count=min(int(p[73]),64);for(int i=0;i<count;i++){const device float*l=p+84+i*20;float3 direction;float strength;scene_light(v,l,direction,strength);if(shadowed)strength*=visibility[i];float diffuse=max(dot(n,direction),0.)*strength;primary+=float3(p[56],p[57],p[58])*float3(l[4],l[5],l[6])*diffuse;if(diffuse>0.){float3 halfv=normalize(direction+view);float shine=pow(max(dot(n,halfv),0.),p[68])*strength;spec+=float3(p[60],p[61],p[62])*float3(l[4],l[5],l[6])*shine;}}float3 modulation=v.color.rgb*tex.rgb;float3 rgb=p[75]>.5?primary*modulation+spec:(primary+spec)*modulation;return float4(rgb,p[59]*v.color.a*tex.a);}
|}

let source_scene3 =
  source_scene3_header
  ^ {|fragment float4 scene_fragment(Out value [[stage_in]],const device float*p [[buffer(6)]],bool front [[front_facing]]){float none[1]={1.};return scene_surface(value,p,float4(1.),front,none,false);}
|}

let source_scene3_textured =
  source_scene3_header
  ^ {|fragment float4 scene_fragment(Out value [[stage_in]],texture2d<float> image [[texture(1)]],sampler sampling [[sampler(2)]],const device float*p [[buffer(6)]],bool front [[front_facing]]){float none[1]={1.};return scene_surface(value,p,image.sample(sampling,value.uv),front,none,false);}
|}

let source_scene3_shadow =
  source_scene3_header
  ^ {|
inline float scene_shadow_depth(float4 c){float3 b=round(c.rgb*255.);return (b.x*65536.+b.y*256.+b.z)/16777215.;}
inline float scene_shadow_visibility(Out value,const device float*m,float constant_bias,float slope_bias,float strength,int radius,int2 origin,int2 extent,texture2d<float>depth_map,sampler depth_sampler,float3 light_direction){
  float4 world=float4(value.world,1.);float4 clip=float4(dot(world,float4(m[0],m[1],m[2],m[3])),dot(world,float4(m[4],m[5],m[6],m[7])),dot(world,float4(m[8],m[9],m[10],m[11])),dot(world,float4(m[12],m[13],m[14],m[15])));if(clip.w<=0.)return 1.;
  float2 uv=float2(clip.x/clip.w*.5+.5,.5-clip.y/clip.w*.5);float z=clip.z/clip.w;if(any(uv<0.)||any(uv>1.)||z<0.||z>1.)return 1.;float facing=clamp(dot(normalize(value.normal),light_direction),0.,1.);float compare_depth=z-(constant_bias+slope_bias*(1.-facing));int2 center=origin+int2(floor(uv*float2(extent)));float visible=0.;float count=0.;
  for(int y=-radius;y<=radius;y++)for(int x=-radius;x<=radius;x++){int2 q=center+int2(x,y);count+=1.;if(q.x<origin.x||q.y<origin.y||q.x>=origin.x+extent.x||q.y>=origin.y+extent.y)visible+=1.;else{float2 sample_uv=(float2(q)+.5)/float2(depth_map.get_width(),depth_map.get_height());visible+=compare_depth<=scene_shadow_depth(depth_map.sample(depth_sampler,sample_uv))?1.:0.;}}return(1.-strength)+strength*(visible/count);
}
fragment float4 scene_fragment(Out value [[stage_in]],texture2d<float> image [[texture(1)]],sampler sampling [[sampler(2)]],const device float *p [[buffer(3)]],texture2d<float> depth_map [[texture(4)]],sampler depth_sampler [[sampler(5)]],const device float*surface [[buffer(6)]],bool front [[front_facing]]){
  float visibility[64];for(int i=0;i<64;i++)visibility[i]=1.;if(p[3]==1357911.){int entries=min(int(p[2]),64);for(int i=0;i<entries;i++){const device float*entry=p+4+i*25;if(entry[0]>.5){int light_index=i;float3 direction;float light_strength;scene_light(value,surface+84+light_index*20,direction,light_strength);visibility[light_index]=scene_shadow_visibility(value,entry+5,entry[21],entry[22],entry[23],int(entry[24]),int2(entry[1],entry[2]),int2(entry[3],entry[4]),depth_map,depth_sampler,direction);}}}else{float3 direction;float light_strength;scene_light(value,surface+84,direction,light_strength);visibility[0]=scene_shadow_visibility(value,p,p[16],p[17],p[18],int(p[19]),int2(0),int2(depth_map.get_width(),depth_map.get_height()),depth_map,depth_sampler,direction);}return scene_surface(value,surface,image.sample(sampling,value.uv),front,visibility,true);
}
|}

(* Environment-lit Scene3 under a World (specification/environment.md).
   buffer(3) is the World block: 0..26 irradiance SH9 rgb, 27 exposure
   multiplier, 28..30 sun direction, 31 sun present, 32..34 sun irradiance,
   35 background (0 camera map, 1 color), 36..38 background color, 39 shadow
   (1 the depths below, 2 the renderer's sun map at texture(8), packed 24-bit
   depth in RGBA8), 40..55 shadow view-projection, 56 bias, 57 slope bias,
   58 strength, 59 PCF radius, 60..61 shadow size, 64.. shadow depths.
   texture(4) holds the 6 GGX-prefiltered mips. Surface words 76..78 are the
   mode (0 lit, 1 unlit, 2 background), roughness and f0; a background draw
   carries the inverse view-projection at 84 and binds the camera map as
   texture(1). texture(9)/sampler(10) is the camera map again, for
   near-mirror reflections. The BRDF and the tone map are copied from
   pathtrace.metal. *)
let source_scene3_world =
  source_scene3_header
  ^ {|
inline float d_ggx(float noh, float a2) {
  float d = noh * noh * (a2 - 1.0f) + 1.0f;
  return a2 / (M_PI_F * d * d);
}
inline float v_smith(float nov, float nol, float a2) {
  float gv = nol * sqrt(nov * nov * (1.0f - a2) + a2);
  float gl = nov * sqrt(nol * nol * (1.0f - a2) + a2);
  return 0.5f / max(gv + gl, 1e-6f);
}
inline float3 fresnel(float3 f0, float voh) {
  float f = pow(1.0f - voh, 5.0f);
  return f0 + (1.0f - f0) * f;
}
// ks scales the specular lobe (see the mirror blend in scene_fragment).
inline float3 eval_brdf(float3 ns, float3 v, float3 l, float3 diffuse, float3 f0, float a2, float ks) {
  float3 h = normalize(l + v);
  float nol = max(dot(ns, l), 1e-4f), nov = max(dot(ns, v), 1e-4f);
  float noh = max(dot(ns, h), 0.0f), voh = max(dot(v, h), 1e-4f);
  float3 F = fresnel(f0, voh);
  return diffuse * (1.0f - F) / M_PI_F + ks * d_ggx(noh, a2) * v_smith(nov, nol, a2) * F;
}
inline uchar4 resolved_rgba(float3 linear, float exposure) {
  float3 c = linear * exposure;
  c = (c * (2.51f * c + 0.03f)) / (c * (2.43f * c + 0.59f) + 0.14f);
  c = pow(clamp(c, 0.0f, 1.0f), 1.0f / 2.2f);
  return uchar4(uchar(c.x * 255.0f + 0.5f), uchar(c.y * 255.0f + 0.5f),
                uchar(c.z * 255.0f + 0.5f), 255);
}
inline float4 world_output(float3 linear,float exposure,float alpha){return float4(float4(resolved_rgba(linear,exposure)).rgb/255.0f,alpha);}
inline float2 world_uv(float3 d){return float2(atan2(d.x,-d.z)/(2.*M_PI_F)+.5,acos(clamp(d.y,-1.,1.))/M_PI_F);}
inline float3 world_irradiance(const device float*w,float3 n){float x=n.x,y=n.y,z=n.z;float b[9]={0.282095,0.488603*y,0.488603*z,0.488603*x,1.092548*x*y,1.092548*y*z,0.315392*(3.*z*z-1.),1.092548*x*z,0.546274*(x*x-y*y)};float3 e=float3(0.);for(int i=0;i<9;i++)e+=float3(w[i*3],w[i*3+1],w[i*3+2])*b[i];return max(e,0.);}
// Karis' analytic split-sum environment BRDF (mobile approximation).
inline float3 env_brdf(float3 f0,float roughness,float nov){const float4 c0=float4(-1.,-.0275,-.572,.022);const float4 c1=float4(1.,.0425,1.04,-.04);float4 r=roughness*c0+c1;float a004=min(r.x*r.x,exp2(-9.28*nov))*r.x+r.y;float2 ab=float2(-1.04,1.04)*a004+r.zw;return f0*ab.x+ab.y;}
inline float world_map_depth(float4 c){float3 b=round(c.rgb*255.);return(b.x*65536.+b.y*256.+b.z)/16777215.;}
inline float world_shadow(Out v,const device float*w,texture2d<float> sun_map){if(w[39]<.5)return 1.;float4 clip=scene_mul(w+40,float4(v.world,1.));if(clip.w<=0.)return 1.;
  float2 uv=float2(clip.x/clip.w*.5+.5,.5-clip.y/clip.w*.5);float z=clip.z/clip.w;if(any(uv<0.)||any(uv>1.)||z<0.||z>1.)return 1.;
  float facing=clamp(dot(normalize(v.normal),float3(w[28],w[29],w[30])),0.,1.);float compare=z-(w[56]+w[57]*(1.-facing));
  int width=int(w[60]),height=int(w[61]),radius=int(w[59]);int2 c=int2(floor(uv*float2(width,height)));float visible=0.,count=0.;
  for(int y=-radius;y<=radius;y++)for(int x=-radius;x<=radius;x++){int2 q=c+int2(x,y);count+=1.;visible+=(q.x<0||q.y<0||q.x>=width||q.y>=height||compare<=(w[39]>1.5?world_map_depth(sun_map.read(uint2(q))):w[64+q.y*width+q.x]))?1.:0.;}
  return(1.-w[58])+w[58]*visible/count;}
// Kind 4: an extracted World rect, centre 1..3, half-extent axes 9..11 and
// 12..14, emitting normal 15..17, 2x2 samples, inverse-square falloff.
inline void world_light(Out v,const device float*l,thread float3&direction,thread float&strength){if(l[0]<3.5){scene_light(v,l,direction,strength);return;}
  float3 u=float3(l[9],l[10],l[11]),w=float3(l[12],l[13],l[14]),axis=float3(l[15],l[16],l[17]);float3 weighted=float3(0.);float total=0.;
  for(int row=0;row<2;row++)for(int column=0;column<2;column++){float3 delta=float3(l[1],l[2],l[3])+(float(column)-.5)*u+(float(row)-.5)*w-v.world;float d2=dot(delta,delta);if(d2>0.){float3 ray=delta*rsqrt(d2);float weight=l[8]*max(dot(axis,-ray),0.)/(4.*d2);weighted+=ray*weight;total+=weight;}}
  direction=length(weighted)>0.?normalize(weighted):float3(0.);strength=total;}
fragment float4 scene_fragment(Out value [[stage_in]],texture2d<float> image [[texture(1)]],sampler sampling [[sampler(2)]],const device float*w [[buffer(3)]],texture2d<float> specular [[texture(4)]],sampler specular_sampler [[sampler(5)]],const device float*p [[buffer(6)]],texture2d<float> sun_map [[texture(8)]],texture2d<float> environment [[texture(9)]],sampler environment_sampler [[sampler(10)]],bool front [[front_facing]]){
  float exposure=w[27];
  if(p[76]>1.5){float4 a=scene_mul(p+84,float4(value.world.xy,0.,1.)),b=scene_mul(p+84,float4(value.world.xy,1.,1.));float3 d=normalize(b.xyz/b.w-a.xyz/a.w);
    float3 radiance=w[35]>.5?float3(w[36],w[37],w[38]):image.sample(sampling,world_uv(d)).rgb;return world_output(radiance,exposure,1.);}
  float4 tex=image.sample(sampling,value.uv);float3 modulation=value.color.rgb*tex.rgb;float alpha=p[59]*value.color.a*tex.a;
  if(p[76]>.5)return float4(float3(p[64],p[65],p[66])*modulation,alpha);
  float3 n=normalize(value.normal);if(p[74]>.5&&!front)n=-n;float3 v=normalize(float3(p[48],p[49],p[50])-value.world);
  float3 albedo=pow(float3(p[56],p[57],p[58])*modulation,2.2);float rough=max(p[77],.03),a=rough*rough,a2=a*a;float3 f0=float3(p[78]);
  float nov=max(dot(n,v),1e-4);float3 spec=env_brdf(f0,rough,nov);
  // Below roughness 0.2 the reflection blends toward the full-resolution
  // camera map (emitters and sun disc included), so the analytic sun and
  // rect highlights fade by the same weight to avoid counting them twice.
  float ks=saturate(p[77]/.2);float2 r=world_uv(reflect(-v,n));
  float3 reflection=specular.sample(specular_sampler,r,level(max(rough,.2)*5.)).rgb;
  if(ks<1.)reflection=mix(environment.sample(environment_sampler,r).rgb,reflection,ks);
  float3 color=albedo/M_PI_F*world_irradiance(w,n)*(1.-spec)+reflection*spec;
  color+=pow(float3(p[64],p[65],p[66])*modulation,2.2);
  if(w[31]>.5){float3 l=float3(w[28],w[29],w[30]);float nol=dot(n,l);if(nol>0.)color+=eval_brdf(n,v,l,albedo,f0,a2,ks)*float3(w[32],w[33],w[34])*nol*world_shadow(value,w,sun_map);}
  int count=min(int(p[73]),64);for(int i=0;i<count;i++){const device float*l=p+84+i*20;float3 direction;float strength;world_light(value,l,direction,strength);float nol=dot(n,direction);
    if(nol>0.&&strength>0.)color+=eval_brdf(n,v,direction,albedo,f0,a2,ks)*float3(l[4],l[5],l[6])*strength*M_PI_F*nol;}
  return world_output(color,exposure,alpha);
}
|}

(* The World sun map pass: opaque World geometry through the sun
   view-projection at World block words 40..55, writing 24-bit depth packed
   into RGBA8 (the Scene3 shadow texture encoding). *)
let source_scene3_sun_depth =
  source_scene3_header
  ^ {|
struct Sun { float4 position [[position]]; };
vertex Sun sun_vertex(uint i [[vertex_id]],uint instance_id [[instance_id]],const device uchar *input [[buffer(0)]],const device float *w [[buffer(3)]],const device float *surface [[buffer(6)]],const device float *instances [[buffer(7)]]){const device uchar*p=input+i*68;const device float*transform=surface[83]>.5?instances+instance_id*48:surface;Sun s;s.position=scene_mul(w+40,scene_mul(transform+16,float4(scene_double(p),scene_double(p+8),scene_double(p+16),1.)));return s;}
fragment float4 sun_fragment(Sun s [[stage_in]]){uint d=uint(saturate(s.position.z)*16777215.+.5);return float4(float((d>>16)&255u),float((d>>8)&255u),float(d&255u),255.)/255.;}
|}

let make_sun_depth_pipeline backend_device =
  let buffer binding = { Ogpu.Shader.group = 0; binding; kind = Storage_buffer; visibility = [ Vertex ] } in
  let artifact bindings =
    Ogpu.Shader.create
      {
        backend = "metal";
        label = Some "scene-sun-depth";
        bytes = Bytes.of_string source_scene3_sun_depth;
        entry_points = [ { name = "sun_vertex"; stage = Vertex }; { name = "sun_fragment"; stage = Fragment } ];
        bindings;
      }
  in
  let ( let* ) = Result.bind in
  let* vertex = artifact (List.map buffer [ 0; 3; 6; 7 ]) in
  let* fragment = artifact [] in
  let* bindings =
    Ogpu.Binding.create_layout
      (List.map (fun binding -> { Ogpu.Binding.binding; kind = Buffer; visibility = [ Vertex ] }) [ 0; 3; 6; 7 ])
  in
  let* layout =
    Ogpu.Binding.create_pipeline_layout
      ~device:(Ogpu.Backend.device_handle backend_device)
      ~capabilities:(Ogpu.Backend.capabilities backend_device)
      [ (0, bindings) ]
  in
  Ogpu.Backend.create_render_pipeline ~blend:Replace ~topology:Triangle_list ~indirect:false
    backend_device
    {
      backend = "metal";
      label = Some "scene-sun-depth";
      layout;
      vertex;
      vertex_entry = "sun_vertex";
      fragment = Some fragment;
      fragment_entry = Some "sun_fragment";
      color_format = Rgba8_unorm;
      depth_format = Depth32_float;
      sample_count = 1;
    }

let create_renderer ?device ~offscreen ~driver ~configuration () =
  let make_pipeline backend_device family blend samples =
    let source, extra =
      match family with
      | Scene_execution.Scene2 | Scene2_textured ->
          ( Runtime_shaders.scene2_textured_argument,
            [
              {
                Ogpu.Shader.group = 0;
                binding = 1;
                kind = Storage_buffer;
                visibility = [ Fragment ];
              };
            ] )
      | Scene3 | Scene3_stencil -> (source_scene3, [])
      | Scene3_points -> ("#define PRISMEL_POINTS\n" ^ source_scene3, [])
      | Scene3_textured | Scene3_textured_stencil ->
          ( source_scene3_textured,
            [
              {
                Ogpu.Shader.group = 0;
                binding = 1;
                kind = Sampled_texture;
                visibility = [ Fragment ];
              };
              { group = 0; binding = 2; kind = Sampler; visibility = [ Fragment ] };
            ] )
      | Scene3_shadow | Scene3_shadow_stencil | Scene3_world ->
          ( (if family = Scene3_world then source_scene3_world else source_scene3_shadow),
            [
              {
                Ogpu.Shader.group = 0;
                binding = 1;
                kind = Sampled_texture;
                visibility = [ Fragment ];
              };
              { group = 0; binding = 2; kind = Sampler; visibility = [ Fragment ] };
              { group = 0; binding = 3; kind = Storage_buffer; visibility = [ Fragment ] };
              { group = 0; binding = 4; kind = Sampled_texture; visibility = [ Fragment ] };
              { group = 0; binding = 5; kind = Sampler; visibility = [ Fragment ] };
            ]
            @ (if family = Scene3_world then
                 [
                   { group = 0; binding = 8; kind = Sampled_texture; visibility = [ Fragment ] };
                   { group = 0; binding = 9; kind = Sampled_texture; visibility = [ Fragment ] };
                   { group = 0; binding = 10; kind = Sampler; visibility = [ Fragment ] };
                 ]
               else []))
      | Ui ->
          ( Runtime_shaders.ui,
            [
              {
                Ogpu.Shader.group = 0;
                binding = 1;
                kind = Sampled_texture;
                visibility = [ Fragment ];
              };
              { group = 0; binding = 2; kind = Sampler; visibility = [ Fragment ] };
            ] )
    in
    let artifact bindings =
      Ogpu.Shader.create
        {
          backend = "metal";
          label = Some "runtime-next";
          bytes = Bytes.of_string source;
          entry_points =
            [
              { name = "scene_vertex"; stage = Vertex };
              {
                name =
                  (if family = Scene2 || family = Scene2_textured then "scene_fragment_argument"
                   else "scene_fragment");
                stage = Fragment;
              };
            ];
          bindings;
        }
    in
    let vertex_schema =
      { Ogpu.Shader.group = 0; binding = 0; kind = Storage_buffer; visibility = [ Vertex ] }
      ::
      (match family with
      | Scene_execution.Scene2 | Scene2_textured | Ui ->
          [ { Ogpu.Shader.group = 0; binding = 6; kind = Storage_buffer; visibility = [ Vertex ] } ]
      | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow | Scene3_stencil
      | Scene3_textured_stencil | Scene3_shadow_stencil | Scene3_world ->
          [
            {
              Ogpu.Shader.group = 0;
              binding = 6;
              kind = Storage_buffer;
              visibility = [ Vertex; Fragment ];
            };
            { Ogpu.Shader.group = 0; binding = 7; kind = Storage_buffer; visibility = [ Vertex ] };
          ])
    in
    match (artifact vertex_schema, artifact extra) with
    | Error e, _ -> Error e
    | _, Error e -> Error e
    | Ok vertex, Ok fragment -> (
        let entries =
          { Ogpu.Binding.binding = 0; kind = Buffer; visibility = [ Vertex ] }
          ::
          (match family with
          | Scene_execution.Scene2 | Scene2_textured | Ui ->
              [ { Ogpu.Binding.binding = 6; kind = Buffer; visibility = [ Vertex ] } ]
          | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow | Scene3_stencil
          | Scene3_textured_stencil | Scene3_shadow_stencil | Scene3_world ->
              [
                { Ogpu.Binding.binding = 6; kind = Buffer; visibility = [ Vertex; Fragment ] };
                { Ogpu.Binding.binding = 7; kind = Buffer; visibility = [ Vertex ] };
              ])
        in
        let bindings =
          match family with
          | Scene2 | Scene2_textured ->
              entries @ [ { Ogpu.Binding.binding = 1; kind = Buffer; visibility = [ Fragment ] } ]
          | Ui ->
              entries
              @ [
                  { Ogpu.Binding.binding = 1; kind = Texture; visibility = [ Fragment ] };
                  { binding = 2; kind = Sampler; visibility = [ Fragment ] };
                ]
          | Scene3 | Scene3_points | Scene3_stencil -> entries
          | Scene3_textured | Scene3_textured_stencil ->
              entries
              @ [
                  { Ogpu.Binding.binding = 1; kind = Texture; visibility = [ Fragment ] };
                  { binding = 2; kind = Sampler; visibility = [ Fragment ] };
                ]
          | Scene3_shadow | Scene3_shadow_stencil | Scene3_world ->
              entries
              @ [
                  { Ogpu.Binding.binding = 1; kind = Texture; visibility = [ Fragment ] };
                  { binding = 2; kind = Sampler; visibility = [ Fragment ] };
                  { binding = 3; kind = Buffer; visibility = [ Fragment ] };
                  { binding = 4; kind = Texture; visibility = [ Fragment ] };
                  { binding = 5; kind = Sampler; visibility = [ Fragment ] };
                ]
              @ (if family = Scene3_world then
                   [
                     { Ogpu.Binding.binding = 8; kind = Texture; visibility = [ Fragment ] };
                     { binding = 9; kind = Texture; visibility = [ Fragment ] };
                     { binding = 10; kind = Sampler; visibility = [ Fragment ] };
                   ]
                 else [])
        in
        match Ogpu.Binding.create_layout bindings with
        | Error e -> Error e
        | Ok bindings -> (
            let groups = [ (0, bindings) ] in
            match
              Ogpu.Binding.create_pipeline_layout
                ~device:(Ogpu.Backend.device_handle backend_device)
                ~capabilities:(Ogpu.Backend.capabilities backend_device)
                groups
            with
            | Error _ as e -> e
            | Ok layout -> (
                let descriptor : Ogpu.Pipeline.render_descriptor =
                  {
                    backend = "metal";
                    label = Some "runtime-next";
                    layout;
                    vertex;
                    vertex_entry = "scene_vertex";
                    fragment = Some fragment;
                    fragment_entry =
                      Some
                        (if family = Scene2 || family = Scene2_textured then
                           "scene_fragment_argument"
                         else "scene_fragment");
                    color_format = Rgba8_unorm;
                    depth_format =
                      (match family with
                      | Scene_execution.Scene2 | Scene2_textured | Ui -> Ogpu.Pipeline.No_depth
                      | Scene3 | Scene3_points | Scene3_textured | Scene3_shadow | Scene3_world ->
                          Depth32_float
                      | Scene3_stencil | Scene3_textured_stencil | Scene3_shadow_stencil ->
                          Depth32_float_stencil8);
                    sample_count = samples;
                  }
                in
                Ogpu.Backend.create_render_pipeline ~blend
                  ~topology:
                    (if family = Scene3_points then Ogpu.Render_pass.Point_list
                     else Triangle_list)
                  ~indirect:
                    (match family with
                     | Scene2 | Scene2_textured | Scene3 | Scene3_points | Scene3_stencil -> true
                     | Scene3_textured | Scene3_shadow | Scene3_textured_stencil
                     | Scene3_shadow_stencil | Scene3_world | Ui -> false)
                  backend_device descriptor)))
  in
  Scene_execution.create ?device ~sun_depth:make_sun_depth_pipeline ~offscreen driver configuration
    make_pipeline

let present_mode vsync = if vsync then Ogpu.Surface.Fifo else Immediate

let configuration ?layer ~vsync ~width ~height () : Ogpu.Surface.configuration =
  {
    logical_width = width;
    logical_height = height;
    physical_width = width;
    physical_height = height;
    format = Bgra8_unorm;
    present_mode = present_mode vsync;
    max_acquired = 2;
    layer;
  }

let reveal window =
  match Sdl3.Window.show window with
  | Error _ as error -> error
  | Ok () ->
      ignore (Sdl3.Window.restore window);
      ignore (Sdl3.Window.raise_window window);
      ignore (Sdl3.Window.center window);
      ignore (Sdl3.Window.sync window);
      Ok ()

let create ?(vsync = true) ?(hidden = true) ?(title = "Prismel") ~width ~height () =
  let op = "Runtime.create" in
  if width <= 0 || height <= 0 then
    Error (Ogpu.Error.make op Invalid_argument "dimensions must be positive")
  else
    (* Each acquired SDL resource pushes its release; any later failure
       unwinds them newest first. *)
    let undo = ref [] in
    let unwind () =
      List.iter (fun release -> ignore (release ())) !undo;
      undo := []
    in
    let acquire result release =
      Result.map
        (fun value ->
          undo := (fun () -> release value) :: !undo;
          value)
        (sdl op result)
    in
    let ( let* ) = Result.bind in
    let created =
      let* () = acquire (Sdl3.Init.init [ Sdl3.Init.Video ]) (fun () ->
        Sdl3.Init.quit_subsystems [ Sdl3.Init.Video ]) in
      let flags : Sdl3.Window.flag list =
        Metal :: High_pixel_density :: (if hidden then [ Hidden ] else [])
      in
      let* window = acquire (Sdl3.Window.create ~title ~width ~height ~flags ()) Sdl3.Window.destroy in
      let* () = acquire (Sdl3.Text_input.start window) (fun () -> Sdl3.Text_input.stop window) in
      let* () = if hidden then Ok () else sdl op (reveal window) in
      let* view = acquire (Sdl3.Metal_view.create window) Sdl3.Metal_view.destroy in
      let* token = sdl op (Sdl3.Metal_view.layer view) in
      (* Size the renderer for the actual drawable once, rather than
         allocating a logical-size target and immediately resizing it. *)
      let* facts = facts window in
      let driver, _live = Ogpu.Impl.create_driver () in
      let configuration =
        {
          (configuration ~layer:token ~vsync ~width:facts.logical_width
             ~height:facts.logical_height ())
          with
          physical_width = facts.drawable_width;
          physical_height = facts.drawable_height;
        }
      in
      let* renderer = create_renderer ~offscreen:false ~driver ~configuration () in
      Ok
        {
          renderer;
          window = Some { handle = window; view; vsync; cursors = []; cursor_shape = None };
          title;
          facts;
          presentation = None;
          counters = new_counters ();
          scaled = new_scaled_cache ();
          dead = false;
        }
    in
    (match created with Ok _ -> undo := [] | Error _ -> unwind ());
    created

let offscreen_facts ~logical_width ~logical_height ~width ~height =
  {
    logical_width;
    logical_height;
    drawable_width = width;
    drawable_height = height;
    pixel_scale_x = float width /. float logical_width;
    pixel_scale_y = float height /. float logical_height;
  }

let create_offscreen ?device ?(title = "Prismel") ~logical_width ~logical_height ~width ~height
    () =
  let op = "Runtime.create_offscreen" in
  if width <= 0 || height <= 0 || logical_width <= 0 || logical_height <= 0 then
    Error (Ogpu.Error.make op Invalid_argument "dimensions must be positive")
  else
    let driver, _live = Ogpu.Impl.create_driver () in
    let configuration = configuration ~vsync:false ~width ~height () in
    match create_renderer ?device ~offscreen:true ~driver ~configuration () with
    | Error _ as error -> error
    | Ok renderer ->
        Ok
          {
            renderer;
            window = None;
            title;
            facts = offscreen_facts ~logical_width ~logical_height ~width ~height;
            presentation = None;
            counters = new_counters ();
            scaled = new_scaled_cache ();
            dead = false;
          }

let scale_rect (facts : frame_facts) (x, y, w, h) =
  let edge value logical drawable = value * drawable / logical in
  let l = edge x facts.logical_width facts.drawable_width
  and t = edge y facts.logical_height facts.drawable_height
  and r = edge (x + w) facts.logical_width facts.drawable_width
  and b = edge (y + h) facts.logical_height facts.drawable_height in
  (l, t, r - l, b - t)

let map_logical_rect = scale_rect

let scale_required (facts : frame_facts) =
  facts.logical_width <> facts.drawable_width || facts.logical_height <> facts.drawable_height

let scale_draw (facts : frame_facts) (draw : Scene_execution.draw) =
  let viewport = scale_rect facts draw.state.viewport
  and scissor = scale_rect facts draw.state.scissor in
  if viewport = draw.state.viewport && scissor = draw.state.scissor then draw
  else { draw with state = { draw.state with viewport; scissor } }

let scale_draws (facts : frame_facts) draws =
  if not (scale_required facts) then draws else List.map (scale_draw facts) draws

let scale_sampled_resources (facts : frame_facts) draws =
  if not (scale_required facts) then draws
  else
    List.map
      (fun (entry:Scene_execution.sampled_draw) ->
        let scaled = scale_draw facts entry.draw in
        if scaled == entry.draw then entry else {entry with draw=scaled})
      draws

let scale_sampled_cached cache (facts : frame_facts) draws =
  if not (scale_required facts) then draws
  else if draws == cache.scaled_input
          && (match cache.scaled_facts with Some cached -> cached == facts | None -> false)
  then cache.scaled_output
  else begin
    let scaled = scale_sampled_resources facts draws in
    cache.scaled_input <- draws;
    cache.scaled_facts <- Some facts;
    cache.scaled_output <- scaled;
    scaled
  end

let apply_facts (value : t) ~vsync (facts : frame_facts) =
  let configuration : Ogpu.Surface.configuration =
    {
      logical_width = facts.logical_width;
      logical_height = facts.logical_height;
      physical_width = facts.drawable_width;
      physical_height = facts.drawable_height;
      format = Bgra8_unorm;
      present_mode = present_mode vsync;
      max_acquired = 2;
      layer = None;
    }
  in
  match Scene_execution.resize value.renderer configuration with
  | Error _ as e -> e
  | Ok () ->
      value.facts <- facts;
      Ok ()

(* A window's drawable follows SDL; an offscreen target changes only through
   [resize]. *)
let sync_facts (value : t) =
  match value.window with
  | None -> Ok ()
  | Some window -> (
      match facts window.handle with
      | Error _ as error -> error
      | Ok live
        when live.logical_width = value.facts.logical_width
             && live.logical_height = value.facts.logical_height
             && live.drawable_width = value.facts.drawable_width
             && live.drawable_height = value.facts.drawable_height ->
          Ok ()
      | Ok live -> apply_facts value ~vsync:window.vsync live)

(* Runs one frame against the synced target; only a window presents. *)
let frame operation ?after_prepare (value : t) draw_count render =
  let release () = Option.iter (fun f -> f ()) after_prepare in
  if value.dead then (
    release ();
    stale operation)
  else
    match sync_facts value with
    | Error _ as error ->
        release ();
        error
    | Ok () -> (
        match render () with
        | Ok presented as result ->
            count value.counters draw_count
              ~presented:(presented && Option.is_some value.window);
            result
        | Error _ as error -> error)

let render ?clear (value : t) draws =
  frame "Runtime.render" value (List.length draws) (fun () ->
      Scene_execution.render ?clear value.renderer (scale_draws value.facts draws))

let render_sampled_resources ?after_prepare ?clear (value : t) draws =
  frame "Runtime.render_sampled_resources" ?after_prepare value (List.length draws) (fun () ->
      Scene_execution.render_sampled_resources ?after_prepare ?clear value.renderer
        (scale_sampled_cached value.scaled value.facts draws))

let render_prepared_sampled_resources ?after_prepare ?clear ~identity ~version (value : t) draws =
  frame "Runtime.render_prepared_sampled_resources" ?after_prepare value (List.length draws)
    (fun () ->
      Scene_execution.render_prepared_sampled_resources ?after_prepare ?clear ~identity ~version
        value.renderer
        (scale_sampled_cached value.scaled value.facts draws))

let replay_prepared_sampled_resources ?clear ~identity ~version (value : t) =
  if value.dead then stale "Runtime.replay_prepared_sampled_resources"
  else
    match sync_facts value with
    | Error _ as error -> error
    | Ok () -> (
        match
          Scene_execution.replay_prepared_sampled_resources ?clear ~identity ~version
            value.renderer
        with
        | Ok (Some (presented, draw_count)) ->
            let presented = presented && Option.is_some value.window in
            count value.counters draw_count ~presented;
            Ok (Some presented)
        | Ok None -> Ok None
        | Error _ as error -> error)

let resize ?drawable (value : t) ~width ~height =
  let op = "Runtime.resize" in
  if value.dead then stale op
  else if width <= 0 || height <= 0 then
    Error (Ogpu.Error.make op Invalid_argument "dimensions must be positive")
  else
    match (value.window, drawable) with
    | Some _, Some _ ->
        Error
          (Ogpu.Error.make op Invalid_argument "a window's drawable size follows its display")
    | Some window, None -> (
        match sdl op (Sdl3.Window.set_size window.handle ~width ~height) with
        | Error _ as e -> e
        | Ok () ->
            value.presentation <- None;
            Result.bind (facts window.handle) (apply_facts value ~vsync:window.vsync))
    | None, drawable ->
        let drawable_width, drawable_height = Option.value drawable ~default:(width, height) in
        if drawable_width <= 0 || drawable_height <= 0 then
          Error (Ogpu.Error.make op Invalid_argument "dimensions must be positive")
        else (
          value.presentation <- None;
          apply_facts value ~vsync:false
            (offscreen_facts ~logical_width:width ~logical_height:height ~width:drawable_width
               ~height:drawable_height))

let read_pixels (value : t) ~bytes_per_row =
  if value.dead then stale "Runtime.read_pixels"
  else Scene_execution.read_pixels value.renderer ~bytes_per_row

let read_pixels_into (value : t) ~bytes_per_row ~destination =
  if value.dead then stale "Runtime.read_pixels_into"
  else Scene_execution.read_pixels_into value.renderer ~bytes_per_row ~destination

let stats (value : t) =
  let renderer = value.renderer and counters = value.counters in
  let timing = Ogpu.Backend.gpu_timing (Scene_execution.queue renderer)
  and retained = Scene_execution.retained_stats renderer in
  {
    frames = counters.frames;
    presented = counters.presented;
    logical_draws = counters.logical_draws;
    logical_passes = counters.logical_passes;
    logical_submissions = counters.logical_submissions;
    pipeline_cache_entries = Scene_execution.pipeline_count renderer;
    mesh_cache_entries = Scene_execution.Private.cache_count_for_report renderer;
    uploaded_bytes = Scene_execution.upload_bytes renderer;
    gpu_timing_supported = timing.timing_supported;
    gpu_duration_seconds = timing.gpu_seconds;
    gpu_sample_count = timing.gpu_samples;
    retained_plan_builds = retained.plan_builds;
    retained_plan_hits = retained.plan_hits;
    retained_plan_misses = retained.plan_misses;
    retained_plan_evictions = retained.plan_evictions;
    retained_plan_executions = retained.plan_executions;
    retained_plan_entries = retained.plan_entries;
    retained_plan_capacity = retained.plan_capacity;
    sun_shadow_passes = Scene_execution.sun_shadow_passes renderer;
  }

let zero_stats =
  {
    frames = 0L;
    presented = 0L;
    logical_draws = 0L;
    logical_passes = 0L;
    logical_submissions = 0L;
    pipeline_cache_entries = 0;
    mesh_cache_entries = 0;
    uploaded_bytes = 0L;
    gpu_timing_supported = false;
    gpu_duration_seconds = 0.;
    gpu_sample_count = 0L;
    retained_plan_builds = 0L;
    retained_plan_hits = 0L;
    retained_plan_misses = 0L;
    retained_plan_evictions = 0L;
    retained_plan_executions = 0L;
    retained_plan_entries = 0;
    retained_plan_capacity = 0;
    sun_shadow_passes = 0L;
  }

let frame_facts (value : t) = value.facts

let live_window operation (value : t) callback =
  if value.dead then stale operation
  else
    match value.window with
    | None -> Error (Ogpu.Error.make operation Unsupported "operation requires a window")
    | Some window -> callback window

let query_presentation (value : t) =
  match value.window with
  | None ->
      let facts = value.facts in
      Ok
        {
          title = value.title;
          logical_width = facts.logical_width;
          logical_height = facts.logical_height;
          drawable_width = facts.drawable_width;
          drawable_height = facts.drawable_height;
          position = None;
          pixel_density = facts.pixel_scale_x;
          display_scale = facts.pixel_scale_x;
          refresh_rate = None;
          vsync = false;
        }
  | Some { handle = window; vsync; _ } -> (
      let op = "Runtime.presentation_facts" in
      match
        ( sdl op (Sdl3.Window.presentation_facts window ~vsync),
          sdl op (Sdl3.Window.title window),
          sdl op (Sdl3.Window.position window) )
      with
      | Ok facts, Ok title, Ok position ->
          Ok
            {
              title;
              logical_width = facts.logical_width;
              logical_height = facts.logical_height;
              drawable_width = facts.drawable_width;
              drawable_height = facts.drawable_height;
              position = Some position;
              pixel_density = facts.pixel_density;
              display_scale = facts.display_scale;
              refresh_rate = facts.refresh_rate;
              vsync = facts.vsync;
            }
      | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e)

(* Queried once and reused while the target's drawable facts are unchanged;
   a drawable change, resize, or show queries again (so a new display's scale
   is read, never guessed). *)
let presentation_facts (value : t) =
  if value.dead then stale "Runtime.presentation_facts"
  else
    let live = value.facts in
    match value.presentation with
    | Some cached
      when cached.logical_width = live.logical_width
           && cached.logical_height = live.logical_height
           && cached.drawable_width = live.drawable_width
           && cached.drawable_height = live.drawable_height ->
        Ok cached
    | Some _ | None ->
        Result.map
          (fun facts ->
            value.presentation <- Some facts;
            facts)
          (query_presentation value)

let window_call operation call value =
  live_window operation value (fun window -> sdl operation (call window.handle))

let set_resizable value enabled =
  window_call "Runtime.set_resizable"
    (fun window -> Sdl3.Window.set_resizable window enabled)
    value

let set_relative_mouse value enabled =
  window_call "Runtime.set_relative_mouse"
    (fun window -> Sdl3.Window.set_relative_mouse window enabled)
    value

let set_cursor value shape =
  live_window "Runtime.set_cursor" value (fun window ->
      if window.cursor_shape = Some shape then Ok ()
      else
        let cursor =
          match List.assoc_opt shape window.cursors with
          | Some cursor -> Ok cursor
          | None ->
              let native =
                match shape with
                | `Default -> Sdl3.Cursor.Default
                | `Horizontal_resize -> Sdl3.Cursor.Ew_resize
                | `Vertical_resize -> Sdl3.Cursor.Ns_resize
              in
              Result.map
                (fun cursor ->
                  window.cursors <- (shape, cursor) :: window.cursors;
                  cursor)
                (sdl "Runtime.set_cursor" (Sdl3.Cursor.create native))
        in
        match cursor with
        | Error _ as error -> error
        | Ok cursor -> (
            match sdl "Runtime.set_cursor" (Sdl3.Cursor.set cursor) with
            | Error _ as error -> error
            | Ok () ->
                window.cursor_shape <- Some shape;
                Ok ()))

let set_text_input_area value area =
  window_call "Runtime.set_text_input_area"
    (fun window ->
      Sdl3.Text_input.set_area window
        (Option.map (fun ((x, y, width, height), _) -> { Sdl3.x; y; width; height }) area)
        ~cursor:(Option.fold ~none:0 ~some:snd area))
    value

let show (value : t) =
  live_window "Runtime.show" value (fun window ->
      match sdl "Runtime.show" (reveal window.handle) with
      | Error _ as error -> error
      | Ok () ->
          let synced = sync_facts value in
          if Result.is_ok synced then value.presentation <- None;
          synced)

let hide = window_call "Runtime.hide" Sdl3.Window.hide

let visible value =
  live_window "Runtime.visible" value (fun window ->
      Result.map
        (fun flags -> Int64.logand flags 0x8L = 0L)
        (sdl "Runtime.visible" (Sdl3.Window.flags window.handle)))

let destroy (value : t) =
  if value.dead then Ok ()
  else (
    value.dead <- true;
    let failure = ref None in
    let record = function
      | Ok () -> ()
      | Error error -> if !failure = None then failure := Some error
    in
    record (Scene_execution.destroy value.renderer);
    Option.iter
      (fun window ->
        record (sdl "Runtime.destroy" (Sdl3.Text_input.stop window.handle));
        List.iter
          (fun (_, cursor) -> record (sdl "Runtime.destroy" (Sdl3.Cursor.destroy cursor)))
          window.cursors;
        window.cursors <- [];
        record (sdl "Runtime.destroy" (Sdl3.Metal_view.destroy window.view));
        record (sdl "Runtime.destroy" (Sdl3.Window.destroy window.handle));
        record (sdl "Runtime.destroy" (Sdl3.Init.quit_subsystems [ Sdl3.Init.Video ])))
      value.window;
    match !failure with None -> Ok () | Some error -> Error error)

module Private = struct
  let scale_draws = scale_draws
  let scale_sampled_resources = scale_sampled_resources
  type nonrec scaled_cache = scaled_cache
  let new_scaled_cache = new_scaled_cache
  let scale_sampled_cached = scale_sampled_cached
end
