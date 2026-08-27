type capability=Ray_tracing|Metal_fx|Timestamp_queries|Unknown of string
type adapter_descriptor={backend_id:string;name:string;priority:int;capabilities:capability list;limits:Capabilities.limits}
type device={handle:Handle.device;generation:int64;mutable dead:bool}
type adapter={id:int64;descriptor:adapter_descriptor;mutable generation:int64;mutable dead:bool;mutable devices:device list}
type t={mutable dead:bool;adapters:adapter array}
let invalid text=Error(Error.make"Ogpu.Instance.create"Error.Invalid_argument text)
let canonical capabilities=List.sort_uniq compare capabilities
let validate_descriptor value=if value.backend_id=""||String.contains value.backend_id '\000'||value.name=""||String.contains value.name '\000'then invalid"adapter names must be nonempty and NUL-free"else if canonical value.capabilities<>value.capabilities then invalid"capabilities must be sorted and unique"else Capabilities.validate{limits=value.limits;ray_tracing=List.mem Ray_tracing value.capabilities;metal_fx=List.mem Metal_fx value.capabilities}
let create descriptors=let sorted=List.sort(fun a b->match compare b.priority a.priority with 0->String.compare a.backend_id b.backend_id|value->value)descriptors in let rec validate seen=function []->Ok()|value::_ when List.mem value.backend_id seen->invalid"backend registration id is duplicated"|value::rest->Result.bind(validate_descriptor value)(fun()->validate(value.backend_id::seen)rest)in Result.map(fun()->{dead=false;adapters=sorted|>List.mapi(fun i descriptor->{id=Int64.of_int(i+1);descriptor;generation=1L;dead=false;devices=[]})|>Array.of_list})(validate[]sorted)
let ensure_instance value=if value.dead then Error(Error.make"Ogpu.Instance"Error.Stale_handle"instance is destroyed")else Ok()
let adapters value=Result.map(fun()->Array.copy value.adapters)(ensure_instance value)
let supports adapter required=List.for_all(fun capability->List.mem capability adapter.descriptor.capabilities)required
let select value ~required=Result.bind(ensure_instance value)(fun()->match Array.find_opt(fun(adapter:adapter)->not adapter.dead&&supports adapter required)value.adapters with Some adapter->Ok adapter|None->Error(Error.make"Ogpu.Instance.select"Error.No_adapter"no adapter satisfies required capabilities"))
let adapter_id value=value.id
let adapter_descriptor value=value.descriptor
let request_device (adapter:adapter) ~required=if adapter.dead then Error(Error.make"Ogpu.Instance.request_device"Error.Stale_handle"adapter is destroyed")else if not(supports adapter required)then Error(Error.make"Ogpu.Instance.request_device"Error.Unsupported"adapter lacks a required capability")else let device={handle=Handle.create_device();generation=adapter.generation;dead=false}in adapter.devices<-device::adapter.devices;Ok device
let device_handle (value:device)=value.handle
let device_generation (value:device)=value.generation
let destroy_device (value:device)=if not value.dead then(value.dead<-true;Handle.destroy_device value.handle)
let destroy_adapter (value:adapter)=if not value.dead then(value.dead<-true;value.generation<-Int64.succ value.generation;List.iter destroy_device value.devices;value.devices<-[])
let destroy (value:t)=if not value.dead then(value.dead<-true;Array.iter destroy_adapter value.adapters)
