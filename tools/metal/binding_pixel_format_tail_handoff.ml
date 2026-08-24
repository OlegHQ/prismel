type package=Sentinel|Pvrtc
type item={id:string;package:package;tests:string list}
let classify id={id;package=(if String.ends_with~suffix:"Invalid"id||String.ends_with~suffix:"Unspecialized"id then Sentinel else Pvrtc);tests=["SDK numeric static_assert";"generated exhaustive round trip";"platform availability provenance";"format-layout capability policy"]}
let validate items=let count p=List.length(List.filter(fun x->x.package=p)items)in if List.length items<>10||count Sentinel<>2||count Pvrtc<>8 then failwith"PixelFormat10 tail drift"
