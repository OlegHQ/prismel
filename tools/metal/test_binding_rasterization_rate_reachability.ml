let () =
  Binding_rasterization_rate_reachability.validate ();
  if Array.length Sys.argv <> 2 then invalid_arg "expected generated inventory path";
  let open Yojson.Safe.Util in
  let inventory_ids =
    Yojson.Safe.from_file Sys.argv.(1) |> member "symbols" |> to_list
    |> List.filter_map (fun symbol ->
      if symbol |> member "classification" |> to_string = "unreviewed"
         && symbol |> member "header" |> to_string
            = "Metal/MTLRasterizationRate.h"
      then Some (symbol |> member "id" |> to_string)
      else None)
    |> List.sort String.compare
  in
  if inventory_ids
     <> List.sort String.compare
          Binding_rasterization_rate_reachability.all_ids
  then failwith "RasterizationRate55 inventory closure drift";
  Printf.printf
    "RasterizationRate55 audit: mechanical callable19; handwritten ownership31; public metadata5; no promotion\n"
