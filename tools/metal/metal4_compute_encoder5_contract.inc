/* MTL4ComputeEncoder5 reconciliation contract. The callable bridge already
   exposes these five selectors through metal4_compute_acceleration (build and
   two refit variants), metal4_compute_write_compacted, and copy_tensor. This
   shard records the validation common to that exact residual set without
   duplicating ABI symbols. */
API_AVAILABLE(macos(26.0))
static bool prismel_metal4_compute5_range(id<MTLBuffer> buffer,
                                          int64_t offset, int64_t length,
                                          uint64_t registry_id) {
  return buffer != nil && offset >= 0 && length > 0
    && (uint64_t)offset <= buffer.length
    && (uint64_t)length <= buffer.length - (uint64_t)offset
    && buffer.device.registryID == registry_id;
}

static bool prismel_metal4_compute5_tensor_slice(
    const std::vector<int64_t> &shape, const std::vector<int64_t> &origin,
    const std::vector<int64_t> &dimensions) {
  if (shape.empty() || shape.size() != origin.size()
      || shape.size() != dimensions.size()) return false;
  for (size_t index = 0; index < shape.size(); ++index)
    if (shape[index] <= 0 || origin[index] < 0 || dimensions[index] <= 0
        || origin[index] > shape[index]
        || dimensions[index] > shape[index] - origin[index]) return false;
  return true;
}
