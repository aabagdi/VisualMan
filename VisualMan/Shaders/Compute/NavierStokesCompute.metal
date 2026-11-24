//
//  NavierStokesCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
#include "../Utilities/ShaderUtils.h"
using namespace metal;

struct SplatParams {
  float2 position;
  float radius;
  float _pad;
  float3 value;
  float weight;
  float2 clumpOffset;
  float3 clumpValue;
};

struct SplatBatchParams {
  uint velocityMode;
  float clumping;
  float clumpScale;
  float clumpHue;
};

struct FrameUniforms {
  float bass;
  float mid;
  float high;
  float time;
  float dt;
  float taaBlend;
  uint  historyValid;
  float bloom;
  float shading;
  float detail;
  float jitter;
  float thinFade;
  float technicolorPresence;
  float technicolorNeutralReach;
  float technicolorLampGain;
  float technicolorCeiling;
  float4 technicolorTheme;
  float4 technicolorMisregistration;
  float4 technicolorMisregistrationWarp;
  float4 technicolorGateWeave;
  float4 technicolorGateJump;
  float4 technicolorHalation;
  float4 technicolorGrain;
  float4 technicolorDepth;
};

inline float2 sampleFaceVelocity(texture2d<float, access::sample> velocity, sampler s,
                                 float2 pos, float2 size) {
  float u = velocity.sample(s, (pos + float2(0.5, 0.0)) / size).x * saturate(size.x - pos.x);
  float v = velocity.sample(s, (pos + float2(0.0, 0.5)) / size).y * saturate(size.y - pos.y);
  return float2(u, v);
}

inline float2 sampleTraceVelocity(texture2d<float, access::sample> velocity, sampler s,
                                  float2 pos, float2 size, bool staggered) {
  return staggered ? sampleFaceVelocity(velocity, s, pos, size) : velocity.sample(s, pos / size).xy;
}

inline float2 traceVelocity(texture2d<float, access::sample> velocity, sampler s,
                            float2 pos, float2 size, float dt, float2 limits, bool staggered) {
  float2 k1 = sampleTraceVelocity(velocity, s, pos, size, staggered);
  float steps = clamp(ceil(length(k1) * abs(dt) / limits.x), 1.0, limits.y);
  float h = dt / steps;
  for (int i = 0; i < int(steps); i++) {
    if (i > 0) k1 = sampleTraceVelocity(velocity, s, pos, size, staggered);
    float2 k2 = sampleTraceVelocity(velocity, s, pos + 0.5 * h * k1, size, staggered);
    float2 k3 = sampleTraceVelocity(velocity, s, pos + 0.5 * h * k2, size, staggered);
    float2 k4 = sampleTraceVelocity(velocity, s, pos + h * k3, size, staggered);
    pos += h * (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0;
  }
  return pos;
}

inline float faceDivergence(texture2d<float, access::read> velocity, uint2 gid, uint w, uint h) {
  float2 c = velocity.read(gid).xy;
  if (gid.x == 0u) c.x = 0;
  if (gid.y == 0u) c.y = 0;
  float uR = (gid.x + 1u < w) ? velocity.read(uint2(gid.x + 1u, gid.y)).x : 0.0;
  float vU = (gid.y + 1u < h) ? velocity.read(uint2(gid.x, gid.y + 1u)).y : 0.0;
  return uR - c.x + vU - c.y;
}

inline float4 subtractPressureGradient(float4 vel, float pC, float pL, float pB, uint2 gid,
                                       float maxSpeed) {
  vel.x -= pC - pL;
  vel.y -= pC - pB;

  if (gid.x == 0u) vel.x = 0;
  if (gid.y == 0u) vel.y = 0;

  if (any(isnan(vel.xy)) || any(isinf(vel.xy))) vel.xy = float2(0);
  float sp = fast::length(vel.xy);
  if (sp > maxSpeed) vel.xy *= maxSpeed / sp;
  return vel;
}

inline float emitterClumps(float2 p) {
  return smoothstep(-0.7, 0.7, shaderSimplex2D(p));
}

kernel void fluidSplatBatch(texture2d<float, access::read_write> field [[texture(0)]],
                            constant SplatParams *splats [[buffer(0)]],
                            constant uint &splatCount [[buffer(1)]],
                            constant uint2 &regionOrigin [[buffer(2)]],
                            constant SplatBatchParams &batch [[buffer(3)]],
                            uint2 tid [[thread_position_in_grid]]) {
  uint2 gid = tid + regionOrigin;
  uint w = field.get_width();
  uint h = field.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 pos = float2(gid) + 0.5;

  float4 current = field.read(gid);
  bool anyHit = false;
  for (uint i = 0; i < splatCount; i++) {
    float2 diff = pos - splats[i].position;
    float dist2 = dot(diff, diff);
    float r2 = splats[i].radius * splats[i].radius;
    if (dist2 >= 6.0 * r2) continue;
    anyHit = true;
    float falloff = fast::exp(-dist2 / r2);
    if (batch.velocityMode != 0u) {
      float2 faceDist2 = dist2 - diff + 0.25;
      float2 weight = min(fast::exp(-faceDist2 / r2) * splats[i].value.z, 1.0);
      current.xy = mix(current.xy, splats[i].value.xy, weight);
    } else {
      float2 clumpPos = (pos - splats[i].clumpOffset) * batch.clumpScale;
      float pattern = emitterClumps(clumpPos);
      float fill = 1.0 - batch.clumping * pattern;
      float lean = smoothstep(0.55, 0.7, pattern) * batch.clumpHue;
      float3 clumpDye = splats[i].clumpValue;
      clumpDye -= min(clumpDye.x, min(clumpDye.y, clumpDye.z));
      float3 dye = mix(splats[i].value, clumpDye, lean);
      float4 added = current + float4(dye, splats[i].weight) * (falloff * fill);
      float cap = 1.5 * fill;
      float3 proportions = clumpDye / max(max(clumpDye.x, max(clumpDye.y, clumpDye.z)), 1e-6);
      float3 dyeCap = cap * mix(float3(1.0), proportions, lean);
      current.xyz = max(current.xyz, min(added.xyz, dyeCap));
      current.w = (splats[i].weight >= 0.0) ? max(current.w, min(added.w, cap))
                                            : min(current.w, max(added.w, -cap));
    }
  }
  if (!anyHit) return;
  if (batch.velocityMode == 0u) {
    current.xyz = min(current.xyz, float3(1.5));
    current.w = clamp(current.w, -1.5, 1.5);
  }
  field.write(current, gid);
}

kernel void fluidTentFilter(texture2d<float, access::sample> src [[texture(0)]],
                            texture2d<float, access::write> dst [[texture(1)]],
                            constant float &tapStep [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = dst.get_width();
  uint h = dst.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 stepUV = tapStep / float2(src.get_width(), src.get_height());

  float4 sum = float4(0.0);
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 4; i++) {
      float weight = ((i == 0 || i == 3) ? 0.125 : 0.375) * ((j == 0 || j == 3) ? 0.125 : 0.375);
      sum += weight * src.sample(linearSampler, uv + (float2(i, j) - 1.5) * stepUV);
    }
  }
  dst.write(sum, gid);
}

kernel void fluidDivergence(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::write> divergenceOut [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float div = faceDivergence(velocity, gid, w, h);
  divergenceOut.write(float4(-div, 0, 0, 0), gid);
}

kernel void fluidJacobiMerged(texture2d<float, access::read_write> pressure [[texture(0)]],
                              texture2d<float, access::read> divergence [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]],
                              uint2 tid [[thread_position_in_threadgroup]],
                              uint2 tgid [[threadgroup_position_in_grid]]) {
  constexpr uint TILE = 18;
  threadgroup float p_tile[TILE * TILE];

  uint w = pressure.get_width();
  uint h = pressure.get_height();

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    uint tx = idx % TILE;
    uint ty = idx / TILE;
    int gx = clamp(tileOriginX + int(tx), 0, int(w) - 1);
    int gy = clamp(tileOriginY + int(ty), 0, int(h) - 1);
    p_tile[idx] = pressure.read(uint2(gx, gy)).x;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  uint localX = tid.x + 1;
  uint localY = tid.y + 1;
  uint myIdx = localY * TILE + localX;

  uint2 gidClamped = uint2(min(gid.x, w - 1), min(gid.y, h - 1));
  float d = divergence.read(gidClamped).x;
  bool isRed = ((gid.x + gid.y) & 1u) == 0u;

  if (isRed) {
    float pL = p_tile[myIdx - 1];
    float pR = p_tile[myIdx + 1];
    float pD = p_tile[myIdx - TILE];
    float pU = p_tile[myIdx + TILE];
    p_tile[myIdx] = (pL + pR + pD + pU + d) * 0.25;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (!isRed) {
    float pL = p_tile[myIdx - 1];
    float pR = p_tile[myIdx + 1];
    float pD = p_tile[myIdx - TILE];
    float pU = p_tile[myIdx + TILE];
    p_tile[myIdx] = (pL + pR + pD + pU + d) * 0.25;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x < w && gid.y < h) {
    pressure.write(float4(p_tile[myIdx], 0, 0, 0), gid);
  }
}

kernel void fluidGradientSubtract(texture2d<float, access::read> pressure [[texture(0)]],
                                  texture2d<float, access::read_write> velocity [[texture(1)]],
                                  constant float &maxSpeed [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  uint w = pressure.get_width();
  uint h = pressure.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 down = uint2(gid.x, max(int(gid.y) - 1, 0));

  float pC = pressure.read(gid).x;
  float pL = pressure.read(left).x;
  float pB = pressure.read(down).x;

  velocity.write(subtractPressureGradient(velocity.read(gid), pC, pL, pB, gid, maxSpeed), gid);
}

constant half blurWeights[9] = { 0.026h, 0.066h, 0.121h, 0.176h, 0.222h, 0.176h, 0.121h, 0.066h, 0.026h };

kernel void fluidBlurH(texture2d<half, access::read> fieldIn [[texture(0)]],
                       texture2d<half, access::write> fieldOut [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tid [[thread_position_in_threadgroup]],
                       uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();

  constexpr uint TILE_W = 24;
  threadgroup half4 tile[TILE_W * 16];

  int tileOriginX = int(tgid.x * 16) - 4;
  int tileOriginY = int(tgid.y * 16);

  uint localIdx = tid.y * 16 + tid.x;
  if (localIdx < TILE_W * 16) {
    uint tileX = localIdx % TILE_W;
    uint tileY = localIdx / TILE_W;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[localIdx] = fieldIn.read(uint2(gx, gy));
  }
  uint secondIdx = localIdx + 256;
  if (secondIdx < TILE_W * 16) {
    uint tileX = secondIdx % TILE_W;
    uint tileY = secondIdx / TILE_W;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[secondIdx] = fieldIn.read(uint2(gx, gy));
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  half4 sum = half4(0.0h);
  for (int i = -4; i <= 4; i++) {
    uint tileCol = uint(int(tid.x) + 4 + i);
    sum += tile[tid.y * TILE_W + tileCol] * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

kernel void fluidBlurV(texture2d<half, access::read> fieldIn [[texture(0)]],
                       texture2d<half, access::write> fieldOut [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tid [[thread_position_in_threadgroup]],
                       uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();

  constexpr uint TILE_H = 24;
  threadgroup half4 tile[16 * TILE_H];

  int tileOriginX = int(tgid.x * 16);
  int tileOriginY = int(tgid.y * 16) - 4;

  uint localIdx = tid.y * 16 + tid.x;
  if (localIdx < 16 * TILE_H) {
    uint tileX = localIdx % 16;
    uint tileY = localIdx / 16;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[localIdx] = fieldIn.read(uint2(gx, gy));
  }
  uint secondIdx = localIdx + 256;
  if (secondIdx < 16 * TILE_H) {
    uint tileX = secondIdx % 16;
    uint tileY = secondIdx / 16;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[secondIdx] = fieldIn.read(uint2(gx, gy));
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  half4 sum = half4(0.0h);
  for (int i = -4; i <= 4; i++) {
    uint tileRow = uint(int(tid.y) + 4 + i);
    sum += tile[tileRow * 16 + tid.x] * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

inline half3 bloomThresholdSample(half4 color, half threshold) {
  half amount = max(color.r, max(color.g, color.b));
  half contrib = max(amount - threshold, 0.0h);
  half factor = contrib / max(amount, 1e-4h);
  return color.rgb * factor;
}

kernel void fluidBloomThresholdBlurH(texture2d<half, access::sample> dye [[texture(0)]],
                                     texture2d<half, access::write> bloomOut [[texture(1)]],
                                     constant float &thresholdF [[buffer(0)]],
                                     uint2 gid [[thread_position_in_grid]],
                                     uint2 tid [[thread_position_in_threadgroup]],
                                     uint2 tgid [[threadgroup_position_in_grid]]) {
  uint bw = bloomOut.get_width();
  uint bh = bloomOut.get_height();

  constexpr uint TILE_W = 24;
  threadgroup half4 tile[TILE_W * 16];

  int tileOriginX = int(tgid.x * 16) - 4;
  int tileOriginY = int(tgid.y * 16);

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 invBloom = 1.0 / float2(bw, bh);
  half threshold = half(thresholdF);

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE_W * 16; idx += 256) {
    uint tileX = idx % TILE_W;
    uint tileY = idx / TILE_W;
    float2 uv = (float2(float(tileOriginX + int(tileX)) + 0.5,
                        float(tileOriginY + int(tileY)) + 0.5)) * invBloom;
    half4 c = dye.sample(bilinear, uv);
    tile[idx] = half4(bloomThresholdSample(c, threshold), 0.0h);
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (gid.x >= bw || gid.y >= bh) return;

  half4 sum = half4(0.0h);
  for (int i = -4; i <= 4; i++) {
    uint tileCol = uint(int(tid.x) + 4 + i);
    sum += tile[tid.y * TILE_W + tileCol] * blurWeights[i + 4];
  }
  bloomOut.write(sum, gid);
}

kernel void fluidBloomDownsample(texture2d<half, access::sample> src [[texture(0)]],
                                 texture2d<half, access::write> dst [[texture(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
  uint w = dst.get_width();
  uint h = dst.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  half4 c = src.sample(bilinear, uv);
  dst.write(c, gid);
}

constant float3 kHalationSensitivity = float3(1.0, 0.43, 0.0);
constant float3 kHalationNear = float3(1.0, 0.42, 0.05);
constant float3 kHalationFar = float3(1.0, 0.06, 0.02);

kernel void fluidHalationSource(texture2d<float, access::sample> exposureIn [[texture(0)]],
                                texture2d<float, access::write> halationOut [[texture(1)]],
                                constant FrameUniforms &frame [[buffer(0)]],
                                constant float2 &coverage [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
  uint w = halationOut.get_width();
  uint h = halationOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h) * coverage;
  float exposure = exposureIn.sample(bilinear, uv).r;
  float knee = frame.technicolorHalation.y * frame.technicolorLampGain;
  halationOut.write(float4(exposure * smoothstep(0.55 * knee, knee, exposure)), gid);
}

inline float dyeDensity(float4 d) {
  return max(d.r, max(d.g, d.b));
}

constant float3 kCloudLightDir = float3(-0.4528, -0.6037, 0.6540);
constant int kCloudLevels = 6;

struct CloudUniforms {
  float advectStep;
  float regrow;
  float time;
  float billow;
  float billowScale;
  float shadow;
  float relief;
  float cavity;
  float ambient;
  float sun;
  float thickness;
  float vortexLift;
  float vortexPresence;
};

inline float cloudDensity(float4 d, float thickness) {
  float amount = pow(saturate(dyeDensity(d) * (1.0 / 1.5)), thickness);
  return amount * (1.0 - 0.2 * clamp(d.w, -1.0, 1.0));
}

inline float cloudBillow(float2 p, float t) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 3; i++) {
    float phase = t * (0.35 + 0.25 * float(i));
    float n = shaderSimplex2D(p) * fast::cos(phase) + shaderSimplex2D(p + 37.7) * fast::sin(phase);
    sum += amplitude * abs(n);
    p = p * 2.0 + float2(17.3, -9.1);
    amplitude *= 0.5;
  }
  return saturate(sum * 2.4);
}

inline float4 sampleBSpline(texture2d<float, access::sample> tex, sampler s, float2 uv, float2 texSize) {
  float2 samplePos = uv * texSize - 0.5;
  float2 base = floor(samplePos);
  float2 f = samplePos - base;
  float2 f2 = f * f;
  float2 f3 = f2 * f;

  float2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) * (1.0 / 6.0);
  float2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) * (1.0 / 6.0);
  float2 w3 = f3 * (1.0 / 6.0);
  float2 g0 = w0 + w1;
  float2 g1 = 1.0 - g0;
  float2 uv0 = (base - 0.5 + w1 / g0) / texSize;
  float2 uv1 = (base + 1.5 + w3 / g1) / texSize;

  return tex.sample(s, float2(uv0.x, uv0.y)) * g0.x * g0.y
       + tex.sample(s, float2(uv1.x, uv0.y)) * g1.x * g0.y
       + tex.sample(s, float2(uv0.x, uv1.y)) * g0.x * g1.y
       + tex.sample(s, float2(uv1.x, uv1.y)) * g1.x * g1.y;
}

kernel void fluidCloudDensity(texture2d<float, access::sample> dye [[texture(0)]],
                              texture2d<float, access::sample> dyeVelocity [[texture(1)]],
                              texture2d<float, access::sample> billowIn [[texture(2)]],
                              texture2d<float, access::write> billowOut [[texture(3)]],
                              texture2d<float, access::write> cloudOut [[texture(4)]],
                              texture2d<float, access::sample> vortexField [[texture(5)]],
                              constant CloudUniforms &cloud [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
  uint w = cloudOut.get_width();
  uint h = cloudOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float2 dyeSize = float2(dye.get_width(), dye.get_height());
  float2 uv = (float2(gid) + 0.5) / size;
  float2 stepUV = 2.0 / dyeSize;

  float density = 0.0;
  float presence = 0.0;
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 4; i++) {
      float weight = ((i == 0 || i == 3) ? 0.125 : 0.375) * ((j == 0 || j == 3) ? 0.125 : 0.375);
      float4 d = dye.sample(linearSampler, uv + (float2(i, j) - 1.5) * stepUV);
      density += weight * cloudDensity(d, cloud.thickness);
      presence += weight * smoothstep(0.0, cloud.vortexPresence, dyeDensity(d));
    }
  }

  float2 vortexSize = float2(vortexField.get_width(), vortexField.get_height());
  float swirl = sampleBSpline(vortexField, linearSampler, uv, vortexSize).z;
  density += cloud.vortexLift * presence * swirl;

  float2 vel = dyeVelocity.sample(linearSampler, uv).xy;
  float2 backUV = uv - cloud.advectStep * vel / dyeSize;
  float billow = saturate(sampleCatmullRom(billowIn, linearSampler, backUV, size).r);
  float2 p = (float2(gid) + 0.5) / min(size.x, size.y) * cloud.billowScale;
  billow = mix(billow, cloudBillow(p, cloud.time), cloud.regrow);
  billowOut.write(float4(billow, 0, 0, 0), gid);

  cloudOut.write(float4(density * (1.0 - cloud.billow * (1.0 - billow)), 0, 0, 0), gid);
}

kernel void fluidCloudLight(array<texture2d<float, access::sample>, kCloudLevels> cloud [[texture(0)]],
                            texture2d<float, access::write> lightOut [[texture(6)]],
                            constant CloudUniforms &uniforms [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = lightOut.get_width();
  uint h = lightOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 texel = 1.0 / float2(w, h);
  float2 uv = (float2(gid) + 0.5) * texel;
  float2 toLight = normalize(kCloudLightDir.xy) * texel;

  float2 slope = float2(0.0);
  float occlusion = 0.0;
  float crest = 0.0;
  for (int i = 0; i < kCloudLevels; i++) {
    float reach = float(1 << i);
    float2 dx = float2(texel.x * reach, 0.0);
    float2 dy = float2(0.0, texel.y * reach);
    slope += 0.5 * float2(cloud[i].sample(bilinear, uv + dx).r - cloud[i].sample(bilinear, uv - dx).r,
                          cloud[i].sample(bilinear, uv + dy).r - cloud[i].sample(bilinear, uv - dy).r);

    float here = cloud[i].sample(bilinear, uv).r;
    float ahead = cloud[i].sample(bilinear, uv + toLight * reach * 2.5).r;
    occlusion += saturate(ahead - here - 0.02);
    if (i == 0) crest += here;
    if (i == 2) crest -= here;
  }

  float3 n = normalize(float3(-slope * uniforms.relief, 1.0));
  float facing = max(dot(n, kCloudLightDir), 0.0) / kCloudLightDir.z;
  float lit = fast::exp(-uniforms.shadow * occlusion);
  float shade = (uniforms.ambient + uniforms.sun * lit * facing) * (1.0 + uniforms.cavity * crest);
  lightOut.write(float4(shade, 0, 0, 0), gid);
}

inline float2 curlNoiseOffset(float2 uv, float t) {
  float a = fast::sin(uv.x * 13.0 + t * 0.7)  + fast::cos(uv.y *  9.0 - t * 0.55);
  float b = fast::cos(uv.x *  7.0 - t * 0.6)  + fast::sin(uv.y * 11.0 + t * 0.45);
  return float2(a, b);
}

constant float3 kTechnicolorDyeLog2[21] = {
  float3(0.2098, 0.0000, 1.9184),
  float3(0.3146, 0.0737, 2.5565),
  float3(0.4897, 0.0000, 3.1981),
  float3(0.4092, 0.0923, 3.3219),
  float3(0.3275, 0.4641, 3.2477),
  float3(0.2673, 0.8500, 2.8274),
  float3(0.1613, 1.7252, 2.0455),
  float3(0.0511, 2.7810, 1.0228),
  float3(0.1286, 3.3169, 0.4328),
  float3(0.2353, 3.3219, 0.3563),
  float3(0.4797, 3.1809, 0.2084),
  float3(0.7716, 2.8081, 0.3135),
  float3(1.2862, 2.3257, 0.3104),
  float3(2.1924, 1.2758, 0.1615),
  float3(2.8159, 0.4690, 0.2320),
  float3(3.2321, 0.0097, 0.4003),
  float3(3.3219, 0.0000, 0.5078),
  float3(3.0897, 0.1999, 0.2786),
  float3(2.8540, 0.3159, 0.0423),
  float3(2.6298, 0.2859, 0.0000),
  float3(2.3478, 0.1467, 0.0000),
};

constant float3 kTechnicolorProjectorRGB[21] = {
  float3(0.00110, -0.00137, 0.01469),
  float3(0.01053, -0.01012, 0.08254),
  float3(0.02313, -0.02679, 0.24036),
  float3(0.02156, -0.02836, 0.30933),
  float3(-0.00851, -0.00604, 0.27081),
  float3(-0.03830, 0.03098, 0.15098),
  float3(-0.07281, 0.08263, 0.05712),
  float3(-0.10573, 0.15555, 0.00839),
  float3(-0.10832, 0.22092, -0.01860),
  float3(-0.04915, 0.23161, -0.02895),
  float3(0.05788, 0.19676, -0.02925),
  float3(0.18164, 0.13308, -0.02413),
  float3(0.27991, 0.06012, -0.01645),
  float3(0.30870, 0.00350, -0.00910),
  float3(0.24955, -0.01872, -0.00424),
  float3(0.15024, -0.01597, -0.00187),
  float3(0.06817, -0.00699, -0.00089),
  float3(0.02329, -0.00146, -0.00044),
  float3(0.00592, 0.00021, -0.00020),
  float3(0.00107, 0.00029, -0.00007),
  float3(0.00012, 0.00017, -0.00003),
};

constant uint kTechnicolorLUTSize = 33;
constant float3 kTechnicolorGrayGains = float3(0.94269, 0.82916, 0.91340);
constant float3x3 kSRGBToDisplayP3 = float3x3(float3(0.8224621, 0.0331941, 0.0170827),
                                              float3(0.1775380, 0.9668058, 0.0723974),
                                              float3(0.0000000, 0.0000000, 0.9105199));

inline float3 technicolorSpectralPrint(float3 dye) {
  float3 rgb = float3(0.0);
  for (int i = 0; i < 21; ++i) {
    rgb += fast::exp2(-dot(dye, kTechnicolorDyeLog2[i])) * kTechnicolorProjectorRGB[i];
  }
  return rgb;
}

kernel void technicolorBakeLUT(texture3d<half, access::write> lut [[texture(0)]],
                               constant float2 &densityAndSharpen [[buffer(0)]],
                               uint3 gid [[thread_position_in_grid]]) {
  if (any(gid >= kTechnicolorLUTSize)) return;
  float3 u = float3(gid) / float(kTechnicolorLUTSize - 1);
  float3 dye = pow(u, 0.5 * densityAndSharpen.y) * densityAndSharpen.x * kTechnicolorGrayGains;
  float3 rgb = kSRGBToDisplayP3 * technicolorSpectralPrint(dye);
  lut.write(half4(half3(rgb), 1.0h), gid);
}

constant uint kFilmGrainSize = 512;
constant float kFilmGrainRadius = 0.4;
constant float kFilmGrainRadiusDeviation = 0.08;
constant float kFilmGrainRadiusMax = 1.0;
constant float kFilmGrainFilter = 0.8;
constant float kFilmGrainCoverage = 0.5;
constant float kFilmGrainCoverageStd = 0.123;
constant float2 kFilmGrainResponse = float2(0.494, 0.674);
constant float kFilmGrainShadowLimit = 0.22;
constant float3x3 kFilmDyeAbsorption = float3x3(float3(0.9948, 0.2414, 0.0940),
                                                float3(0.0995, 0.9656, 0.3289),
                                                float3(0.0199, 0.0966, 0.9397));

inline uint grainHash(uint x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  x ^= x >> 16;
  return x;
}

inline float grainUnit(uint x) {
  return (float(x >> 8) + 0.5) * (1.0 / 16777216.0);
}

inline float grainCoverage(int2 texel, uint record) {
  const float meanSquare = kFilmGrainRadius * kFilmGrainRadius
                         + kFilmGrainRadiusDeviation * kFilmGrainRadiusDeviation;
  const float logVariance = log(meanSquare / (kFilmGrainRadius * kFilmGrainRadius));
  const float logMean = log(kFilmGrainRadius) - 0.5 * logVariance;
  const float lambda = log(1.0 / (1.0 - kFilmGrainCoverage)) / (M_PI_F * meanSquare);
  const float empty = exp(-lambda);
  uint covered = 0u;
  for (int dy = -1; dy <= 1; ++dy) {
    for (int dx = -1; dx <= 1; ++dx) {
      int2 cell = texel + int2(dx, dy);
      uint2 p = uint2(cell) & (kFilmGrainSize - 1);
      uint h = grainHash(p.x + grainHash(p.y + grainHash(record + 7u)));
      float u = grainUnit(h);
      float term = empty;
      float cdf = empty;
      uint count = 0u;
      while (u > cdf && count < 10u) {
        count++;
        term *= lambda / float(count);
        cdf += term;
      }
      for (uint k = 0u; k < count; ++k) {
        uint h1 = grainHash(h + 0x9e3779b9u * (2u * k + 1u));
        uint h2 = grainHash(h1 ^ 0x85ebca6bu);
        uint h3 = grainHash(h2 + 0xc2b2ae35u);
        uint h4 = grainHash(h3 ^ 0x27d4eb2fu);
        float2 pos = float2(cell) + float2(grainUnit(h1), grainUnit(h2));
        float z = sqrt(-2.0 * log(grainUnit(h3))) * cos(2.0 * M_PI_F * grainUnit(h4));
        float r = min(exp(logMean + sqrt(logVariance) * z), kFilmGrainRadiusMax);
        for (uint i = 0u; i < 16u; ++i) {
          float2 s = float2(texel) + (float2(float(i & 3u), float(i >> 2)) + 0.5) * 0.25;
          float2 d = s - pos;
          covered |= (dot(d, d) < r * r) ? (1u << i) : 0u;
        }
      }
    }
  }
  return float(popcount(covered)) * (1.0 / 16.0);
}

inline float3 grainResponse(float3 rgb, float white) {
  float3 level = clamp(sqrt(rgb / white), kFilmGrainShadowLimit, 1.0);
  return pow(2.0 * level, float3(-kFilmGrainResponse.x))
       * pow(2.0 * (1.0 - level), float3(kFilmGrainResponse.y));
}

inline float3 grainGain(float3 rgb, float3 density, float white) {
  return exp(-(kFilmDyeAbsorption * (grainResponse(rgb, white) * density)));
}

kernel void technicolorBakeGrainCoverage(texture2d<half, access::write> coverageOut [[texture(0)]],
                                         uint2 gid [[thread_position_in_grid]]) {
  if (any(gid >= kFilmGrainSize)) return;
  int2 texel = int2(gid);
  coverageOut.write(half4(half3(float3(grainCoverage(texel, 0u), grainCoverage(texel, 1u),
                                       grainCoverage(texel, 2u))), 1.0h), gid);
}

constant int kFilmCloudReach = 5;
constant float kFilmCloudCoverage = 0.1;

inline float cloudCell(int2 cell, uint record) {
  uint2 p = uint2(cell) & (kFilmGrainSize - 1);
  uint a = grainHash(p.x + grainHash(p.y + grainHash(record)));
  return float(a >> 8) < kFilmCloudCoverage * 16777216.0 ? 1.0 : 0.0;
}

kernel void technicolorBakeGrain(texture2d<half, access::write> grainOut [[texture(0)]],
                                 texture2d<half, access::read> coverage [[texture(1)]],
                                 constant float4 &strength [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
  if (any(gid >= kFilmGrainSize)) return;
  const float filterVariance = kFilmGrainFilter * kFilmGrainFilter - 1.0 / 12.0;
  float3 filtered = float3(0.0);
  float filterSum = 0.0;
  for (int dy = -3; dy <= 3; ++dy) {
    for (int dx = -3; dx <= 3; ++dx) {
      float weight = exp(-0.5 * float(dx * dx + dy * dy) / filterVariance);
      uint2 tap = uint2(int2(gid) + int2(dx, dy)) & (kFilmGrainSize - 1);
      filtered += weight * float3(coverage.read(tap).rgb);
      filterSum += weight;
    }
  }
  float3 n = (filtered / filterSum - kFilmGrainCoverage) / kFilmGrainCoverageStd;

  float4 cloud = float4(0.0);
  float2 weightSum = float2(0.0);
  for (int dy = -kFilmCloudReach; dy <= kFilmCloudReach; ++dy) {
    for (int dx = -kFilmCloudReach; dx <= kFilmCloudReach; ++dx) {
      float weight = exp(-0.5 * float(dx * dx + dy * dy) / (strength.w * strength.w));
      int2 cell = int2(gid) + int2(dx, dy);
      cloud += weight * float4(cloudCell(cell, 3u), cloudCell(cell, 4u), cloudCell(cell, 5u),
                               cloudCell(cell, 6u));
      weightSum += float2(weight, weight * weight);
    }
  }
  cloud = (cloud - kFilmCloudCoverage * weightSum.x)
    / sqrt(kFilmCloudCoverage * (1.0 - kFilmCloudCoverage) * weightSum.y);
  float3 clouds = sqrt(1.0 - strength.z * strength.z) * cloud.w + strength.z * cloud.xyz;

  grainOut.write(half4(half3(strength.x * n + strength.y * clouds), 1.0h), gid);
}

inline float3 technicolorIV(float3 dyeAmounts, texture3d<float, access::sample> lut,
                            float presence, float3 themeDye, float neutralReach,
                            float depth, float lamp, float ceiling) {
  float3 a = max(dyeAmounts, float3(0.0));
  float amount = max(a.x, max(a.y, a.z));
  if (amount < 1e-5) return float3(0.0);
  float3 ratio = a / amount;
  float chroma = 1.0 - min(ratio.x, min(ratio.y, ratio.z));
  ratio = mix(themeDye, ratio, smoothstep(0.0, neutralReach, chroma));

  constexpr sampler lutSampler(filter::linear, address::clamp_to_edge);
  const float n = float(kTechnicolorLUTSize);
  float3 rgb = max(lut.sample(lutSampler, (ratio * ratio * depth * (n - 1.0) + 0.5) / n).rgb, float3(0.0));
  rgb *= (1.0 - exp(-amount * presence)) * lamp;
  float peak = max(rgb.r, max(rgb.g, rgb.b)) / ceiling;
  float peak2 = peak * peak;
  rgb *= rsqrt(sqrt(1.0 + peak2 * peak2));
  return rgb;
}

kernel void fluidRender(texture2d<float, access::sample> dye [[texture(0)]],
                        texture2d<float, access::sample> cloudLight [[texture(1)]],
                        texture2d<float, access::sample> bloomHi [[texture(2)]],
                        texture2d<float, access::sample> bloomMid [[texture(3)]],
                        texture2d<float, access::sample> bloomLo [[texture(4)]],
                        texture2d<float, access::read> historyIn [[texture(5)]],
                        texture2d<float, access::write> historyOut [[texture(6)]],
                        texture3d<float, access::sample> technicolorLUT [[texture(7)]],
                        texture2d<float, access::sample> halation [[texture(8)]],
                        texture2d<float, access::read> grain [[texture(9)]],
                        texture2d<float, access::write> exposureOut [[texture(10)]],
                        constant FrameUniforms &frame [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]],
                        uint2 tid [[thread_position_in_threadgroup]]) {
  float bass = frame.bass;
  float mid = frame.mid;
  float renderTime = frame.time;
  float taaBlend = frame.taaBlend;
  uint historyValid = frame.historyValid;
  uint w = historyOut.get_width();
  uint h = historyOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 center = (float2(gid) + 0.5) / float2(w, h);
  float2 dyeSize = float2(dye.get_width(), dye.get_height());
  float2 texel = 1.0 / dyeSize;

  float2 registerScale = float(min(w, h)) / float2(w, h);
  float2 weavePos = (center - 0.5) / registerScale;
  float4 gateWeave = frame.technicolorGateWeave;

  float2 jitter = curlNoiseOffset(center, renderTime) * frame.jitter;
  float2 sampleCenter = center + jitter
                      + (gateWeave.xy + gateWeave.z * float2(-weavePos.y, weavePos.x)) * registerScale
                      + frame.technicolorGateJump.xy / float2(w, h);

  float dL = dyeDensity(dye.sample(bilinear, sampleCenter - float2(1.5, 0.0) * texel));
  float dR = dyeDensity(dye.sample(bilinear, sampleCenter + float2(1.5, 0.0) * texel));
  float dD = dyeDensity(dye.sample(bilinear, sampleCenter - float2(0.0, 1.5) * texel));
  float dU = dyeDensity(dye.sample(bilinear, sampleCenter + float2(0.0, 1.5) * texel));
  float2 grad = float2(dR - dL, dU - dD) / 3.0;
  float gradMag = fast::length(grad);

  float2 detailWarp = curlNoiseOffset(center * 2.5, renderTime * 1.1)
                    * texel * frame.detail * saturate(gradMag * 3.0);

  float2 dyeUV = sampleCenter + detailWarp;

  float2 registerPos = (dyeUV - 0.5) / registerScale;
  float2 registerTurn = float2(-registerPos.y, registerPos.x);
  float4 registerWarp = frame.technicolorMisregistrationWarp;
  float2 cyanUV = dyeUV + (frame.technicolorMisregistration.xy + registerWarp.x * registerTurn
                           + registerWarp.y * registerPos) * registerScale;
  float2 yellowUV = dyeUV + (frame.technicolorMisregistration.zw + registerWarp.z * registerTurn
                             + registerWarp.w * registerPos) * registerScale;
  float3 cRGB = max(float3(sampleCatmullRom5(dye, bilinear, cyanUV, dyeSize).r,
                           sampleCatmullRom5(dye, bilinear, dyeUV, dyeSize).g,
                           sampleCatmullRom5(dye, bilinear, yellowUV, dyeSize).b),
                    float3(0.0));

  float amount = dyeDensity(float4(cRGB, 0.0));
  float thin = pow(saturate(amount / max(frame.thinFade, 1e-3)), 0.6);
  float3 c = cRGB * thin;
  float depth = mix(frame.technicolorDepth.x, 1.0,
                    smoothstep(frame.technicolorDepth.y, frame.technicolorDepth.z, amount));

  float3 bHi  = bloomHi.sample(bilinear, sampleCenter).rgb;
  float3 bMid = bloomMid.sample(bilinear, sampleCenter).rgb;
  float3 bLo  = bloomLo.sample(bilinear, sampleCenter).rgb;
  
  float hiW  = 0.08 + frame.high * 0.40;
  float midW = 0.08 + frame.mid  * 0.40;
  float loW  = 0.08 + frame.bass * 0.55;
  float3 bloom = (bHi * hiW + bMid * midW + bLo * loW) * frame.bloom;
  c += bloom;

  float ceiling = frame.technicolorCeiling;
  float lamp = frame.technicolorLampGain
             * (1.0 + (bass * 0.4 + mid * 0.25) * ceiling
                + dyeDensity(float4(bloom, 0.0)) * (ceiling - 1.0));

  {
    float3 n = normalize(float3(-grad * 6.0, 1.0));
    float diffuse = max(dot(n, kCloudLightDir), 0.0);
    float shade = mix(1.0, 0.5 + 0.8 * diffuse, frame.shading);
    lamp *= shade;

    float2 lightSize = float2(cloudLight.get_width(), cloudLight.get_height());
    lamp *= max(sampleBSpline(cloudLight, bilinear, dyeUV, lightSize).r, 0.0);
  }

  c = technicolorIV(c, technicolorLUT, frame.technicolorPresence,
                    frame.technicolorTheme.xyz, frame.technicolorNeutralReach,
                    depth, lamp, ceiling);

  float vDist = fast::length(center - 0.5) * 1.414;
  float vAmount = 0.35 - frame.bass * 0.25;
  float vignette = max(1.0 - vDist * vDist * vAmount, 0.0);
  c *= vignette * vignette * sqrt(vignette);

  float3 finalColor = c;
  float exposure = dot(c, kHalationSensitivity);
  int4 grainShift = int4(frame.technicolorGrain);
  float grainWhite = frame.technicolorLampGain;
  if (historyValid != 0u) {
    int2 gateStep = int2(frame.technicolorGateJump.zw);
    int2 prevPos = clamp(int2(gid) + gateStep, int2(0), int2(w, h) - 1);
    float4 prev = max(historyIn.read(uint2(prevPos)), float4(0.0));
    float3 prevGrain = grain.read(uint2(prevPos + grainShift.zw) & (kFilmGrainSize - 1)).rgb;
    float3 shown = prev.rgb;
    for (int i = 0; i < 4; ++i) {
      prev.rgb = shown / grainGain(prev.rgb, prevGrain, grainWhite);
    }

    float knee = frame.technicolorHalation.y * frame.technicolorLampGain;
    float2 haloUV = center + float2(gateStep) / float2(w, h);
    float spill = halation.sample(bilinear, haloUV).r;
    float glow = spill * (1.0 - smoothstep(0.25 * knee, max(knee, spill), exposure));
    float3 tint = mix(kHalationFar, kHalationNear, saturate(2.0 * glow / knee));
    float room = max(max(spill, knee) - exposure, 0.0) / dot(tint, kHalationSensitivity);
    c += tint * min(frame.technicolorHalation.x * glow, room);

    float4 blended = mix(sqrt(float4(c, exposure)), sqrt(prev), taaBlend);
    blended *= blended;
    finalColor = blended.rgb;
    exposure = blended.a;
  }

  float3 grainDensity = grain.read(uint2(int2(gid) + grainShift.xy) & (kFilmGrainSize - 1)).rgb;
  finalColor *= grainGain(finalColor, grainDensity, grainWhite);

  historyOut.write(float4(finalColor, exposure), gid);

  threadgroup float exposureTile[256];
  exposureTile[tid.y * 16 + tid.x] = exposure;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (((tid.x | tid.y) & 3u) != 0u) return;

  uint2 span = min(uint2(4), uint2(w, h) - gid);
  float sum = 0.0;
  for (uint y = 0; y < span.y; y++) {
    for (uint x = 0; x < span.x; x++) {
      sum += exposureTile[(tid.y + y) * 16 + tid.x + x];
    }
  }
  exposureOut.write(float4(sum / float(span.x * span.y)), gid >> 2);
}

kernel void fluidPsiInit(texture2d<float, access::write> psiOut [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= psiOut.get_width() || gid.y >= psiOut.get_height()) return;
  psiOut.write(float4(float(gid.x) + 0.5, float(gid.y) + 0.5, 0, 0), gid);
}

kernel void fluidCopyRG(texture2d<float, access::read>  src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
  dst.write(float4(src.read(gid).xy, 0, 0), gid);
}

kernel void fluidPsiAdvect(texture2d<float, access::sample> velocity [[texture(0)]],
                           texture2d<float, access::sample> psiIn   [[texture(1)]],
                           texture2d<float, access::write> psiOut   [[texture(2)]],
                           constant float &dt [[buffer(0)]],
                           constant float2 &traceLimits [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
  uint w = psiIn.get_width();
  uint h = psiIn.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 size = float2(w, h);
  float2 backPos = traceVelocity(velocity, linearSampler, float2(gid) + 0.5, size, -dt, traceLimits,
                                 true);
  float2 psiBack = psiIn.sample(linearSampler, backPos / size).xy;

  psiOut.write(float4(psiBack, 0, 0), gid);
}

kernel void fluidCovectorPullback(texture2d<float, access::read>   psi  [[texture(0)]],
                                  texture2d<float, access::sample> u0   [[texture(1)]],
                                  texture2d<float, access::write>  uOut [[texture(2)]],
                                  texture2d<float, access::read>   dye  [[texture(3)]],
                                  texture2d<float, access::sample> vortexField [[texture(4)]],
                                  constant float &dissipation [[buffer(0)]],
                                  device atomic_uint *stats [[buffer(1)]],
                                  constant float &stretchThreshold [[buffer(2)]],
                                  constant float &maxSpeed [[buffer(3)]],
                                  constant float4 &forces [[buffer(4)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  int w = int(psi.get_width());
  int h = int(psi.get_height());
  bool inBounds = int(gid.x) < w && int(gid.y) < h;
  uint stretched = 0u;
  uint fast = 0u;

  if (inBounds) {
    int xL = max(int(gid.x) - 1, 0);
    int yD = max(int(gid.y) - 1, 0);

    float2 psiL = psi.read(uint2(uint(xL), gid.y)).xy;
    float2 psiD = psi.read(uint2(gid.x, uint(yD))).xy;
    float2 psiC = psi.read(gid).xy;

    half2 dpsi_dx = half2(psiC - psiL);
    half2 dpsi_dy = half2(psiC - psiD);

    {
      half2 dev_x = dpsi_dx - half2(1, 0);
      half2 dev_y = dpsi_dy - half2(0, 1);
      half devX = length(dev_x);
      half devY = length(dev_y);
      {
        int xL2 = max(int(gid.x) - 2, 0);
        int xR2 = min(int(gid.x) + 2, w - 1);
        int yD2 = max(int(gid.y) - 2, 0);
        int yU2 = min(int(gid.y) + 2, h - 1);
        float2 wx = (psi.read(uint2(uint(xR2), gid.y)).xy - psi.read(uint2(uint(xL2), gid.y)).xy)
                  / float(max(xR2 - xL2, 1));
        float2 wy = (psi.read(uint2(gid.x, uint(yU2))).xy - psi.read(uint2(gid.x, uint(yD2))).xy)
                  / float(max(yU2 - yD2, 1));
        float wideDev = max(length(wx - float2(1, 0)), length(wy - float2(0, 1)));
        stretched = (wideDev > stretchThreshold) ? 1u : 0u;
      }
      if (devX > 0.5h) dpsi_dx = half2(1, 0) + dev_x * (0.5h / devX);
      if (devY > 0.5h) dpsi_dy = half2(0, 1) + dev_y * (0.5h / devY);
    }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 size = float2(float(w), float(h));
    half2 u0x = half2(sampleFaceVelocity(u0, linearSampler, 0.5 * (psiC + psiL), size));
    half2 u0y = half2(sampleFaceVelocity(u0, linearSampler, 0.5 * (psiC + psiD), size));

    half2 uh;
    uh.x = dot(dpsi_dx, u0x);
    uh.y = dot(dpsi_dy, u0y);

    float2 u = float2(uh) * dissipation;
    if (gid.x == 0u) u.x = 0;
    if (gid.y == 0u) u.y = 0;

    if (any(isnan(u)) || any(isinf(u))) u = float2(0);
    float sp = fast::length(u);
    fast = (sp > 0.5 * maxSpeed) ? 1u : 0u;
    if (sp > maxSpeed) u *= maxSpeed / sp;

    if (forces.x != 0.0 || forces.z != 0.0) {
      float2 vortexSize = float2(vortexField.get_width(), vortexField.get_height());
      float2 push = forces.z * sampleBSpline(vortexField, linearSampler, (float2(gid) + 0.5) / size,
                                             vortexSize).xy;
      if (gid.x > 0u) u.x += push.x;
      if (gid.y > 0u) {
        float settle = 1.0 - saturate(fast::length(u) / forces.y);
        float weight = 0.5 * (dye.read(gid).w + dye.read(uint2(gid.x, gid.y - 1u)).w);
        u.y += forces.x * weight * settle + push.y;
      }
    }

    uOut.write(float4(u, 0, 0), gid);
  }

  uint groupStretched = simd_sum(stretched);
  if (simd_is_first() && groupStretched > 0u) {
    atomic_fetch_add_explicit(stats, groupStretched, memory_order_relaxed);
  }
  uint groupFast = simd_sum(fast);
  if (simd_is_first() && groupFast > 0u) {
    atomic_fetch_add_explicit(stats + 1, groupFast, memory_order_relaxed);
  }
}

kernel void fluidClearRGBA(texture2d<float, access::write> t [[texture(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
  t.write(float4(0), gid);
}

struct VortexUniforms {
  float cells;
  float floor;
  float cap;
  float swirlScale;
};

kernel void fluidVortexField(texture2d<float, access::read> flow [[texture(0)]],
                             texture2d<float, access::write> fieldOut [[texture(1)]],
                             constant VortexUniforms &uniforms [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  int w = flow.get_width();
  int h = flow.get_height();
  if (int(gid.x) >= w || int(gid.y) >= h) return;

  float perCell = 0.5 / uniforms.cells;
  float spin[5];
  float swirl = 0.0;
  const int2 offsets[5] = { int2(0, 0), int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
  for (int i = 0; i < 5; i++) {
    int2 p = int2(gid) + offsets[i];
    float2 l = flow.read(uint2(clamp(p.x - 1, 0, w - 1), clamp(p.y, 0, h - 1))).xy;
    float2 r = flow.read(uint2(clamp(p.x + 1, 0, w - 1), clamp(p.y, 0, h - 1))).xy;
    float2 d = flow.read(uint2(clamp(p.x, 0, w - 1), clamp(p.y - 1, 0, h - 1))).xy;
    float2 u = flow.read(uint2(clamp(p.x, 0, w - 1), clamp(p.y + 1, 0, h - 1))).xy;
    float2 ddx = perCell * (r - l);
    float2 ddy = perCell * (u - d);
    spin[i] = ddx.y - ddy.x;
    if (i == 0) {
      float2 strain = float2(ddx.x - ddy.y, ddx.y + ddy.x);
      swirl = 0.5 * (spin[0] * spin[0] - dot(strain, strain));
    }
  }

  float2 toward = 0.5 * float2(abs(spin[2]) - abs(spin[1]), abs(spin[4]) - abs(spin[3]));
  toward /= max(length(toward), uniforms.floor);
  float turn = clamp(spin[0], -uniforms.cap, uniforms.cap);
  swirl /= abs(swirl) + uniforms.swirlScale;
  fieldOut.write(float4(turn * toward.y, -turn * toward.x, swirl, 0), gid);
}

kernel void fluidResample(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float4 &scale [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
  uint w = dst.get_width();
  uint h = dst.get_height();
  if (gid.x >= w || gid.y >= h) return;
  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  dst.write(src.sample(linearSampler, uv) * scale, gid);
}

struct DyeMapUniforms {
  float2 gridSize;
  float2 traceLimits;
  float dt;
  float strayCells;
};

kernel void fluidDyeMapReset(texture2d<float, access::read>  dye        [[texture(0)]],
                             texture2d<float, access::write> snapshot   [[texture(1)]],
                             texture2d<float, access::write> backMap    [[texture(2)]],
                             texture2d<float, access::write> forwardMap [[texture(3)]],
                             uint2 gid [[thread_position_in_grid]]) {
  uint w = dye.get_width();
  uint h = dye.get_height();
  if (gid.x >= w || gid.y >= h) return;
  snapshot.write(dye.read(gid), gid);

  uint mapW = backMap.get_width();
  uint mapH = backMap.get_height();
  if (gid.x >= mapW || gid.y >= mapH) return;
  float4 here = float4((float2(gid) + 0.5) * float2(w, h) / float2(mapW, mapH), 0, 0);
  backMap.write(here, gid);
  forwardMap.write(here, gid);
}

kernel void fluidDyeMapAccumulate(texture2d<float, access::sample>     dye        [[texture(0)]],
                                  texture2d<float, access::sample>     lookedUp   [[texture(1)]],
                                  texture2d<float, access::sample>     forwardMap [[texture(2)]],
                                  texture2d<float, access::read_write> snapshot   [[texture(3)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  uint w = snapshot.get_width();
  uint h = snapshot.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float2 uv = forwardMap.sample(linearSampler, (float2(gid) + 0.5) / size).xy / size;
  float4 d = snapshot.read(gid) + dye.sample(linearSampler, uv) - lookedUp.sample(linearSampler, uv);
  d.xyz = clamp(d.xyz, 0.0, 1.5);
  d.w = clamp(d.w, -1.5, 1.5);
  snapshot.write(d, gid);
}

kernel void fluidDyeMapAdvance(texture2d<float, access::sample> velocity   [[texture(0)]],
                               texture2d<float, access::sample> backIn     [[texture(1)]],
                               texture2d<float, access::sample> forwardIn  [[texture(2)]],
                               texture2d<float, access::write>  backOut    [[texture(3)]],
                               texture2d<float, access::write>  forwardOut [[texture(4)]],
                               constant DyeMapUniforms &uniforms [[buffer(0)]],
                               device atomic_uint *stats [[buffer(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
  uint w = backIn.get_width();
  uint h = backIn.get_height();
  uint backStray = 0u;
  uint forthStray = 0u;

  if (gid.x < w && gid.y < h) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 size = uniforms.gridSize;
    float2 here = (float2(gid) + 0.5) * size / float2(w, h);
    float2 from = backIn.read(gid).xy;
    float2 to = forwardIn.read(gid).xy;

    float2 back = backIn.sample(linearSampler, to / size).xy;
    float2 forth = forwardIn.sample(linearSampler, from / size).xy;
    backStray = (distance(back, here) > uniforms.strayCells) ? 1u : 0u;
    forthStray = (distance(forth, here) > uniforms.strayCells) ? 1u : 0u;

    float2 backPos = traceVelocity(velocity, linearSampler, here, size, -uniforms.dt,
                                   uniforms.traceLimits, false);
    float2 moved = sampleCatmullRom(backIn, linearSampler, backPos / size, float2(w, h)).xy;
    backOut.write(float4(moved, 0, 0), gid);

    to = traceVelocity(velocity, linearSampler, to, size, uniforms.dt, uniforms.traceLimits, false);
    forwardOut.write(float4(clamp(to, float2(0.0), size), 0, 0), gid);
  }

  uint groupBackStray = simd_sum(backStray);
  uint groupForthStray = simd_sum(forthStray);
  if (simd_is_first()) {
    if (groupBackStray > 0u) atomic_fetch_add_explicit(&stats[0], groupBackStray, memory_order_relaxed);
    if (groupForthStray > 0u) atomic_fetch_add_explicit(&stats[1], groupForthStray, memory_order_relaxed);
  }
}

kernel void fluidDyeMapLookup(texture2d<float, access::sample> backMap  [[texture(0)]],
                              texture2d<float, access::sample> snapshot [[texture(1)]],
                              texture2d<float, access::write>  dyeOut   [[texture(2)]],
                              uint2 gid [[thread_position_in_grid]]) {
  uint w = snapshot.get_width();
  uint h = snapshot.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float2 from = backMap.sample(linearSampler, (float2(gid) + 0.5) / size).xy;
  float4 looked = sampleCatmullRom(snapshot, linearSampler, from / size, size);
  looked.xyz = clamp(looked.xyz, 0.0, 1.5);
  looked.w = clamp(looked.w, -1.5, 1.5);
  dyeOut.write(looked, gid);
}

kernel void fluidDyeMapError(texture2d<float, access::sample> lookedUp   [[texture(0)]],
                             texture2d<float, access::read>   snapshot   [[texture(1)]],
                             texture2d<float, access::sample> forwardMap [[texture(2)]],
                             texture2d<float, access::write>  errorOut   [[texture(3)]],
                             uint2 gid [[thread_position_in_grid]]) {
  uint w = snapshot.get_width();
  uint h = snapshot.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float2 uv = forwardMap.sample(linearSampler, (float2(gid) + 0.5) / size).xy / size;
  errorOut.write(0.5 * (lookedUp.sample(linearSampler, uv) - snapshot.read(gid)), gid);
}

kernel void fluidDyeMapCorrect(texture2d<half, access::read>    lookedUp [[texture(0)]],
                               texture2d<float, access::sample> error    [[texture(1)]],
                               texture2d<float, access::sample> backMap  [[texture(2)]],
                               texture2d<half, access::write>   dyeOut   [[texture(3)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint2 tid [[thread_position_in_threadgroup]],
                               uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = lookedUp.get_width();
  uint h = lookedUp.get_height();

  constexpr uint TILE = 18;
  threadgroup half4 tile[TILE * TILE];

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    uint tx = idx % TILE;
    uint ty = idx / TILE;
    int gx = clamp(tileOriginX + int(tx), 0, int(w) - 1);
    int gy = clamp(tileOriginY + int(ty), 0, int(h) - 1);
    tile[idx] = lookedUp.read(uint2(gx, gy));
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  uint myIdx = (tid.y + 1) * TILE + (tid.x + 1);
  half4 c = tile[myIdx];
  half4 lo = c;
  half4 hi = c;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      half4 n = tile[uint(int(myIdx) + j * int(TILE) + i)];
      lo = min(lo, n);
      hi = max(hi, n);
    }
  }

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 size = float2(w, h);
  float2 uv = backMap.sample(linearSampler, (float2(gid) + 0.5) / size).xy / size;
  half4 corrected = c - half4(error.sample(linearSampler, uv));
  dyeOut.write(clamp(corrected, lo, hi), gid);
}

kernel void fluidDyeDiffuse(texture2d<half, access::read>  dyeIn  [[texture(0)]],
                            texture2d<half, access::write> dyeOut [[texture(1)]],
                            constant float &baseStrengthF [[buffer(0)]],
                            constant float &edgeBoostF    [[buffer(1)]],
                            constant float2 &edgeFade     [[buffer(2)]],
                            constant float &decay         [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]],
                            uint2 tid [[thread_position_in_threadgroup]],
                            uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = dyeIn.get_width();
  uint h = dyeIn.get_height();

  constexpr uint TILE = 18;
  threadgroup half4 tile[TILE * TILE];

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    uint tx = idx % TILE;
    uint ty = idx / TILE;
    int gx = clamp(tileOriginX + int(tx), 0, int(w) - 1);
    int gy = clamp(tileOriginY + int(ty), 0, int(h) - 1);
    tile[idx] = dyeIn.read(uint2(gx, gy));
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  uint lx = tid.x + 1;
  uint ly = tid.y + 1;
  uint myIdx = ly * TILE + lx;

  half4 c  = tile[myIdx];
  half4 cL = tile[myIdx - 1];
  half4 cR = tile[myIdx + 1];
  half4 cD = tile[myIdx - TILE];
  half4 cU = tile[myIdx + TILE];
  half4 neighbours = (cL + cR + cD + cU) * 0.25h;

  half3 gradVec = neighbours.xyz - c.xyz;
  half gradMag = length(gradVec);

  half edgeT = min(gradMag * 3.0h, 1.0h);

  half s = half(baseStrengthF) + half(edgeBoostF) * edgeT;
  s = min(s, 0.35h);

  half4 out = mix(c, neighbours, s);

  float distToWall = float(min(min(gid.x, w - 1u - gid.x), min(gid.y, h - 1u - gid.y)));
  float inside = smoothstep(0.0, edgeFade.x, distToWall);
  out *= half(decay * (1.0 - edgeFade.y * (1.0 - inside)));

  dyeOut.write(out, gid);
}

constant int kMGTile = 22;
constant int kMGMargin = 3;
constant int kMGCoarseTile = 12;

struct MGEntry {
  uint index;
  int2 cell;
  int ring;
  uint colour;
  float walls;
  bool exists;
};

inline float mgWalls(int2 cell, int2 size) {
  return float(int(cell.x == 0) + int(cell.y == 0)
             + int(cell.x == size.x - 1) + int(cell.y == size.y - 1));
}

inline MGEntry mgEntry(uint index, int2 origin, int2 size) {
  MGEntry e;
  e.index = index;
  e.exists = index < uint(kMGTile * kMGTile);
  int2 t = int2(int(index) % kMGTile, int(index) / kMGTile);
  e.cell = origin + t;
  int2 out = max(max(kMGMargin - t, t - (kMGMargin + 15)), int2(0));
  bool inLevel = e.exists && all(e.cell >= 0) && all(e.cell < size);
  e.ring = inLevel ? max(out.x, out.y) : kMGTile;
  e.colour = uint(e.cell.x + e.cell.y) & 1u;
  e.walls = mgWalls(e.cell, size);
  return e;
}

inline float mgNeighbours(threadgroup const float *p, uint i, float walls) {
  return p[i - 1u] + p[i + 1u] + p[i - uint(kMGTile)] + p[i + uint(kMGTile)] + walls * p[i];
}

inline void mgRelax(threadgroup float *p, threadgroup const float *f, MGEntry e, uint colour,
                    int reach) {
  if (e.ring > reach || e.colour != colour) return;
  p[e.index] = (mgNeighbours(p, e.index, e.walls) - f[e.index]) * 0.25f;
}

inline void mgWriteDescended(threadgroup const float *p, threadgroup const float *f,
                             texture2d<float, access::write> pressureOut,
                             texture2d<float, access::write> rhsCoarse,
                             int2 size, uint2 tid, uint2 gid) {
  int2 cell = int2(gid);
  if (any(cell >= size)) return;
  uint own = (tid.y + uint(kMGMargin)) * uint(kMGTile) + tid.x + uint(kMGMargin);
  pressureOut.write(float4(p[own], 0, 0, 0), gid);

  if (((gid.x | gid.y) & 1u) != 0u) return;
  float sum = 0.0f;
  for (int j = 0; j < 2; j++) {
    for (int i = 0; i < 2; i++) {
      int2 c = cell + int2(i, j);
      if (any(c >= size)) continue;
      float walls = mgWalls(c, size);
      if (((i + j) & 1) != 0 && walls == 0.0f) continue;
      uint k = own + uint(j * kMGTile + i);
      sum += f[k] - (mgNeighbours(p, k, walls) - 4.0f * p[k]);
    }
  }
  rhsCoarse.write(float4(sum, 0, 0, 0), gid / 2u);
}

kernel void fluidMGDescendDivergence(texture2d<float, access::read>  velocity    [[texture(0)]],
                                     texture2d<float, access::write> rhsOut      [[texture(1)]],
                                     texture2d<float, access::write> pressureOut [[texture(2)]],
                                     texture2d<float, access::write> rhsCoarse   [[texture(3)]],
                                     uint2 gid [[thread_position_in_grid]],
                                     uint2 tid [[thread_position_in_threadgroup]],
                                     uint2 tgid [[threadgroup_position_in_grid]]) {
  threadgroup float p[kMGTile * kMGTile];
  threadgroup float f[kMGTile * kMGTile];

  int2 size = int2(velocity.get_width(), velocity.get_height());
  int2 origin = int2(tgid) * 16 - kMGMargin;
  uint lane = tid.y * 16u + tid.x;
  MGEntry entries[2] = { mgEntry(lane, origin, size), mgEntry(lane + 256u, origin, size) };

  for (int n = 0; n < 2; n++) {
    MGEntry e = entries[n];
    if (!e.exists) continue;
    float div = 0.0f;
    if (e.ring <= 2) div = faceDivergence(velocity, uint2(e.cell), uint(size.x), uint(size.y));
    f[e.index] = div;
    p[e.index] = e.colour == 0u ? -0.25f * div : 0.0f;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 1u, 1);

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (all(int2(gid) < size)) {
    uint own = (tid.y + uint(kMGMargin)) * uint(kMGTile) + tid.x + uint(kMGMargin);
    rhsOut.write(float4(f[own], 0, 0, 0), gid);
  }
  mgWriteDescended(p, f, pressureOut, rhsCoarse, size, tid, gid);
}

kernel void fluidMGDescendZero(texture2d<float, access::read>  rhs         [[texture(0)]],
                               texture2d<float, access::write> pressureOut [[texture(1)]],
                               texture2d<float, access::write> rhsCoarse   [[texture(2)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint2 tid [[thread_position_in_threadgroup]],
                               uint2 tgid [[threadgroup_position_in_grid]]) {
  threadgroup float p[kMGTile * kMGTile];
  threadgroup float f[kMGTile * kMGTile];

  int2 size = int2(rhs.get_width(), rhs.get_height());
  int2 origin = int2(tgid) * 16 - kMGMargin;
  uint lane = tid.y * 16u + tid.x;
  MGEntry entries[2] = { mgEntry(lane, origin, size), mgEntry(lane + 256u, origin, size) };

  for (int n = 0; n < 2; n++) {
    MGEntry e = entries[n];
    if (!e.exists) continue;
    float value = e.ring <= 2 ? rhs.read(uint2(e.cell)).x : 0.0f;
    f[e.index] = value;
    p[e.index] = e.colour == 0u ? -0.25f * value : 0.0f;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 1u, 1);

  threadgroup_barrier(mem_flags::mem_threadgroup);

  mgWriteDescended(p, f, pressureOut, rhsCoarse, size, tid, gid);
}

kernel void fluidMGDescend(texture2d<float, access::read>  pressure    [[texture(0)]],
                           texture2d<float, access::read>  rhs         [[texture(1)]],
                           texture2d<float, access::write> pressureOut [[texture(2)]],
                           texture2d<float, access::write> rhsCoarse   [[texture(3)]],
                           uint2 gid [[thread_position_in_grid]],
                           uint2 tid [[thread_position_in_threadgroup]],
                           uint2 tgid [[threadgroup_position_in_grid]]) {
  threadgroup float p[kMGTile * kMGTile];
  threadgroup float f[kMGTile * kMGTile];

  int2 size = int2(pressure.get_width(), pressure.get_height());
  int2 origin = int2(tgid) * 16 - kMGMargin;
  uint lane = tid.y * 16u + tid.x;
  MGEntry entries[2] = { mgEntry(lane, origin, size), mgEntry(lane + 256u, origin, size) };

  for (int n = 0; n < 2; n++) {
    MGEntry e = entries[n];
    if (!e.exists) continue;
    p[e.index] = e.ring <= 3 ? pressure.read(uint2(e.cell)).x : 0.0f;
    f[e.index] = e.ring <= 2 ? rhs.read(uint2(e.cell)).x : 0.0f;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 0u, 2);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 1u, 1);
  threadgroup_barrier(mem_flags::mem_threadgroup);

  mgWriteDescended(p, f, pressureOut, rhsCoarse, size, tid, gid);
}

inline int2 mgLoadCoarse(threadgroup float *coarse, texture2d<float, access::read> pressureCoarse,
                         int2 origin, uint lane) {
  int2 coarseSize = int2(pressureCoarse.get_width(), pressureCoarse.get_height());
  int2 coarseOrigin = (origin + kMGMargin) / 2 - 2;
  if (lane < uint(kMGCoarseTile * kMGCoarseTile)) {
    int2 t = int2(int(lane) % kMGCoarseTile, int(lane) / kMGCoarseTile);
    int2 cell = clamp(coarseOrigin + t, int2(0), coarseSize - 1);
    coarse[lane] = pressureCoarse.read(uint2(cell)).x;
  }
  return coarseOrigin;
}

inline void mgLoadCorrected(threadgroup float *p, threadgroup float *f,
                            threadgroup const float *coarse,
                            texture2d<float, access::read> pressure,
                            texture2d<float, access::read> rhs,
                            MGEntry e, int reach, int2 coarseOrigin) {
  if (!e.exists) return;
  float value = 0.0f;
  if (e.ring <= reach) {
    float2 at = (float2(e.cell) + 0.5) * 0.5 - 0.5;
    int2 base = int2(floor(at));
    float2 fr = at - float2(base);
    int2 ct = base - coarseOrigin;
    uint i = uint(ct.y * kMGCoarseTile + ct.x);
    float below = mix(coarse[i], coarse[i + 1u], fr.x);
    float above = mix(coarse[i + uint(kMGCoarseTile)], coarse[i + uint(kMGCoarseTile) + 1u], fr.x);
    value = pressure.read(uint2(e.cell)).x + mix(below, above, fr.y);
  }
  p[e.index] = value;
  f[e.index] = e.ring < reach ? rhs.read(uint2(e.cell)).x : 0.0f;
}

kernel void fluidMGAscend(texture2d<float, access::read>  pressure       [[texture(0)]],
                          texture2d<float, access::read>  pressureCoarse [[texture(1)]],
                          texture2d<float, access::read>  rhs            [[texture(2)]],
                          texture2d<float, access::write> pressureOut    [[texture(3)]],
                          uint2 gid [[thread_position_in_grid]],
                          uint2 tid [[thread_position_in_threadgroup]],
                          uint2 tgid [[threadgroup_position_in_grid]]) {
  threadgroup float p[kMGTile * kMGTile];
  threadgroup float f[kMGTile * kMGTile];
  threadgroup float coarse[kMGCoarseTile * kMGCoarseTile];

  int2 size = int2(pressure.get_width(), pressure.get_height());
  int2 origin = int2(tgid) * 16 - kMGMargin;
  uint lane = tid.y * 16u + tid.x;
  MGEntry entries[2] = { mgEntry(lane, origin, size), mgEntry(lane + 256u, origin, size) };

  int2 coarseOrigin = mgLoadCoarse(coarse, pressureCoarse, origin, lane);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgLoadCorrected(p, f, coarse, pressure, rhs, entries[n], 2, coarseOrigin);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 0u, 1);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 1u, 0);
  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (any(int2(gid) >= size)) return;
  uint own = (tid.y + uint(kMGMargin)) * uint(kMGTile) + tid.x + uint(kMGMargin);
  pressureOut.write(float4(p[own], 0, 0, 0), gid);
}

kernel void fluidMGAscendProject(texture2d<float, access::read>       pressure       [[texture(0)]],
                                 texture2d<float, access::read>       pressureCoarse [[texture(1)]],
                                 texture2d<float, access::read>       rhs            [[texture(2)]],
                                 texture2d<float, access::read_write> velocity       [[texture(3)]],
                                 constant float &maxSpeed [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]],
                                 uint2 tid [[thread_position_in_threadgroup]],
                                 uint2 tgid [[threadgroup_position_in_grid]]) {
  threadgroup float p[kMGTile * kMGTile];
  threadgroup float f[kMGTile * kMGTile];
  threadgroup float coarse[kMGCoarseTile * kMGCoarseTile];

  int2 size = int2(pressure.get_width(), pressure.get_height());
  int2 origin = int2(tgid) * 16 - kMGMargin;
  uint lane = tid.y * 16u + tid.x;
  MGEntry entries[2] = { mgEntry(lane, origin, size), mgEntry(lane + 256u, origin, size) };

  int2 coarseOrigin = mgLoadCoarse(coarse, pressureCoarse, origin, lane);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgLoadCorrected(p, f, coarse, pressure, rhs, entries[n], 3, coarseOrigin);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 0u, 2);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int n = 0; n < 2; n++) mgRelax(p, f, entries[n], 1u, 1);
  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (any(int2(gid) >= size)) return;
  uint own = (tid.y + uint(kMGMargin)) * uint(kMGTile) + tid.x + uint(kMGMargin);
  float pC = p[own];
  float pL = p[own - 1u];
  float pB = p[own - uint(kMGTile)];
  velocity.write(subtractPressureGradient(velocity.read(gid), pC, pL, pB, gid, maxSpeed), gid);
}

kernel void fluidDivergenceRHS(texture2d<float, access::read>  velocity [[texture(0)]],
                               texture2d<float, access::write> rhsOut   [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float div = faceDivergence(velocity, gid, w, h);
  rhsOut.write(float4(div, 0, 0, 0), gid);
}

inline float mgLocalRead(threadgroup const float *p, int x, int y, int w, int h) {
  x = clamp(x, 0, w - 1);
  y = clamp(y, 0, h - 1);
  return p[y * w + x];
}

kernel void fluidMGCoarseSolve(texture2d<float, access::read>  rhs         [[texture(0)]],
                               texture2d<float, access::write> pressureOut [[texture(1)]],
                               constant uint &sweeps [[buffer(0)]],
                               uint tid [[thread_index_in_threadgroup]],
                               uint threads [[threads_per_threadgroup]]) {
  constexpr uint MAX_CELLS = 2048;
  threadgroup float p[MAX_CELLS];
  threadgroup float f[MAX_CELLS];

  int w = int(rhs.get_width());
  int h = int(rhs.get_height());
  uint cells = uint(w * h);
  if (cells > MAX_CELLS) return;

  for (uint i = tid; i < cells; i += threads) {
    p[i] = 0.0f;
    f[i] = rhs.read(uint2(i % uint(w), i / uint(w))).x;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  for (uint s = 0; s < sweeps; s++) {
    for (uint colour = 0; colour < 2; colour++) {
      for (uint i = tid; i < cells; i += threads) {
        int x = int(i % uint(w));
        int y = int(i / uint(w));
        if (uint((x + y) & 1) != colour) continue;
        p[i] = (mgLocalRead(p, x - 1, y, w, h) + mgLocalRead(p, x + 1, y, w, h) +
                mgLocalRead(p, x, y - 1, w, h) + mgLocalRead(p, x, y + 1, w, h) - f[i]) * 0.25;
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
  }

  for (uint i = tid; i < cells; i += threads) {
    pressureOut.write(float4(p[i], 0, 0, 0), uint2(i % uint(w), i / uint(w)));
  }
}
