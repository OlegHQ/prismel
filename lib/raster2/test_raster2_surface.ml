let fail message = failwith message

let get_ok = function Ok value -> value | Error _ -> fail "unexpected error"

let () =
  let surface = get_ok (Raster2.Surface.create ~pitch:16 ~width:3 ~height:2 ()) in
  assert (Raster2.Surface.width surface = 3);
  assert (Raster2.Surface.height surface = 2);
  assert (Raster2.Surface.pitch surface = 16);
  Raster2.Surface.clear surface 0x12345678l;
  assert (get_ok (Raster2.Surface.get_rgba surface ~x:2 ~y:1) = 0x12345678l);
  assert (Bytes.get (Raster2.Surface.bytes surface) 12 = '\000');
  get_ok (Raster2.Surface.set_rgba surface ~x:1 ~y:0 0xaabbccddl);
  assert (get_ok (Raster2.Surface.get_rgba surface ~x:1 ~y:0) = 0xaabbccddl);
  (match Raster2.Surface.get_rgba surface ~x:3 ~y:0 with
  | Error (Raster2.Surface.Coordinate_out_of_bounds _) -> ()
  | _ -> fail "out-of-bounds coordinate accepted");
  (match Raster2.Surface.create ~pitch:7 ~width:2 ~height:1 () with
  | Error (Raster2.Surface.Invalid_pitch { minimum = 8; actual = 7 }) -> ()
  | _ -> fail "short pitch accepted");
  (match Raster2.Surface.of_bytes ~width:2 ~height:2 ~pitch:8 (Bytes.create 15) with
  | Error (Raster2.Surface.Storage_too_small { required = 16; actual = 15 }) -> ()
  | _ -> fail "short storage accepted")
