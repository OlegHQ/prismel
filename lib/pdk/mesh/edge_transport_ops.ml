type roots = Edge_transport.roots =
  | Transport_first_point
  | Transport_last_point
  | Transport_root_group of Group.t
type operation = Edge_transport.operation =
  | Transport
  | Transport_from_root
  | Transport_total
  | Transport_maximum
  | Transport_minimum
type root_value = Edge_transport.root_value =
  | Transport_root_zero
  | Transport_root_hold
type split = Edge_transport.split = Transport_copy | Transport_split
type normalization = Edge_transport.normalization =
  | Transport_no_normalization
  | Transport_normalize_components
  | Transport_normalize_global
type direction = Edge_transport.direction = Transport_forward | Transport_backward
type merge = Edge_transport.merge =
  | Transport_merge_add
  | Transport_merge_maximum
  | Transport_merge_minimum

let run_checked ?cancel ?grain ?points ?roots ?operation ?root_value
    ?integrate_constant ?scale_by_edge_length ?split ?direction ?merge
    ?normalization ~attribute geometry =
  Error.guard ~operation:"edge_transport" ~code:"invalid_edge_transport"
    (fun () -> Edge_transport.run ?cancel ?grain ?points ?roots ?operation
      ?root_value ?integrate_constant ?scale_by_edge_length ?split ?direction
      ?merge ?normalization ~attribute geometry)

let run_curves_checked ?cancel ?grain ?primitives ?owner ?direction ?operation
    ?root_value ?integrate_constant ?scale_by_edge_length ?normalization
    ~attribute geometry =
  Error.guard ~operation:"edge_transport_curves" ~code:"invalid_edge_transport"
    (fun () -> Edge_transport.run_curves ?cancel ?grain ?primitives ?owner
      ?direction ?operation ?root_value ?integrate_constant
      ?scale_by_edge_length ?normalization ~attribute geometry)

let run_parent_checked ?cancel ?grain ?points ?parent_attribute ?direction
    ?operation ?root_value ?integrate_constant ?scale_by_edge_length ?split
    ?merge ?normalization ~attribute geometry =
  Error.guard ~operation:"edge_transport_parent" ~code:"invalid_edge_transport"
    (fun () -> Edge_transport.run_parent ?cancel ?grain ?points
      ?parent_attribute ?direction ?operation ?root_value ?integrate_constant
      ?scale_by_edge_length ?split ?merge ?normalization ~attribute geometry)
