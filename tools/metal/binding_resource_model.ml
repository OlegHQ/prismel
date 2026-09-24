type range = { offset : int; length : int }
type extent = { width : int; height : int; depth : int }
type allocation = Buffer of { length : int; alignment : int } | Texture of extent
let validate_range ~total ~alignment range =
  if total < 0 || alignment <= 0 then Error "invalid allocation metadata"
  else if range.offset < 0 || range.length < 0 || range.offset > total - range.length
  then Error "resource range is out of bounds"
  else if range.offset mod alignment <> 0 then Error "resource offset is misaligned"
  else Ok ()
let validate_extent extent =
  if extent.width <= 0 || extent.height <= 0 || extent.depth <= 0
  then Error "texture extent must be positive" else Ok ()
let lifecycle_invariants =
  [ "resource and heap must belong to the command device"
  ; "subranges are overflow-safe and explicitly aligned"
  ; "texture views cannot widen format, usage, mip, slice, or plane bounds"
  ; "heap aliases are unusable between makeAliasable and a new allocation"
  ; "borrowed rootResource and parentTexture never outlive their owner"
  ; "sampler state is retained through command completion"
  ; "resource-state encoders retain fences and sparse mappings through completion"
  ; "every constructor failure unwinds all partially retained handles" ]
