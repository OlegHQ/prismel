type buffer_usage=Copy_src|Copy_dst|Uniform|Storage|Vertex|Index
type buffer_descriptor={label:string option;size:int64;usage:buffer_usage list}
type texture_usage=Texture_binding|Render_attachment|Texture_copy_src|Texture_copy_dst
type texture_descriptor={label:string option;width:int;height:int;depth:int;mip_levels:int;sample_count:int;usage:texture_usage list}
let label_ok=function None->true|Some s->not(String.contains s '\000')
let validate_buffer (caps:Capabilities.t) (value:buffer_descriptor)=
  if not(label_ok value.label)then Error(Error.make "Ogpu.Types.validate_buffer" Error.Invalid_argument "label contains NUL")
  else if value.size<=0L||value.size>caps.Capabilities.limits.max_buffer_size then Error(Error.make "Ogpu.Types.validate_buffer" Error.Invalid_argument "buffer size is outside device limits")
  else if value.usage=[] then Error(Error.make "Ogpu.Types.validate_buffer" Error.Invalid_argument "buffer usage is empty")else Ok()
let validate_texture (caps:Capabilities.t) (value:texture_descriptor)=
  let l=caps.Capabilities.limits in
  if not(label_ok value.label)then Error(Error.make "Ogpu.Types.validate_texture" Error.Invalid_argument "label contains NUL")
  else if value.width<=0||value.height<=0||value.depth<=0||value.width>l.max_texture_dimension_2d||value.height>l.max_texture_dimension_2d then Error(Error.make "Ogpu.Types.validate_texture" Error.Invalid_argument "texture extent is outside device limits")
  else if value.mip_levels<=0||value.sample_count<=0||value.sample_count>l.max_sample_count then Error(Error.make "Ogpu.Types.validate_texture" Error.Invalid_argument "texture cardinality is invalid")
  else if value.usage=[] then Error(Error.make "Ogpu.Types.validate_texture" Error.Invalid_argument "texture usage is empty")else Ok()
