(** Deterministic functional 3D compute dispatch. *)

type invocation = {
  global_id : int * int * int;
  local_id : int * int * int;
  group_id : int * int * int;
  num_groups : int * int * int;
  local_size : int * int * int;
  linear_index : int;
  uniforms : Shader3.uniforms;
}

val dispatch :
  ?grain:int ->
  ?uniforms:Shader3.uniforms ->
  groups:int * int * int ->
  local_size:int * int * int ->
  (invocation -> 'a) ->
  'a array
(** Invoke one pure function for every global invocation, returning results in
    row-major order with X varying fastest. Large dispatches use [Parallel]
    while preserving output order. Functions must not mutate shared data or
    access SDL resources. *)
