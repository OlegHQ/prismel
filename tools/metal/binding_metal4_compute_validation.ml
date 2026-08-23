type resource={device:int;live:bool;length:int}
let range r offset size alignment=alignment>0&&offset>=0&&size>=0&&offset mod alignment=0&&size mod alignment=0&&offset<=r.length-size
let pair~device~source~source_offset~destination~destination_offset~size~alignment=
 if not source.live||not destination.live then Error"destroyed Metal4 resource"
 else if source.device<>device||destination.device<>device then Error"cross-device Metal4 resource"
 else if not(range source source_offset size alignment&&range destination destination_offset size alignment)then Error"Metal4 range/alignment"else Ok()
let texture_region~width~height~depth~x~y~z~w~h~d=width>=0&&height>=0&&depth>=0&&x>=0&&y>=0&&z>=0&&w>=0&&h>=0&&d>=0&&x<=width-w&&y<=height-h&&z<=depth-d
