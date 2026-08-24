open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok value -> value | Error error -> fail "%s" error.message
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" error.message
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let manager = get (Capture.Manager.shared ()) in
  let source = Capture.Capture_device device in
  let scope = get (Capture.Scope.create manager source) in
  if Capture.Scope.device scope != device then fail "scope device identity drift";
  get (Capture.Manager.set_default_scope manager (Some scope));
  (match get (Capture.Manager.default_scope manager) with
   | Some retained when retained == scope -> ()
   | _ -> fail "default scope identity drift");
  expect Parent_has_dependents (Capture.Scope.destroy scope);
  expect Invalid_argument
    (Capture.Descriptor.create ~source ~destination:Capture.Developer_tools
       ~output_url:"/tmp/invalid.gputrace" ());
  expect Invalid_argument
    (Capture.Descriptor.create ~source
       ~destination:Capture.Gpu_trace_document ());
  let descriptor =
    get (Capture.Descriptor.create ~source
           ~destination:Capture.Gpu_trace_document
           ~output_url:"/tmp/prismel-capture.gputrace" ())
  in
  (match Capture.Descriptor.source descriptor with
   | Some (Capture.Capture_device retained) when retained == device -> ()
   | _ -> fail "descriptor source snapshot drift");
  if Capture.Descriptor.output_url descriptor
     <> Some "/tmp/prismel-capture.gputrace"
  then fail "descriptor URL snapshot drift";
  expect Parent_has_dependents (Device.destroy device);
  get (Capture.Descriptor.set_source descriptor (Some (Capture.Capture_scope scope)));
  expect Parent_has_dependents (Capture.Scope.destroy scope);
  get (Capture.Descriptor.set_source descriptor (Some source));
  get (Capture.Descriptor.destroy descriptor);
  get (Capture.Manager.set_default_scope manager None);
  get (Capture.Scope.destroy scope);
  expect Invalid_state (Capture.Manager.stop manager);
  get (Capture.Manager.destroy manager);
  get (Device.destroy device)
