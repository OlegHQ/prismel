open Binding_direct_spec

let mtl_gpu_address =
  Unsigned { objc_type = "MTLGPUAddress"; width = Bits64 }

let mtl_stages = named_nsuint "MTLStages"
let mtl_primitive_type = named_nsuint "MTLPrimitiveType"
let mtl_barrier_scope = named_nsuint "MTLBarrierScope"
let mtl4_counter_heap_type = named_nsint "MTL4CounterHeapType"
let mtl_counter_sampling_point = named_nsuint "MTLCounterSamplingPoint"

let entries =
  [ method_entry
      ~sdk_id:"method:-[MTL4CommandBuffer popDebugGroup]"
      ~owner:"MTL4CommandBuffer" ~selector:"popDebugGroup"
      ~header:"Metal/MTL4CommandBuffer.h"
      ~signature:"instance () -> void" ~macos_introduced:(version 26 0)
      ~arguments:[] ~result:None ~semantics:Command ()
  ; method_entry
      ~sdk_id:
        "method:-[MTL4ComputeCommandEncoder dispatchThreadsWithIndirectBuffer:]"
      ~owner:"MTL4ComputeCommandEncoder"
      ~selector:"dispatchThreadsWithIndirectBuffer:"
      ~header:"Metal/MTL4ComputeCommandEncoder.h"
      ~signature:"instance (MTLGPUAddress) -> void"
      ~macos_introduced:(version 26 0) ~arguments:[ mtl_gpu_address ]
      ~result:None ~semantics:Command ()
  ; method_entry
      ~sdk_id:"method:-[MTL4ComputeCommandEncoder stages]"
      ~owner:"MTL4ComputeCommandEncoder" ~selector:"stages"
      ~header:"Metal/MTL4ComputeCommandEncoder.h"
      ~signature:"instance () -> MTLStages"
      ~macos_introduced:(version 26 0) ~arguments:[]
      ~result:(Some mtl_stages) ~semantics:Query ()
  ; method_entry
      ~sdk_id:
        "method:-[MTL4RenderCommandEncoder drawPrimitives:vertexStart:vertexCount:instanceCount:]"
      ~owner:"MTL4RenderCommandEncoder"
      ~selector:"drawPrimitives:vertexStart:vertexCount:instanceCount:"
      ~header:"Metal/MTL4RenderCommandEncoder.h"
      ~signature:
        "instance (MTLPrimitiveType, NSUInteger, NSUInteger, NSUInteger) -> void"
      ~macos_introduced:(version 26 0)
      ~arguments:[ mtl_primitive_type; nsuint; nsuint; nsuint ]
      ~result:None ~semantics:Command ()
  ; method_entry ~sdk_id:"method:-[MTLBuffer removeAllDebugMarkers]"
      ~owner:"MTLBuffer" ~selector:"removeAllDebugMarkers"
      ~header:"Metal/MTLBuffer.h" ~signature:"instance () -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 10 12) ~arguments:[] ~result:None
      ~semantics:Command ()
  ; method_entry ~sdk_id:"method:-[MTLCommandBuffer enqueue]"
      ~owner:"MTLCommandBuffer" ~selector:"enqueue"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"instance () -> void"
      ~macos_introduced:(version 10 11) ~arguments:[] ~result:None
      ~semantics:Command ()
  ; method_entry ~sdk_id:"method:-[MTLCommandBuffer popDebugGroup]"
      ~owner:"MTLCommandBuffer" ~selector:"popDebugGroup"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"instance () -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 10 13) ~arguments:[] ~result:None
      ~semantics:Command ()
  ; method_entry
      ~sdk_id:"method:-[MTLCommandBuffer waitUntilScheduled]"
      ~owner:"MTLCommandBuffer" ~selector:"waitUntilScheduled"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"instance () -> void"
      ~attributes:[ "SwiftAttrAttr" ]
      ~macos_introduced:(version 10 11) ~arguments:[] ~result:None
      ~semantics:Blocking ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLComputeCommandEncoder memoryBarrierWithScope:]"
      ~owner:"MTLComputeCommandEncoder" ~selector:"memoryBarrierWithScope:"
      ~header:"Metal/MTLComputeCommandEncoder.h"
      ~signature:"instance (MTLBarrierScope) -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 10 14) ~arguments:[ mtl_barrier_scope ]
      ~result:None ~semantics:Command ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLComputeCommandEncoder setBufferOffset:atIndex:]"
      ~owner:"MTLComputeCommandEncoder" ~selector:"setBufferOffset:atIndex:"
      ~header:"Metal/MTLComputeCommandEncoder.h"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 10 11) ~arguments:[ nsuint; nsuint ]
      ~result:None ~semantics:Command ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLComputeCommandEncoder setBufferOffset:attributeStride:atIndex:]"
      ~owner:"MTLComputeCommandEncoder"
      ~selector:"setBufferOffset:attributeStride:atIndex:"
      ~header:"Metal/MTLComputeCommandEncoder.h"
      ~signature:"instance (NSUInteger, NSUInteger, NSUInteger) -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 14 0)
      ~arguments:[ nsuint; nsuint; nsuint ] ~result:None ~semantics:Command
      ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLComputeCommandEncoder setImageblockWidth:height:]"
      ~owner:"MTLComputeCommandEncoder"
      ~selector:"setImageblockWidth:height:"
      ~header:"Metal/MTLComputeCommandEncoder.h"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 11 0) ~arguments:[ nsuint; nsuint ]
      ~result:None ~semantics:Command ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLComputeCommandEncoder setThreadgroupMemoryLength:atIndex:]"
      ~owner:"MTLComputeCommandEncoder"
      ~selector:"setThreadgroupMemoryLength:atIndex:"
      ~header:"Metal/MTLComputeCommandEncoder.h"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~macos_introduced:(version 10 11) ~arguments:[ nsuint; nsuint ]
      ~result:None ~semantics:Command ()
  ; method_entry ~sdk_id:"method:-[MTLDevice queryTimestampFrequency]"
      ~owner:"MTLDevice" ~selector:"queryTimestampFrequency"
      ~header:"Metal/MTLDevice.h" ~signature:"instance () -> uint64_t"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 26 0) ~arguments:[] ~result:(Some uint64)
      ~semantics:Query ()
  ; method_entry
      ~sdk_id:"method:-[MTLDevice sizeOfCounterHeapEntry:]"
      ~owner:"MTLDevice" ~selector:"sizeOfCounterHeapEntry:"
      ~header:"Metal/MTLDevice.h"
      ~signature:"instance (MTL4CounterHeapType) -> NSUInteger"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 26 0)
      ~arguments:[ mtl4_counter_heap_type ] ~result:(Some nsuint)
      ~semantics:Query ()
  ; method_entry ~sdk_id:"method:-[MTLDevice supportsCounterSampling:]"
      ~owner:"MTLDevice" ~selector:"supportsCounterSampling:"
      ~header:"Metal/MTLDevice.h"
      ~signature:"instance (MTLCounterSamplingPoint) -> BOOL"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 11 0)
      ~arguments:[ mtl_counter_sampling_point ] ~result:(Some bool)
      ~semantics:Query ()
  ; method_entry
      ~sdk_id:
        "method:-[MTLDevice supportsRasterizationRateMapWithLayerCount:]"
      ~owner:"MTLDevice"
      ~selector:"supportsRasterizationRateMapWithLayerCount:"
      ~header:"Metal/MTLDevice.h"
      ~signature:"instance (NSUInteger) -> BOOL"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version ~patch:4 10 15) ~arguments:[ nsuint ]
      ~result:(Some bool) ~semantics:Query ()
  ; method_entry
      ~sdk_id:"method:-[MTLResource setOwnerWithIdentity:]"
      ~owner:"MTLResource" ~selector:"setOwnerWithIdentity:"
      ~header:"Metal/MTLResource.h"
      ~signature:"instance (task_id_token_t) -> kern_return_t"
      ~attributes:[ "AvailabilityAttr" ]
      ~macos_introduced:(version 14 4) ~arguments:[ mach_port ]
      ~result:(Some kern_return) ~semantics:Process_identity ()
  ]

let inventory_ids = List.concat_map method_inventory_ids entries

let expected_owner_count = 8
let expected_method_count = 18
let expected_declaration_count = 18
let expected_query_count = 5
let expected_command_count = 11
let expected_blocking_count = 1
let expected_process_identity_count = 1

let fail format = Printf.ksprintf invalid_arg format

let reject_duplicates description values =
  let rec loop = function
    | left :: right :: _ when String.equal left right ->
        fail "Duplicate Metal direct-method %s: %s" description left
    | _ :: rest -> loop rest
    | [] -> ()
  in
  loop (List.sort String.compare values)

let selector_arity selector =
  String.fold_left
    (fun count character -> if Char.equal character ':' then count + 1 else count)
    0 selector

let signature_of_entry (entry : method_entry) =
  let arguments =
    entry.arguments |> List.map scalar_objc_type |> String.concat ", "
  in
  let result =
    match entry.result with
    | None -> "void"
    | Some result -> scalar_objc_type result
  in
  "instance (" ^ arguments ^ ") -> " ^ result

let unique values =
  values |> List.sort_uniq String.compare |> List.length

let count_semantics semantics =
  entries
  |> List.fold_left
       (fun count (entry : method_entry) ->
         if entry.semantics = semantics then count + 1 else count)
       0

let validate_entry (entry : method_entry) =
  let expected_sdk_id =
    "method:-[" ^ entry.owner ^ " " ^ entry.selector ^ "]"
  in
  if not (String.equal entry.sdk_id expected_sdk_id) then
    fail "Metal direct-method SDK identifier drift: %s" entry.sdk_id;
  if selector_arity entry.selector <> List.length entry.arguments then
    fail "Metal direct-method selector arity drift: %s" entry.sdk_id;
  if not (String.equal entry.signature (signature_of_entry entry)) then
    fail "Metal direct-method signature drift: %s" entry.sdk_id;
  if
    entry.header = "" || entry.ocaml_name = "" || entry.c_symbol = ""
    || entry.macos_introduced.major <= 0 || entry.macos_introduced.minor < 0
    || entry.macos_introduced.patch < 0
  then fail "Incomplete Metal direct-method entry: %s" entry.sdk_id;
  match entry.semantics, entry.result with
  | Query, Some _ -> ()
  | Command, None -> ()
  | Blocking, None
    when String.equal entry.sdk_id
           "method:-[MTLCommandBuffer waitUntilScheduled]" ->
      ()
  | Process_identity, Some result
    when String.equal entry.sdk_id
           "method:-[MTLResource setOwnerWithIdentity:]"
         && String.equal (scalar_objc_type result) "kern_return_t" ->
      ()
  | _ -> fail "Metal direct-method semantics drift: %s" entry.sdk_id

let validate () =
  List.iter validate_entry entries;
  reject_duplicates "SDK identifier" inventory_ids;
  reject_duplicates "OCaml name"
    (List.map (fun (entry : method_entry) -> entry.ocaml_name) entries);
  reject_duplicates "C symbol"
    (List.map (fun (entry : method_entry) -> entry.c_symbol) entries);
  if unique (List.map (fun (entry : method_entry) -> entry.owner) entries)
     <> expected_owner_count
  then fail "Metal direct-method owner count drift";
  if List.length entries <> expected_method_count then
    fail "Metal direct-method method count drift";
  if List.length inventory_ids <> expected_declaration_count then
    fail "Metal direct-method declaration count drift";
  if count_semantics Query <> expected_query_count then
    fail "Metal direct-method query count drift";
  if count_semantics Command <> expected_command_count then
    fail "Metal direct-method command count drift";
  if count_semantics Blocking <> expected_blocking_count then
    fail "Metal direct-method blocking count drift";
  if count_semantics Process_identity <> expected_process_identity_count then
    fail "Metal direct-method process-identity count drift"

let () = validate ()
