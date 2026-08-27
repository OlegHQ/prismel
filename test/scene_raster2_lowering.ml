let () =
  let open Prismel in
  let fill=Color.rgba 220 40 80 255 and stroke=Color.rgba 20 240 90 255 in
  let square=Scene.square~at:(3,4)~size:9~fill~stroke()in
  let rectangle=Scene.rect~at:(3,4)~w:9~h:9~fill~stroke()in
  if square<>rectangle then failwith"public square canonical Rect drift";
  let quad=Scene.quad(2,2)(15,3)(14,17)(3,16)~fill~stroke()in
  let polygon=Scene.polygon[(2,2);(15,3);(14,17);(3,16)]~fill~stroke()in
  if quad<>polygon then failwith"public quad canonical Polygon drift";
  let snapshot()=Marshal.to_bytes[square;quad][]in
  let expected=snapshot()in
  for _frame=1 to 600 do if snapshot()<>expected then
    failwith"Scene convenience frame drift"done;
  let workers=Array.init 4(fun _->Domain.spawn snapshot)in
  Array.iter(fun worker->if Domain.join worker<>expected then
    failwith"Scene convenience domain drift")workers;
  print_endline "Prismel private Scene to Raster2 IR lowering passed"
