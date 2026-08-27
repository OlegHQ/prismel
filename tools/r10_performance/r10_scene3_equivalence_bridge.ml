open Prismel_next_api

type public_workload = { camera : Camera.t; scene : Scene3.t }

type proof = {
  triangles : int;
  transforms : int;
  representative_pixels_milli : (int * int * int * int) list;
  semantic_signature : string;
}

let transforms () =
  Array.init 12 (fun index ->
      let angle = float index /. 12. *. Math.two_pi in
      Mat4.mul
        (Mat4.translation
           (Vec3.create (Float.cos angle *. 1.9) (Float.sin angle *. 1.2) 0.))
        (Mat4.scaling (Vec3.create 0.38 0.38 0.38)))

let public_workload () =
  let mesh = Mesh.sphere ~segments:96 ~rings:48 ~radius:1. () in
  let material =
    Material.create ~diffuse:(Color.hex_exn "#38bdf8")
      ~ambient:(Color.hex_exn "#082f49") ~specular:Color.white ~shininess:42.
      ()
  in
  let scene =
    Scene3.create ~samples:4 ~ambient:(Color.rgb 18 22 30)
      ~lights:
        [ Light.directional ~direction:(Vec3.create (-0.6) (-1.) (-1.4))
            ~diffuse:Color.white () ]
      [ Scene3.instances_array ~material ~cull:Scene3.Cull_back mesh
          (transforms ()) ]
  and camera =
    Camera.perspective ~at:(Vec3.create 0. 0. 5.4) ~target:Vec3.zero ()
  in
  { camera; scene }

let fail message = Error message
let equal_color left right = Color.equal left right

let packed_index bytes index =
  Int32.to_int (Bytes.get_int32_le bytes (index * 4))

let packed_pixel bytes index =
  ( Int64.float_of_bits (Bytes.get_int64_le bytes (index * 16)),
    Int64.float_of_bits (Bytes.get_int64_le bytes ((index * 16) + 8)) )

let milli value = int_of_float ((value *. 1000.) +. 0.5)

let prove ~width ~height (artifact : R10_scene3_legacy_equivalent.t) =
  let public = public_workload () in
  let drawings = ref [] in
  Scene3.Private.iter_batches
    (fun drawing instances -> drawings := (drawing, instances) :: !drawings)
    public.scene;
  match List.rev !drawings with
  | [ (drawing, Some public_transforms) ] ->
      let mesh = Mesh.Private.view drawing.mesh in
      let expected_transforms = transforms () in
      if Scene3.Private.samples public.scene <> artifact.samples then
        fail "MSAA mismatch"
      else if not (equal_color (Scene3.Private.ambient public.scene) (Color.rgb 18 22 30)) then
        fail "ambient mismatch"
      else if drawing.cull <> Scene3.Cull_back then fail "cull mismatch"
      else if not (equal_color drawing.material.diffuse (Color.rgb 56 189 248)) then
        fail "diffuse mismatch"
      else if Array.length public_transforms <> artifact.instances then
        fail "instance cardinality mismatch"
      else if Array.length mesh.vertices <> artifact.vertices_per_instance then
        fail "vertex cardinality mismatch"
      else if Array.length mesh.indices <> artifact.indices_per_instance then
        fail "index cardinality mismatch"
      else if
        not
          (Array.for_all2
             (fun left right -> Mat4.nearly_equal left right ~eps:0.)
             public_transforms expected_transforms)
      then fail "transform mismatch"
      else
        let lights = Scene3.Private.lights public.scene in
        (match lights with
        | [ { Light.kind = Light.Directional { direction }; diffuse; _ } ]
          when direction = Vec3.create (-0.6) (-1.) (-1.4)
               && equal_color diffuse Color.white ->
            let staged = Array.of_list artifact.software_draws in
            let indices_ok =
              Array.for_all
                (fun (draw : Scene_execution.draw) ->
                  Array.length mesh.indices = draw.mesh.index_count
                  && Array.for_alli
                       (fun index value ->
                         value = packed_index draw.mesh.indices index)
                       mesh.indices)
                staged
            in
            if not indices_ok then fail "triangle topology mismatch"
            else
              let view_projection =
                Camera.view_projection_matrix ~viewport:(0, 0, width, height)
                  public.camera
              in
              let representatives = [| 0; 48; 96; 97 * 24; (97 * 49) - 1 |] in
              let pixels = ref [] and pixels_ok = ref true in
              Array.iteri
                (fun instance transform ->
                  let matrix = Mat4.mul view_projection transform in
                  Array.iter
                    (fun vertex ->
                      let point = mesh.vertices.(vertex) in
                      let x, y, _, w =
                        Mat4.transform matrix
                          (point.Vec3.x, point.y, point.z, 1.)
                      in
                      let expected_x = (x /. w +. 1.) *. 0.5 *. float width
                      and expected_y =
                        (1. -. (y /. w)) *. 0.5 *. float height
                      in
                      let actual_x, actual_y =
                        packed_pixel staged.(instance).mesh.vertices vertex
                      in
                      if actual_x <> expected_x || actual_y <> expected_y then
                        pixels_ok := false;
                      pixels :=
                        (instance, vertex, milli actual_x, milli actual_y)
                        :: !pixels)
                    representatives)
                public_transforms;
              if not !pixels_ok then fail "representative pixel mismatch"
              else
                Ok
                  { triangles = Array.length mesh.indices / 3 * artifact.instances;
                    transforms = Array.length public_transforms;
                    representative_pixels_milli = List.rev !pixels;
                    semantic_signature = artifact.signature }
        | _ -> fail "directional light mismatch")
  | _ -> fail "public Scene3 must contain one instanced batch"
