(workspace variations

  (graph garden :context sop [(seed : int 1) (count : int 40)]
    (let* [bed (sop/circle :radius 1 :segments 48)
           spots (sop/scatter bed :count count :seed seed)
           dot (sop/uv_sphere :radius 0.06 :segments 8 :rings 4)
           dots (sop/copy_to_points dot spots)
           result (sop/merge bed dots)]
      result))

  (graph scene :context scene [(seed : int 1)]
    (scene/object (ref garden :seed seed) :color "#3b7d4e"))

  (graph editor :context editor
    (let* [sheet (ui/tile (for [s (range 4)]
                            (ui/viewport (ref scene :seed (+ s 1)))))
           network (ui/graph)
           code (ui/lisp)
           left (ui/split-at "vertical" 0.58 network code)
           outline (ui/outline)
           right (ui/split-at "horizontal" 0.5 left sheet)
           panels (ui/split-at "horizontal" 0.13 outline right)
           shell (ui/workspace panels)]
      shell)))
