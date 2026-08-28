#include <caml/mlvalues.h>
#include <stdlib.h>

CAMLprim value caml_runtime_next_headless_unsetenv(value name)
{
  unsetenv(String_val(name));
  return Val_unit;
}
