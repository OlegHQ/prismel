type device type child type completion type error=Destroyed|Parent_has_dependents|Invalid_argument
val device:unit->device val create_child:device->(child,error)result
val destroy_child:child->(unit,error)result val schedule:device->(completion,error)result
val complete:completion->(unit,error)result val unwind:completion->unit
val destroy_device:device->(unit,error)result
val validate_array:count:int->capacity:int->bool val validate_size3:int*int*int->bool
