open Metal
let get=function Ok value->value|Error e->failwith(Format.asprintf "%a" pp_error e)
let ()=
  let callbacks=ref 0 in
  let observer,devices=get(Device_observer.create(fun device _notification->
    incr callbacks;ignore(Device.destroy device)))in
  if not(Device_observer.active observer)then failwith"observer inactive after create";
  List.iter(fun device->get(Device.destroy device))devices;
  get(Device_observer.cancel observer);
  if Device_observer.active observer then failwith"observer active after cancel";
  (match Device_observer.cancel observer with
   |Error{kind=Invalid_state;_}->()|_->failwith"double cancel accepted");
  ignore !callbacks;
  print_endline"device metadata7: observer ownership ok"
