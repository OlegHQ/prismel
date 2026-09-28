open Prismel
open Procedural

let program = [%flow {|(graph terrain :context sop
  (let* [grid (sop/grid :columns 32 :rows 32 :width 5 :height 5)
         clock (value/time :speed 0.4)
         pulse (+ 0.65 (* clock.t 0.25))
         mountain (sop/mountain grid :height pulse
           :frequency [0.8 1 0.8] :octaves 3 :recompute_normals true)]
    mountain))|}]

let () =
  Prismel_editor.Editor3.run
    ~config:{Sketch.default_config with width = 1200; height = 760;
      title = "Prismel Flow terrain"}
    ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:8.
      ~azimuth:0.6 ~elevation:0.5 ())
    ~lights:[Light.directional ~direction:(Vec3.create (-1.) (-1.4) (-0.8))
      ~diffuse:Color.white ()]
    ~factories:Sop_catalog.Editor.factories ~program
    ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
      |> Result.map_error Pdk.Error.to_string)
    ~scene3:(fun _ mesh -> Scene3.create
      [Scene3.mesh ~cull:Scene3.Cull_none mesh]) ()
