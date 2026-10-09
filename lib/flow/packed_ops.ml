type binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max | Lt | Le | Gt | Ge | Eq | And | Or
type unary = Sin | Cos | Sqrt | Abs | Not

let register_limit = 64
let supported_noise_octaves n = n >= 1 && n <= 32
let finite_float32 x = Float.is_finite (Int32.float_of_bits (Int32.bits_of_float x))

let binaries = ["+", Add; "-", Sub; "*", Mul; "/", Div; "mod", Mod; "pow", Pow;
  "min", Min; "max", Max; "<", Lt; "<=", Le; ">", Gt; ">=", Ge; "=", Eq;
  "and", And; "or", Or]
let unaries = ["sin", Sin; "cos", Cos; "sqrt", Sqrt; "abs", Abs; "not", Not]
let noise_names = ["noise3"]
let derived_names = ["length"]
let binary name = List.assoc_opt name binaries
let unary name = List.assoc_opt name unaries
let names = List.map fst binaries @ List.map fst unaries @ noise_names @ derived_names
let supports name = List.mem name names
