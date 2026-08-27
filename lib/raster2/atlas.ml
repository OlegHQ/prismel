type key =
  | Glyph of { font : int64; codepoint : int; density : int }
  | Image of { id : int64; generation : int64; density : int }

type placement = { page : int; x : int; y : int; width : int; height : int }
type error = Invalid_capacity | Invalid_dimensions | Invalid_density | Storage_too_small | Full
type entry = { key : key; width : int; height : int; pixels : bytes; mutable place : placement }
type page = { pixels : bytes; mutable x : int; mutable y : int; mutable row_h : int }
type t = {
  page_width : int; page_height : int; max_pages : int; max_entries : int;
  padding : int; mutable entries : entry list; mutable pages : page array;
}

let density = function Glyph k -> k.density | Image k -> k.density
let valid_key key = density key > 0
let fresh_page t =
  { pixels = Bytes.make (t.page_width * t.page_height * 4) '\000'; x = t.padding;
    y = t.padding; row_h = 0 }

let put t page entry =
  let padded_w = entry.width + t.padding in
  let padded_h = entry.height + t.padding in
  if page.x + entry.width + t.padding > t.page_width then begin
    page.x <- t.padding; page.y <- page.y + page.row_h; page.row_h <- 0
  end;
  if page.y + entry.height + t.padding > t.page_height then None else begin
    let place = { page = 0; x = page.x; y = page.y; width = entry.width; height = entry.height } in
    for y = 0 to entry.height - 1 do
      Bytes.blit entry.pixels (y * entry.width * 4) page.pixels
        (((page.y + y) * t.page_width + page.x) * 4) (entry.width * 4)
    done;
    page.x <- page.x + padded_w;
    page.row_h <- max page.row_h padded_h;
    Some place
  end

let rebuild t entries =
  let pages = ref [] in
  let place entry =
    let rec try_pages index = function
      | [] when index < t.max_pages ->
          let page = fresh_page t in
          begin match put t page entry with
          | None -> None
          | Some p -> pages := !pages @ [ page ]; Some { p with page = index }
          end
      | [] -> None
      | page :: rest ->
          begin match put t page entry with
          | Some p -> Some { p with page = index }
          | None -> try_pages (index + 1) rest
          end
    in
    try_pages 0 !pages
  in
  let rec loop = function
    | [] -> t.pages <- Array.of_list !pages; true
    | entry :: rest ->
        begin match place entry with
        | None -> false
        | Some placement -> entry.place <- placement; loop rest
        end
  in
  loop entries

let create ~page_width ~page_height ~max_pages ~max_entries ~padding =
  if page_width <= 0 || page_height <= 0 || max_pages <= 0 || max_entries <= 0 || padding < 0
  then Error Invalid_capacity
  else if page_width > max_int / page_height / 4 then Error Invalid_capacity
  else Ok { page_width; page_height; max_pages; max_entries; padding; entries = []; pages = [||] }

let remove_key key entries = List.filter (fun entry -> entry.key <> key) entries

let add t key ~width ~height pixels =
  if not (valid_key key) then Error Invalid_density
  else if width <= 0 || height <= 0 then Error Invalid_dimensions
  else if width > max_int / height / 4 then Error Invalid_dimensions
  else if Bytes.length pixels <> width * height * 4 then Error Storage_too_small
  else if width + (2 * t.padding) > t.page_width || height + (2 * t.padding) > t.page_height
  then Error Full
  else
    let copied = Bytes.copy pixels in
    let candidate = { key; width; height; pixels = copied;
      place = { page = 0; x = 0; y = 0; width; height } } in
    let base = remove_key key t.entries in
    let rec fit entries =
      let entries = if List.length entries >= t.max_entries then List.tl entries else entries in
      let next = entries @ [ candidate ] in
      if rebuild t next then Some next
      else match entries with [] -> None | _ :: rest -> fit rest
    in
    begin match fit base with
    | None -> ignore (rebuild t t.entries); Error Full
    | Some entries -> t.entries <- entries; Ok candidate.place
    end

let find t key =
  match List.find_opt (fun entry -> entry.key = key) t.entries with
  | None -> None
  | Some entry ->
      t.entries <- remove_key key t.entries @ [ entry ];
      Some entry.place

let invalidate t key = t.entries <- remove_key key t.entries; ignore (rebuild t t.entries)
let invalidate_density t ~density:target =
  t.entries <- List.filter (fun entry -> density entry.key <> target) t.entries;
  ignore (rebuild t t.entries)
let length t = List.length t.entries
let page_count t = Array.length t.pages
let page_bytes t ~page =
  if page < 0 || page >= Array.length t.pages then None
  else Some (Bytes.copy t.pages.(page).pixels)
let placements t = List.map (fun entry -> (entry.key, entry.place)) t.entries
