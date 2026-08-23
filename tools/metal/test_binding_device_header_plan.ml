let ()=
 if Binding_device_header_plan.expected_count<>119 then failwith"closure drift";
 if List.length Binding_device_header_plan.excluded_ids<>9 then failwith"overlap exclusion drift";
 if Binding_device_header_plan.expected_digest<>"8d460a76b5f5e00d2bab8b55af7a148127272bee5099f97e9fd4f383573a0d6c"
 then failwith"digest drift"
