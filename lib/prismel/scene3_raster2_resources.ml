type t = {
  capacity : int;
  mutable textures : (Texture.t * Raster2.Texture.t) list;
  mutable shadows : (Shadow3.t * Raster2.Shadow_map.prepared) list;
  mutable generation : int64;
  mutable destroyed : bool;
}

let create ?(capacity=64) () =
  if capacity<=0 then invalid_arg"Scene3_raster2_resources.create: capacity";
  {capacity;textures=[];shadows=[];generation=0L;destroyed=false}

let pack color=Int32.of_int((color.Color.r lsl 24)lor(color.g lsl 16)
  lor(color.b lsl 8)lor color.a)

let surface (width,height,pixels) =
  match Raster2.Surface.create~width~height()with Error _->Error Scene3_raster2_lowering.Texture_error|Ok surface->
  Array.iteri(fun index color->ignore(Raster2.Surface.set_rgba surface
    ~x:(index mod width)~y:(index/width)(pack color)))pixels;
  Ok surface

let trim capacity values =
  let rec take count values=match count,values with 0,_->[]|_,[]->[]|n,x::xs->x::take(n-1)xs in
  take capacity values

let texture resources (value:Scene3.texture) =
  if resources.destroyed then Error Scene3_raster2_lowering.Texture_error else
  match List.find_opt(fun(source,_)->source==value.value)resources.textures with
  | Some(source,resolved)->resources.textures<-(source,resolved)::List.filter(fun(entry,_)->entry!=source)resources.textures;Ok resolved
  | None->
    let levels=Texture.Private.levels value.value in
    let converted=Array.map surface levels in
    if Array.exists Result.is_error converted then Error Scene3_raster2_lowering.Texture_error else
    let surfaces=Array.map(function Ok value->value|Error _->assert false)converted in
    let capacity=Array.fold_left(fun total surface->total+Bytes.length(Raster2.Surface.bytes surface))0 surfaces in
    begin match Raster2.Texture.create_levels~color_space:Raster2.Texture.Srgb
      ~hard_capacity:capacity surfaces with
    | Error _->Error Scene3_raster2_lowering.Texture_error
    | Ok resolved->resources.generation<-Int64.succ resources.generation;
      resources.textures<-trim resources.capacity((value.value,resolved)::resources.textures);
      Ok resolved
    end

let matrix value=Array.init 16(fun index->Mat4.get value~row:(index/4)~column:(index mod 4))
let depth_zero_to_one=Mat4.of_rows(1.,0.,0.,0.)(0.,1.,0.,0.)
  (0.,0.,0.5,0.5)(0.,0.,0.,1.)

let shadow resources source =
  if resources.destroyed then Error Scene3_raster2_lowering.Shadow_error else
  match List.find_opt(fun(value,_)->value==source)resources.shadows with
  | Some(value,resolved)->resources.shadows<-(value,resolved)::List.filter(fun(entry,_)->entry!=value)resources.shadows;Ok resolved
  | None->
    let value=Shadow3.Private.snapshot source in
    let light_kind=match (Shadow3.light source).Light.kind with
      | Directional _->Ok Raster2.Shadow_map.Directional
      | Spot _->Ok Raster2.Shadow_map.Spot
      | Ambient|Point _|Area _->Error Scene3_raster2_lowering.Shadow_error in
    begin match light_kind,Raster2.Shadow_map.create~width:value.width~height:value.height with
    | Error error,_->Error error
    | _,Error _->Error Scene3_raster2_lowering.Shadow_error
    | Ok light_kind,Ok map->
      let failure=ref false in
      Array.iteri(fun index depth->if not !failure then
        match Raster2.Shadow_map.write map~x:(index mod value.width)
          ~y:(index/value.width)~depth with Ok()->()|Error _->failure:=true)value.depths;
      if !failure then Error Scene3_raster2_lowering.Shadow_error else
      let kernel=match value.filter with Shadow3.Hard->Raster2.Shadow_map.Tap1
        | Pcf_3x3->Tap9|Pcf_5x5->Tap25 in
      match Raster2.Shadow_map.prepare~strength:value.strength map~light_kind
        ~matrix:(matrix(Mat4.mul depth_zero_to_one value.view_projection))
        ~bias:{constant=value.bias;slope=value.normal_bias}~kernel with
      | Error _->Error Scene3_raster2_lowering.Shadow_error
      | Ok resolved->resources.generation<-Int64.succ resources.generation;
        resources.shadows<-trim resources.capacity((source,resolved)::resources.shadows);
        Ok resolved
    end

let callbacks resources : Scene3_raster2_lowering.resources =
  {texture=(fun value->Result.map(fun resolved->{Raster2.Triangle.texture=resolved;
      filter=(match value.filter with Texture.Nearest->Raster2.Texture.Nearest
        | Bilinear->Bilinear|Trilinear->Trilinear);
      address_u=(match value.wrap_u with Texture.Clamp->Raster2.Texture.Clamp
        | Repeat->Repeat|Mirror->Mirror);
      address_v=(match value.wrap_v with Texture.Clamp->Raster2.Texture.Clamp
        | Repeat->Repeat|Mirror->Mirror)}) (texture resources value));
   shadow=shadow resources}

let generation resources=resources.generation
let counts resources=List.length resources.textures,List.length resources.shadows
let destroy resources=resources.destroyed<-true;resources.textures<-[];resources.shadows<-[]

let self_test()=
  let get=function Ok value->value|Error _->failwith"Scene3 resource adapter"in
  let resources=create~capacity:2()in
  let texture=Texture.create_exn~width:2~height:2
    [Color.red;Color.green;Color.blue;Color.white]|>Texture.generate_mipmaps in
  let descriptor=Scene3.textured~filter:Texture.Trilinear~wrap_u:Mirror texture in
  let adapter=callbacks resources in
  ignore(get(adapter.texture descriptor));
  let first_generation=generation resources in
  ignore(get(adapter.texture descriptor));
  if generation resources<>first_generation||counts resources<>(1,0)then
    failwith"texture identity was not retained";
  let light=Light.directional~direction:(Vec3.create 0. 0.(-1.))()in
  let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)~target:Vec3.zero()in
  let depths=Array.init 25(fun index->if index=12 then 0.25 else 1.)in
  let shadows=List.map(fun filter->Shadow3.create~filter~strength:0.5~light~camera
    ~width:5~height:5~depths()) [Shadow3.Hard;Pcf_3x3;Pcf_5x5]in
  List.iter(fun shadow->ignore(get(adapter.shadow shadow)))shadows;
  if snd(counts resources)>2 then failwith"shadow cache exceeded capacity";
  let snapshot()=let local=create~capacity:4()in let local_callbacks=callbacks local in
    ignore(get(local_callbacks.texture descriptor));
    let visibility=List.map(fun shadow->let prepared=get(local_callbacks.shadow shadow)in
      Raster2.Shadow_map.visibility prepared~position:{x=0.;y=0.;z=0.}
        ~normal_dot_light:0.5)shadows in
    let result=generation local,counts local,visibility in destroy local;result in
  let expected=snapshot()in
  List.iter(fun _frame->if snapshot()<>expected then failwith"resource frame drift")
    [1;2;60;600];
  let workers=Array.init 4(fun _->Domain.spawn snapshot)in
  Array.iter(fun worker->if Domain.join worker<>expected then
    failwith"resource domain drift")workers;
  destroy resources;
  if counts resources<>(0,0)then failwith"resource teardown retained entries";
  (match adapter.texture descriptor with Error Scene3_raster2_lowering.Texture_error->()|_->failwith"destroyed texture adapter accepted work");
  (try ignore(Shadow3.create~light~camera~width:1~height:1~depths:[|Float.nan|]());
    failwith"nonfinite shadow depth accepted"with Invalid_argument _->())

let()=match Sys.getenv_opt"PRISMEL_TEST_SCENE3_RASTER2_RESOURCES"with
  |Some"1"->self_test()|_->()
