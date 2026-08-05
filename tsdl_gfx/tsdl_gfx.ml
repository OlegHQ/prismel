open Tsdl

module Gfx = struct
  type 'a result = 'a Sdl.result

  external scalar_stub : int -> nativeint -> int array -> int
    = "caml_tsdl_gfx_scalar"
  external polygon_stub : int -> nativeint -> (int * int) list -> int array -> int
    = "caml_tsdl_gfx_polygon"
  external string_stub : nativeint -> string -> int array -> int
    = "caml_tsdl_gfx_string"
  external set_font_rotation_stub : int -> unit
    = "caml_tsdl_gfx_font_rotation"

  let arguments = Domain.DLS.new_key (fun () -> Array.make 10 0)
  let cached_renderer : (Sdl.renderer * nativeint) option ref = ref None
  let ok = Ok ()

  let renderer_pointer renderer =
    match !cached_renderer with
    | Some (cached, pointer) when cached == renderer -> pointer
    | _ ->
        let pointer = Sdl.unsafe_ptr_of_renderer renderer in
        cached_renderer := Some (renderer, pointer);
        pointer

  let finish = function
    | 0 -> ok
    | _ -> Error (`Msg (Sdl.get_error ()))

  let invoke operation renderer args =
    scalar_stub operation (renderer_pointer renderer) args |> finish

  let pixel_rgba renderer ~x ~y ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y;
    args.(2) <- r; args.(3) <- g; args.(4) <- b; args.(5) <- a;
    invoke 0 renderer args

  let hline_rgba renderer ~x1 ~x2 ~y ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- x2; args.(2) <- y;
    args.(3) <- r; args.(4) <- g; args.(5) <- b; args.(6) <- a;
    invoke 1 renderer args

  let vline_rgba renderer ~x ~y1 ~y2 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y1; args.(2) <- y2;
    args.(3) <- r; args.(4) <- g; args.(5) <- b; args.(6) <- a;
    invoke 2 renderer args

  let rectangle_rgba renderer ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- r; args.(5) <- g; args.(6) <- b; args.(7) <- a;
    invoke 3 renderer args

  let rounded_rectangle_rgba renderer ~x1 ~y1 ~x2 ~y2 ~rad ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- rad; args.(5) <- r; args.(6) <- g; args.(7) <- b; args.(8) <- a;
    invoke 4 renderer args

  let box_rgba renderer ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- r; args.(5) <- g; args.(6) <- b; args.(7) <- a;
    invoke 5 renderer args

  let rounded_box_rgba renderer ~x1 ~y1 ~x2 ~y2 ~rad ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- rad; args.(5) <- r; args.(6) <- g; args.(7) <- b; args.(8) <- a;
    invoke 6 renderer args

  let line_rgba renderer ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- r; args.(5) <- g; args.(6) <- b; args.(7) <- a;
    invoke 7 renderer args

  let aaline_rgba renderer ~x1 ~y1 ~x2 ~y2 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- r; args.(5) <- g; args.(6) <- b; args.(7) <- a;
    invoke 8 renderer args

  let thick_line_rgba renderer ~x1 ~y1 ~x2 ~y2 ~width ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- width; args.(5) <- r; args.(6) <- g; args.(7) <- b; args.(8) <- a;
    invoke 9 renderer args

  let circle_call operation renderer ~x ~y ~rad ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y; args.(2) <- rad;
    args.(3) <- r; args.(4) <- g; args.(5) <- b; args.(6) <- a;
    invoke operation renderer args

  let circle_rgba = circle_call 10
  let aacircle_rgba = circle_call 11
  let filled_circle_rgba = circle_call 12

  let ellipse_call operation renderer ~x ~y ~rx ~ry ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y; args.(2) <- rx; args.(3) <- ry;
    args.(4) <- r; args.(5) <- g; args.(6) <- b; args.(7) <- a;
    invoke operation renderer args

  let ellipse_rgba = ellipse_call 13
  let aaellipse_rgba = ellipse_call 14
  let filled_ellipse_rgba = ellipse_call 15

  let pie_call operation renderer ~x ~y ~rad ~start ~end_ ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y; args.(2) <- rad;
    args.(3) <- start; args.(4) <- end_;
    args.(5) <- r; args.(6) <- g; args.(7) <- b; args.(8) <- a;
    invoke operation renderer args

  let arc_rgba = pie_call 16
  let pie_rgba = pie_call 17
  let filled_pie_rgba = pie_call 18

  let trigon_call operation renderer ~x1 ~y1 ~x2 ~y2 ~x3 ~y3 ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x1; args.(1) <- y1; args.(2) <- x2; args.(3) <- y2;
    args.(4) <- x3; args.(5) <- y3;
    args.(6) <- r; args.(7) <- g; args.(8) <- b; args.(9) <- a;
    invoke operation renderer args

  let trigon_rgba = trigon_call 19
  let aatrigon_rgba = trigon_call 20
  let filled_trigon_rgba = trigon_call 21

  let polygon_call operation renderer ~ps ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- 0; args.(1) <- r; args.(2) <- g; args.(3) <- b; args.(4) <- a;
    polygon_stub operation (renderer_pointer renderer) ps args |> finish

  let polygon_rgba = polygon_call 0
  let aapolygon_rgba = polygon_call 1
  let filled_polygon_rgba = polygon_call 2
  let polyline_rgba = polygon_call 4

  let bezier_rgba renderer ~ps ~s ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- s; args.(1) <- r; args.(2) <- g; args.(3) <- b; args.(4) <- a;
    polygon_stub 3 (renderer_pointer renderer) ps args |> finish

  let character_rgba renderer ~x ~y ~c ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y; args.(2) <- Char.code c;
    args.(3) <- r; args.(4) <- g; args.(5) <- b; args.(6) <- a;
    invoke 22 renderer args

  let string_rgba renderer ~x ~y ~s ~r ~g ~b ~a =
    let args = Domain.DLS.get arguments in
    args.(0) <- x; args.(1) <- y;
    args.(2) <- r; args.(3) <- g; args.(4) <- b; args.(5) <- a;
    string_stub (renderer_pointer renderer) s args |> finish

  let set_font_rotation ~rot = set_font_rotation_stub rot
end
