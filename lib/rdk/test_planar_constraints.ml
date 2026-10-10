open Rdk

let fail format = Printf.ksprintf failwith format
let check condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format
let get_string = function Ok value -> value | Error message -> fail "%s" message

let edge_present value first second =
  let found = ref false in
  for triangle = 0 to Planar_cdt.triangle_count value - 1 do
    let a = Planar_cdt.triangle_point value triangle 0
    and b = Planar_cdt.triangle_point value triangle 1
    and c = Planar_cdt.triangle_point value triangle 2 in
    if (a = first && b = second) || (a = second && b = first)
        || (b = first && c = second) || (b = second && c = first)
        || (c = first && a = second) || (c = second && a = first) then
      found := true
  done;
  !found

let test_crossing_policy () =
  let x = [|0.;2.;2.;0.|] and y = [|0.;0.;2.;2.|] in
  match Planar_constraints.build ~split_crossings:false ~x ~y
      ~segment_points:[|0;2; 1;3|] () with
  | Error _ -> ()
  | Ok _ -> fail "crossing constraints succeeded when splitting was disabled"

let test_validation_and_cancellation () =
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.|] ~y:[||]
      ~segment_points:[||] () with
   | Error _ -> () | Ok _ -> fail "mismatched coordinate planes succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;0|] () with
   | Error _ -> () | Ok _ -> fail "degenerate segment succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0|] () with
   | Error _ -> () | Ok _ -> fail "odd endpoint array succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;infinity|]
      ~y:[|0.;0.|] ~segment_points:[|0;1|] () with
   | Error _ -> () | Ok _ -> fail "non-finite coordinate succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;2|] () with
   | Error _ -> () | Ok _ -> fail "out-of-range endpoint succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;1|] ~segment_winding:[||] () with
   | Error _ -> () | Ok _ -> fail "mismatched winding cardinality succeeded");
  (match Planar_constraints.build ~grain:0 ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;1|] () with
   | Error _ -> () | Ok _ -> fail "non-positive grain succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;1|] ~embedded_points:[|2|] () with
   | Error _ -> () | Ok _ -> fail "out-of-range embedded point succeeded");
  (match Planar_constraints.build ~split_crossings:true ~x:[|0.;1.|]
      ~y:[|0.;0.|] ~segment_points:[|0;1|] ~embedded_points:[|0;0|] () with
   | Error _ -> () | Ok _ -> fail "duplicate embedded point succeeded");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  match Planar_constraints.build ~cancel ~split_crossings:true
      ~x:[|0.;1.|] ~y:[|0.;0.|] ~segment_points:[|0;1|] () with
  | Error _ -> () | Ok _ -> fail "cancelled arrangement succeeded"

let run () =
  test_crossing_policy ();
  test_validation_and_cancellation ()
