#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <time.h>

CAMLprim value prismel_r10_monotonic_seconds(value unit)
{
  CAMLparam1(unit);
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) != 0)
    caml_failwith("clock_gettime(CLOCK_MONOTONIC) failed");
  CAMLreturn(caml_copy_double((double)time.tv_sec + (double)time.tv_nsec / 1e9));
}
