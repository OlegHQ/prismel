let origin=ref(Unix.gettimeofday())and last=ref 0. and delta=ref 0. and fps=ref 0. and target=ref None and vsync=ref true and scale=ref 1.
let init()=origin:=Unix.gettimeofday();last:=0.;delta:=0.;fps:=0.
let now()=Unix.gettimeofday() -. !origin let elapsed=now let get_delta_time() = !delta let get_frame_rate() = !fps
let set_frame_rate value=target:=if value>0 then Some value else None
let set_vsync value=vsync:=value
let set_time_scale value=scale:=max 0. value let get_time_scale() = !scale
let update()=let current=now()in let raw=current -. !last in delta:=min raw 0.1 *. !scale;fps:=if raw > 0. then 1. /. raw else 0.;last:=current
let limit_frame_rate()=match !target with Some value when not !vsync->let target_dt=1. /. float value in let raw=if !scale = 0. then 0. else !delta /. !scale in if raw<target_dt then Unix.sleepf(target_dt-.raw)|_->()
let clamp x=max 0. (min 1. x) let elapsed_fraction start duration=if duration <= 0. then 1. else clamp((now()-.start)/.duration)
let smoothstep t=let t=clamp t in t*.t*.(3.-.2.*.t) let ease_in t=t*.t let ease_out t=1.-.(1.-.t)*.(1.-.t) let ease_in_out=smoothstep
module Easing=struct
 let linear t=t let ease_in_quad=ease_in let ease_out_quad=ease_out let ease_in_out_quad=smoothstep
 let ease_in_cubic t=t*.t*.t let ease_out_cubic t=1.-.(1.-.t)**3. let ease_in_out_cubic=smoothstep
 let ease_in_quart t=t**4. let ease_out_quart t=1.-.(1.-.t)**4. let ease_in_out_quart=smoothstep
 let ease_in_quint t=t**5. let ease_out_quint t=1.-.(1.-.t)**5. let ease_in_out_quint=smoothstep
 let ease_in_sine t=1.-.cos(t*.Float.pi/.2.) let ease_out_sine t=sin(t*.Float.pi/.2.) let ease_in_out_sine t=(1.-.cos(Float.pi*.t))/.2.
 let ease_in_expo t=if t = 0. then 0. else 2.**(10.*.t-.10.) let ease_out_expo t=if t = 1. then 1. else 1.-.2.**(-10.*.t) let ease_in_out_expo=smoothstep
 let ease_in_circ t=1.-.sqrt(1.-.t*.t) let ease_out_circ t=sqrt(1.-.(t-.1.)**2.) let ease_in_out_circ=smoothstep
 let ease_in_back t=2.70158*.t**3.-.1.70158*.t*.t let ease_out_back t=1.+.2.70158*.(t-.1.)**3.+.1.70158*.(t-.1.)**2. let ease_in_out_back=smoothstep
 let ease_in_elastic=smoothstep let ease_out_elastic=smoothstep let ease_in_out_elastic=smoothstep
 let ease_out_bounce t=let n=7.5625 and d=2.75 in if t<1./.d then n*.t*.t else if t<2./.d then let x=t-.1.5/.d in n*.x*.x+.0.75 else if t<2.5/.d then let x=t-.2.25/.d in n*.x*.x+.0.9375 else let x=t-.2.625/.d in n*.x*.x+.0.984375
 let ease_in_bounce t=1.-.ease_out_bounce(1.-.t) let ease_in_out_bounce t=if t<0.5 then ease_in_bounce(2.*.t)/.2. else (1.+.ease_out_bounce(2.*.t-.1.))/.2.
end
module Scheduler=struct type job={interval:float;mutable due:float;repeat:bool;callback:unit->unit}let jobs=ref[]
 let add delay repeat callback=if Float.is_finite delay&&delay >= 0. then jobs:={interval=delay;due=now()+.delay;repeat;callback}::!jobs
 let delay_call delay callback=add delay false callback let every delay callback=if delay > 0. then add delay true callback
 let update()=let current=now()in jobs:=List.filter_map(fun job->if current<job.due then Some job else(job.callback();if job.repeat then(job.due<-current+.job.interval;Some job)else None))!jobs
end
let ()=init()
