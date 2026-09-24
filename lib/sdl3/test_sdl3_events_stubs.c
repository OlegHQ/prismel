#include <caml/mlvalues.h>

#include <SDL3/SDL.h>

static char input_text[] = "\xC5\xBE" "irafa";
static char editing_text[] = "\xC4\x8D";
static char candidate_one[] = "\xC4\x8D" "aj";
static char candidate_two[] = "chai";
static const char *candidate_strings[] = { candidate_one, candidate_two };
static char drop_source[] = "event-test";
static char drop_path[] = "/tmp/\xC5\xBE" "aba.png";
static char mime_one[] = "text/plain";
static char mime_two[] = "image/png";
static const char *mime_strings[] = { mime_one, mime_two };

static bool push(SDL_Event *event)
{
  SDL_SetEventEnabled(event->type, true);
  return SDL_PushEvent(event);
}

CAMLprim value caml_sdl3_test_push_event_trace(value unit)
{
  SDL_Event event;
  bool success = true;
  (void)unit;

  SDL_zero(event);
  event.key.type = SDL_EVENT_KEY_DOWN;
  event.key.timestamp = 1;
  event.key.windowID = 7;
  event.key.which = 8;
  event.key.scancode = SDL_SCANCODE_A;
  event.key.key = SDLK_A;
  event.key.mod = SDL_KMOD_SHIFT;
  event.key.raw = 42;
  event.key.down = true;
  event.key.repeat = false;
  success = push(&event) && success;

  event.key.type = SDL_EVENT_KEY_UP;
  event.key.timestamp = 2;
  event.key.down = false;
  success = push(&event) && success;

  SDL_zero(event);
  event.text.type = SDL_EVENT_TEXT_INPUT;
  event.text.timestamp = 3;
  event.text.windowID = 7;
  event.text.text = input_text;
  success = push(&event) && success;

  SDL_zero(event);
  event.edit.type = SDL_EVENT_TEXT_EDITING;
  event.edit.timestamp = 4;
  event.edit.windowID = 7;
  event.edit.text = editing_text;
  event.edit.start = 1;
  event.edit.length = 2;
  success = push(&event) && success;

  SDL_zero(event);
  event.edit_candidates.type = SDL_EVENT_TEXT_EDITING_CANDIDATES;
  event.edit_candidates.timestamp = 5;
  event.edit_candidates.windowID = 7;
  event.edit_candidates.candidates = candidate_strings;
  event.edit_candidates.num_candidates = 2;
  event.edit_candidates.selected_candidate = 1;
  event.edit_candidates.horizontal = true;
  success = push(&event) && success;

  SDL_zero(event);
  event.motion.type = SDL_EVENT_MOUSE_MOTION;
  event.motion.timestamp = 6;
  event.motion.windowID = 7;
  event.motion.which = 9;
  event.motion.state = SDL_BUTTON_LMASK;
  event.motion.x = 10.5f;
  event.motion.y = 20.5f;
  event.motion.xrel = 3.0f;
  event.motion.yrel = -2.0f;
  success = push(&event) && success;

  event.motion.timestamp = 7;
  event.motion.x = 14.5f;
  event.motion.y = 25.5f;
  event.motion.xrel = 4.0f;
  event.motion.yrel = 5.0f;
  success = push(&event) && success;

  SDL_zero(event);
  event.button.type = SDL_EVENT_MOUSE_BUTTON_DOWN;
  event.button.timestamp = 8;
  event.button.windowID = 7;
  event.button.which = 9;
  event.button.button = SDL_BUTTON_LEFT;
  event.button.down = true;
  event.button.clicks = 2;
  event.button.x = 14.5f;
  event.button.y = 25.5f;
  success = push(&event) && success;

  SDL_zero(event);
  event.wheel.type = SDL_EVENT_MOUSE_WHEEL;
  event.wheel.timestamp = 9;
  event.wheel.windowID = 7;
  event.wheel.which = 9;
  event.wheel.x = 1.0f;
  event.wheel.y = -2.0f;
  event.wheel.direction = SDL_MOUSEWHEEL_FLIPPED;
  event.wheel.mouse_x = 14.5f;
  event.wheel.mouse_y = 25.5f;
  event.wheel.integer_x = 1;
  event.wheel.integer_y = -2;
  success = push(&event) && success;

  SDL_zero(event);
  event.window.type = SDL_EVENT_WINDOW_RESIZED;
  event.window.timestamp = 10;
  event.window.windowID = 7;
  event.window.data1 = 640;
  event.window.data2 = 480;
  success = push(&event) && success;

  event.window.type = SDL_EVENT_WINDOW_EXPOSED;
  event.window.timestamp = 11;
  success = push(&event) && success;

  event.window.type = SDL_EVENT_WINDOW_FOCUS_LOST;
  event.window.timestamp = 12;
  success = push(&event) && success;

  SDL_zero(event);
  event.display.type = SDL_EVENT_DISPLAY_MOVED;
  event.display.timestamp = 13;
  event.display.displayID = 12;
  success = push(&event) && success;

  SDL_zero(event);
  event.tfinger.type = SDL_EVENT_FINGER_CANCELED;
  event.tfinger.timestamp = 14;
  event.tfinger.touchID = 13;
  event.tfinger.fingerID = 14;
  event.tfinger.x = 0.25f;
  event.tfinger.y = 0.75f;
  event.tfinger.dx = 0.1f;
  event.tfinger.dy = -0.2f;
  event.tfinger.pressure = 0.5f;
  event.tfinger.windowID = 7;
  success = push(&event) && success;

  SDL_zero(event);
  event.pmotion.type = SDL_EVENT_PEN_MOTION;
  event.pmotion.timestamp = 15;
  event.pmotion.windowID = 7;
  event.pmotion.which = 15;
  event.pmotion.pen_state = SDL_PEN_INPUT_DOWN;
  event.pmotion.x = 100.0f;
  event.pmotion.y = 200.0f;
  success = push(&event) && success;

  SDL_zero(event);
  event.paxis.type = SDL_EVENT_PEN_AXIS;
  event.paxis.timestamp = 16;
  event.paxis.windowID = 7;
  event.paxis.which = 15;
  event.paxis.pen_state = SDL_PEN_INPUT_DOWN;
  event.paxis.x = 100.0f;
  event.paxis.y = 200.0f;
  event.paxis.axis = SDL_PEN_AXIS_PRESSURE;
  event.paxis.value = 0.75f;
  success = push(&event) && success;

  SDL_zero(event);
  event.gaxis.type = SDL_EVENT_GAMEPAD_AXIS_MOTION;
  event.gaxis.timestamp = 17;
  event.gaxis.which = 16;
  event.gaxis.axis = SDL_GAMEPAD_AXIS_LEFTX;
  event.gaxis.value = 1234;
  success = push(&event) && success;

  SDL_zero(event);
  event.gdevice.type = SDL_EVENT_GAMEPAD_ADDED;
  event.gdevice.timestamp = 18;
  event.gdevice.which = 16;
  success = push(&event) && success;

  SDL_zero(event);
  event.drop.type = SDL_EVENT_DROP_FILE;
  event.drop.timestamp = 19;
  event.drop.windowID = 7;
  event.drop.x = 30.0f;
  event.drop.y = 40.0f;
  event.drop.source = drop_source;
  event.drop.data = drop_path;
  success = push(&event) && success;

  SDL_zero(event);
  event.clipboard.type = SDL_EVENT_CLIPBOARD_UPDATE;
  event.clipboard.timestamp = 20;
  event.clipboard.owner = true;
  event.clipboard.num_mime_types = 2;
  event.clipboard.mime_types = mime_strings;
  success = push(&event) && success;

  SDL_zero(event);
  event.adevice.type = SDL_EVENT_AUDIO_DEVICE_ADDED;
  event.adevice.timestamp = 21;
  event.adevice.which = 17;
  event.adevice.recording = false;
  success = push(&event) && success;

  SDL_zero(event);
  event.sensor.type = SDL_EVENT_SENSOR_UPDATE;
  event.sensor.timestamp = 22;
  event.sensor.which = 18;
  event.sensor.data[0] = 1.0f;
  event.sensor.data[1] = 2.0f;
  event.sensor.data[2] = 3.0f;
  event.sensor.data[3] = 4.0f;
  event.sensor.data[4] = 5.0f;
  event.sensor.data[5] = 6.0f;
  event.sensor.sensor_timestamp = 220;
  success = push(&event) && success;

  SDL_zero(event);
  event.quit.type = SDL_EVENT_QUIT;
  event.quit.timestamp = 23;
  success = push(&event) && success;

  SDL_zero(event);
  event.kdevice.type = SDL_EVENT_KEYBOARD_ADDED;
  event.kdevice.timestamp = 24;
  event.kdevice.which = 19;
  success = push(&event) && success;

  SDL_zero(event);
  event.mdevice.type = SDL_EVENT_MOUSE_REMOVED;
  event.mdevice.timestamp = 25;
  event.mdevice.which = 20;
  success = push(&event) && success;

  SDL_zero(event);
  event.gbutton.type = SDL_EVENT_GAMEPAD_BUTTON_DOWN;
  event.gbutton.timestamp = 26;
  event.gbutton.which = 21;
  event.gbutton.button = SDL_GAMEPAD_BUTTON_SOUTH;
  event.gbutton.down = true;
  success = push(&event) && success;

  SDL_zero(event);
  event.gtouchpad.type = SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN;
  event.gtouchpad.timestamp = 27;
  event.gtouchpad.which = 21;
  event.gtouchpad.touchpad = 2;
  event.gtouchpad.finger = 3;
  event.gtouchpad.x = 0.25f;
  event.gtouchpad.y = 0.5f;
  event.gtouchpad.pressure = 0.75f;
  success = push(&event) && success;

  SDL_zero(event);
  event.gsensor.type = SDL_EVENT_GAMEPAD_SENSOR_UPDATE;
  event.gsensor.timestamp = 28;
  event.gsensor.which = 21;
  event.gsensor.sensor = SDL_SENSOR_ACCEL;
  event.gsensor.data[0] = 7.0f;
  event.gsensor.data[1] = 8.0f;
  event.gsensor.data[2] = 9.0f;
  event.gsensor.sensor_timestamp = 280;
  success = push(&event) && success;

  SDL_zero(event);
  event.pinch.type = SDL_EVENT_PINCH_UPDATE;
  event.pinch.timestamp = 29;
  event.pinch.scale = 1.25f;
  event.pinch.windowID = 7;
  success = push(&event) && success;

  SDL_zero(event);
  event.pproximity.type = SDL_EVENT_PEN_PROXIMITY_IN;
  event.pproximity.timestamp = 30;
  event.pproximity.windowID = 7;
  event.pproximity.which = 22;
  success = push(&event) && success;

  SDL_zero(event);
  event.ptouch.type = SDL_EVENT_PEN_DOWN;
  event.ptouch.timestamp = 31;
  event.ptouch.windowID = 7;
  event.ptouch.which = 22;
  event.ptouch.pen_state = SDL_PEN_INPUT_DOWN;
  event.ptouch.x = 11.0f;
  event.ptouch.y = 12.0f;
  event.ptouch.eraser = false;
  event.ptouch.down = true;
  success = push(&event) && success;

  SDL_zero(event);
  event.pbutton.type = SDL_EVENT_PEN_BUTTON_DOWN;
  event.pbutton.timestamp = 32;
  event.pbutton.windowID = 7;
  event.pbutton.which = 22;
  event.pbutton.pen_state = SDL_PEN_INPUT_DOWN;
  event.pbutton.x = 11.0f;
  event.pbutton.y = 12.0f;
  event.pbutton.button = 2;
  event.pbutton.down = true;
  success = push(&event) && success;

  SDL_zero(event);
  event.common.type = SDL_EVENT_USER;
  event.common.timestamp = 33;
  success = push(&event) && success;

  return Val_bool(success);
}

CAMLprim value caml_sdl3_test_mutate_event_sources(value unit)
{
  (void)unit;
  input_text[0] = 'x';
  editing_text[0] = 'x';
  candidate_one[0] = 'x';
  candidate_two[0] = 'x';
  drop_source[0] = 'x';
  drop_path[0] = 'x';
  mime_one[0] = 'x';
  mime_two[0] = 'x';
  return Val_unit;
}
