(** Public native Metal runtime facade.

    The implementation remains in [Runtime_next] while the former SDL2
    runtime has been retired.  Keeping this thin module makes [Runtime] the
    only public lifecycle entry point without duplicating ownership logic. *)

include Runtime_next
