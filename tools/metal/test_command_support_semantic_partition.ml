let ()=let module P=Binding_command_support_semantic_partition in
 if P.count `Mechanical_value+P.count `Handwritten_lifecycle<>121 then failwith"total";
 List.iter(fun id->if not(String.starts_with~prefix:"method:-[MTLBlitCommandEncoder "id)then failwith"unexpected false mechanical")P.blit_false_mechanical;
 Printf.printf"command-support121 corrected: %d mechanical + %d handwritten; %d blit misclassifications caught\n"(P.count `Mechanical_value)(P.count `Handwritten_lifecycle)(List.length P.blit_false_mechanical)
