let ids =
  [ "method:-[MTLDevice newDefaultLibrary]"
  ; "method:-[MTLDevice newDefaultLibraryWithBundle:error:]"
  ; "method:-[MTLDevice newLibraryWithData:error:]"
  ; "method:-[MTLDevice newLibraryWithFile:error:]"
  ; "method:-[MTLDevice newLibraryWithStitchedDescriptor:error:]" ]

type public_site =
  { id : string; module_name : string; value_name : string }

let public_sites =
  [ { id = "method:-[MTLDevice newDefaultLibrary]"; module_name = "Library"; value_name = "default" }
  ; { id = "method:-[MTLDevice newDefaultLibraryWithBundle:error:]"; module_name = "Library"; value_name = "default_in_bundle" }
  ; { id = "method:-[MTLDevice newLibraryWithData:error:]"; module_name = "Library"; value_name = "load_data" }
  ; { id = "method:-[MTLDevice newLibraryWithFile:error:]"; module_name = "Library"; value_name = "load_file_legacy" }
  ; { id = "method:-[MTLDevice newLibraryWithStitchedDescriptor:error:]"; module_name = "Stitched_library_descriptor"; value_name = "compile" } ]

let validate () =
  if List.length ids <> 5 || List.length (List.sort_uniq String.compare ids) <> 5 then
    invalid_arg "Device library5 ID drift";
  if List.map (fun site -> site.id) public_sites <> ids then
    invalid_arg "Device library5 public-site mapping drift"
