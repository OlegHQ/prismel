module Make(T:sig type handle end)=struct type handle=T.handle
 external capture_set_destination:handle->int->(unit,string)result="caml_prismel_metal_capture_set_destination"
 external capture_is_capturing:handle->(bool,string)result="caml_prismel_metal_capture_is_capturing"
 external function_log_type:handle->(int64,string)result="caml_prismel_metal_function_log_type"
 external function_log_column:handle->(int64,string)result="caml_prismel_metal_function_log_column"
 external function_log_line:handle->(int64,string)result="caml_prismel_metal_function_log_line"
 external shared_event_value:handle->(int64,string)result="caml_prismel_metal_shared_event_value"
 external shared_event_set_value:handle->int64->(unit,string)result="caml_prismel_metal_shared_event_set_value"
end
