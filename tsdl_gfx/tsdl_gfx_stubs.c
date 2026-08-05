#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/misc.h>
#if defined(__has_include)
#  if __has_include(<SDL2/SDL.h>)
#    include <SDL2/SDL.h>
#    include <SDL2/SDL2_gfxPrimitives.h>
#  else
#    include <SDL.h>
#    include <SDL2_gfxPrimitives.h>
#  endif
#else
#  include <SDL.h>
#  include <SDL2_gfxPrimitives.h>
#endif

static SDL_Renderer *renderer_of_value(value renderer)
{
  return (SDL_Renderer *)(intnat)Nativeint_val(renderer);
}

static int arg(value args, mlsize_t index)
{
  return Int_val(Field(args, index));
}

CAMLprim value caml_tsdl_gfx_scalar(value operation, value renderer, value args)
{
  SDL_Renderer *r = renderer_of_value(renderer);
  int result;
  switch (Int_val(operation)) {
  case 0:
    result = pixelRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                       arg(args, 3), arg(args, 4), arg(args, 5));
    break;
  case 1:
    result = hlineRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                       arg(args, 3), arg(args, 4), arg(args, 5), arg(args, 6));
    break;
  case 2:
    result = vlineRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                       arg(args, 3), arg(args, 4), arg(args, 5), arg(args, 6));
    break;
  case 3:
    result = rectangleRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                           arg(args, 3), arg(args, 4), arg(args, 5),
                           arg(args, 6), arg(args, 7));
    break;
  case 4:
    result = roundedRectangleRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                                  arg(args, 3), arg(args, 4), arg(args, 5),
                                  arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 5:
    result = boxRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                     arg(args, 3), arg(args, 4), arg(args, 5),
                     arg(args, 6), arg(args, 7));
    break;
  case 6:
    result = roundedBoxRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                            arg(args, 3), arg(args, 4), arg(args, 5),
                            arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 7:
    result = lineRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                      arg(args, 3), arg(args, 4), arg(args, 5),
                      arg(args, 6), arg(args, 7));
    break;
  case 8:
    result = aalineRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                        arg(args, 3), arg(args, 4), arg(args, 5),
                        arg(args, 6), arg(args, 7));
    break;
  case 9:
    result = thickLineRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                           arg(args, 3), arg(args, 4), arg(args, 5),
                           arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 10:
    result = circleRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                        arg(args, 3), arg(args, 4), arg(args, 5), arg(args, 6));
    break;
  case 11:
    result = aacircleRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                          arg(args, 3), arg(args, 4), arg(args, 5), arg(args, 6));
    break;
  case 12:
    result = filledCircleRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                              arg(args, 3), arg(args, 4), arg(args, 5),
                              arg(args, 6));
    break;
  case 13:
    result = ellipseRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                         arg(args, 3), arg(args, 4), arg(args, 5),
                         arg(args, 6), arg(args, 7));
    break;
  case 14:
    result = aaellipseRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                           arg(args, 3), arg(args, 4), arg(args, 5),
                           arg(args, 6), arg(args, 7));
    break;
  case 15:
    result = filledEllipseRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                               arg(args, 3), arg(args, 4), arg(args, 5),
                               arg(args, 6), arg(args, 7));
    break;
  case 16:
    result = arcRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                     arg(args, 3), arg(args, 4), arg(args, 5),
                     arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 17:
    result = pieRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                     arg(args, 3), arg(args, 4), arg(args, 5),
                     arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 18:
    result = filledPieRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                           arg(args, 3), arg(args, 4), arg(args, 5),
                           arg(args, 6), arg(args, 7), arg(args, 8));
    break;
  case 19:
    result = trigonRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                        arg(args, 3), arg(args, 4), arg(args, 5),
                        arg(args, 6), arg(args, 7), arg(args, 8), arg(args, 9));
    break;
  case 20:
    result = aatrigonRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                          arg(args, 3), arg(args, 4), arg(args, 5),
                          arg(args, 6), arg(args, 7), arg(args, 8), arg(args, 9));
    break;
  case 21:
    result = filledTrigonRGBA(r, arg(args, 0), arg(args, 1), arg(args, 2),
                              arg(args, 3), arg(args, 4), arg(args, 5),
                              arg(args, 6), arg(args, 7), arg(args, 8),
                              arg(args, 9));
    break;
  case 22:
    result = characterRGBA(r, arg(args, 0), arg(args, 1), (char)arg(args, 2),
                           arg(args, 3), arg(args, 4), arg(args, 5), arg(args, 6));
    break;
  default:
    result = -1;
    break;
  }
  return Val_int(result);
}

CAMLprim value caml_tsdl_gfx_polygon(value operation, value renderer,
                                     value points, value args)
{
  CAMLparam4(operation, renderer, points, args);
  mlsize_t count = 0;
  value cursor;
  for (cursor = points; cursor != Val_emptylist; cursor = Field(cursor, 1)) {
    count++;
  }
  Sint16 *xs = caml_stat_alloc(sizeof(Sint16) * (count == 0 ? 1 : count));
  Sint16 *ys = caml_stat_alloc(sizeof(Sint16) * (count == 0 ? 1 : count));
  cursor = points;
  for (mlsize_t index = 0; index < count; index++) {
    value point = Field(cursor, 0);
    xs[index] = (Sint16)Int_val(Field(point, 0));
    ys[index] = (Sint16)Int_val(Field(point, 1));
    cursor = Field(cursor, 1);
  }
  SDL_Renderer *r = renderer_of_value(renderer);
  int red = arg(args, 1), green = arg(args, 2);
  int blue = arg(args, 3), alpha = arg(args, 4);
  int result;
  switch (Int_val(operation)) {
  case 0:
    result = polygonRGBA(r, xs, ys, (int)count, red, green, blue, alpha);
    break;
  case 1:
    result = aapolygonRGBA(r, xs, ys, (int)count, red, green, blue, alpha);
    break;
  case 2:
    result = filledPolygonRGBA(r, xs, ys, (int)count,
                               red, green, blue, alpha);
    break;
  case 3:
    result = bezierRGBA(r, xs, ys, (int)count, arg(args, 0),
                        red, green, blue, alpha);
    break;
  default:
    result = 0;
    for (mlsize_t index = 1; index < count; index++) {
      if (aalineRGBA(r, xs[index - 1], ys[index - 1], xs[index], ys[index],
                     red, green, blue, alpha) != 0) {
        result = -1;
        break;
      }
    }
    break;
  }
  caml_stat_free(xs);
  caml_stat_free(ys);
  CAMLreturn(Val_int(result));
}

CAMLprim value caml_tsdl_gfx_string(value renderer, value string, value args)
{
  return Val_int(stringRGBA(renderer_of_value(renderer),
                            arg(args, 0), arg(args, 1), String_val(string),
                            arg(args, 2), arg(args, 3), arg(args, 4),
                            arg(args, 5)));
}

CAMLprim value caml_tsdl_gfx_font_rotation(value rotation)
{
  gfxPrimitivesSetFontRotation((Uint32)Int_val(rotation));
  return Val_unit;
}
