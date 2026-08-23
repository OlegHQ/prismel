type resource = Fence | Depth_attachment | Stencil_attachment | Heap
              | Buffer_resource | Texture_resource | Indirect_command_buffer
              | Indirect_range_buffer
type check = Encoder_open | Same_device | Range | Capability | Attachment_present
           | Retain_resource | Pipeline_supports_icb
type entry = { id:string; safe_name:string; resources:resource list;
               checks:check list; deprecated_alias:bool }
val entries : entry list
val expected_count : int
