let () =
  let module A=Binding_resource_callable_audit in
  let constants=A.count A.Constant_or_class and scalars=A.count A.Scalar_selector
  and ownership=A.count A.Handwritten_ownership in
  if constants+scalars+ownership<>100 then failwith "callable audit drift";
  Printf.printf "resource callable audit: %d constants/classes + %d scalar wrappers + %d handwritten ownership\n"
    constants scalars ownership
