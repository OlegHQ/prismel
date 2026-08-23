let ()=
 if Binding_device_header_plan.expected_count<>94 then failwith"closure drift";
 if List.length Binding_device_header_plan.excluded_ids<>9 then failwith"overlap exclusion drift";
 if Binding_device_header_plan.expected_digest<>"81285a3cf295bf0394f127daafbb8e75972f0cfe70c55e42a5937afc5a2eec71"
 then failwith"digest drift"
