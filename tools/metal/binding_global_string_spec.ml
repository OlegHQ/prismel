type family =
  | Error_domain
  | Error_user_info_key
  | Common_counter
  | Common_counter_set
  | Device_notification

type entry =
  { sdk_id : string
  ; name : string
  ; header : string
  ; signature : string
  ; objc_typedef : string
  ; family : family
  ; macos_introduced : Binding_availability.version
  }

let parse_version value =
  match String.split_on_char '.' value with
  | [ major; minor ] ->
      { Binding_availability.major = int_of_string major
      ; minor = int_of_string minor
      ; patch = 0
      }
  | [ major; minor; patch ] ->
      { Binding_availability.major = int_of_string major
      ; minor = int_of_string minor
      ; patch = int_of_string patch
      }
  | _ -> invalid_arg ("Invalid Metal availability version: " ^ value)

let entry ~name ~header ~signature ~objc_typedef ~family ~introduced =
  { sdk_id = "variable:" ^ name
  ; name
  ; header
  ; signature
  ; objc_typedef
  ; family
  ; macos_introduced = parse_version introduced
  }

let domain name header introduced =
  entry ~name ~header ~signature:"const NSErrorDomain  _Nonnull __strong"
    ~objc_typedef:"NSErrorDomain" ~family:Error_domain ~introduced

let counter name =
  entry ~name ~header:"Metal/MTLCounters.h"
    ~signature:"MTLCommonCounter  _Nonnull __strong"
    ~objc_typedef:"MTLCommonCounter" ~family:Common_counter ~introduced:"10.15"

let counter_set name =
  entry ~name ~header:"Metal/MTLCounters.h"
    ~signature:"MTLCommonCounterSet  _Nonnull __strong"
    ~objc_typedef:"MTLCommonCounterSet" ~family:Common_counter_set
    ~introduced:"10.15"

let notification name =
  entry ~name ~header:"Metal/MTLDevice.h"
    ~signature:"API_AVAILABLE const MTLDeviceNotificationName __strong"
    ~objc_typedef:"MTLDeviceNotificationName" ~family:Device_notification
    ~introduced:"10.13"

let entries =
  [ domain "MTL4CommandQueueErrorDomain" "Metal/MTL4CommandQueue.h" "26.0"
  ; domain "MTLBinaryArchiveDomain" "Metal/MTLBinaryArchive.h" "11.0"
  ; domain "MTLCaptureErrorDomain" "Metal/MTLCaptureManager.h" "10.15"
  ; entry ~name:"MTLCommandBufferEncoderInfoErrorKey"
      ~header:"Metal/MTLCommandBuffer.h"
      ~signature:"const NSErrorUserInfoKey  _Nonnull __strong"
      ~objc_typedef:"NSErrorUserInfoKey" ~family:Error_user_info_key
      ~introduced:"11.0"
  ; domain "MTLCommandBufferErrorDomain" "Metal/MTLCommandBuffer.h" "10.11"
  ; counter "MTLCommonCounterClipperInvocations"
  ; counter "MTLCommonCounterClipperPrimitivesOut"
  ; counter "MTLCommonCounterComputeKernelInvocations"
  ; counter "MTLCommonCounterFragmentCycles"
  ; counter "MTLCommonCounterFragmentInvocations"
  ; counter "MTLCommonCounterFragmentsPassed"
  ; counter "MTLCommonCounterPostTessellationVertexCycles"
  ; counter "MTLCommonCounterPostTessellationVertexInvocations"
  ; counter "MTLCommonCounterRenderTargetWriteCycles"
  ; counter_set "MTLCommonCounterSetStageUtilization"
  ; counter_set "MTLCommonCounterSetStatistic"
  ; counter_set "MTLCommonCounterSetTimestamp"
  ; counter "MTLCommonCounterTessellationCycles"
  ; counter "MTLCommonCounterTessellationInputPatches"
  ; counter "MTLCommonCounterTimestamp"
  ; counter "MTLCommonCounterTotalCycles"
  ; counter "MTLCommonCounterVertexCycles"
  ; counter "MTLCommonCounterVertexInvocations"
  ; domain "MTLCounterErrorDomain" "Metal/MTLCounters.h" "10.15"
  ; domain "MTLDeviceErrorDomain" "Metal/MTLDevice.h" "26.4"
  ; notification "MTLDeviceRemovalRequestedNotification"
  ; notification "MTLDeviceWasAddedNotification"
  ; notification "MTLDeviceWasRemovedNotification"
  ; domain "MTLDynamicLibraryDomain" "Metal/MTLDynamicLibrary.h" "11.0"
  ; domain "MTLIOErrorDomain" "Metal/MTLIOCommandQueue.h" "13.0"
  ; domain "MTLLibraryErrorDomain" "Metal/MTLLibrary.h" "10.11"
  ; domain "MTLLogStateErrorDomain" "Metal/MTLLogState.h" "15.0"
  ; domain "MTLTensorDomain" "Metal/MTLTensor.h" "26.0"
  ]

let expected_count = 33

let snake_case value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri
    (fun index character ->
      let uppercase = character >= 'A' && character <= 'Z' in
      if uppercase && index > 0 then begin
        let previous = value.[index - 1] in
        let next_lowercase =
          index + 1 < String.length value
          && value.[index + 1] >= 'a' && value.[index + 1] <= 'z'
        in
        if
          (previous >= 'a' && previous <= 'z')
          || (previous >= '0' && previous <= '9')
          || next_lowercase
        then Buffer.add_char output '_'
      end;
      Buffer.add_char output (Char.lowercase_ascii character))
    value;
  Buffer.contents output

let ocaml_name entry = "generated_global_" ^ snake_case entry.name
let c_symbol entry = "caml_prismel_metal_" ^ ocaml_name entry
