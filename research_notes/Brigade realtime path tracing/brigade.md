# OTOY Brigade and Octane real-time path tracing

## What does Brigade actually do during interaction?

### Takeaway
The published Brigade design separates scene change processing from tracing, updates acceleration structures incrementally, and trades sample count against a frame budget. Its 2013 temporal accumulation is a camera-speed-controlled blend, not documented motion-vector reprojection; that distinction matters for a rotating camera.

### Cited Findings
- The original paper describes a scene graph, a core that synchronizes changes, an acceleration-structure updater that selectively rebuilds changed BVH portions, and GPU tracers with next-event estimation and multiple importance sampling. It says materials and lights can change without rebuilding the BVH. — [Bikker and van Schijndel, *The Brigade Renderer*, §§4.1–4.2](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- Each scene-graph node has its own BVH; a top-level BVH is rebuilt each frame; changed nodes are reconstructed or refit. CPU updates run alongside rendering, changes go through a commit buffer, and the next rendered frame uses the previous frame's BVH. — [Bikker and van Schijndel, §4.4](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- Their temporal convergence blends previous and new images with a blend factor tied to camera speed. For moving cameras the factor approaches 1 to avoid ghosting; even with a still camera, animated objects force a lower bound on that factor. The paper does not describe reprojecting history by motion vectors. — [Bikker and van Schijndel, §4.5](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- Brigade adapts samples per pixel to frame-rate bounds. It also describes shifting work between primary and secondary rays and changing Russian roulette termination probability. The latter preserves unbiasedness while increasing variance. — [Bikker and van Schijndel, §4.7](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- The 2013 system reached 2–4 samples per pixel at real-time frame rates at 640×360 on two GTX 470s; the authors said 8–16 samples per pixel were needed for acceptable quality in most views of their outdoor demo and that full 720p needed 8–16× more performance. This is historical evidence, not a current performance estimate. — [Bikker and van Schijndel, §6.2.6](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- The original paper reports an animated 18,000-polygon water surface increasing CPU BVH maintenance and GPU scene-transfer time. It also reports an explicit sampling ray toward the primary light to reduce variance. — [Bikker and van Schijndel, §§6.2.3–6.2.4](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)

### Inferences
- For a camera orbit around unchanged geometry, acceleration rebuild should be near zero; sampling, denoising, presentation, and per-frame scene translation become the likely costs. This follows the separation of camera data from changed geometry in the published design, but OTOY has not published a current Octane frame profile.
- Copying the old same-pixel blend would retain little useful history during rotation or cause ghosting. The paper itself acknowledges the moving-camera error; a modern implementation should evaluate reprojection and visibility checks independently.

### Gaps
- No public current Brigade source or detailed current frame graph was located. The 2013 paper is an architecture reference, not a description of the 2024+ Octane kernel.
- No verified public detail was found for Brigade's current motion vectors, disocclusion tests, history rejection, reservoir sampling, denoiser network, per-frame ray budget, or resolution policy.

## How does Brigade relate to Octane, denoising, and feature parity?

### Takeaway
"Brigade" has referred to at least two integrations: scene-graph interactivity integrated into Octane 4, and a later planned real-time spectral kernel. OTOY says the kernel builds on Octane's existing spectral pipeline to retain materials and volumes, but launch statements and roadmaps should not be treated as proof that all promised real-time features shipped.

### Cited Findings
- OTOY announced Brigade scene-graph integration in Octane 4 in 2018, claiming 10–100× faster heavy-scene loading and interaction, including moving and deforming multi-million-triangle scenes. That same release introduced interactive Spectral AI denoising and AI Light. The speed numbers are OTOY's claims. — [OTOY, OctaneRender 4 launch](https://home.otoy.com/octanerender-4/)
- OTOY's Octane page says its Spectral AI Denoiser plus AI Light cleaned a room at 50 samples and its Brigade-powered scene graph moved high-poly street objects. It separately attributes acceleration to RTX hardware. — [OTOY, OctaneRender overview](https://home.otoy.com/render/octane-render/)
- In a 2022 forum statement, an OTOY team member said the earlier Brigade technology had shipped with Octane 4, whereas a newer Brigade kernel was distinct, built into the Octane spectral pipeline, and intended to retain all Octane features including depth of field, fog, and volumetric effects. The same statement identified DCC scene-graph throughput and Octane's CPU film buffer as obstacles to 60 fps, and said the film buffer had moved back to GPU in 2022.1 XB2. These are staff statements about development at the time. — [OTOY forum, June 2022](https://render.otoy.com/forum/viewtopic.php?t=80031)
- The 2022.1 experimental-build announcement promised a 60+ fps Brigade spectral rendering kernel with material, volume, displacement, shader, and spectral parity and offered a BrigadeBench preview. The post labels that build experimental and the future kernel as planned for RC1. — [OTOY forum, November 2021](https://render.otoy.com/forum/viewtopic.php?t=78783)
- OTOY's 2024.1 alpha post says Brigade temporal denoising was in the 2023 core and planned for plugin exposure in 2024. The 2024 launch page lists Brigade temporal denoising among features still “coming up,” which is a roadmap status rather than proof of general plugin availability. — [OTOY 2024.1 alpha](https://render.otoy.com/forum/viewtopic.php?t=82267); [OTOY 2024 announcement](https://home.otoy.com/render/octane-render/news/octane2024/)
- Octane's documented interactive denoiser can rerun before completion at a configured minimum sample count and maximum interval, and can blend denoised with raw beauty. OTOY also documents separate denoised lighting AOVs. — [OTOY Spectral AI Denoiser documentation](https://docs.otoy.com/standaloneSE/SpectralAIDenoiser.html); [OTOY Denoised AOVs documentation](https://docs.otoy.com/standaloneSE/DenoisedAOVs.html)
- Octane offers an AI upsampler that renders at lower resolution then scales to output resolution; its own documentation identifies upsampling as a separate configurable operation. — [OTOY C4D Camera Imager documentation](https://docs.otoy.com/cinema4d/CameraImager.html)
- OTOY's 2024.1 announcement says hardware ray tracing on Apple M3 showed scene-dependent 2–12× gains in heavily instanced scenes and describes a geometry-pipeline redesign. Those figures are OTOY marketing measurements, not a transferable Prismel benchmark. — [OTOY 2024 announcement](https://home.otoy.com/render/octane-render/news/octane2024/)

### Inferences
- Preserving all path-tracing capabilities is easiest if interaction changes scheduling, scene synchronization, acceleration-structure maintenance, sampling and denoising around one material/light/volume representation, mirroring OTOY's stated integration strategy. A separate simplified renderer risks feature drift.
- A stable native-resolution image under camera movement likely requires better spatiotemporal reconstruction and sampling before aggressive resolution reduction. OTOY's public material does not reveal a single transferable “Brigade algorithm” that solves both quality and latency.

### Gaps
- OTOY has not published enough current internals to reproduce Brigade's temporal denoiser exactly or verify universal feature parity in a publicly released real-time kernel.
- Public claims about 60+ fps lack a stated repeatable scene, GPU, output resolution, and quality metric for comparison with Prismel's voxel-wall case.

## Is there Brigade code to reuse?

### Takeaway
The original research paper provides enough algorithmic detail to guide architecture, but no current OTOY Brigade implementation was found to reuse directly. Lighthouse 2 is open-source work by Brigade's original author, useful as adjacent reference rather than current Brigade code.

### Cited Findings
- The 2013 Brigade paper includes a compact CUDA path-tracing reference kernel in its appendix. Its main architecture sections specify incremental scene updates, workload balancing, and convergence. — [Bikker and van Schijndel, paper and appendix](https://jbikker.github.io/literature/The%20Brigade%20Renderer%20-%20A%20Path%20Tracer%20for%20Real-Time%20Games%20-%202012.pdf)
- Jacco Bikker publicly announced the separate open-source Lighthouse 2 renderer, linking its repository; this is a later project by Brigade's original author, not the Octane Brigade code. — [Jacco Bikker, Lighthouse 2 announcement](https://jacco.ompf2.com/2019/07/11/lighthouse-2/); [Lighthouse 2 repository](https://github.com/jbikker/lighthouse2)

### Inferences
- Read Lighthouse 2 for implementation patterns only after profiling identifies a matching bottleneck; porting a whole alternate renderer would duplicate Prismel's Metal/OGPU architecture.

### Gaps
- No OTOY-maintained public repository or license for the current Brigade kernel or scene graph was found.
