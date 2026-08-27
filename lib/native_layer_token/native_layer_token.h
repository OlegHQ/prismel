#ifndef PRISMEL_NATIVE_LAYER_TOKEN_H
#define PRISMEL_NATIVE_LAYER_TOKEN_H
#include <caml/mlvalues.h>
#include <stdint.h>
value prismel_native_layer_token_create(void *layer, uint64_t owner, uint64_t generation);
void prismel_native_layer_token_invalidate(value token);
void *prismel_native_layer_token_borrow(value token, uint64_t owner, uint64_t generation);
#endif
