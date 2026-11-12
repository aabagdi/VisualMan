//
//  LiquidLightCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

struct LiquidLightParams {
  float time;
  float bass;
  float mid;
  float high;
  float2 simSize;
  float eps;
  float apertureRadius;
  float whiteLevel;
  float4 plate[6];
  float4 ripples[4];
};

struct SeedParams {
  float2 simSize;
  float eps;
  float threshold;
};

struct AdvectParams {
  float2 simSize;
  float2 tilt;
  float frames;
  float time;
  float swirl;
  float press;
  float eps;
  float pad0;
  float pad1;
  float pad2;
  float4 drops[4];
  float4 dropState[4];
};

struct ProbeParams {
  float2 simSize;
  float2 center;
  float2 offset;
  float2 pad;
};

struct RelaxParams {
  float dt;
  float mobility;
  float eps2;
  float acMobility;
};

struct ReduceParams {
  uint tileCount;
  float invCellCount;
};

struct BlurParams {
  float innerRadius;
  float outerRadius;
  float maxBlurRadius;
  float bass;
  float mid;
  float bloomRadius;
  float bloomStrength;
  float whiteLevel;
};

struct FeedbackParams {
  float dt;
  float time;
  float bass;
  uint historyValid;
};

constant float SQRT2 = 1.41421356;

constant float2x2 ROT1 = float2x2( 0.7974,  0.6034, -0.6034,  0.7974);
constant float2x2 ROT2 = float2x2(-0.4161,  0.9093, -0.9093, -0.4161);
constant float2x2 ROT3 = float2x2( 0.2837, -0.9589,  0.9589,  0.2837);

inline float2 liquidCurl(float2 p) {
  const float e = 0.02;
  float dx = shaderSimplex2D(p + float2(e, 0.0)) - shaderSimplex2D(p - float2(e, 0.0));
  float dy = shaderSimplex2D(p + float2(0.0, e)) - shaderSimplex2D(p - float2(0.0, e));
  return float2(dy, -dx) / (2.0 * e);
}

inline float discField(float2 p, float cellSize, float seed, float fillProb,
                       float rMin, float rMax) {
  float2 q = p / cellSize;
  float2 n = floor(q);
  float best = 1e3;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      float2 cell = n + float2(float(i), float(j));
      float2 h = shaderHash22(cell + seed);
      if (h.x > fillProb) continue;
      float r = mix(rMin, rMax, shaderHash21(cell * 1.91 + seed + 4.7));
      float margin = max(0.5 - r / cellSize, 0.0);
      float2 centre = (cell + 0.5 + (h * 2.0 - 1.0) * margin) * cellSize;
      best = min(best, length(p - centre) - r);
    }
  }
  return best;
}

inline float continentField(float2 p, float freq, float threshold, float2 offset) {
  float n = shaderSimplex2D(p * freq + offset)
  + 0.5 * shaderSimplex2D(p * freq * 2.1 + offset * 1.7 + 3.3);
  return (threshold - n) / (freq * 1.6);
}

struct SeedLayer {
  float continentFreq;
  float continentThreshold;
  float discCell;
  float discProb;
  float2 discRadius;
  float holeCell;
  float holeProb;
  float2 holeRadius;
};

inline float seedPhase(float2 p, SeedLayer L, float seed, float simLongSide, float eps) {
  float sd = continentField(p, L.continentFreq, L.continentThreshold, float2(seed, seed * 0.37));
  sd = min(sd, discField(p, L.discCell, seed + 11.0, L.discProb, L.discRadius.x, L.discRadius.y));
  float hole = discField(p, L.holeCell, seed + 23.0, L.holeProb, L.holeRadius.x, L.holeRadius.y);
  sd = max(sd, -hole);
  float sdPx = sd * simLongSide;
  return -tanh(clamp(sdPx, -40.0, 40.0) / (SQRT2 * eps));
}

kernel void liquidSimSeed(texture2d<float, access::write> phaseOut [[texture(0)]],
                          constant SeedParams &params          [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  uint w = phaseOut.get_width();
  uint h = phaseOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float2 size = float2(w, h);
  float longSide = max(size.x, size.y);
  float2 uv = (float2(gid) + 0.5) / size;
  float2 p = (uv - 0.5) * size / longSide;
  float simH = longSide;
  float eps = params.eps;
  
  SeedLayer a = { 1.3, 0.10, 0.11, 0.55, float2(0.014, 0.038), 0.09, 0.40, float2(0.010, 0.026) };
  SeedLayer b = { 1.7, 0.25, 0.14, 0.60, float2(0.020, 0.055), 0.10, 0.30, float2(0.012, 0.030) };
  SeedLayer c = { 1.0, 0.35, 0.08, 0.55, float2(0.009, 0.028), 0.12, 0.25, float2(0.015, 0.040) };
  SeedLayer d = { 1.0, 9.00, 0.17, 0.55, float2(0.030, 0.070), 0.06, 0.45, float2(0.004, 0.011) };
  
  float4 phi;
  phi.x = seedPhase(p, a, 0.0, simH, eps);
  phi.y = seedPhase(ROT3 * p + float2(2.3, 1.1), b, 7.0, simH, eps);
  phi.z = seedPhase(ROT1 * p + float2(5.1, 3.7), c, 13.0, simH, eps);
  phi.w = seedPhase(ROT2 * p + float2(8.7, 0.4), d, 19.0, simH, eps);
  phaseOut.write(phi, gid);
}

constant float4 LAYER_TILT_SCALE  = float4(1.0, 0.74, 0.55, 0.4);
constant float4 LAYER_TILT_ANGLE  = float4(0.0, 0.2, -0.3, 0.45);
constant float4 LAYER_SWIRL_SCALE = float4(1.0, 0.82, 0.68, 0.55);
constant float4 LAYER_PRESS_SCALE = float4(1.0, 0.85, 0.72, 0.6);

inline float2 rotate2(float2 v, float angle) {
  float c = fast::cos(angle), s = fast::sin(angle);
  return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

constant float DROP_RELEASE = 0.3;
constant float DROP_SPREAD_END = 0.85;
constant float RIPPLE_SPEED = 0.10;
constant float RIPPLE_WIDTH = 0.014;

inline float dropRadius(float age, float finalRadius) {
  float r;
  if (age < DROP_RELEASE) {
    r = finalRadius * (0.12 + 0.18 * age / DROP_RELEASE);
  } else {
    float u = saturate((age - DROP_RELEASE) / (DROP_SPREAD_END - DROP_RELEASE));
    r = finalRadius * (0.30 + 0.70 * sqrt(u));
  }
  return max(r, 3.5);
}

inline float ringRadius(float age, float finalRadius, float longSide) {
  float launched = max(0.12 * finalRadius, 3.5) + age * RIPPLE_SPEED * longSide;
  return max(launched, dropRadius(age, finalRadius));
}

inline float rippleWave(float dist, float age, float finalRadius, float longSide) {
  if (age < 0.0) return 0.0;
  float ringR = ringRadius(age, finalRadius, longSide);
  float width = RIPPLE_WIDTH * longSide;
  float s = (dist - ringR) / width;
  float s2 = (dist - ringR + 2.2 * width) / width;
  float wave = s * fast::exp(-s * s) + 0.5 * s2 * fast::exp(-s2 * s2);
  float spread = rsqrt(max(ringR / max(finalRadius, 1.0), 1.0));
  return wave * fast::exp(-age / 1.3) * spread;
}

inline float dropImpactFlow(float dist, float age, float finalRadius, float longSide) {
  float amp = 2.4 * finalRadius / (0.06 * longSide);
  float ripple = rippleWave(dist, age, finalRadius, longSide) * amp * 0.45;
  if (age < DROP_RELEASE) return ripple;
  float front = dropRadius(age, finalRadius);
  float sf = (dist - front) / max(0.5 * finalRadius, 2.0);
  float frontFlow = 0.8 * fast::exp(-sf * sf) * step(0.4 * front, dist)
                  * (1.0 - smoothstep(DROP_SPREAD_END - 0.15, DROP_SPREAD_END, age));
  float t = max(age - DROP_SPREAD_END + 0.15, 0.0);
  float sr = dist / (finalRadius * 1.7);
  float recoil = 2.0 * sr * fast::exp(-sr * sr) * 0.2 * fast::exp(-t / 0.8) * -fast::cos(t * 7.0)
               * smoothstep(0.0, 0.2, t);
  return (frontFlow + recoil) * amp + ripple;
}

inline float dropSwellFlow(float dist, float age, float finalRadius, float longSide) {
  if (age < DROP_RELEASE) return 0.0;
  float amp = 2.4 * finalRadius / (0.06 * longSide);
  float s = dist / (3.0 * finalRadius);
  float envelope = smoothstep(DROP_RELEASE, DROP_RELEASE + 0.15, age)
                 * (age < DROP_SPREAD_END ? 1.0 : fast::exp(-(age - DROP_SPREAD_END) / 0.5));
  return 0.5 * amp * s * fast::exp(-s * s) * 1.65 * envelope;
}

kernel void liquidSimAdvect(texture2d<float, access::sample> phaseIn  [[texture(0)]],
                            texture2d<float, access::write>  phaseOut [[texture(1)]],
                            constant AdvectParams &params            [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = phaseOut.get_width();
  uint h = phaseOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  constexpr sampler bilinear(filter::linear, address::mirrored_repeat);
  float2 size = params.simSize;
  float2 px = float2(gid) + 0.5;
  float2 uv = px / size;
  float longSide = max(size.x, size.y);
  float2 p = (uv - 0.5) * size / longSide;
  
  float2 pushVel = float2(0.0);
  for (int i = 0; i < 4; i++) {
    float4 st = params.dropState[i];
    if (st.w < 0.5) continue;
    float2 dropPx = params.drops[i].xy * longSide + size * 0.5;
    float2 toHere = px - dropPx;
    float d = length(toHere);
    float2 dir = d > 1e-3 ? toHere / d : float2(0.0);
    pushVel += dir * dropImpactFlow(d, st.z, st.x, longSide);
  }
  pushVel *= params.frames;
  
  float4 result = float4(0.0);
  for (int k = 0; k < 4; k++) {
    float2 tilt = rotate2(params.tilt, LAYER_TILT_ANGLE[k]) * LAYER_TILT_SCALE[k];
    float2 swirlCoord = p * 1.1 + params.time * 0.03 + float2(3.1, 1.7) * float(k);
    float2 swirl = liquidCurl(swirlCoord)
    + 0.15 * liquidCurl(p * 2.6 - params.time * 0.05 + float2(1.3, 6.2) * float(k));
    swirl *= params.swirl * LAYER_SWIRL_SCALE[k];
    float2 press = p * params.press * LAYER_PRESS_SCALE[k];

    float2 swell = float2(0.0);
    for (int i = 0; i < 4; i++) {
      float4 st = params.dropState[i];
      if (st.w < 0.5 || st.y < 0.0 || int(params.drops[i].w + 0.5) != k) continue;
      float2 dropPx = params.drops[i].xy * longSide + size * 0.5;
      float2 toHere = px - dropPx;
      float d = length(toHere);
      float2 dir = d > 1e-3 ? toHere / d : float2(0.0);
      swell += dir * dropSwellFlow(d, st.z, st.x, longSide) * st.w;
    }
    
    float2 vel = (tilt + swirl) * params.frames + press + pushVel + swell * params.frames;
    float2 srcUV = (px - vel) / size;
    float phi = sampleCatmullRom(phaseIn, bilinear, srcUV, size)[k];
    result[k] = clamp(phi, -1.0, 1.0);
  }
  
  for (int i = 0; i < 4; i++) {
    float4 st = params.dropState[i];
    if (st.w < 0.5 || st.z > DROP_SPREAD_END) continue;
    int layer = int(params.drops[i].w + 0.5);
    float2 dropPx = params.drops[i].xy * longSide + size * 0.5;
    float d = length(px - dropPx);
    float blob = tanh((dropRadius(st.z, st.x) - d) / (SQRT2 * params.eps));
    if (st.y > 0.0) {
      result[layer] = max(result[layer], blob);
    } else {
      result = min(result, float4(-blob));
    }
  }
  
  phaseOut.write(result, gid);
}

kernel void liquidSimProbe(texture2d<float, access::sample> phase [[texture(0)]],
                           device float4 *probe                   [[buffer(1)]],
                           constant ProbeParams &params           [[buffer(0)]],
                           uint tid [[thread_position_in_grid]]) {
  if (tid >= 5) return;
  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 offsets[5] = { float2(0.0), float2(1.0, 0.0), float2(-1.0, 0.0),
                        float2(0.0, 1.0), float2(0.0, -1.0) };
  float2 p = params.center + offsets[tid] * params.offset;
  float longSide = max(params.simSize.x, params.simSize.y);
  float2 uv = p * longSide / params.simSize + 0.5;
  probe[tid] = phase.sample(bilinear, uv);
}

kernel void liquidSimResample(texture2d<float, access::sample> phaseIn  [[texture(0)]],
                              texture2d<float, access::write>  phaseOut [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
  uint w = phaseOut.get_width();
  uint h = phaseOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 inSize = float2(phaseIn.get_width(), phaseIn.get_height());
  float4 phi = sampleCatmullRom(phaseIn, bilinear, uv, inSize);
  phaseOut.write(clamp(phi, -1.0, 1.0), gid);
}

inline float4 phaseAt(texture2d<float, access::read> t, int2 c, int2 maxC) {
  return t.read(uint2(clamp(c, int2(0), maxC)));
}

inline float4 chemicalPotential(texture2d<float, access::read> t, int2 c, int2 maxC, float eps2) {
  float4 phi = phaseAt(t, c, maxC);
  float4 lap = phaseAt(t, c + int2(1, 0), maxC) + phaseAt(t, c - int2(1, 0), maxC)
  + phaseAt(t, c + int2(0, 1), maxC) + phaseAt(t, c - int2(0, 1), maxC)
  - 4.0 * phi;
  return phi * phi * phi - phi - eps2 * lap;
}

kernel void liquidSimReduceTiles(texture2d<float, access::read> phase [[texture(0)]],
                                 device float4 *tiles                 [[buffer(1)]],
                                 uint2 gid       [[thread_position_in_grid]],
                                 uint2 tgid      [[threadgroup_position_in_grid]],
                                 uint2 tgCount   [[threadgroups_per_grid]],
                                 uint  tid       [[thread_index_in_threadgroup]],
                                 uint  simdLane  [[thread_index_in_simdgroup]],
                                 uint  simdIndex [[simdgroup_index_in_threadgroup]],
                                 uint  simdCount [[simdgroups_per_threadgroup]]) {
  threadgroup float4 partial[16];
  
  float4 v = float4(0.0);
  if (gid.x < phase.get_width() && gid.y < phase.get_height()) {
    float4 phi = phase.read(gid);
    v = phi * phi * phi - phi;
  }
  v = simd_sum(v);
  if (simdLane == 0) partial[simdIndex] = v;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  
  if (tid == 0) {
    float4 s = float4(0.0);
    for (uint i = 0; i < simdCount; i++) s += partial[i];
    tiles[tgid.y * tgCount.x + tgid.x] = s;
  }
}

kernel void liquidSimReduceFinal(device const float4 *tiles  [[buffer(1)]],
                                 device float4 *lambda        [[buffer(2)]],
                                 constant ReduceParams &params [[buffer(0)]],
                                 uint tid       [[thread_index_in_threadgroup]],
                                 uint simdLane  [[thread_index_in_simdgroup]],
                                 uint simdIndex [[simdgroup_index_in_threadgroup]],
                                 uint simdCount [[simdgroups_per_threadgroup]]) {
  threadgroup float4 partial[16];
  
  float4 s = float4(0.0);
  for (uint i = tid; i < params.tileCount; i += 256u) s += tiles[i];
  s = simd_sum(s);
  if (simdLane == 0) partial[simdIndex] = s;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  
  if (tid == 0) {
    float4 total = float4(0.0);
    for (uint i = 0; i < simdCount; i++) total += partial[i];
    lambda[0] = total * params.invCellCount;
  }
}

kernel void liquidSimRelax(texture2d<float, access::read>  phaseIn  [[texture(0)]],
                           texture2d<float, access::write> phaseOut [[texture(1)]],
                           constant RelaxParams &params            [[buffer(0)]],
                           device const float4 *lambda             [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
  int w = int(phaseOut.get_width());
  int h = int(phaseOut.get_height());
  if (int(gid.x) >= w || int(gid.y) >= h) return;
  
  int2 c = int2(gid);
  int2 maxC = int2(w - 1, h - 1);
  float eps2 = params.eps2;
  
  float4 muC = chemicalPotential(phaseIn, c, maxC, eps2);
  float4 lapMu = chemicalPotential(phaseIn, c + int2(1, 0), maxC, eps2)
  + chemicalPotential(phaseIn, c - int2(1, 0), maxC, eps2)
  + chemicalPotential(phaseIn, c + int2(0, 1), maxC, eps2)
  + chemicalPotential(phaseIn, c - int2(0, 1), maxC, eps2)
  - 4.0 * muC;
  
  float4 dphi = params.mobility * lapMu + params.acMobility * (lambda[0] - muC);
  float4 phi = phaseIn.read(gid) + params.dt * dphi;
  phaseOut.write(clamp(phi, -1.05, 1.05), gid);
}

struct DyeLayer {
  float coverage;
  float body;
  float rim;
  float fringe;
  float shadow;
  float lit;
  float ndl;
};

inline DyeLayer resolveLayer(float phi, float phiShadowNear, float phiShadowFar,
                             float2 gradPx, float eps, float simLongSide, float pixel,
                             float rimWidth, float3 lightDir) {
  float c = clamp(phi, -0.995, 0.995);
  float sdPx = SQRT2 * eps * 0.5 * log((1.0 + c) / (1.0 - c));
  float inside = sdPx / simLongSide;
  
  DyeLayer L;
  L.coverage = smoothstep(-pixel, pixel, inside);
  L.body = smoothstep(0.0, 0.9, phi);
  float edge = fast::exp(-inside / rimWidth * 1.6);
  L.rim = L.coverage * saturate((edge - 0.1) / 0.9);
  L.fringe = L.coverage
  * smoothstep(rimWidth * 0.5, rimWidth * 1.0, inside)
  * (1.0 - smoothstep(rimWidth * 1.3, rimWidth * 2.6, inside));
  float near = smoothstep(-0.7, 0.7, phiShadowNear);
  float far = smoothstep(-0.7, 0.7, phiShadowFar);
  L.shadow = (0.6 * near + 0.4 * far) * (1.0 - L.coverage);
  
  float gradLen = max(length(gradPx), 1e-4);
  float2 outward = -gradPx / gradLen;
  L.lit = saturate(dot(outward, normalize(lightDir.xy)) * 0.5 + 0.5);
  float3 nrm = fast::normalize(float3(-gradPx * 3.5, 1.0));
  L.ndl = saturate(dot(nrm, lightDir));
  return L;
}

inline float vnoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  float2 u = f * f * (3.0 - 2.0 * f);
  float a = shaderHash21(i);
  float b = shaderHash21(i + float2(1.0, 0.0));
  float c = shaderHash21(i + float2(0.0, 1.0));
  float d = shaderHash21(i + float2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

inline float3 highlightRolloff(float3 c, float white) {
  float range = max(white - 1.0, 1e-4);
  return saturate(c) + range * (1.0 - exp(-max(c - 1.0, 0.0) / range));
}

inline float3 agedFilm(float3 c, float white) {
  c *= float3(1.05, 0.98, 0.80);
  c = c * (1.0 + c * (1.0 / 1.44)) / (1.0 + c);
  float l = dot(c, float3(0.299, 0.587, 0.114));
  c = mix(c, float3(l), 0.1);
  c = c * 0.94 + float3(0.055, 0.04, 0.018);
  c += (l - 0.5) * float3(0.03, 0.015, -0.03);
  return highlightRolloff(c, white);
}

inline float glassDust(float2 pxPos) {
  float2 cell = floor(pxPos / 46.0);
  float2 h = shaderHash22(cell + 31.7);
  if (h.x > 0.14) return 0.0;
  float2 centre = (cell + 0.2 + 0.6 * shaderHash22(cell + 9.1)) * 46.0;
  float radius = 1.2 + h.y * 2.2;
  float d = length(pxPos - centre);
  float speck = 1.0 - smoothstep(radius - 1.0, radius + 1.0, d);
  float bubble = step(0.09, h.x) * (1.0 - smoothstep(0.0, radius * 0.6, d));
  return speck * (0.55 - 0.9 * bubble);
}

kernel void liquidLightRender(texture2d<float, access::write>  output [[texture(0)]],
                              texture2d<float, access::sample> phase  [[texture(1)]],
                              constant LiquidLightParams &params      [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float longSide = max(size.x, size.y);
  float2 uv = (float2(gid) + 0.5) / size;
  float2 p = (uv - 0.5) * size / longSide;
  float pixel = 1.4 / longSide;
  float time = params.time;
  
  float R = params.apertureRadius;
  float circ = fast::length(p);
  float2 radial = circ > 1e-4 ? p / circ : float2(0.0);
  const float groovePitch = 0.0045;
  float grooves = sin(6.2831853 * fract(circ / groovePitch));
  
  float2 rippleDisp = float2(0.0);
  float caustic = 0.0;
  for (int i = 0; i < 4; i++) {
    float4 rp = params.ripples[i];
    if (rp.z < 0.0) continue;
    float2 toHere = p - rp.xy;
    float d = fast::length(toHere);
    float2 dir = d > 1e-4 ? toHere / d : float2(0.0);
    float wave = rippleWave(d * longSide, rp.z, rp.w * longSide, longSide);
    float ahead = rippleWave((d + 0.004) * longSide, rp.z, rp.w * longSide, longSide);
    float strength = rp.w / 0.06;
    rippleDisp += dir * wave * 0.003 * strength;
    caustic += (ahead - wave) * 1.0 * strength;
  }
  
  float2 shimmer = float2(vnoise(p * 6.0 + time * 1.5),
                          vnoise(p * 6.0 + float2(3.1, 7.4) - time * 1.3)) * 0.0012
                 + radial * grooves * 0.00035
                 + rippleDisp;
  float2 suv = uv + shimmer * longSide / size;
  
  float2 simSize = params.simSize;
  float2 texel = 1.0 / simSize;
  float4 phi = sampleCatmullRom(phase, bilinear, suv, simSize);
  float4 gx = (phase.sample(bilinear, suv + float2(texel.x, 0.0))
               - phase.sample(bilinear, suv - float2(texel.x, 0.0))) * 0.5;
  float4 gy = (phase.sample(bilinear, suv + float2(0.0, texel.y))
               - phase.sample(bilinear, suv - float2(0.0, texel.y))) * 0.5;
  
  const float3 lightDir = float3(-0.42, -0.55, 0.722);
  float2 shadowDir = -normalize(lightDir.xy);
  float rimWidth = 0.003 + params.bass * 0.0006;
  float mottle = vnoise(p * 9.0 + time * 0.05) * 0.5
  + vnoise(p * 23.0 - time * 0.03) * 0.25;
  
  DyeLayer layers[4];
  for (int k = 0; k < 4; k++) {
    float2 offset = shadowDir * (0.004 + 0.003 * float(k)) * longSide / size;
    float phiNear = phase.sample(bilinear, suv - offset * 0.5)[k];
    float phiFar = phase.sample(bilinear, suv - offset)[k];
    layers[k] = resolveLayer(phi[k], phiNear, phiFar, float2(gx[k], gy[k]),
                             params.eps, max(simSize.x, simSize.y), pixel, rimWidth, lightDir);
  }
  
  float3 T = float3(1.0);
  float3 additive = float3(0.0);
  float covSum = 0.0;
  float spec = 0.0;
  float gaps = 1.0;
  for (int k = 0; k < 4; k++) {
    DyeLayer L = layers[k];
    float3 dye = params.plate[k].rgb;

    float thickness = 0.85 + 0.25 * L.body + 0.15 * mottle;
    float3 dyeT = pow(dye, max(thickness, 0.3));
    T *= mix(float3(1.0), dyeT, L.coverage);

    float3 deep = dye * dye * 0.7;
    T *= mix(float3(1.0), deep, L.rim * (0.8 - 0.25 * L.lit));
    T *= 1.0 + L.fringe * (0.06 + 0.12 * L.lit);
    T *= mix(float3(1.0), dye * 0.55 + 0.1, L.shadow * (0.5 + 0.1 * float(k)));
    
    float sheen = L.ndl * L.ndl * L.ndl;
    sheen *= sheen;
    float hot = sheen * sheen * sheen * sheen * sheen * sheen * sheen * sheen;
    float above = 1.0;
    for (int j = k + 1; j < 4; j++) above *= 1.0 - layers[j].coverage * 0.7;
    spec += (sheen * 0.04 + hot * 0.22) * L.coverage * (1.0 - L.rim) * above;
    
    additive += dye * L.coverage;
    covSum += L.coverage;
    gaps *= 1.0 - L.coverage;
  }
  
  float4 water = params.plate[4];
  T *= mix(float3(1.0), water.rgb, water.w * gaps);

  float beam = 1.0 - smoothstep(R - 0.010, R + 0.003, circ);
  float rimward = smoothstep(R * 0.45, R, circ);
  float3 lamp = params.plate[5].rgb;
  lamp = mix(lamp, lamp * float3(1.0, 0.78, 0.50) * 0.8, rimward);
  float hotspot = fast::exp(-circ * circ / (R * R) * 2.2);
  float flicker = 1.0 + 0.012 * fast::sin(time * 37.0) + 0.012 * vnoise(float2(time * 9.0, 0.5));
  lamp *= (1.0 + hotspot * 0.14 + params.bass * 0.10) * flicker;

  float sheet2 = sin(6.2831853 * fract(length(p - float2(0.011, -0.007)) / (groovePitch * 1.012)));
  float fresnel = 1.0 + grooves * (0.012 + 0.035 * rimward) + grooves * sheet2 * 0.02;
  lamp *= fresnel * (1.0 + clamp(caustic, -0.35, 0.5));

  float lumaT = dot(T, float3(0.333));
  float3 scatter = covSum > 0.0 ? additive / max(covSum, 1.0) : float3(0.0);
  float3 result = lamp * (T + 0.2 * scatter * (1.0 - lumaT)) + lamp * spec;
  
  result *= 1.0 - glassDust(float2(gid) * 1.333);
  
  float weave = vnoise(float2(gid) * 0.33) * 0.015 + vnoise(float2(gid) * 0.09) * 0.012;
  result *= 1.0 + weave;
  result += params.plate[5].rgb * 0.03;
  
  result = agedFilm(result, params.whiteLevel);
  
  float grain = shaderHash21(float2(gid) + fract(time * 13.7) * 97.0) - 0.5;
  result += grain * 0.02;
  
  float flare = fast::exp(-max(circ - R, 0.0) * 60.0) * (1.0 - beam) * 0.05;
  result = result * beam + params.plate[5].rgb * flare;
  
  output.write(float4(clamp(result, 0.0, params.whiteLevel), 1.0), gid);
}

kernel void liquidLightFeedback(texture2d<float, access::read>   render     [[texture(0)]],
                                texture2d<float, access::sample> historyIn  [[texture(1)]],
                                texture2d<float, access::write>  historyOut [[texture(2)]],
                                constant FeedbackParams &params            [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
  uint w = historyOut.get_width();
  uint h = historyOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float4 current = render.read(gid);
  if (params.historyValid == 0u) {
    historyOut.write(current, gid);
    return;
  }
  
  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 size = float2(w, h);
  float3 previous = max(sampleCatmullRom(historyIn, bilinear, uv, size).rgb, 0.0);

  float retention60 = 0.45 - params.bass * 0.15;
  float retention = pow(saturate(retention60), params.dt * 60.0);
  
  float3 blended = mix(current.rgb, previous, retention);
  historyOut.write(float4(blended, 1.0), gid);
}

constant float4 BLUR_SAMPLES[16] = {
  float4( 0.697581f,  0.716505f, 0.176777f, 0.992218f),
  float4(-0.840742f, -0.541437f, 0.306186f, 0.931558f),
  float4( 0.211276f, -0.977432f, 0.395285f, 0.824084f),
  float4( 0.642915f,  0.765938f, 0.467707f, 0.680319f),
  float4(-0.999893f, -0.014610f, 0.529150f, 0.522046f),
  float4( 0.758020f, -0.652232f, 0.583095f, 0.371577f),
  float4(-0.119523f,  0.992831f, 0.631614f, 0.243117f),
  float4(-0.582199f, -0.813048f, 0.676123f, 0.144862f),
  float4( 0.970273f,  0.242007f, 0.717137f, 0.078662f),
  float4(-0.813781f,  0.581171f, 0.755190f, 0.038988f),
  float4( 0.274818f, -0.961502f, 0.790569f, 0.017639f),
  float4( 0.478860f,  0.877891f, 0.823754f, 0.007262f),
  float4(-0.988253f,  0.152809f, 0.854990f, 0.002714f),
  float4( 0.865665f, -0.500622f, 0.884529f, 0.000921f),
  float4(-0.329257f,  0.944240f, 0.912576f, 0.000283f),
  float4(-0.406217f,  0.913776f, 0.939150f, 0.000079f),
};

constant int BLUR_TAPS = 12;

kernel void liquidGlassBlur(texture2d<float, access::read>  input   [[texture(0)]],
                            texture2d<float, access::write> output  [[texture(1)]],
                            constant BlurParams &params             [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  const int w = int(input.get_width());
  const int h = int(input.get_height());
  if (int(gid.x) >= w || int(gid.y) >= h) return;
  
  const int2 maxXY = int2(w - 1, h - 1);
  const half4 sharp_h = half4(clamp(input.read(gid), 0.0, params.whiteLevel));
  
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 norm = (uv - 0.5) * 2.0;
  float dist = length(norm);
  
  float dynamicInner = params.innerRadius - params.bass * 0.15;
  float dynamicOuter = params.outerRadius - params.bass * 0.1;
  dynamicOuter = max(dynamicOuter, dynamicInner + 0.01);
  
  float blurStrength = smoothstep(dynamicInner, dynamicOuter, dist);
  blurStrength *= blurStrength;

  float radius = params.bloomRadius + blurStrength * params.maxBlurRadius * (1.0 + params.bass * 0.3);
  
  float rndAngle = fract(sin(dot(float2(gid), float2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
  float rc = fast::cos(rndAngle), rs = fast::sin(rndAngle);
  
  half4 accum = half4(0.0h);
  half  totalWeight = 0.0h;
  
  const int2 centeri = int2(gid);
  for (int i = 0; i < BLUR_TAPS; i++) {
    float4 s = BLUR_SAMPLES[i];
    float2 o = float2(s.x * rc - s.y * rs, s.x * rs + s.y * rc);
    float2 offset = o * (s.z * radius);
    
    int2 sp = clamp(centeri + int2(round(offset)), int2(0), maxXY);
    
    half weight = half(s.w);
    accum += half4(input.read(uint2(sp))) * weight;
    totalWeight += weight;
  }
  
  half4 blurred_h = accum / max(totalWeight, 1e-4h);
  half4 result_h = mix(sharp_h, blurred_h, half(blurStrength));
  
  half3 bloom = max(blurred_h.rgb - 0.55h, 0.0h) * half(params.bloomStrength);
  result_h.rgb += bloom;
  
  float rimCA = smoothstep(0.35, 1.3, dist);
  if (rimCA > 0.01) {
    float2 radialDir = dist > 1e-4 ? norm / dist : float2(1.0, 0.0);
    float shift = 1.0 + rimCA * 2.5;
    int2 offR = clamp(centeri + int2(round(radialDir * shift)), int2(0), maxXY);
    int2 offB = clamp(centeri - int2(round(radialDir * shift)), int2(0), maxXY);
    half rCh = half(input.read(uint2(offR)).r);
    half bCh = half(input.read(uint2(offB)).b);
    half mixAmt = half(rimCA * 0.6);
    result_h.r = mix(result_h.r, rCh, mixAmt);
    result_h.b = mix(result_h.b, bCh, mixAmt);
  }
  
  half luma = dot(result_h.rgb, half3(0.2126h, 0.7152h, 0.0722h));
  half desatAmount = half(blurStrength * max(0.12 - params.mid * 0.1, 0.03));
  result_h.rgb = mix(result_h.rgb, half3(luma), desatAmount);
  
  float3 encoded = highlightRolloff(float3(result_h.rgb), params.whiteLevel);
  float3 linear = mix(encoded / 12.92, pow((encoded + 0.055) / 1.055, 2.4), step(0.04045, encoded));
  output.write(float4(linear, 1.0), gid);
}
