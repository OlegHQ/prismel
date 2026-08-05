#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdlib.h>

CAMLprim value prismel_runtime_unsetenv(value name)
{
  CAMLparam1(name);
#ifdef _WIN32
  if (_putenv_s(String_val(name), "") != 0)
#else
  if (unsetenv(String_val(name)) != 0)
#endif
    caml_failwith("Runtime could not restore the process environment");
  CAMLreturn(Val_unit);
}
