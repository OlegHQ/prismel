type device={mutable live:bool;mutable children:int;mutable completions:int}
type child={device:device;mutable live:bool}
type completion={device:device;mutable pending:bool}
type error=Destroyed|Parent_has_dependents|Invalid_argument
let device()={live=true;children=0;completions=0}
let create_child (device:device) = if not device.live then Error Destroyed else
 (device.children<-device.children+1;Ok{device;live=true})
let destroy_child child = if not child.live then Error Destroyed else
 (child.live<-false;child.device.children<-child.device.children-1;Ok())
let schedule (device:device) = if not device.live then Error Destroyed else
 (device.completions<-device.completions+1;Ok{device;pending=true})
let complete completion = if not completion.pending then Error Invalid_argument else
 (completion.pending<-false;completion.device.completions<-completion.device.completions-1;Ok())
let unwind completion = if completion.pending then ignore(complete completion)
let destroy_device (device:device) = if not device.live then Error Destroyed
 else if device.children<>0||device.completions<>0 then Error Parent_has_dependents
 else(device.live<-false;Ok())
let validate_array ~count ~capacity = count>0&&count<=capacity
let validate_size3(x,y,z)=x>0&&y>0&&z>0
