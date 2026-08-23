type ownership = Scalar | Copied | Retained | Borrowed | Completion_retained
type lane = Mechanical | Lifecycle
type entry = { owner : string; property : string; ownership : ownership; lane : lane }
val properties : entry list
val lifecycle_requirements : string list
