(** Packed ragged-array remapping and concatenation. *)
val validate_source_index : string -> int -> int -> unit
val offsets_for_mapping :
  ?cancel:Cancel.t -> ?grain:int -> operation:string ->
  source_offsets:int array -> int array -> int array
val remap_int :
  ?cancel:Cancel.t -> ?grain:int -> int array -> Packed.Int_array.t -> Packed.Int_array.t
val remap_float :
  ?cancel:Cancel.t -> ?grain:int -> int array -> Packed.Float_array.t -> Packed.Float_array.t
val concat_layout :
  operation:string -> 'a array -> ('a -> int) -> ('a -> int) -> int array * int
val concat_int : Packed.Int_array.t array -> Packed.Int_array.t
val concat_float : Packed.Float_array.t array -> Packed.Float_array.t
val overlay_offsets :
  ?cancel:Cancel.t -> ?grain:int -> operation:string -> mapping:int array ->
  source_offsets:int array -> existing_offsets:int array -> unit -> int array
val overlay_int :
  ?cancel:Cancel.t -> ?grain:int -> int array ->
  source:Packed.Int_array.t -> existing:Packed.Int_array.t -> Packed.Int_array.t
val overlay_float :
  ?cancel:Cancel.t -> ?grain:int -> int array ->
  source:Packed.Float_array.t -> existing:Packed.Float_array.t -> Packed.Float_array.t
