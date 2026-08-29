module D=R10_scene2_legacy_equivalent
let contains text fragment =
  let n=String.length text and m=String.length fragment in
  let rec loop i=i+m<=n&&(String.sub text i m=fragment||loop(i+1))in loop 0
let check scenario work_units feature fragments =
  let value=D.describe scenario ~width:640 ~height:480 in
  if value.work_units<>work_units||not(List.mem feature value.required_features)
  then failwith "descriptor cardinality/feature drift";
  List.iter(fun fragment->if not(contains value.canonical_parameters fragment)
    then failwith("descriptor missing "^fragment))fragments;
  if value<>D.describe scenario ~width:640 ~height:480 then failwith "nondeterminism"
let ()=check Basic 9 "affine-image" ["generated96x96";"bezier="];
  check Pxui 21 "pxui-four-expanded-accordions" ["sections=0..3";"choice Mode"];
  check Canvas 5 "offscreen-canvas" ["resource=stable-after-setup";"image-at0,0"];
  check Scene3 110_592 "sphere96x48" ["instances=12";"msaa4"];
  if D.phase ~frame:1<>1||D.phase ~frame:600<>120 then failwith "phase drift";
  print_endline "R10 exact neutral non-Scene descriptors passed"
