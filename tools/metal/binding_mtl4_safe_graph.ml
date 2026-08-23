type device=int
type command_buffer={device:device;mutable state:[`Recording|`Committed|`Completed];mutable retained:int}
type encoder={parent:command_buffer;mutable ended:bool}
type resource={device:device;id:int}
let command_buffer device={device;state=`Recording;retained=0}
let encoder parent=if parent.state<>`Recording then Error"command buffer is not recording"else(parent.retained<-parent.retained+1;Ok{parent;ended=false})
let use_resource e r=if e.ended then Error"encoder already ended"else if r.device<>e.parent.device then Error"resource belongs to another device"else Ok()
let finish e=if e.ended then Error"encoder already ended"else(e.ended<-true;Ok())
let commit b=if b.state<>`Recording then Error"command buffer already committed"else(b.state<-`Committed;Ok())
let complete b=if b.state<>`Committed then Error"command buffer not committed"else(b.state<-`Completed;b.retained<-0;Ok())
