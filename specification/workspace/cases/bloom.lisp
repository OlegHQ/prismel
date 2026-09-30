(workspace bloom_studio

  ; A petal is one shared function. The flower repeats it with for.
  (defn half :context value [(x : float)]
    (* x 0.5))

  (defmacro twice [x]
    (+ x x))

  (defn petal :context sop [(length : float 1.0) (width : float 0.3)]
    (sop/transform (sop/uv_sphere :radius [(half length) 0.04 width]
                                  :center [(half length) 0 0]
                                  :segments 14
                                  :rings 6)
                   :rotate [0 0 0.35]))

  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)]
                  (let* [u (/ i petals)
                         wobble (* 0.35 (value/rand seed i))
                         leaf (petal :length (+ 0.9 wobble) :width 0.22)
                         tint (sop/set_color leaf
                                             :color (value/hsv (+ 0.05 (* u 0.12)) 0.55 0.92))]
                    (sop/transform tint :rotate [0 (* u 6.2832) 0])))
           bloom (sop/merge ring)
           heart (sop/uv_sphere :radius [0.22 0.12 0.22] :center [0 0.05 0])
           result (sop/merge bloom (sop/set_color heart :color "#6b7650"))]
      result))

  (graph scene :context scene
    (let* [main (scene/object (ref flower) :color "#d69f61")
           accent (scene/object (ref flower :petals 7 :seed 2)
                                :color "#6fa6a1"
                                :at [2.2 0 -1.2]
                                :scale 0.55)
           composed (scene/merge main accent)]
      composed))

  (graph world :context world
    (world/layer (ref scene) :name "Bloom study"))

  (graph settings :context settings
    (let* [fps 60
           seed 42
           config (settings/config :fps fps :seed seed :exposure (twice 0.5))]
      config))

  (graph editor :context editor
    (let* [outline (ui/outline)
           network (ui/graph)
           preview (ui/viewport (ref scene))
           inspector (ui/inspector)
           code (ui/lisp)
           lower (ui/split-at "vertical" 0.46 inspector code)
           side (ui/split-at "vertical" 0.4 preview lower)
           main (ui/split-at "horizontal" 0.66 network side)
           panels (ui/split-at "horizontal" 0.13 outline main)
           shell (ui/workspace panels)]
      shell)))
