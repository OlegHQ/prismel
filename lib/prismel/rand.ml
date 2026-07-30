type t = int64

let seed64 value = value
let seed value = Int64.of_int value

let next state =
  let open Int64 in
  let state = add state 0x9E3779B97F4A7C15L in
  let value = logxor state (shift_right_logical state 30) in
  let value = mul value 0xBF58476D1CE4E5B9L in
  let value = logxor value (shift_right_logical value 27) in
  let value = mul value 0x94D049BB133111EBL in
  logxor value (shift_right_logical value 31), state

let bits = next

let split state =
  let left, state = next state in
  let right, _ = next state in
  left, right

let float state =
  let value, state = next state in
  let mantissa = Int64.shift_right_logical value 11 in
  Int64.to_float mantissa /. 9_007_199_254_740_992., state

let range ~min ~max state =
  if max < min then invalid_arg "Rand.range: max must be >= min";
  let value, state = float state in
  min +. (value *. (max -. min)), state

let int ~bound state =
  if bound <= 0 then invalid_arg "Rand.int: bound must be positive";
  let value, state = next state in
  Int64.(unsigned_rem value (of_int bound) |> to_int), state

let int_range ~min ~max state =
  if max < min then invalid_arg "Rand.int_range: max must be >= min";
  let span = max - min + 1 in
  let value, state = int ~bound:span state in
  min + value, state

let bool state =
  let value, state = next state in
  Int64.logand value 1L = 1L, state

let chance probability state =
  let probability = max 0. (min 1. probability) in
  let value, state = float state in
  value < probability, state

let choose values state =
  match values with
  | [] -> None
  | _ ->
      let index, state = int ~bound:(List.length values) state in
      Some (List.nth values index, state)

let choose_exn values state =
  match choose values state with
  | Some result -> result
  | None -> invalid_arg "Rand.choose_exn: empty list"

let shuffle values state =
  let values = Array.of_list values in
  let state = ref state in
  for index = Array.length values - 1 downto 1 do
    let other, next_state = int ~bound:(index + 1) !state in
    state := next_state;
    let value = values.(index) in
    values.(index) <- values.(other);
    values.(other) <- value
  done;
  Array.to_list values, !state

let weighted values state =
  let positive =
    List.filter (fun (_, weight) -> Float.is_finite weight && weight > 0.) values
  in
  let total =
    List.fold_left (fun sum (_, weight) -> sum +. weight) 0. positive
  in
  if total = 0. then None
  else
    let target, state = range ~min:0. ~max:total state in
    let rec pick remaining = function
      | [] -> None
      | [value, _] -> Some (value, state)
      | (value, weight) :: rest ->
          if remaining < weight then Some (value, state)
          else pick (remaining -. weight) rest
    in
    pick target positive
