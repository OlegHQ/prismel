open Rays
type t={mutable samples:(string*Audio.Sample.t)list;
  mutable images:(string*Image.t)list;mutable audio_owned:bool;mutable closed:bool;
  mutable samples_created:int;mutable samples_destroyed:int}
let create ()={samples=[];images=[];audio_owned=false;closed=false;
  samples_created=0;samples_destroyed=0}
let error code message=Error(Flow.Diagnostic.error ~code message)
let sample resources key make =
  if resources.closed then error "E_AUDIO" "Workspace resources are closed." else
  match List.assoc_opt key resources.samples with
  |Some sample->Ok sample
  |None when List.length resources.samples>=64->error "E_AUDIO" "A workspace owns at most 64 audio samples."
  |None->
      let initialized=if Audio.is_initialized()then Ok()else
        Result.map(fun()->resources.audio_owned<-true)(Audio.init())in
      Result.bind (Result.map_error(fun message->Flow.Diagnostic.error ~code:"E_AUDIO" message)initialized)
        (fun()->Result.map(fun sample->resources.samples<-(key,sample)::resources.samples;
          resources.samples_created<-resources.samples_created+1;sample)
          (Result.map_error(fun message->Flow.Diagnostic.error ~code:"E_AUDIO" message)(make())))
let image resources key make =
  if resources.closed then error "E_IMAGE" "Workspace resources are closed."else
  match List.assoc_opt key resources.images with
  |Some image->Ok image
  |None when List.length resources.images>=64->error "E_IMAGE" "A workspace owns at most 64 images."
  |None->Result.map(fun image->resources.images<-(key,image)::resources.images;image)
      (Result.map_error(fun message->Flow.Diagnostic.error ~code:"E_IMAGE" message)(make()))
let close resources = if not resources.closed then begin
  List.iter(fun(_,sample)->Audio.Sample.destroy sample;
    resources.samples_destroyed<-resources.samples_destroyed+1)resources.samples;
  List.iter(fun(_,image)->Image.destroy image)resources.images;
  resources.samples<-[];resources.images<-[];
  if resources.audio_owned then Audio.shutdown();
  resources.closed<-true
end
