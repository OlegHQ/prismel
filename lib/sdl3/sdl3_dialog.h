/* Native file dialogs, without OCaml. SDL3 reports a dialog's outcome through
   a callback that may run on any thread, so the outcome goes into one of a
   fixed number of slots and is published with a release store; the initial
   domain takes finished slots with prismel_dialog_take. The slots are the
   bounded queue: a dialog is refused while every slot is in use, so the
   callback never has to drop or grow anything. */
#ifndef PRISMEL_SDL3_DIALOG_H
#define PRISMEL_SDL3_DIALOG_H

#include <stddef.h>
#include <stdbool.h>
#include <SDL3/SDL.h>

#define PRISMEL_DIALOG_SLOTS 8

typedef enum {
  PRISMEL_DIALOG_OPEN_FILE,
  PRISMEL_DIALOG_OPEN_FILES,
  PRISMEL_DIALOG_SAVE_FILE,
  PRISMEL_DIALOG_OPEN_FOLDER
} prismel_dialog_kind;

typedef enum {
  PRISMEL_OUTCOME_CHOSEN,
  PRISMEL_OUTCOME_CANCELLED,
  PRISMEL_OUTCOME_FAILED
} prismel_dialog_outcome_kind;

/* A finished dialog. [payload] is malloc'd: for a chosen outcome the paths
   separated by NULs (each terminated), for a failure the message; the caller
   frees it. */
typedef struct {
  int id;
  prismel_dialog_outcome_kind outcome;
  char *payload;
  size_t payload_length;
} prismel_dialog_result;

/* Claim a slot and copy [count] filters (names and patterns) and the default
   location (may be NULL) into it. Returns the slot, or NULL with the SDL
   error set; [id] receives the new dialog's id. Main thread. */
void *prismel_dialog_reserve(const char *const *names,
    const char *const *patterns, int count, const char *default_location,
    int *id);

/* Give a reserved slot back without showing anything. */
void prismel_dialog_abandon(void *slot);

/* SDL's callback: copies the outcome and publishes the slot. Any thread. */
void SDLCALL prismel_dialog_callback(
    void *slot, const char *const *filelist, int filter);

/* Reserve and show: the dialog's id, or 0 with the SDL error set. */
int prismel_dialog_show(prismel_dialog_kind kind, SDL_Window *window,
    const char *const *names, const char *const *patterns, int count,
    const char *default_location);

/* Take the oldest finished dialog, if any. Initial domain only. */
bool prismel_dialog_take(prismel_dialog_result *result);

#endif
