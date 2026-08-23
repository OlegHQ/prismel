type owner={mutable live:bool;mutable dependents:int}
type child={owner:owner;mutable live:bool}
type error=Destroyed|Dependents|Invalid
let owner()={live=true;dependents=0}
let child (owner:owner)=if not owner.live then Error Destroyed else(owner.dependents<-owner.dependents+1;Ok{owner;live=true})
let destroy_child c=if not c.live then Error Destroyed else(c.live<-false;c.owner.dependents<-c.owner.dependents-1;Ok())
let destroy_owner (o:owner)=if not o.live then Error Destroyed else if o.dependents>0 then Error Dependents else(o.live<-false;Ok())
let validate_extents xs=Array.length xs>0&&Array.length xs<=16&&Array.for_all((<)0)xs
let validate_rates xs=Array.length xs>0&&Array.for_all(fun x->Float.is_finite x&&x>0.)xs
let validate_layer ~index ~count=index>=0&&count>0&&index<count
