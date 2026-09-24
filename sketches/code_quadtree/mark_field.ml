(* Stable glyph-space stippling. Zoom only projects these fixed sample IDs;
   additional detail fades in without moving or reseeding existing samples. *)
let mix seed index = ((seed lxor (index * 374761393)) * 668265263) land 0x3fffffff
let smooth low high value =
  let t=max 0. (min 1. ((value-.low)/.(high-.low))) in
  t*.t*.(3.-.2.*.t)

let samples =
  Array.init 256 (fun index ->
    let a=index mod 16 and b=index/16 in
    let level=if a=8 && b=8 then 0
      else if a mod 8=0 && b mod 8=0 then 1
      else if a mod 4=0 && b mod 4=0 then 2
      else if a mod 2=0 && b mod 2=0 then 3 else 4 in
    level,index,(float a+.0.5)/.16.,(float b+.0.5)/.16.)
  |> Array.to_list
  |> List.stable_sort (fun (a,_,_,_) (b,_,_,_) -> Int.compare a b)
  |> Array.of_list

let iter ~seed ~density ~x ~y ~size emit =
  (* Match sample count to projected area. Sixteen subpixel marks in a two-
     pixel glyph only create overdraw; retain one stable representative there. *)
  let count=if size<=4. then 1 else if size<=8. then 4
    else if size<=16. then 16 else if size<=32. then 64 else 256 in
  let coarse=smooth 1. 4. size and quarters=smooth 4. 8. size
  and medium=smooth 8. 16. size and fine=smooth 16. 32. size
  and finest=smooth 32. 64. size in
  let diameter=max 0.75 (size/.32.) in
  for i=0 to count-1 do
    let level,id,u,v=samples.(i) in
    let opacity=match level with 0->coarse|1->quarters|2->medium|3->fine|_->finest in
    if opacity>0. && density>0 && (level=0 || mix seed id mod 100<density) then
      emit id (x+.u*.size) (y+.v*.size) diameter opacity
  done
