open Metal

let reject kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok library ->
      ignore (Library.destroy library);
      failwith "expected Device library-constructor rejection"

let run () =
  match Device.system_default () with
  | Error _ -> print_endline "Device library5: skipped (no Metal device)"
  | Ok device ->
      reject Invalid_argument (Library.load_data ~device "");
      reject Native_error (Library.load_data ~device "not-a-metallib");
      (match Device.destroy device with Ok () -> () | Error error ->
        failwith (Format.asprintf "%a" pp_error error));
      print_endline "Device library5: ownership/path/data rejection passed"
