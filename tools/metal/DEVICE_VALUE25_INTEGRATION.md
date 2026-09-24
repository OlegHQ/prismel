# Device value25 integration

After the final Device selector lane yields shared files:

- include `metal_device_architecture5_bridge.inc` in `metal_bridge.mm`;
- declare `device_architecture_name : handle -> (string,string) result` in raw ML/MLI;
- expose copied immutable `Architecture.t` and `Device.architecture`;
- extend the final-selector `Shader_argument_encoder.Descriptor` with snapshot
  accessors for its six exact SDK fields;
- register and run `test_metal_device_value25_safe.ml`, the exact25 package,
  and `test_device_descriptor_value25_native.mm` before promotion.

The architecture pointer remains private. Descriptor lists remain owned OCaml
values marshalled atomically by the final-selector constructor; no raw object
pointer crosses the public boundary.
