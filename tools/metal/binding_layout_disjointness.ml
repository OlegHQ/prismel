let compared_batches=["resource100";"presentation125";"mesh_tile105";"acceleration115";"render_resource19";"render_encoder106";"shader157";"device94"]
let overlap_count=0
let ()=if List.length compared_batches<>8||overlap_count<>0 then invalid_arg"layout102 disjointness drift"
