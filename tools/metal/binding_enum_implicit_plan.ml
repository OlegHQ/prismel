type case =
  { sdk_name : string
  ; unsigned_decimal : string
  ; expected_line : int
  }

type family =
  { sdk_name : string
  ; header : string
  ; enum_line : int
  ; typedef_signature : string
  ; cases : case list
  }

let case sdk_name unsigned_decimal expected_line =
  { sdk_name; unsigned_decimal; expected_line }

let families =
  [ { sdk_name = "MTL4CounterHeapType"
    ; header = "Metal/MTL4Counters.h"
    ; enum_line = 24
    ; typedef_signature = "enum MTL4CounterHeapType"
    ; cases =
        [ case "MTL4CounterHeapTypeInvalid" "0" 27
        ; case "MTL4CounterHeapTypeTimestamp" "1" 30
        ]
    }
  ; { sdk_name = "MTLCaptureError"
    ; header = "Metal/MTLCaptureManager.h"
    ; enum_line = 22
    ; typedef_signature = "enum MTLCaptureError"
    ; cases =
        [ case "MTLCaptureErrorNotSupported" "1" 25
        ; case "MTLCaptureErrorAlreadyCapturing" "2" 27
        ; case "MTLCaptureErrorInvalidDescriptor" "3" 29
        ]
    }
  ; { sdk_name = "MTLCaptureDestination"
    ; header = "Metal/MTLCaptureManager.h"
    ; enum_line = 33
    ; typedef_signature = "enum MTLCaptureDestination"
    ; cases =
        [ case "MTLCaptureDestinationDeveloperTools" "1" 36
        ; case "MTLCaptureDestinationGPUTraceDocument" "2" 38
        ]
    }
  ; { sdk_name = "MTLCounterSampleBufferError"
    ; header = "Metal/MTLCounters.h"
    ; enum_line = 215
    ; typedef_signature = "enum MTLCounterSampleBufferError"
    ; cases =
        [ case "MTLCounterSampleBufferErrorOutOfMemory" "0" 217
        ; case "MTLCounterSampleBufferErrorInvalid" "1" 218
        ; case "MTLCounterSampleBufferErrorInternal" "2" 219
        ]
    }
  ; { sdk_name = "MTLDispatchType"
    ; header = "Metal/MTLCommandBuffer.h"
    ; enum_line = 235
    ; typedef_signature = "enum MTLDispatchType"
    ; cases =
        [ case "MTLDispatchTypeSerial" "0" 236
        ; case "MTLDispatchTypeConcurrent" "1" 237
        ]
    }
  ; { sdk_name = "MTLCounterSamplingPoint"
    ; header = "Metal/MTLDevice.h"
    ; enum_line = 353
    ; typedef_signature = "enum MTLCounterSamplingPoint"
    ; cases =
        [ case "MTLCounterSamplingPointAtStageBoundary" "0" 355
        ; case "MTLCounterSamplingPointAtDrawBoundary" "1" 356
        ; case "MTLCounterSamplingPointAtDispatchBoundary" "2" 357
        ; case "MTLCounterSamplingPointAtTileDispatchBoundary" "3" 358
        ; case "MTLCounterSamplingPointAtBlitBoundary" "4" 359
        ]
    }
  ; { sdk_name = "MTLLogLevel"
    ; header = "Metal/MTLLogState.h"
    ; enum_line = 20
    ; typedef_signature = "enum MTLLogLevel"
    ; cases =
        [ case "MTLLogLevelUndefined" "0" 22
        ; case "MTLLogLevelDebug" "1" 23
        ; case "MTLLogLevelInfo" "2" 24
        ; case "MTLLogLevelNotice" "3" 25
        ; case "MTLLogLevelError" "4" 26
        ; case "MTLLogLevelFault" "5" 27
        ]
    }
  ]

let expected_family_count = 7
let expected_case_count = 23
let expected_declaration_count = 37

let source_paths =
  [ "tools/metal/binding_enum_implicit_plan.ml"
  ; "tools/metal/binding_enum_implicit_plan.mli"
  ; "tools/metal/binding_enum_implicit_codegen.ml"
  ; "tools/metal/binding_enum_implicit_codegen.mli"
  ]

let validate () =
  let family_names =
    List.sort_uniq String.compare
      (List.map (fun (family : family) -> family.sdk_name) families)
  in
  if List.length family_names <> expected_family_count then
    invalid_arg "implicit Metal enum family count/uniqueness drift";
  let cases =
    List.concat_map
      (fun (family : family) ->
        List.map (fun (case : case) -> case.sdk_name) family.cases)
      families
  in
  if List.length cases <> expected_case_count
     || List.length (List.sort_uniq String.compare cases) <> expected_case_count
  then invalid_arg "implicit Metal enum case count/uniqueness drift";
  if expected_declaration_count <> expected_case_count + (2 * expected_family_count) then
    invalid_arg "implicit Metal enum declaration relationship drift"

let () = validate ()
