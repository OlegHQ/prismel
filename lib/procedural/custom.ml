let resolved_label operation = function
  | Some label when String.trim label <> "" -> label
  | Some _ | None -> operation

let node ?label ~operation ~schema ~values inputs operator =
  if String.trim operation = "" then
    invalid_arg "Custom.node: operation must not be blank";
  let rec build ~label ~inputs values =
    operator ~label ~inputs ~parameters:values
    |> Node.parameterize ~schema ~values ~rebuild:build
  in
  build ~label:(resolved_label operation label) ~inputs values

let create ?label ?(version = 1) ?(cook_mode = Node.Generic)
    ?(dependencies = Context.Dependencies.static) ~operation ~schema ~values
    inputs cook =
  node ?label ~operation ~schema ~values inputs
    (fun ~label ~inputs ~parameters ->
      Sop.custom ~label ~version ~parameters:(Parameter.key schema parameters)
        ~cook_mode ~dependencies ~operation inputs
        (fun ~context geometries -> cook ~parameters ~context geometries))

let map ?label ?version ?(cook_mode = Node.Duplicate_input 0) ?dependencies
    ~operation ~schema ~values input cook =
  create ?label ?version ~cook_mode ?dependencies ~operation ~schema ~values
    [input] (fun ~parameters ~context inputs ->
      if Array.length inputs <> 1 then Error
          (operation ^ ": custom map expected exactly one input")
      else cook ~parameters ~context inputs.(0))
