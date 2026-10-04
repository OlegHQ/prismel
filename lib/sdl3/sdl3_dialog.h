/* Native file dialogs, without OCaml. SDL3 reports a dialog's outcome through
   a callback that may run on any thread, so the outcome goes into one of a
   fixed number of slots and is published with a release store; the initial
   domain takes finished slots with rays_dialog_take. The slots are the
   bounded queue: a dialog is refused while every slot is in use, so the
   callback never has to drop or grow anything. */
#ifndef RAYS_SDL3_DIALOG_H
#define RAYS_SDL3_DIALOG_H

#include <stddef.h>
#include <stdbool.h>
#include <SDL3/SDL.h>

#define RAYS_DIALOG_SLOTS 8

typedef enum {
  RAYS_DIALOG_OPEN_FILE,
  RAYS_DIALOG_OPEN_FILES,
  RAYS_DIALOG_SAVE_FILE,
  RAYS_DIALOG_OPEN_FOLDER
} rays_dialog_kind;

typedef enum {
  RAYS_OUTCOME_CHOSEN,
  RAYS_OUTCOME_CANCELLED,
  RAYS_OUTCOME_FAILED
} rays_dialog_outcome_kind;

/* A finished dialog. [payload] is malloc'd: for a chosen outcome the paths
   separated by NULs (each terminated), for a failure the message; the caller
   frees it. */
typedef struct {
  int id;
  rays_dialog_outcome_kind outcome;
  char *payload;
  size_t payload_length;
} rays_dialog_result;

/* Claim a slot and copy [count] filters (names and patterns) and the default
   location (may be NULL) into it. Returns the slot, or NULL with the SDL
   error set; [id] receives the new dialog's id. Main thread. */
void *rays_dialog_reserve(const char *const *names,
    const char *const *patterns, int count, const char *default_location,
    int *id);

/* Give a reserved slot back without showing anything. */
void rays_dialog_abandon(void *slot);

/* SDL's callback: copies the outcome and publishes the slot. Any thread. */
void SDLCALL rays_dialog_callback(
    void *slot, const char *const *filelist, int filter);

/* Reserve and show: the dialog's id, or 0 with the SDL error set. */
int rays_dialog_show(rays_dialog_kind kind, SDL_Window *window,
    const char *const *names, const char *const *patterns, int count,
    const char *default_location);

/* Take the oldest finished dialog, if any. Initial domain only. */
bool rays_dialog_take(rays_dialog_result *result);

#endif
