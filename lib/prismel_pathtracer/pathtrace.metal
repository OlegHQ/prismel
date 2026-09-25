#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

// One library, one kernel specialized per mesh shape: INSTANCED selects the
// instance acceleration structure and per-instance transforms; MOTION adds a
// second transform keyframe per instance and a shutter time per sample;
// SPHERES adds bounding-box geometry resolved by an intersection function
// table; CURVES adds linear round strands. The kernel body is templated on the
// structure, intersector, and table types so every specialization compiles
// from this single source.
constant bool INSTANCED [[function_constant(0)]];
constant bool MOTION [[function_constant(1)]];
constant bool SPHERES [[function_constant(2)]];
constant bool CURVES [[function_constant(3)]];
constant bool FLAT = !INSTANCED;
constant bool STATIC_INSTANCED = INSTANCED && !MOTION;
constant bool MOTION_INSTANCED = INSTANCED && MOTION;
constant bool T_F = SPHERES && FLAT && !CURVES;
constant bool T_FC = SPHERES && FLAT && CURVES;
constant bool T_I = SPHERES && INSTANCED && !MOTION && !CURVES;
constant bool T_IC = SPHERES && INSTANCED && !MOTION && CURVES;
constant bool T_IM = SPHERES && INSTANCED && MOTION && !CURVES;
constant bool T_IMC = SPHERES && INSTANCED && MOTION && CURVES;

// Per-instance transform records: four columns of the 3x4 world transform and
// three columns of its normal matrix; with MOTION a second such record for the
// shutter's end keyframe follows and the columns are interpolated.
inline float3 column(device const packed_float3 *transforms, uint instance, uint k, float time) {
  if (MOTION) {
    uint base = instance * 14u;
    return mix(float3(transforms[base + k]), float3(transforms[base + 7u + k]), time);
  }
  return float3(transforms[instance * 7u + k]);
}
inline float3 world_point(device const packed_float3 *transforms, uint instance, float3 p, float time) {
  return column(transforms, instance, 0u, time) * p.x + column(transforms, instance, 1u, time) * p.y
       + column(transforms, instance, 2u, time) * p.z + column(transforms, instance, 3u, time);
}
inline float3 world_normal(device const packed_float3 *transforms, uint instance, float3 n, float time) {
  return column(transforms, instance, 4u, time) * n.x + column(transforms, instance, 5u, time) * n.y
       + column(transforms, instance, 6u, time) * n.z;
}
// The normal matrix is the inverse transpose of the 3x3 part, so its columns
// dotted with a world offset give the object-space offset.
inline float3 object_offset(device const packed_float3 *transforms, uint instance, float3 world, float time) {
  float3 d = world - column(transforms, instance, 3u, time);
  return float3(dot(column(transforms, instance, 4u, time), d),
                dot(column(transforms, instance, 5u, time), d),
                dot(column(transforms, instance, 6u, time), d));
}
template <typename Hit> inline uint instance_of(Hit) { return 0u; }
inline uint instance_of(intersection_result<triangle_data, instancing> hit) { return hit.instance_id; }
inline uint instance_of(intersection_result<triangle_data, instancing, instance_motion> hit) { return hit.instance_id; }
inline uint instance_of(intersection_result<triangle_data, curve_data, instancing> hit) { return hit.instance_id; }
inline uint instance_of(intersection_result<triangle_data, curve_data, instancing, instance_motion> hit) { return hit.instance_id; }
template <typename Hit> inline uint user_of(Hit) { return 0u; }
inline uint user_of(intersection_result<triangle_data, instancing> hit) { return hit.user_instance_id; }
inline uint user_of(intersection_result<triangle_data, instancing, instance_motion> hit) { return hit.user_instance_id; }
inline uint user_of(intersection_result<triangle_data, curve_data, instancing> hit) { return hit.user_instance_id; }
inline uint user_of(intersection_result<triangle_data, curve_data, instancing, instance_motion> hit) { return hit.user_instance_id; }
template <typename Hit> inline float curve_u(Hit) { return 0.0f; }
inline float curve_u(intersection_result<triangle_data, curve_data> hit) { return hit.curve_parameter; }
inline float curve_u(intersection_result<triangle_data, curve_data, instancing> hit) { return hit.curve_parameter; }
inline float curve_u(intersection_result<triangle_data, curve_data, instancing, instance_motion> hit) { return hit.curve_parameter; }

// Spheres are bounding-box primitives resolved in object space; one variant
// per intersector tag set the pipelines use.
struct Sphere { float4 center_radius; uint4 material; };
struct SphereHit { bool accept [[accept_intersection]]; float distance [[distance]]; };
inline SphereHit sphere_test(float3 origin, float3 direction, float min_distance, float max_distance, float4 s) {
  SphereHit result; result.accept = false; result.distance = 0.0f;
  float3 oc = origin - s.xyz;
  float b = dot(oc, direction), c = dot(oc, oc) - s.w * s.w, disc = b * b - c;
  if (disc < 0.0f) return result;
  float root = sqrt(disc), t = -b - root;
  if (t < min_distance) t = -b + root;
  if (t < min_distance || t > max_distance) return result;
  result.accept = true; result.distance = t; return result;
}
#define SPHERE_FUNCTION(NAME, ...) \
  [[intersection(bounding_box, __VA_ARGS__)]] SphereHit NAME(float3 origin [[origin]], float3 direction [[direction]], \
      float min_distance [[min_distance]], float max_distance [[max_distance]], uint primitive_id [[primitive_id]], \
      const device Sphere *spheres [[buffer(0)]]) { \
    return sphere_test(origin, direction, min_distance, max_distance, spheres[primitive_id].center_radius); }
SPHERE_FUNCTION(sphere_hit_f, triangle_data)
SPHERE_FUNCTION(sphere_hit_fc, triangle_data, curve_data)
SPHERE_FUNCTION(sphere_hit_i, triangle_data, instancing)
SPHERE_FUNCTION(sphere_hit_ic, triangle_data, curve_data, instancing)
SPHERE_FUNCTION(sphere_hit_im, triangle_data, instancing, instance_motion)
SPHERE_FUNCTION(sphere_hit_imc, triangle_data, curve_data, instancing, instance_motion)

// intersect() takes a table only with spheres and a time only with motion.
template <bool MOT, bool SPH> struct Isect;
template <> struct Isect<false, false> {
  template <typename Tracer, typename Scene, typename Table>
  static auto go(thread Tracer &t, ray r, Scene s, Table, float) { return t.intersect(r, s); }
};
template <> struct Isect<false, true> {
  template <typename Tracer, typename Scene, typename Table>
  static auto go(thread Tracer &t, ray r, Scene s, Table table, float) { return t.intersect(r, s, table); }
};
template <> struct Isect<true, false> {
  template <typename Tracer, typename Scene, typename Table>
  static auto go(thread Tracer &t, ray r, Scene s, Table, float time) { return t.intersect(r, s, time); }
};
template <> struct Isect<true, true> {
  template <typename Tracer, typename Scene, typename Table>
  static auto go(thread Tracer &t, ray r, Scene s, Table table, float time) { return t.intersect(r, s, time, table); }
};

struct Uniforms {
  float4 eye;      // xyz
  float4 forward;  // xyz, w = tan(fov / 2)
  float4 right;    // xyz, w = aspect
  float4 up;       // xyz
  float4 sky;
  float4 ground;
  uint width, height, frame, spp;
  uint panel_count, bounces;
  float exposure;
  uint round_samples;
  uint light_count, preview, pad1, pad2;
  float4 prev_eye;
  float4 prev_forward;
  float4 prev_right;
  float4 prev_up;
};
struct Material { float4 albedo_roughness; float4 emission_metallic; float4 round; };
// Rectangle area light: corner + two edge vectors; radiance.w is the area.
struct Light { float4 origin; float4 u; float4 v; float4 radiance; };
struct Panel { float4 direction; float4 color; float4 extents; };

inline uint pcg(thread uint &state) {
  uint s = state;
  state = s * 747796405u + 2891336453u;
  uint word = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
  return (word >> 22u) ^ word;
}
inline float rnd(thread uint &state) { return float(pcg(state) & 0x00ffffffu) / 16777216.0f; }

inline void basis(float3 n, thread float3 &t, thread float3 &b) {
  float s = n.z >= 0.0f ? 1.0f : -1.0f;
  float a = -1.0f / (s + n.z);
  float c = n.x * n.y * a;
  t = float3(1.0f + s * n.x * n.x * a, s * c, -s * n.x);
  b = float3(c, s + n.y * n.y * a, -n.y);
}

inline float3 environment(constant Uniforms &u, device const Panel *panels, float3 d) {
  float3 c = mix(u.ground.xyz, u.sky.xyz, smoothstep(-0.25f, 0.6f, d.y));
  for (uint i = 0; i < u.panel_count; ++i) {
    float3 n = panels[i].direction.xyz;
    float z = dot(d, n);
    if (z <= 0.0f) continue;
    float3 t, b;
    basis(n, t, b);
    float ax = atan2(dot(d, t), z), ay = atan2(dot(d, b), z);
    float3 e = panels[i].extents.xyz;
    float wx = 1.0f - smoothstep(e.x - e.z, e.x + e.z, fabs(ax));
    float wy = 1.0f - smoothstep(e.y - e.z, e.y + e.z, fabs(ay));
    c += panels[i].color.xyz * (wx * wy);
  }
  return c;
}

// Round-corners shading normal (Redshift/Cycles bevel style). Probe rays
// through random points of a disk of [radius], projected along one of three
// axes (N with probability 1/2, the two tangents 1/4 each), collect every
// surface inside the sphere and weight each hit by the inverse of the
// combined projection pdf. The result is an unbiased estimate of the
// area-weighted mean normal of all geometry within [radius]: flat interiors
// return N, and within [radius] of an edge the normal rolls smoothly onto the
// adjacent face, including faces parallel to N that a single-axis probe
// would never see.
template <bool INST, bool MOT, typename Scene, typename Tracer>
inline float3 round_corners(Scene scene,
                            device const packed_float3 *positions,
                            device const packed_float3 *transforms,
                            float3 P, float3 N, float radius, uint samples,
                            float time, thread uint &state) {
  float3 t, b;
  basis(N, t, b);
  Tracer probe;
  probe.assume_geometry_type(geometry_type::triangle);
  probe.force_opacity(forced_opacity::opaque);
  float3 sum = float3(0.0f);
  for (uint i = 0; i < samples; ++i) {
    float pick = rnd(state);
    float3 axis, u, v;
    if (pick < 0.5f) { axis = N; u = t; v = b; }
    else if (pick < 0.75f) { axis = t; u = b; v = N; }
    else { axis = b; u = N; v = t; }
    float rd = radius * sqrt(rnd(state)), phi = 2.0f * M_PI_F * rnd(state);
    ray r;
    r.origin = P + u * (rd * cos(phi)) + v * (rd * sin(phi)) - axis * radius;
    r.direction = axis;
    r.min_distance = 0.0f;
    r.max_distance = 2.0f * radius;
    for (uint k = 0; k < 4; ++k) {
      auto hit = Isect<MOT, false>::go(probe, r, scene, 0, time);
      if (hit.type != intersection_type::triangle) break;
      uint prim = hit.primitive_id;
      float3 p0 = float3(positions[prim * 3]), p1 = float3(positions[prim * 3 + 1]), p2 = float3(positions[prim * 3 + 2]);
      if (INST) {
        p0 = world_point(transforms, instance_of(hit), p0, time);
        p1 = world_point(transforms, instance_of(hit), p1, time);
        p2 = world_point(transforms, instance_of(hit), p2, time);
      }
      float3 hn = normalize(cross(p1 - p0, p2 - p0));
      if (dot(hn, N) < 0.0f) hn = -hn;
      float3 hp = r.origin + r.direction * hit.distance;
      if (length_squared(hp - P) < radius * radius) {
        float pdf = 0.5f * fabs(dot(hn, N)) + 0.25f * fabs(dot(hn, t)) + 0.25f * fabs(dot(hn, b));
        sum += hn / max(pdf, 1e-3f);
      }
      float advance = hit.distance + radius * 1e-3f;
      r.origin = r.origin + r.direction * advance;
      r.max_distance -= advance;
      if (r.max_distance <= 0.0f) break;
    }
  }
  return dot(sum, sum) < 1e-12f ? N : normalize(sum);
}

inline float d_ggx(float noh, float a2) {
  float d = noh * noh * (a2 - 1.0f) + 1.0f;
  return a2 / (M_PI_F * d * d);
}
inline float v_smith(float nov, float nol, float a2) {
  float gv = nol * sqrt(nov * nov * (1.0f - a2) + a2);
  float gl = nov * sqrt(nol * nol * (1.0f - a2) + a2);
  return 0.5f / max(gv + gl, 1e-6f);
}
inline float3 fresnel(float3 f0, float voh) {
  float f = pow(1.0f - voh, 5.0f);
  return f0 + (1.0f - f0) * f;
}

inline float bsdf_pdf(float3 ns, float3 v, float3 l, float a2, float ps) {
  float3 h = normalize(l + v);
  float nol = max(dot(ns, l), 0.0f), noh = max(dot(ns, h), 0.0f), voh = max(dot(v, h), 1e-4f);
  return ps * (d_ggx(noh, a2) * noh / (4.0f * voh)) + (1.0f - ps) * (nol / M_PI_F);
}

// Solid-angle pdf of the dome-panel light sampler for direction d: a panel is
// picked uniformly, then (ax, ay) uniformly over its angular rectangle
// including the soft border. Panels may overlap, so the pdf is the mixture.
inline float panel_pdf(constant Uniforms &u, device const Panel *panels, float3 d) {
  if (u.panel_count == 0) return 0.0f;
  float total = 0.0f;
  for (uint i = 0; i < u.panel_count; ++i) {
    float3 n = panels[i].direction.xyz;
    float z = dot(d, n);
    if (z <= 0.0f) continue;
    float3 t, b;
    basis(n, t, b);
    float x = dot(d, t), y = dot(d, b);
    float3 e = panels[i].extents.xyz;
    float wx = e.x + e.z, wy = e.y + e.z;
    if (fabs(atan2(x, z)) >= wx || fabs(atan2(y, z)) >= wy) continue;
    total += z / ((x * x + z * z) * (y * y + z * z) * 4.0f * wx * wy);
  }
  return total / float(u.panel_count);
}

inline float3 sample_panel(constant Uniforms &u, device const Panel *panels, thread uint &state) {
  uint i = min(uint(rnd(state) * float(u.panel_count)), u.panel_count - 1u);
  float3 n = panels[i].direction.xyz;
  float3 t, b;
  basis(n, t, b);
  float3 e = panels[i].extents.xyz;
  float ax = (2.0f * rnd(state) - 1.0f) * (e.x + e.z), ay = (2.0f * rnd(state) - 1.0f) * (e.y + e.z);
  return normalize(t * tan(ax) + b * tan(ay) + n);
}

inline float3 eval_brdf(float3 ns, float3 v, float3 l, float3 diffuse, float3 f0, float a2) {
  float3 h = normalize(l + v);
  float nol = max(dot(ns, l), 1e-4f), nov = max(dot(ns, v), 1e-4f);
  float noh = max(dot(ns, h), 0.0f), voh = max(dot(v, h), 1e-4f);
  float3 F = fresnel(f0, voh);
  return diffuse * (1.0f - F) / M_PI_F + d_ggx(noh, a2) * v_smith(nov, nol, a2) * F;
}

inline uchar4 resolved_rgba(float3 linear, float exposure) {
  float3 c = linear * exposure;
  c = (c * (2.51f * c + 0.03f)) / (c * (2.43f * c + 0.59f) + 0.14f);
  c = pow(clamp(c, 0.0f, 1.0f), 1.0f / 2.2f);
  return uchar4(uchar(c.x * 255.0f + 0.5f), uchar(c.y * 255.0f + 0.5f),
                uchar(c.z * 255.0f + 0.5f), 255);
}

template <bool INST, bool MOT, bool SPH, bool CRV, typename Scene, typename Tracer, typename Table>
inline void trace_pixel(
    Scene scene,
    constant Uniforms &u,
    device const packed_float3 *positions,
    device const packed_float3 *normals,
    device const uint *material_ids,
    device const Material *materials,
    device const Panel *panels,
    device float4 *accum,
    texture2d<float, access::write> output,
    device const Light *lights,
    device const packed_float3 *transforms,
    device const float4 *previous_color,
    device const float4 *previous_geometry,
    device float4 *next_color,
    device float4 *next_geometry,
    device const Sphere *spheres,
    Table table,
    device const packed_float3 *strand_points,
    device const uint *strand_indices,
    device const uint *strand_ids,
    uint2 gid) {
  // Trace primary visibility at every output pixel during camera motion.
  // Preview spends its smaller ray budget on direct light and one bevel probe.
  if (gid.x >= u.width || gid.y >= u.height) return;
  uint pixel = gid.y * u.width + gid.x;
  uint bounces = u.preview ? 1u : u.bounces;
  uint spp = u.preview ? 1u : u.spp;
  uint state = (pixel + 1u) * 0x9E3779B9u ^ ((u.frame + 1u) * 0x85EBCA6Bu);
  pcg(state); pcg(state);
  geometry_type kinds = geometry_type::triangle;
  if (SPH) kinds |= geometry_type::bounding_box;
  if (CRV) kinds |= geometry_type::curve;
  Tracer trace;
  trace.assume_geometry_type(kinds);
  trace.force_opacity(forced_opacity::opaque);
  Tracer shadow;
  shadow.assume_geometry_type(kinds);
  shadow.force_opacity(forced_opacity::opaque);
  shadow.accept_any_intersection(true);
  float aspect = u.right.w, tan_half = u.forward.w;
  float3 sum = float3(0.0f);
  float3 primary_position = float3(0.0f), primary_normal = float3(0.0f);
  float primary_depth = 0.0f;
  for (uint s = 0; s < spp; ++s) {
    float jx = u.preview ? 0.5f : rnd(state), jy = u.preview ? 0.5f : rnd(state);
    // Shutter time for this sample's whole path.
    float time = MOT ? (u.preview ? 0.5f : rnd(state)) : 0.0f;
    float px = ((float(gid.x) + jx) / float(u.width)) * 2.0f - 1.0f;
    float py = 1.0f - ((float(gid.y) + jy) / float(u.height)) * 2.0f;
    ray r;
    r.origin = u.eye.xyz;
    r.direction = normalize(u.forward.xyz + u.right.xyz * (px * tan_half * aspect) + u.up.xyz * (py * tan_half));
    r.min_distance = 1e-4f;
    r.max_distance = INFINITY;
    float3 throughput = float3(1.0f), radiance = float3(0.0f);
    float last_pdf = 0.0f;  // BSDF pdf of the direction that produced this ray
    for (uint bounce = 0; bounce < bounces; ++bounce) {
      auto hit = Isect<MOT, SPH>::go(trace, r, scene, table, time);
      if (hit.type == intersection_type::none) {
        // MIS (balance heuristic) against the panel sampler below; camera rays
        // have no competing strategy.
        float w = bounce == 0 ? 1.0f : last_pdf / (last_pdf + panel_pdf(u, panels, r.direction));
        radiance += throughput * environment(u, panels, r.direction) * w;
        break;
      }
      uint prim = hit.primitive_id;
      uint instance = instance_of(hit);
      float3 hitp = r.origin + r.direction * hit.distance;
      float3 v = -r.direction;
      float3 ng, ns;
      uint material_index;
      bool bevel = false;
      if (SPH && hit.type == intersection_type::bounding_box) {
        // Sphere: the object-space offset from its centre is the normal.
        float3 offset = INST ? object_offset(transforms, instance, hitp, time) : hitp;
        offset -= spheres[prim].center_radius.xyz;
        ns = INST ? normalize(world_normal(transforms, instance, offset, time)) : normalize(offset);
        ng = ns;
        material_index = spheres[prim].material.x;
      } else if (CRV && hit.type == intersection_type::curve) {
        // Strand: the offset from the interpolated axis point is the normal.
        uint first = strand_indices[prim];
        float3 axis = mix(float3(strand_points[first]), float3(strand_points[first + 1u]), curve_u(hit));
        float3 offset = (INST ? object_offset(transforms, instance, hitp, time) : hitp) - axis;
        float3 tangent = float3(strand_points[first + 1u]) - float3(strand_points[first]);
        offset -= tangent * (dot(offset, tangent) / max(dot(tangent, tangent), 1e-8f));
        ns = INST ? normalize(world_normal(transforms, instance, offset, time)) : normalize(offset);
        ng = ns;
        material_index = strand_ids[prim];
      } else {
        float2 bc = hit.triangle_barycentric_coord;
        float3 p0 = float3(positions[prim * 3]), p1 = float3(positions[prim * 3 + 1]), p2 = float3(positions[prim * 3 + 2]);
        if (INST) {
          p0 = world_point(transforms, instance, p0, time);
          p1 = world_point(transforms, instance, p1, time);
          p2 = world_point(transforms, instance, p2, time);
        }
        ng = normalize(cross(p1 - p0, p2 - p0));
        ns = normalize(float3(normals[prim * 3]) * (1.0f - bc.x - bc.y)
                       + float3(normals[prim * 3 + 1]) * bc.x
                       + float3(normals[prim * 3 + 2]) * bc.y);
        if (INST) ns = normalize(world_normal(transforms, instance, ns, time));
        // Instances select their material by user id; flat meshes per triangle.
        material_index = INST ? user_of(hit) : material_ids[prim];
        bevel = true;
      }
      if (dot(ng, v) < 0.0f) { ng = -ng; ns = -ns; }
      Material m = materials[material_index];
      if (bounce == 0 && s == 0) {
        primary_position = hitp;
        primary_normal = ng;
        primary_depth = hit.distance;
      }
      if (bevel && m.round.x > 0.0f && bounce < 2)
        ns = round_corners<INST, MOT, Scene, Tracer>(scene, positions, transforms,
                           hitp, ns, m.round.x,
                           u.preview ? 1u : (bounce == 0 ? u.round_samples : max(u.round_samples / 4u, 1u)), time, state);
      if (dot(ns, v) <= 0.0f) ns = ng;
      radiance += throughput * m.emission_metallic.xyz;
      float3 albedo = m.albedo_roughness.xyz;
      float rough = max(m.albedo_roughness.w, 0.03f), metal = m.emission_metallic.w;
      float3 f0 = mix(float3(0.04f), albedo, metal);
      float3 diffuse = albedo * (1.0f - metal);
      float nov = max(dot(ns, v), 1e-4f);
      float a = rough * rough, a2 = a * a;
      float ps = clamp(metal + (1.0f - metal) * (0.04f + 0.96f * pow(1.0f - nov, 5.0f)), 0.05f, 0.95f);
      // Next-event estimation on one rectangle light per bounce. Lights are
      // analytic (not in the acceleration structure), so they are never hit by
      // BSDF-sampled rays and this estimator is complete for them.
      if (u.light_count > 0) {
        uint li = min(uint(rnd(state) * float(u.light_count)), u.light_count - 1u);
        Light L = lights[li];
        float3 lp = L.origin.xyz + L.u.xyz * rnd(state) + L.v.xyz * rnd(state);
        float3 ln = normalize(cross(L.u.xyz, L.v.xyz));
        float3 wi = lp - hitp;
        float dist2 = max(dot(wi, wi), 1e-8f), dist = sqrt(dist2);
        wi /= dist;
        float cos_l = fabs(dot(ln, wi)), cos_s = dot(ns, wi);
        if (cos_s > 0.0f && dot(ng, wi) > 0.0f && cos_l > 1e-4f) {
          ray sr;
          sr.origin = hitp + ng * 1e-3f;
          sr.direction = wi;
          sr.min_distance = 0.0f;
          sr.max_distance = dist - 2e-3f;
          if (Isect<MOT, SPH>::go(shadow, sr, scene, table, time).type == intersection_type::none) {
            float pdf = dist2 / (cos_l * L.radiance.w * float(u.light_count));
            radiance += throughput * L.radiance.xyz * eval_brdf(ns, v, wi, diffuse, f0, a2) * cos_s / pdf;
          }
        }
      }
      // Dome panels: importance-sample their angular rectangles and weight
      // against BSDF sampling, so small bright panels stop being fireflies.
      if (u.panel_count > 0) {
        float3 wi = sample_panel(u, panels, state);
        float pl = panel_pdf(u, panels, wi), cos_s = dot(ns, wi);
        if (pl > 0.0f && cos_s > 0.0f && dot(ng, wi) > 0.0f) {
          ray sr;
          sr.origin = hitp + ng * 1e-3f;
          sr.direction = wi;
          sr.min_distance = 0.0f;
          sr.max_distance = INFINITY;
          if (Isect<MOT, SPH>::go(shadow, sr, scene, table, time).type == intersection_type::none) {
            float w = pl / (pl + bsdf_pdf(ns, v, wi, a2, ps));
            radiance += throughput * environment(u, panels, wi) * eval_brdf(ns, v, wi, diffuse, f0, a2) * cos_s * (w / pl);
          }
        }
      }
      float3 t, b;
      basis(ns, t, b);
      float r1 = rnd(state), r2 = rnd(state);
      float phi = 2.0f * M_PI_F * r1;
      float3 l, h;
      if (rnd(state) < ps) {
        float cos_t = sqrt((1.0f - r2) / (1.0f + (a2 - 1.0f) * r2));
        float sin_t = sqrt(max(0.0f, 1.0f - cos_t * cos_t));
        h = normalize(t * (sin_t * cos(phi)) + b * (sin_t * sin(phi)) + ns * cos_t);
        l = reflect(-v, h);
      } else {
        float rr = sqrt(r2);
        l = normalize(t * (rr * cos(phi)) + b * (rr * sin(phi)) + ns * sqrt(max(0.0f, 1.0f - r2)));
        h = normalize(l + v);
      }
      float nol = dot(ns, l);
      if (nol <= 0.0f || dot(ng, l) <= 0.0f) break;
      float noh = max(dot(ns, h), 0.0f), voh = max(dot(v, h), 1e-4f);
      float D = d_ggx(noh, a2);
      float pdf = ps * (D * noh / (4.0f * voh)) + (1.0f - ps) * (nol / M_PI_F);
      if (pdf <= 1e-6f) break;
      float3 F = fresnel(f0, voh);
      float3 f = diffuse * (1.0f - F) / M_PI_F + D * v_smith(nov, nol, a2) * F;
      throughput *= f * nol / pdf;
      last_pdf = pdf;
      if (bounce >= 3) {
        float q = min(max(throughput.x, max(throughput.y, throughput.z)), 0.95f);
        if (rnd(state) > q) break;
        throughput /= q;
      }
      r.origin = hitp + ng * 1e-3f;
      r.direction = l;
    }
    // ponytail: firefly clamp; replace with next-event estimation on panels if noise matters.
    float lum = dot(radiance, float3(0.2126f, 0.7152f, 0.0722f));
    if (lum > 8.0f) radiance *= 8.0f / lum;
    sum += radiance;
  }
  float4 total = float4(sum, float(spp));
  if (!u.preview) {
    total += u.frame == 0 ? float4(0.0f) : accum[pixel];
    accum[pixel] = total;
  }
  float3 linear = total.xyz / max(total.w, 1.0f);
  float history_count = u.preview ? 1.0f : 12.0f;
  if (u.preview && u.pad1 != 0u && primary_depth > 0.0f) {
    float3 previous_ray = primary_position - u.prev_eye.xyz;
    float z = dot(previous_ray, u.prev_forward.xyz);
    if (z > 1e-4f) {
      float px = dot(previous_ray, u.prev_right.xyz) / (z * u.prev_forward.w * u.prev_right.w);
      float py = dot(previous_ray, u.prev_up.xyz) / (z * u.prev_forward.w);
      int x = int(round((px + 1.0f) * 0.5f * float(u.width) - 0.5f));
      int y = int(round((1.0f - py) * 0.5f * float(u.height) - 0.5f));
      if (x >= 0 && y >= 0 && x < int(u.width) && y < int(u.height)) {
        uint previous_pixel = uint(y) * u.width + uint(x);
        float4 geometry = previous_geometry[previous_pixel];
        float expected_depth = length(previous_ray);
        if (geometry.w > 0.0f
            && fabs(geometry.w - expected_depth) < max(0.03f, expected_depth * 0.01f)
            && dot(geometry.xyz, primary_normal) > 0.95f) {
          float4 previous = previous_color[previous_pixel];
          linear = mix(linear, previous.xyz, min(previous.w / (previous.w + 1.0f), 0.92f));
          history_count = min(previous.w + 1.0f, 12.0f);
        }
      }
    }
  }
  next_color[pixel] = float4(linear, history_count);
  next_geometry[pixel] = float4(primary_normal, primary_depth);
  output.write(float4(resolved_rgba(linear, u.exposure)) / 255.0f, gid);
}

kernel void pathtrace(
    primitive_acceleration_structure flat_scene [[buffer(0), function_constant(FLAT)]],
    instance_acceleration_structure instanced_scene [[buffer(0), function_constant(STATIC_INSTANCED)]],
    acceleration_structure<instancing, instance_motion> motion_scene [[buffer(0), function_constant(MOTION_INSTANCED)]],
    constant Uniforms &u [[buffer(1)]],
    device const packed_float3 *positions [[buffer(2)]],
    device const packed_float3 *normals [[buffer(3)]],
    device const uint *material_ids [[buffer(4), function_constant(FLAT)]],
    device const Material *materials [[buffer(5)]],
    device const Panel *panels [[buffer(6)]],
    device float4 *accum [[buffer(7)]],
    texture2d<float, access::write> output [[texture(0)]],
    device const Light *lights [[buffer(9)]],
    device const packed_float3 *transforms [[buffer(10), function_constant(INSTANCED)]],
    device const float4 *previous_color [[buffer(11)]],
    device const float4 *previous_geometry [[buffer(12)]],
    device float4 *next_color [[buffer(13)]],
    device float4 *next_geometry [[buffer(14)]],
    device const Sphere *spheres [[buffer(15), function_constant(SPHERES)]],
    intersection_function_table<triangle_data> table_f [[buffer(16), function_constant(T_F)]],
    intersection_function_table<triangle_data, curve_data> table_fc [[buffer(16), function_constant(T_FC)]],
    intersection_function_table<triangle_data, instancing> table_i [[buffer(16), function_constant(T_I)]],
    intersection_function_table<triangle_data, curve_data, instancing> table_ic [[buffer(16), function_constant(T_IC)]],
    intersection_function_table<triangle_data, instancing, instance_motion> table_im [[buffer(16), function_constant(T_IM)]],
    intersection_function_table<triangle_data, curve_data, instancing, instance_motion> table_imc [[buffer(16), function_constant(T_IMC)]],
    device const packed_float3 *strand_points [[buffer(17), function_constant(CURVES)]],
    device const uint *strand_indices [[buffer(18), function_constant(CURVES)]],
    device const uint *strand_ids [[buffer(19), function_constant(CURVES)]],
    uint2 gid [[thread_position_in_grid]]) {
  using S_F = primitive_acceleration_structure;
  using S_I = instance_acceleration_structure;
  using S_IM = acceleration_structure<instancing, instance_motion>;
  using R_F = intersector<triangle_data>;
  using R_FC = intersector<triangle_data, curve_data>;
  using R_I = intersector<triangle_data, instancing>;
  using R_IC = intersector<triangle_data, curve_data, instancing>;
  using R_IM = intersector<triangle_data, instancing, instance_motion>;
  using R_IMC = intersector<triangle_data, curve_data, instancing, instance_motion>;
  using T_F_ = intersection_function_table<triangle_data>;
  using T_FC_ = intersection_function_table<triangle_data, curve_data>;
  using T_I_ = intersection_function_table<triangle_data, instancing>;
  using T_IC_ = intersection_function_table<triangle_data, curve_data, instancing>;
  using T_IM_ = intersection_function_table<triangle_data, instancing, instance_motion>;
  using T_IMC_ = intersection_function_table<triangle_data, curve_data, instancing, instance_motion>;
#define TRACE(INST, MOT, SPH, CRV, SCENE, TRACER, TABLE, SCENE_ARG, TABLE_ARG) \
  trace_pixel<INST, MOT, SPH, CRV, SCENE, TRACER, TABLE>( \
      SCENE_ARG, u, positions, normals, INST ? nullptr : material_ids, materials, panels, accum, output, lights, \
      INST ? transforms : nullptr, previous_color, previous_geometry, next_color, next_geometry, \
      SPH ? spheres : nullptr, TABLE_ARG, CRV ? strand_points : nullptr, CRV ? strand_indices : nullptr, \
      CRV ? strand_ids : nullptr, gid)
  if (INSTANCED) {
    if (MOTION) {
      if (CURVES) {
        if (SPHERES) TRACE(true, true, true, true, S_IM, R_IMC, T_IMC_, motion_scene, table_imc);
        else TRACE(true, true, false, true, S_IM, R_IMC, int, motion_scene, 0);
      } else {
        if (SPHERES) TRACE(true, true, true, false, S_IM, R_IM, T_IM_, motion_scene, table_im);
        else TRACE(true, true, false, false, S_IM, R_IM, int, motion_scene, 0);
      }
    } else {
      if (CURVES) {
        if (SPHERES) TRACE(true, false, true, true, S_I, R_IC, T_IC_, instanced_scene, table_ic);
        else TRACE(true, false, false, true, S_I, R_IC, int, instanced_scene, 0);
      } else {
        if (SPHERES) TRACE(true, false, true, false, S_I, R_I, T_I_, instanced_scene, table_i);
        else TRACE(true, false, false, false, S_I, R_I, int, instanced_scene, 0);
      }
    }
  } else {
    if (CURVES) {
      if (SPHERES) TRACE(false, false, true, true, S_F, R_FC, T_FC_, flat_scene, table_fc);
      else TRACE(false, false, false, true, S_F, R_FC, int, flat_scene, 0);
    } else {
      if (SPHERES) TRACE(false, false, true, false, S_F, R_F, T_F_, flat_scene, table_f);
      else TRACE(false, false, false, false, S_F, R_F, int, flat_scene, 0);
    }
  }
#undef TRACE
}

kernel void resolve_preview(
    constant Uniforms &u [[buffer(0)]],
    device const float4 *color [[buffer(1)]],
    device const float4 *geometry [[buffer(2)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= u.width || gid.y >= u.height) return;
  uint pixel = gid.y * u.width + gid.x;
  float4 center = geometry[pixel];
  float3 sum = color[pixel].xyz;
  float weight = 1.0f;
  if (center.w > 0.0f) {
    for (int dy = -1; dy <= 1; ++dy) {
      for (int dx = -1; dx <= 1; ++dx) {
        if (dx == 0 && dy == 0) continue;
        int x = int(gid.x) + dx, y = int(gid.y) + dy;
        if (x < 0 || y < 0 || x >= int(u.width) || y >= int(u.height)) continue;
        uint neighbor = uint(y) * u.width + uint(x);
        float4 surface = geometry[neighbor];
        if (surface.w > 0.0f
            && fabs(surface.w - center.w) < max(0.03f, center.w * 0.01f)
            && dot(surface.xyz, center.xyz) > 0.95f) {
          float w = dx == 0 || dy == 0 ? 0.5f : 0.25f;
          sum += color[neighbor].xyz * w;
          weight += w;
        }
      }
    }
  }
  output.write(float4(resolved_rgba(sum / weight, u.exposure)) / 255.0f, gid);
}
