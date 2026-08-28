open Prismel_next_api
let check condition message=if not condition then failwith message
let finite x=Float.is_finite x
let ()=
  check(Color.hex"#f08c"=Ok(Color.rgba 255 0 136 204))"Color hex";
  check(Color.gradient[Color.red;Color.blue]0.5=Color.rgba 128 0 128 255)"Color gradient";
  check(abs_float(Math.rad_to_deg Math.pi-.180.)<1e-12)"Math radians";
  check(Math.rect_overlap(0.,0.,2.,2.)(1.,1.,2.,2.))"Math overlap";
  let m3=Mat3.mul(Mat3.translation 4. 5.)(Mat3.rotation(Math.deg_to_rad 90.))in
  let x,y=Mat3.transform_point m3(1.,0.)in check(abs_float(x-.4.)<1e-12&&abs_float(y-.6.)<1e-12)"Mat3 composition";
  let m4=Mat4.mul(Mat4.translation(Vec3.create 2. 3. 4.))(Mat4.scaling(Vec3.create 2. 2. 2.))in
  check(Vec3.nearly_equal(Mat4.transform_point m4(Vec3.create 1. 1. 1.))(Vec3.create 4. 5. 6.)~eps:1e-12)"Mat4 affine";
  check(match Mat4.inverse m4 with Some inverse->Mat4.nearly_equal(Mat4.mul inverse m4)Mat4.identity~eps:1e-12|None->false)"Mat4 inverse";
  let q=Quat.axis_angle~axis:Vec3.unit_z(Math.deg_to_rad 90.)in
  check(Vec3.nearly_equal(Quat.rotate q Vec3.unit_x)Vec3.unit_y~eps:1e-12)"Quat rotate";
  check(Quat.nearly_equal(Quat.of_mat4(Quat.to_mat4 q))q~eps:1e-12)"Quat matrix";
  let a=Rand.seed64 0x123456789abcdefL and b=Rand.seed64 0x123456789abcdefL in
  let left=Array.init 100_000(fun index->Rand.float_at a~index)
  and right=Array.init 100_000(fun index->Rand.float_at b~index)in
  check(left=right&&Array.for_all(fun x->x>=0.&&x<1.)left)"Rand deterministic 100k";
  let noise=Noise.create 42 in
  let xs=Array.init 100_000(fun i->float i*.0.001)and ys=Array.init 100_000(fun i->float(i mod 97)*.0.01)in
  let sequential=Array.make 100_000 0. and parallel=Array.make 100_000 0. in
  Noise.Private.sample2_into noise~first:0~last:100_000~frequency:0.5~x:xs~y:ys~output:sequential;
  let workers=Array.init 4(fun domain->Domain.spawn(fun()->let first=domain*25_000 in Noise.Private.sample2_into noise~first~last:(first+25_000)~frequency:0.5~x:xs~y:ys~output:parallel))in
  Array.iter Domain.join workers;check(sequential=parallel&&Array.for_all finite parallel)"Noise one/four-domain 100k";
  check(Noise.sample3 noise~x:0.25~y:0.5~z:0.75=Noise.sample3(Noise.create 42)~x:0.25~y:0.5~z:0.75)"Noise seed";
  print_endline"Prismel_next_api batch A exact deterministic facade passed"
