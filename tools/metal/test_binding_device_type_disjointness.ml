let ()=
 if List.length Binding_device_type_disjointness.resource100_overlap<>2 then failwith"resource overlap";
 if List.length Binding_device_type_disjointness.acceleration115_overlap<>7 then failwith"acceleration overlap";
 if List.length Binding_device_type_disjointness.zero_overlap_batches<>4 then failwith"zero-overlap matrix"
