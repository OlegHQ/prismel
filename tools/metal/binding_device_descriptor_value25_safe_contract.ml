type argument_descriptor =
  { access:int64; array_length:int64; constant_block_alignment:int64
  ; data_type:int64; index:int64; texture_type:int64 }

let power_of_two value = value>0L && Int64.logand value(Int64.pred value)=0L

let validate value =
  value.array_length>0L && value.index>=0L &&
  power_of_two value.constant_block_alignment &&
  value.constant_block_alignment<=4096L && value.access>=0L &&
  value.data_type>=0L && value.texture_type>=0L

let snapshot value =
  {access=value.access;array_length=value.array_length;
   constant_block_alignment=value.constant_block_alignment;
   data_type=value.data_type;index=value.index;texture_type=value.texture_type}

let validate_architecture_name name = name<>"" && not(String.contains name '\000')
