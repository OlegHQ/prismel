open Binding_acceleration_ownership_plan

type ('buffer, 'element, 'acceleration) value =
  | Buffer of 'buffer option
  | Buffer_range of { buffer : 'buffer; offset : int64; length : int64 }
  | String of string option
  | Elements of 'element list
  | Accelerations of 'acceleration list
  | Resource_id of int64

let same_device expected actual =
  if expected = actual then Ok () else Error "Metal acceleration descriptor mixes devices"

let validate ~expected_device ~buffer_device ~buffer_length ~element_device
    ~acceleration_device = function
  | Buffer None | String _ | Resource_id _ -> Ok ()
  | Buffer (Some buffer) -> same_device expected_device (buffer_device buffer)
  | Buffer_range { buffer; offset; length } ->
      (match same_device expected_device (buffer_device buffer) with
      | Error _ as error -> error
      | Ok () ->
          if offset < 0L || length < 0L then Error "Metal acceleration buffer range is negative"
          else if offset > Int64.sub Int64.max_int length then Error "Metal acceleration buffer range overflows"
          else if Int64.add offset length > buffer_length buffer then Error "Metal acceleration buffer range exceeds its buffer"
          else Ok ())
  | Elements elements ->
      List.fold_left
        (fun result element ->
          match result with Error _ -> result | Ok () -> same_device expected_device (element_device element))
        (Ok ()) elements
  | Accelerations values ->
      List.fold_left
        (fun result acceleration ->
          match result with Error _ -> result | Ok () -> same_device expected_device (acceleration_device acceleration))
        (Ok ()) values

let copy_retained_array ~retain ~release values =
  let retained = ref [] in
  let rec loop = function
    | [] -> Ok (Array.of_list (List.rev !retained))
    | value :: rest ->
        (match retain value with
        | Ok owned -> retained := owned :: !retained; loop rest
        | Error _ as error -> List.iter release !retained; retained := []; error
        | exception exn ->
            List.iter release !retained;
            retained := [];
            raise exn)
  in
  loop values

let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c ->
    if index > 0 && c >= 'A' && c <= 'Z' then Buffer.add_char output '_';
    Buffer.add_char output (Char.lowercase_ascii c)) value;
  Buffer.contents output

let receiver_type owner =
  if owner = "MTLAccelerationStructure" then "id<MTLAccelerationStructure>"
  else owner ^ " *"

let getter_type = function
  | Borrowed_buffer -> "id<MTLBuffer>"
  | Copied_string -> "NSString *"
  | Copied_retained_array -> "NSArray *"
  | Buffer_range -> "MTL4BufferRange"
  | Resource_id -> "MTLResourceID"

let render_native_materializers selection =
  let output = Buffer.create 30000 in
  List.iter
    (fun value ->
      let owner = Option.get value.property.owner in
      let receiver = receiver_type owner in
      let availability = Option.value ~default:"10.11" value.property.macos_introduced in
      let base = snake owner ^ "_" ^ snake value.property.name in
      Printf.bprintf output
        "/* %s */ API_AVAILABLE(macos(%s)) static __attribute__((unused)) %s prismel_as_ownership_get_%s(%s descriptor) { return descriptor.%s; }\n"
        value.property.id availability (getter_type value.ownership) base receiver
        value.property.name;
      (match value.ownership with
      | Copied_string ->
          Printf.bprintf output
            "API_AVAILABLE(macos(%s)) static __attribute__((unused)) NSString *prismel_as_ownership_copy_%s(%s descriptor) { return [descriptor.%s copy]; }\n"
            availability base receiver value.property.name
      | Copied_retained_array ->
          Printf.bprintf output
            "API_AVAILABLE(macos(%s)) static __attribute__((unused)) NSArray *prismel_as_ownership_copy_%s(%s descriptor) { return [descriptor.%s copy]; }\n"
            availability base receiver value.property.name
      | _ -> ());
      Option.iter
        (fun _ ->
          Printf.bprintf output
            "API_AVAILABLE(macos(%s)) static __attribute__((unused)) void prismel_as_ownership_set_%s(%s descriptor, %s input) { descriptor.%s = input; }\n"
            availability base receiver (getter_type value.ownership)
            value.property.name)
        value.setter)
    selection.properties;
  Buffer.contents output
