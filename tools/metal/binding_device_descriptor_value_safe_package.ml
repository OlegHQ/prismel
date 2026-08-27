(* Exact immutable/public-value and owned descriptor closure inside the
   MTLDevice.h residual.  ArgumentDescriptor mutation remains handwritten at
   the safe boundary; the method/property pairs are one semantic field each. *)

let argument_descriptor_ids =
  [ "class:MTLArgumentDescriptor"
  ; "method:+[MTLArgumentDescriptor argumentDescriptor]"
  ; "method:-[MTLArgumentDescriptor access]"
  ; "method:-[MTLArgumentDescriptor arrayLength]"
  ; "method:-[MTLArgumentDescriptor constantBlockAlignment]"
  ; "method:-[MTLArgumentDescriptor dataType]"
  ; "method:-[MTLArgumentDescriptor index]"
  ; "method:-[MTLArgumentDescriptor setAccess:]"
  ; "method:-[MTLArgumentDescriptor setArrayLength:]"
  ; "method:-[MTLArgumentDescriptor setConstantBlockAlignment:]"
  ; "method:-[MTLArgumentDescriptor setDataType:]"
  ; "method:-[MTLArgumentDescriptor setIndex:]"
  ; "method:-[MTLArgumentDescriptor setTextureType:]"
  ; "method:-[MTLArgumentDescriptor textureType]"
  ; "property:MTLArgumentDescriptor:access"
  ; "property:MTLArgumentDescriptor:arrayLength"
  ; "property:MTLArgumentDescriptor:constantBlockAlignment"
  ; "property:MTLArgumentDescriptor:dataType"
  ; "property:MTLArgumentDescriptor:index"
  ; "property:MTLArgumentDescriptor:textureType" ]

let architecture_ids =
  [ "class:MTLArchitecture"
  ; "method:-[MTLArchitecture name]"
  ; "property:MTLArchitecture:name"
  ; "method:-[MTLDevice architecture]"
  ; "property:MTLDevice:architecture" ]

let ids = argument_descriptor_ids @ architecture_ids

let validate () =
  if List.length argument_descriptor_ids <> 20 then
    invalid_arg "MTLArgumentDescriptor exact closure drift";
  if List.length architecture_ids <> 5 then
    invalid_arg "MTLArchitecture exact closure drift";
  if List.length (List.sort_uniq String.compare ids) <> 25 then
    invalid_arg "Device descriptor/value closure duplicate IDs"
