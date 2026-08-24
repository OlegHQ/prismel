type state = Idle | In_use
type t = { mutable label : string option; mutable state : state; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTL4MachineLearningPipelineState label]"
  ; "property:MTL4MachineLearningPipelineState:label" ]

let valid_utf8 value =
  let length = String.length value in
  let continuation index = index < length && Char.code value.[index] land 0xc0 = 0x80 in
  let rec loop index =
    if index = length then true else
    let byte = Char.code value.[index] in
    if byte < 0x80 then loop (index + 1)
    else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then loop (index + 2)
    else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1) && continuation (index + 2) then loop (index + 3)
    else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3) then loop (index + 4)
    else false
  in loop 0

let snapshot = function
  | Some value when not (valid_utf8 value) -> Error "invalid UTF-8 MTL4 ML pipeline label"
  | value -> Ok (Option.map (fun text -> String.sub text 0 (String.length text)) value)

let create ~available ~native_label =
  if not available then Error "MTL4 machine-learning pipelines require macOS 26"
  else Result.map (fun label -> { label; state = Idle; destroyed = false }) (snapshot native_label)

let label pipeline =
  if pipeline.destroyed then Error "destroyed MTL4 ML pipeline state" else Ok pipeline.label

(* The SDK property is readonly. This models a fresh native getter snapshot,
   not a public label setter. *)
let refresh_label pipeline ~native_label =
  if pipeline.destroyed then Error "destroyed MTL4 ML pipeline state"
  else Result.map (fun label -> pipeline.label <- label) (snapshot native_label)

let begin_use pipeline =
  if pipeline.destroyed then Error "destroyed MTL4 ML pipeline state"
  else if pipeline.state = In_use then Error "MTL4 ML pipeline is already in use"
  else begin pipeline.state <- In_use; Ok () end

let end_use pipeline =
  if pipeline.destroyed then Error "destroyed MTL4 ML pipeline state"
  else if pipeline.state = Idle then Error "MTL4 ML pipeline is not in use"
  else begin pipeline.state <- Idle; Ok () end

let destroy pipeline =
  if pipeline.destroyed then Ok ()
  else if pipeline.state = In_use then Error "MTL4 ML pipeline must remain alive while in use"
  else begin pipeline.destroyed <- true; pipeline.label <- None; Ok () end

let validate_handoff () =
  if List.length callable_ids <> 2 || List.length (List.sort_uniq String.compare callable_ids) <> 2 then
    invalid_arg "MTL4MLPipeline callable2 drift"
