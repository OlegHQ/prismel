open Metal
let reject kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf"%a"pp_error e)|Ok f->ignore(IO.File.destroy f);failwith"expected IO rejection"
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=match Device.system_default()with
|Error _->print_endline"Device legacy IO2: skipped (no device)"
|Ok device->
  reject Invalid_argument(Device.open_io_handle_legacy device "");
  reject Invalid_argument(Device.open_compressed_io_handle_legacy device~method_:Io_lz4 "");
  (match Device.open_io_handle_legacy device "/prismel/missing.bin" with Error e when e.kind=Native_error||e.kind=Unsupported->()|Error e->failwith(Format.asprintf"%a"pp_error e)|Ok f->get(IO.File.destroy f));
  (match Device.open_compressed_io_handle_legacy device~method_:Io_lz4 "/prismel/missing.bin" with Error e when e.kind=Native_error||e.kind=Unsupported->()|Error e->failwith(Format.asprintf"%a"pp_error e)|Ok f->get(IO.File.destroy f));
  get(Device.destroy device);print_endline"Device legacy IO2: validation/capability passed"
