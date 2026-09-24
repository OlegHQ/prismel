let field ?(seed=37) ?(density=100) ~x ~y size =
  let result=Hashtbl.create 256 in
  Mark_field.iter ~seed ~density ~x ~y ~size (fun id cx cy diameter opacity ->
    if Hashtbl.mem result id then failwith "duplicate sample";
    Hashtbl.add result id (cx,cy,diameter,opacity));
  result

let close a b = if abs_float (a-.b)>1e-9 then failwith "sample moved in glyph space"

let () =
  let previous=ref (field ~x:0. ~y:0. 1.) in
  List.iter (fun size ->
    let current=field ~x:13.125 ~y:(-27.75) size in
    Hashtbl.iter (fun id (_,_,_,old_alpha) ->
      match Hashtbl.find_opt current id with
      |None -> failwith "zoom removed a visible sample"
      |Some (_,_,_,alpha) when alpha<old_alpha -> failwith "detail faded backwards"
      |Some _ -> ()) !previous;
    Hashtbl.iter (fun id (x,y,diameter,alpha) ->
      close ((x-.13.125)/.size) ((float (id mod 16)+.0.5)/.16.);
      close ((y+.27.75)/.size) ((float (id/16)+.0.5)/.16.);
      if diameter<0.75 || alpha<=0. || alpha>1. then failwith "invalid sample" ) current;
    previous:=current)
    [1.01;2.;3.99;4.;7.99;8.;8.01;15.99;16.;16.01;23.99;24.;
     31.99;32.;59.99;60.;60.01;63.99;64.;64.01;120.;1000.];
  if Hashtbl.length !previous<>256 then failwith "missing full detail";
  List.iter (fun threshold ->
    let a=field ~x:0. ~y:0. (threshold-.1e-6)
    and b=field ~x:0. ~y:0. (threshold+.1e-6) in
    Hashtbl.iter (fun id (x,y,d,alpha) ->
      match Hashtbl.find_opt a id with
      |None -> if alpha>1e-9 then failwith "new detail popped in"
      |Some (px,py,pd,pa) ->
          if abs_float (x-.px)>3e-6 || abs_float (y-.py)>3e-6 ||
             abs_float (d-.pd)>3e-6 || abs_float (alpha-.pa)>3e-6 then
            failwith "discontinuous zoom threshold") b)
    [1.;4.;8.;16.;24.;32.;60.;64.];
  List.iter (fun (size,limit) ->
    if Hashtbl.length (field ~x:0. ~y:0. size)>limit then
      failwith "subpixel sample overdraw") [4.,1;8.,4;16.,16;32.,64;64.,256];
  if field ~seed:93 ~density:55 ~x:12. ~y:5. 80.<>
     field ~seed:93 ~density:55 ~x:12. ~y:5. 80. then failwith "nondeterministic marks";
  if Hashtbl.length (field ~density:0 ~x:0. ~y:0. 80.)<>0 then failwith "zero density";
  print_endline "mark field: fixed sample identities, fractional projection, continuous detail thresholds"
