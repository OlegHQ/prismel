open Rays
let check condition message=if not condition then failwith message
let finite x=Float.is_finite x
let run () =
  check(Color.hex"#f08c"=Ok(Color.rgba 255 0 136 204))"Color hex";
  check(Color.gradient[Color.red;Color.blue]0.5=Color.rgba 128 0 128 255)"Color gradient";
  let m4=Mat4.mul(Mat4.translation(Vec3.create 2. 3. 4.))(Mat4.scaling(Vec3.create 2. 2. 2.))in
  check(Vec3.nearly_equal(Mat4.transform_point m4(Vec3.create 1. 1. 1.))(Vec3.create 4. 5. 6.)~eps:1e-12)"Mat4 affine";
  check(match Mat4.inverse m4 with Some inverse->Mat4.nearly_equal(Mat4.mul inverse m4)Mat4.identity~eps:1e-12|None->false)"Mat4 inverse";
  let q=Quat.axis_angle~axis:Vec3.unit_z(Float.pi/.2.)in
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
  List.iter (fun seed ->
    let noise = Noise.create seed in
    let coordinates = [|0.; -0.; Float.epsilon; -.Float.epsilon; 1.; -1.;
      Float.pred 1.; Float.succ 1.; 255.; -256.; 1e20; -1e20|] in
    Array.iter (fun x -> Array.iter (fun y ->
      check (Int64.bits_of_float (Noise.sample2 noise ~x ~y)
        = Int64.bits_of_float (Noise.sample3 noise ~x ~y ~z:0.))
        "Noise 2D boundary bits differ from original 3D plane") coordinates) coordinates;
    for index = 0 to 19_999 do
      let x = float (index - 10_000) *. 0.017
      and y = float (index * 97 mod 30_011 - 15_000) *. 0.031 in
      check (Int64.bits_of_float (Noise.sample2 noise ~x ~y)
        = Int64.bits_of_float (Noise.sample3 noise ~x ~y ~z:0.))
        "Noise 2D bits differ from original 3D plane"
    done) [0; 1; 42; -1; 1999];
  Parallel.run ~domains:8 (fun () ->
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:7 (fun chunk ->
      let first = chunk * 12_500 in
      Noise.Private.sample2_into noise ~first ~last:(first + 12_500)
        ~frequency:0.5 ~x:xs ~y:ys ~output:parallel));
  check (sequential = parallel) "Noise one/eight-domain exact 2D plane";
  for index = 0 to Array.length sequential - 1 do
    check (Int64.bits_of_float sequential.(index)
      = Int64.bits_of_float (Noise.sample3 noise
          ~x:(xs.(index) *. 0.5) ~y:(ys.(index) *. 0.5) ~z:0.))
      "packed 2D noise differs from original 3D plane"
  done;
  check(Noise.sample3 noise~x:0.25~y:0.5~z:0.75=Noise.sample3(Noise.create 42)~x:0.25~y:0.5~z:0.75)"Noise seed";
  print_endline"Rays batch A exact deterministic API passed"
