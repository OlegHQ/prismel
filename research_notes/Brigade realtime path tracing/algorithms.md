# Real-time path tracing algorithms and fast scene updates

## How should Metal update a dynamic path-traced scene?

### Takeaway
Keep reusable primitive acceleration structures (BLAS) separate from the instance acceleration structure (TLAS). Camera motion changes neither; object transforms and instance membership generally require a TLAS update, small deformations can refit affected BLAS, and topology changes require rebuilding affected BLAS. Apple explicitly recommends building primitive structures at load time, refitting a handful of deforming objects, and rebuilding the instance structure each frame for typical game scenes.

### Cited Findings
- Metal has primitive and instance acceleration structures; instances reference primitive structures through transforms. Apple recommends building as many primitive structures at load time as possible, refitting deforming models, and rebuilding the instance structure each frame when objects move or membership changes. — [Apple WWDC22: Maximize your Metal ray tracing performance](https://developer.apple.com/videos/play/wwdc2022/10105/)
- Metal refit is faster than rebuilding for small geometric changes, but may degrade later ray traversal performance; it cannot add or remove geometry. The `Refit` usage option can itself reduce intersection performance relative to immutable structures. — [Apple refit API](https://developer.apple.com/documentation/metal/mtlaccelerationstructurecommandencoder/refit%28sourceaccelerationstructure%3Adescriptor%3Adestinationaccelerationstructure%3Ascratchbuffer%3Ascratchbufferoffset%3Aoptions%3A%29), [Apple Refit usage](https://developer.apple.com/documentation/metal/mtlaccelerationstructureusage/refit)
- Apple says batching multiple acceleration structure operations into one command encoder permits parallel execution, but operations sharing a scratch buffer cannot run in parallel. Apple also recommends combining simple nearby geometry into one primitive structure when excessive TLAS instance traversal becomes costly. — [Apple WWDC22](https://developer.apple.com/videos/play/wwdc2022/10105/)
- Metal supports instance-descriptor buffers, including indirect descriptors populated on the GPU. — [Apple WWDC23: Your guide to Metal ray tracing](https://developer.apple.com/videos/play/wwdc2023/10128/), [instance descriptor API](https://developer.apple.com/documentation/metal/mtlaccelerationstructureinstancedescriptor)
- Metal supports bounding-box primitives with custom intersection functions, so voxel-like procedural primitives can be traced without always expanding each voxel into triangles. Whether this beats meshed surfaces depends on traversal/intersection cost. — [Apple WWDC20: Discover ray tracing with Metal](https://developer.apple.com/videos/play/wwdc2020/10012/)
- Apple provides per-build tradeoff flags including `PreferFastBuild`, `PreferFastIntersection`, `MinimizeMemory`, and `Refit`; the latest Metal 4 flags are feature dependent. — [Apple Metal 4 gaming session](https://developer.apple.com/videos/play/wwdc2025/211/), [Apple Refit usage](https://developer.apple.com/documentation/metal/mtlaccelerationstructureusage/refit)

### Inferences
- If the reported voxel-wall stutter occurs during camera rotation without geometry edits, acceleration structure rebuilding/upload is avoidable work. First check for rebuilds triggered by camera or frame changes, CPU voxel remeshing, whole-scene copies, and GPU/CPU synchronization; keep scene structures and buffers resident and update only camera matrices. This follows the separation of instance transforms from primitive geometry in Apple's architecture.
- For changing voxel walls, a modest chunk mesh with one primitive structure per edited chunk is a practical starting point: rebuild edited chunks, retain untouched chunks, and rebuild/refit the instance structure according to measured build/traversal cost. Chunk size is a calibration parameter, not a universal constant. A single procedural bounding-box representation is an alternative only if benchmarked faster and it preserves the current material/geometry behavior.
- Do not blanket-enable refit. Static structures can favor traversal; moving geometry can favor fast update. Track both build time and later trace time because a cheap refit can make rendering slower.

### Gaps
- Apple publishes no universal chunk size or refit-versus-rebuild threshold for Prismel's voxel workload; this needs an on-device trace/build benchmark.
- The cited sources do not establish whether Prismel's existing OGPU/Metal binding exposes every relevant Metal acceleration structure feature; that requires a repository audit.

## How can interaction remain sharp at a small ray budget?

### Takeaway
Use full-resolution visibility/geometry guides, low sample-count lighting, temporal reprojection with history rejection, and spatial denoising. Progressive accumulation alone resets or ghosts during camera motion, while lowering the entire framebuffer destroys silhouettes and texture detail.

### Cited Findings
- SVGF reconstructs one path per pixel using temporal accumulation, spatiotemporal luminance variance, and a hierarchical image-space wavelet filter. Its original paper reports roughly 10 ms at 1080p on the tested 2017 hardware; this is historical evidence, not an Apple Silicon prediction. — [SVGF paper/project](https://research.nvidia.com/labs/rtr/publication/schied2017spatiotemporal/)
- NVIDIA NRD is a spatiotemporal denoiser aimed at roughly one path per pixel and requires G-buffer guides including normals, roughness, view depth, and motion vectors. Its documented ready integration targets D3D11/12 and Vulkan; the README does not list a Metal integration. It uses the NVIDIA RTX SDK license. — [NRD official repository](https://github.com/NVIDIA-RTX/NRD), [NRD license](https://github.com/NVIDIA-RTX/NRD/blob/main/LICENSE.txt)
- MetalFX temporal upscaling consumes current color, depth, and motion to reuse temporal information. Apple also documents a MetalFX temporal *denoised* scaler with albedo, normal, and roughness inputs; the Metal feature table marks denoised upscaling as Apple9, while ordinary temporal upscaling is Apple7. — [Apple WWDC22 MetalFX](https://developer.apple.com/videos/play/wwdc2022/10103/), [Apple WWDC25 denoised scaler](https://developer.apple.com/videos/play/wwdc2025/211/), [Apple Metal feature set table](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
- Intel Open Image Denoise (OIDN) supports Apple silicon Metal GPUs and has balanced/fast modes for interactive or real-time preview. It accepts color with optional albedo/normal guides and has a native Metal command-queue/buffer interop API. The project is Apache-2.0, but a GPU-enabled build adds integration/build complexity. — [OIDN official README](https://github.com/RenderKit/oidn)
- OIDN's documented input model is per-image color/albedo/normal, whereas NRD and SVGF explicitly use temporal guides/history. This distinction matters for rapidly rotating views. — [OIDN official README](https://github.com/RenderKit/oidn), [NRD official README](https://github.com/NVIDIA-RTX/NRD), [SVGF project](https://research.nvidia.com/labs/rtr/publication/schied2017spatiotemporal/)

### Inferences
- Preserve a native-resolution primary hit/depth/normal/motion path while decoupling stochastic lighting resolution or sample count. This keeps edges and motion data precise for temporal reconstruction and avoids the present coarse-pixel appearance. Benchmark primary-hit cost before choosing a lower-resolution lighting pass; some paths may be cheaper at full resolution with one ray and good reuse.
- The shortest Apple-native path is ordinary MetalFX temporal upscaling if available, fed correct motion/depth and jitter. It improves spatial resolution but is not a substitute for a denoiser when the input is noisy. An Apple9-only denoised scaler cannot be a mandatory solution for all Apple Silicon targets. A small in-house SVGF-style filter is plausible if MetalFX plus sampling still leaves objectionable noise; OIDN may be useful for stopped-camera preview/final accumulation, but requires device-specific timing before adopting it for every interactive frame.
- History must be rejected or shortened at disocclusions, changed geometry/materials/lights, and camera cuts; otherwise temporal reuse creates ghosting. Versioning the changed scene region rather than invalidating the whole image could preserve stable areas, but that adds complexity and should follow measurements.

### Gaps
- There is no sourced Apple Silicon comparison of MetalFX, SVGF, and OIDN on this exact scene and target hardware. The choice requires timing, image differences during motion, and stationary convergence measurements.
- The cited Apple documents do not guarantee denoised MetalFX availability on every Apple Silicon device; query device capability at startup.

## Which advanced sampling techniques are worth implementing?

### Takeaway
Prioritize fast updates and temporal reconstruction first. Add ReSTIR Direct Illumination only if many dynamic emissive lights are a measured noise bottleneck; add ReSTIR GI or adaptive sampling after a simpler one-sample path has been measured against quality and frame-time targets.

### Cited Findings
- ReSTIR DI resamples candidate lights across pixels and frames without maintaining a complex light hierarchy. The original paper reports 6–60× equal-error gains over its tested baselines and up to 3.4 million dynamic emissive triangles under 50 ms on its tested GPU; the figures do not transfer directly to Metal/Apple Silicon. — [Original ReSTIR DI paper](https://research.nvidia.com/labs/rtr/publication/bitterli2020spatiotemporal/)
- ReSTIR GI resamples multi-bounce indirect paths across time and pixels. Its paper reports 9.3–166× MSE improvement over its path-tracing baseline at one sample per pixel in its test scenes, alongside a denoiser. — [Original ReSTIR GI paper](https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing)
- NVIDIA's RTXDI reference code includes ReSTIR DI/GI integration documentation but its sample targets D3D12/Vulkan and HLSL/SPIR-V, so a Metal integration is a port and license review rather than drop-in code. Its license is the NVIDIA RTX SDK agreement, not Apache/MIT. — [RTXDI repository](https://github.com/NVIDIA-RTX/RTXDI), [RTXDI license](https://github.com/NVIDIA-RTX/RTXDI/blob/main/LICENSE.txt)
- Research on sparse-volume rendering combines unbiased volume path tracing, sparse voxel storage, temporal neural denoising, and adaptive sampling, demonstrating the techniques can coexist for *volumetric* content; it does not prove they are the right representation for a solid voxel wall. — [Hofmann et al., Interactive Path Tracing and Reconstruction of Sparse Volumes](https://research.nvidia.com/publication/2021-03_interactive-path-tracing-and-reconstruction-sparse-volumes)

### Inferences
- For a wall with few light sources, ReSTIR DI's main advantage may be irrelevant; a conventional next-event estimate and temporal denoise are much smaller changes. ReSTIR GI has more state, visibility checks, and failure modes around disocclusion and dynamic edits, so treat it as a later measured feature rather than the first fix for janky camera rotation.
- Adaptive sampling can spend rays at high-variance/newly exposed regions while stable regions reuse history, but it cannot repair a low-resolution visibility buffer or stalled scene update pipeline. Keep unbiased/progressive output available as a reference to detect temporal bias and missing details.

### Gaps
- Public papers do not disclose OTOY Brigade's implementation details or give a directly transferable algorithm for this specific renderer. Similar effects do not establish identical architecture.
- No cited source provides a licensed, native Metal drop-in implementation of ReSTIR DI/GI or NRD. An independent Metal implementation or carefully reviewed port would be required.
