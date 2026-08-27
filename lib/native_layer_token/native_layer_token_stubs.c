#include "native_layer_token.h"
#include <CoreFoundation/CoreFoundation.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/memory.h>

typedef struct { void *layer; uint64_t owner; uint64_t generation; int alive; } token;
static token *get(value v){return(token*)Data_custom_val(v);}
static void finalize(value v){token*t=get(v);if(t->layer!=NULL)CFRelease(t->layer);t->layer=NULL;t->alive=0;}
static struct custom_operations ops={"prismel.native-layer-token",finalize,custom_compare_default,custom_hash_default,custom_serialize_default,custom_deserialize_default,custom_compare_ext_default,custom_fixed_length_default};
value prismel_native_layer_token_create(void *layer,uint64_t owner,uint64_t generation){CAMLparam0();CAMLlocal1(v);v=caml_alloc_custom(&ops,sizeof(token),0,1);token*t=get(v);t->layer=layer;t->owner=owner;t->generation=generation;t->alive=layer!=NULL;if(layer!=NULL)CFRetain(layer);CAMLreturn(v);}
void prismel_native_layer_token_invalidate(value v){token*t=get(v);if(t->layer!=NULL)CFRelease(t->layer);t->layer=NULL;t->alive=0;}
void *prismel_native_layer_token_borrow(value v,uint64_t owner,uint64_t generation){token*t=get(v);return t->alive&&t->owner==owner&&t->generation==generation?t->layer:NULL;}
CAMLprim value caml_prismel_native_layer_token_owner(value v){return caml_copy_int64(get(v)->owner);}
CAMLprim value caml_prismel_native_layer_token_generation(value v){return caml_copy_int64(get(v)->generation);}
CAMLprim value caml_prismel_native_layer_token_alive(value v){return Val_bool(get(v)->alive);}
