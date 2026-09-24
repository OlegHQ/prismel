open Binding_spec

let entries =
  [ { sdk_id = "method:-[MTLDevice maxThreadgroupMemoryLength]"
    ; expect =
        { kind = "method"
        ; owner = "MTLDevice"
        ; name = "maxThreadgroupMemoryLength"
        ; header = "Metal/MTLDevice.h"
        ; signature = "instance () -> NSUInteger"
        ; attributes = [ "AvailabilityAttr" ]
        ; availability = macos_10_13_availability
        }
    ; companions =
        [ { sdk_id = "property:MTLDevice:maxThreadgroupMemoryLength"
          ; kind = "property"
          ; owner = "MTLDevice"
          ; name = "maxThreadgroupMemoryLength"
          ; header = "Metal/MTLDevice.h"
          ; signature = "NSUInteger"
          ; attributes = [ "AvailabilityAttr" ]
          }
        ]
    ; disposition =
        Generate
          (Direct_getter
             { ocaml_name = "device_max_threadgroup_memory_length"
             ; c_symbol =
                 "caml_prismel_metal_device_max_threadgroup_memory_length"
             ; receiver = Device
             ; result =
                 Nsuint_to_checked_int64
                   { overflow_error =
                       "Metal returned a threadgroup-memory limit outside signed 64-bit range"
                   }
             })
    ; safe_api =
        Some
          (safe_api ~module_path:[ "Device" ] ~value_name:"info"
             ~test_value:"test_device_info")
    }
  ]
