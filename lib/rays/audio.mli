val init : unit -> (unit,string) result
(* Opens the default playback device. *)
val is_initialized:unit->bool
val shutdown:unit->unit
module Sample:sig
  type t
  type waveform = Sine | Square | Saw | Triangle
  val load:string->(t,string)result
  val synth : ?volume:float -> waveform:waveform -> frequency:float -> duration:float -> unit -> (t,string) result
  val play : ?loops:int -> ?volume:float -> t -> (int,string) result
  val destroy:t->unit
end
