#ifndef RAYS_NATIVE_LAYER_TOKEN_H
#define RAYS_NATIVE_LAYER_TOKEN_H
#include <caml/mlvalues.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
value rays_native_layer_token_create(void *layer, uint64_t owner, uint64_t generation);
void rays_native_layer_token_invalidate(value token);
void *rays_native_layer_token_borrow(value token, uint64_t owner, uint64_t generation);
#ifdef __cplusplus
}
#endif
#endif
