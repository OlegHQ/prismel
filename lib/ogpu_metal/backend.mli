type control

(** The Metal driver: one device per [create_device] call, immediate-mode
    encoders, and surfaces adopted from the configuration's native layer
    token. *)
val create : unit -> Ogpu_core.Backend.driver * control

module Private : sig
  (* Borrowed until the portable texture is destroyed; validates the exact
     backend control so numeric driver tokens cannot alias across devices. *)
  val native_texture : control -> Ogpu_core.Backend.texture -> (Metal.Texture.t,Ogpu_core.Error.t) result
end
