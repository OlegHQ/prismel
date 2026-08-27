module Artifact = R10_scene2_legacy_equivalent

let bytes_equal expected actual label =
  if not (Bytes.equal expected actual) then failwith (label ^ " bytes drift")

let validate scenario ~signature ~vertices ~indices ~work_units =
  let artifact = Artifact.create scenario ~width:4 ~height:4 in
  if artifact.workload_signature <> signature then failwith "signature drift";
  if artifact.work_units <> work_units then failwith "work-unit drift";
  match artifact.draws with
  | [ draw ] ->
      bytes_equal vertices draw.mesh.vertices "vertex";
      bytes_equal indices draw.mesh.indices "index"
  | _ -> failwith "canonical artifact must contain exactly one draw"

let vertex_bytes points =
  let bytes = Bytes.make (List.length points * 16) '\000' in
  List.iteri
    (fun index (x, y) ->
      Bytes.set_int64_le bytes (index * 16) (Int64.bits_of_float x);
      Bytes.set_int64_le bytes ((index * 16) + 8) (Int64.bits_of_float y))
    points;
  bytes

let index_bytes values =
  let bytes = Bytes.make (List.length values * 4) '\000' in
  List.iteri
    (fun index value -> Bytes.set_int32_le bytes (index * 4) (Int32.of_int value))
    values;
  bytes

let () =
  validate Artifact.Basic
    ~signature:"phase5-b0:basic:v1:4x4:vertices:3:indices:3:triangles:1"
    ~vertices:(vertex_bytes [ 0., 0.; 4., 0.; 0., 4. ])
    ~indices:(index_bytes [ 0; 1; 2 ]) ~work_units:1;
  validate Artifact.Pxui
    ~signature:"phase5-b0:pxui:v1:4x4:vertices:4:indices:6:triangles:2"
    ~vertices:(vertex_bytes [ 0., 0.; 4., 0.; 4., 4.; 0., 4. ])
    ~indices:(index_bytes [ 0; 1; 2; 0; 2; 3 ]) ~work_units:2;
  validate Artifact.Canvas
    ~signature:"phase5-b0:canvas:v1:4x4:vertices:3:indices:3:triangles:1"
    ~vertices:(vertex_bytes [ 0., 0.; 2., 0.; 0., 2. ])
    ~indices:(index_bytes [ 0; 1; 2 ]) ~work_units:1;
  let expected = Artifact.create Artifact.Pxui ~width:64 ~height:64 in
  for _ = 1 to 4 do
    let actual = Artifact.create Artifact.Pxui ~width:64 ~height:64 in
    if actual.workload_signature <> expected.workload_signature
       || actual.work_units <> expected.work_units
    then failwith "independent-domain artifact drift"
  done;
  print_endline "R10 canonical non-Scene artifacts passed"
