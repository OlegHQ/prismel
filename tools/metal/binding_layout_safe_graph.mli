type owner type child type error=Destroyed|Dependents|Invalid
val owner:unit->owner val child:owner->(child,error)result val destroy_child:child->(unit,error)result val destroy_owner:owner->(unit,error)result
val validate_extents:int array->bool val validate_rates:float array->bool val validate_layer:index:int->count:int->bool
