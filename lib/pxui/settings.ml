type value =
  | Bool of bool
  | Float of float
  | Int of int
  | Text of string
  | Choice of string
  | Pair of float * float

type t = (string * value) list

let hex_of_string text =
  let digits = "0123456789abcdef" in
  String.init (String.length text * 2) (fun index ->
    let byte = Char.code text.[index / 2] in
    digits.[if index mod 2 = 0 then byte lsr 4 else byte land 0xf])

let string_of_hex encoded =
  let nibble = function
    | '0' .. '9' as c -> Ok (Char.code c - Char.code '0')
    | 'a' .. 'f' as c -> Ok (10 + Char.code c - Char.code 'a')
    | 'A' .. 'F' as c -> Ok (10 + Char.code c - Char.code 'A')
    | c -> Error (Printf.sprintf "invalid hexadecimal digit %C" c) in
  if String.length encoded mod 2 <> 0 then Error "odd hexadecimal value"
  else
    let decoded = Bytes.create (String.length encoded / 2) in
    let rec loop index =
      if index = Bytes.length decoded then Ok (Bytes.unsafe_to_string decoded)
      else match nibble encoded.[index * 2], nibble encoded.[(index * 2) + 1] with
        | Ok high, Ok low ->
            Bytes.set decoded index (Char.chr ((high lsl 4) lor low));
            loop (index + 1)
        | Error message, _ | _, Error message -> Error message in
    loop 0

let encode settings =
  let line (name, value) =
    let name = hex_of_string name in
    match value with
    | Bool value -> Printf.sprintf "B\t%s\t%d" name (if value then 1 else 0)
    | Float value -> Printf.sprintf "F\t%s\t%.17g" name value
    | Int value -> Printf.sprintf "I\t%s\t%d" name value
    | Text value -> Printf.sprintf "S\t%s\t%s" name (hex_of_string value)
    | Choice value -> Printf.sprintf "C\t%s\t%s" name (hex_of_string value)
    | Pair (x, y) -> Printf.sprintf "P\t%s\t%.17g,%.17g" name x y in
  "PXUI1\n" ^ String.concat "\n" (List.map line settings) ^ "\n"

let decode encoded =
  match String.split_on_char '\n' encoded with
  | "PXUI1" :: entries ->
      let rec parse line_number values = function
        | [] -> Ok (List.rev values)
        | "" :: rest -> parse (line_number + 1) values rest
        | entry :: rest ->
            let error message =
              Error (Printf.sprintf "PXUI settings line %d: %s" line_number message) in
            (match String.split_on_char '\t' entry with
             | [kind; encoded_name; raw] ->
                 (match string_of_hex encoded_name with
                  | Error message -> error message
                  | Ok name ->
                      let value = match kind with
                        | ("A" | "B") when raw = "0" -> Ok (Bool false)
                        | ("A" | "B") when raw = "1" -> Ok (Bool true)
                        | "F" ->
                            (match float_of_string_opt raw with
                             | Some value when Float.is_finite value -> Ok (Float value)
                             | Some _ -> error "non-finite float"
                             | None -> error "invalid float")
                        | "I" ->
                            (match int_of_string_opt raw with
                             | Some value -> Ok (Int value)
                             | None -> error "invalid integer")
                        | "S" -> Result.map (fun s -> Text s) (string_of_hex raw)
                        | "C" -> Result.map (fun s -> Choice s) (string_of_hex raw)
                        | "R" | "P" ->
                            (match String.split_on_char ',' raw with
                             | [first; second] ->
                                 (match float_of_string_opt first,
                                    float_of_string_opt second with
                                  | Some x, Some y -> Ok (Pair (x, y))
                                  | _ -> error "invalid float pair")
                             | _ -> error "invalid float pair")
                        | _ -> error "unknown value kind" in
                      Result.bind value (fun value ->
                        parse (line_number + 1)
                          ((name, value) :: List.remove_assoc name values) rest))
             | _ -> error "expected three tab-separated fields") in
      parse 2 [] entries
  | _ -> Error "PXUI settings: unsupported or missing PXUI1 header"

let save filename settings =
  try
    let channel = open_out_bin filename in
    Fun.protect ~finally:(fun () -> close_out channel)
      (fun () -> output_string channel (encode settings));
    Ok ()
  with Sys_error message -> Error message

let load filename =
  try
    let channel = open_in_bin filename in
    let encoded = Fun.protect ~finally:(fun () -> close_in channel)
        (fun () -> really_input_string channel (in_channel_length channel)) in
    decode encoded
  with Sys_error message -> Error message

let find settings name extract = Option.bind (List.assoc_opt name settings) extract
let bool settings name = find settings name (function Bool v -> Some v | _ -> None)
let float settings name = find settings name (function Float v -> Some v | _ -> None)
let int settings name = find settings name (function Int v -> Some v | _ -> None)
let text settings name = find settings name (function Text v -> Some v | _ -> None)
let choice settings name = find settings name (function Choice v -> Some v | _ -> None)
let pair settings name = find settings name (function Pair (x, y) -> Some (x, y) | _ -> None)
