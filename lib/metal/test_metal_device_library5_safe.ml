open Metal

let reject kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok library ->
      ignore (Library.destroy library);
      failwith "expected Device library-constructor rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "Device library5: skipped (no Metal device)"
  | Ok device ->
      (match Library.default ~device with
       | Ok library ->
           if Library.device library != device then failwith "default library device drift";
           (match Library.destroy library with Ok () -> () | Error error ->
             failwith (Format.asprintf "%a" pp_error error))
       | Error error when error.kind = Native_error || error.kind = Unsupported -> ()
       | Error error -> failwith (Format.asprintf "%a" pp_error error));
      reject Invalid_argument (Library.default_in_bundle ~device "relative.bundle");
      reject Invalid_argument (Library.load_data ~device "");
      reject Invalid_argument (Library.load_file_legacy ~device "relative.metallib");
      reject Native_error
        (Library.load_file_legacy ~device "/prismel/does/not/exist.metallib");
      (match Device.destroy device with Ok () -> () | Error error ->
        failwith (Format.asprintf "%a" pp_error error));
      print_endline "Device library5: ownership/path/data rejection passed"
