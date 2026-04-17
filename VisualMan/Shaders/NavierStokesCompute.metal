//
//  NavierStokesCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
using namespace metal;

struct SplatParams {
  float2 position;
  float radius;
  float _pad;
  float3 value;
  float _pad2;
};

kernel void fluidSplatBatch(texture2d<float, access::read_write> field [[texture(0)]],
                            constant SplatParams *splats [[buffer(0)]],
                            constant uint &splatCount [[buffer(1)]],
                            constant uint2 &regionOrigin [[buffer(2)]],
                            uint2 tid [[thread_position_in_grid]]) {
  uint2 gid = tid + regionOrigin;
  uint w = field.get_width();
  uint h = field.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 pos = float2(gid) + 0.5;

  bool anyNearby = false;
  for (uint i = 0; i < splatCount; i++) {
    float2 diff = pos - splats[i].position;
    if (dot(diff, diff) < 6.0 * splats[i].radius * splats[i].radius) {
      anyNearby = true;
      break;
    }
  }
  if (!anyNearby) return;

  float4 current = field.read(gid);
  for (uint i = 0; i < splatCount; i++) {
    float2 diff = pos - splats[i].position;
    float dist2 = dot(diff, diff);
    float r2 = splats[i].radius * splats[i].radius;
    float falloff = exp(-dist2 / r2);
    current.xyz += splats[i].value * falloff;
  }
  current.xyz = min(current.xyz, float3(1.5));
  field.write(current, gid);
}

kernel void fluidAdvect(texture2d<float, access::read> velocityIn [[texture(0)]],
                        texture2d<float, access::sample> fieldIn [[texture(1)]],
                        texture2d<float, access::write> fieldOut [[texture(2)]],
                        constant float &dt [[buffer(0)]],
                        constant float &dissipation [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldOut.get_width();
  uint h = fieldOut.get_height();

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 pos = float2(gid) + 0.5;
  float2 vel = velocityIn.read(gid).xy;
  float2 backPos = pos - dt * vel;
  float2 uv = backPos / float2(w, h);
  float4 result = fieldIn.sample(linearSampler, uv) * dissipation;
  fieldOut.write(result, gid);
}

kernel void fluidDivergence(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::write> divergenceOut [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();

  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float vR = velocity.read(right).x;
  float vL = velocity.read(left).x;
  float vT = velocity.read(up).y;
  float vB = velocity.read(down).y;

  float div = 0.5 * (vR - vL + vT - vB);
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
                                  uint2 gid [[thread_position_in_grid]]) {
  uint w = pressure.get_width();
  uint h = pressure.get_height();

  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float pL = pressure.read(left).x;
  float pR = pressure.read(right).x;
  float pB = pressure.read(down).x;
  float pT = pressure.read(up).x;

  float4 vel = velocity.read(gid);
  vel.x -= 0.5 * (pR - pL);
  vel.y -= 0.5 * (pT - pB);

  if (gid.x == 0u || gid.x == w - 1u) vel.x = 0;
  if (gid.y == 0u || gid.y == h - 1u) vel.y = 0;

  velocity.write(vel, gid);
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
  half brightness = dot(color.rgb, half3(0.299h, 0.587h, 0.114h));
  half contrib = max(brightness - threshold, 0.0h);
  half factor = contrib / max(brightness, 1e-4h);
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

inline float2 curlNoiseOffset(float2 uv, float t) {
  float a = sin(uv.x * 13.0 + t * 0.7)  + cos(uv.y *  9.0 - t * 0.55);
  float b = cos(uv.x *  7.0 - t * 0.6)  + sin(uv.y * 11.0 + t * 0.45);
  return float2(a, b);
}

inline float srgbEncode(float c) {
  c = max(c, 0.0);
  return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

struct FrameUniforms {
  float bass;
  float mid;
  float high;
  float time;
  float dt;
  float taaBlend;
  uint  historyValid;
  uint  _pad;
};

kernel void fluidRender(texture2d<float, access::sample> dye [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        texture2d<float, access::sample> bloomHi [[texture(2)]],
                        texture2d<float, access::sample> bloomMid [[texture(3)]],
                        texture2d<float, access::sample> bloomLo [[texture(4)]],
                        texture2d<float, access::read> historyIn [[texture(5)]],
                        texture2d<float, access::write> historyOut [[texture(6)]],
                        constant FrameUniforms &frame [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  float bass = frame.bass;
  float mid = frame.mid;
  float renderTime = frame.time;
  float taaBlend = frame.taaBlend;
  uint historyValid = frame.historyValid;
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 center = (float2(gid) + 0.5) / float2(w, h);
  float2 texel = 1.0 / float2(dye.get_width(), dye.get_height());

  float2 jitter = curlNoiseOffset(center, renderTime) * 0.0015;
  float2 sampleCenter = center + jitter;

  float4 color = float4(0);
  color += dye.sample(bilinear, sampleCenter + float2(-0.25, -0.75) * texel);
  color += dye.sample(bilinear, sampleCenter + float2( 0.75, -0.25) * texel);
  color += dye.sample(bilinear, sampleCenter + float2(-0.75,  0.25) * texel);
  color += dye.sample(bilinear, sampleCenter + float2( 0.25,  0.75) * texel);
  color *= 0.25;

  float3 cRGB = max(color.rgb, float3(0.0));

  float2 fromCenter = center - 0.5;
  float radialLen = length(fromCenter);
  if (radialLen > 1e-4) {
    float2 radialDir = fromCenter / radialLen;
    float caStrength = (frame.bass * 0.006 + frame.high * 0.002) * radialLen;
    if (caStrength > 1e-5) {
      float rCh = dye.sample(bilinear, sampleCenter + radialDir * caStrength).r;
      float bCh = dye.sample(bilinear, sampleCenter - radialDir * caStrength).b;
      cRGB.r = rCh;
      cRGB.b = bCh;
    }
  }
  float3 c = cRGB;

  float3 bHi  = bloomHi.sample(bilinear, sampleCenter).rgb;
  float3 bMid = bloomMid.sample(bilinear, sampleCenter).rgb;
  float3 bLo  = bloomLo.sample(bilinear, sampleCenter).rgb;

  float hiW  = 0.08 + frame.high * 0.40;
  float midW = 0.08 + frame.mid  * 0.40;
  float loW  = 0.08 + frame.bass * 0.55;
  c += bHi * hiW + bMid * midW + bLo * loW;

  c *= 1.0 + bass * 0.4 + mid * 0.25;

  float lum0 = dot(c, float3(0.299, 0.587, 0.114));
  float saturation = 1.8 + mid * 0.4;
  c = mix(float3(lum0), c, saturation);
  c = max(c, float3(0.0));

  float lum = dot(c, float3(0.299, 0.587, 0.114));
  float whitePoint = 4.0;
  float scaledLum = (lum * (1.0 + lum / (whitePoint * whitePoint))) / (1.0 + lum);
  c = c * (scaledLum / max(lum, 1e-4));
  c = clamp(c, 0.0, 1.0);

  float vDist = length(center - 0.5) * 1.414;
  float vAmount = 0.35 - frame.bass * 0.25;
  c *= 1.0 - vDist * vDist * vAmount;
  c = max(c, float3(0.0));

  c = float3(srgbEncode(c.r), srgbEncode(c.g), srgbEncode(c.b));

  float3 finalColor = c;
  if (historyValid != 0u) {
    float3 prev = historyIn.read(gid).rgb;
    finalColor = mix(c, prev, taaBlend);
  }

  float4 outColor = float4(finalColor, 1.0);
  output.write(outColor, gid);
  historyOut.write(outColor, gid);
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

kernel void fluidPsiAdvect(texture2d<float, access::read>  velocity [[texture(0)]],
                           texture2d<float, access::sample> psiIn   [[texture(1)]],
                           texture2d<float, access::write> psiOut   [[texture(2)]],
                           constant float &dt [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
  uint w = psiIn.get_width();
  uint h = psiIn.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 pos = float2(gid) + 0.5;
  float2 u   = velocity.read(gid).xy;

  float2 backPos = pos - dt * u;
  float2 uv = backPos / float2(w, h);
  float2 psiBack = psiIn.sample(linearSampler, uv).xy;

  psiOut.write(float4(psiBack, 0, 0), gid);
}

kernel void fluidPsiMacCormackCorrect(texture2d<float, access::sample> psiN     [[texture(0)]],
                                      texture2d<float, access::sample> psiHat1  [[texture(1)]],
                                      texture2d<float, access::sample> psiHat0  [[texture(2)]],
                                      texture2d<float, access::read>   velocity [[texture(3)]],
                                      texture2d<float, access::write>  psiOut   [[texture(4)]],
                                      constant float &dt [[buffer(0)]],
                                      uint2 gid [[thread_position_in_grid]]) {
  uint w = psiOut.get_width();
  uint h = psiOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 pos = float2(gid) + 0.5;
  float2 vel = velocity.read(gid).xy;
  float2 backPos = pos - dt * vel;
  float2 invSize = 1.0 / float2(w, h);

  float2 forward  = psiHat1.sample(linearSampler, backPos * invSize).xy;
  float2 backward = psiHat0.sample(linearSampler, pos * invSize).xy;
  float2 source   = psiN.sample(linearSampler, backPos * invSize).xy;

  float2 corrected = forward + 0.5 * (source - backward);

  psiOut.write(float4(corrected, 0, 0), gid);
}

kernel void fluidCovectorPullback(texture2d<float, access::read>   psi  [[texture(0)]],
                                  texture2d<float, access::sample> u0   [[texture(1)]],
                                  texture2d<float, access::write>  uOut [[texture(2)]],
                                  constant float &dissipation [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  int w = int(psi.get_width());
  int h = int(psi.get_height());
  if (int(gid.x) >= w || int(gid.y) >= h) return;

  int xL = max(int(gid.x) - 1, 0);
  int xR = min(int(gid.x) + 1, w - 1);
  int yD = max(int(gid.y) - 1, 0);
  int yU = min(int(gid.y) + 1, h - 1);

  float2 psiL = psi.read(uint2(uint(xL), gid.y)).xy;
  float2 psiR = psi.read(uint2(uint(xR), gid.y)).xy;
  float2 psiD = psi.read(uint2(gid.x, uint(yD))).xy;
  float2 psiU = psi.read(uint2(gid.x, uint(yU))).xy;
  float2 psiC = psi.read(gid).xy;

  float invDx = 1.0 / float(xR - xL);
  float invDy = 1.0 / float(yU - yD);
  float2 dpsi_dx = invDx * (psiR - psiL);
  float2 dpsi_dy = invDy * (psiU - psiD);

  {
    float2 dev_x = dpsi_dx - float2(1, 0);
    float2 dev_y = dpsi_dy - float2(0, 1);
    float devNorm = max(length(dev_x), length(dev_y));
    if (devNorm > 0.5) {
      float scale = 0.5 / devNorm;
      dpsi_dx = float2(1, 0) + dev_x * scale;
      dpsi_dy = float2(0, 1) + dev_y * scale;
    }
  }

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  float2 uv = psiC / float2(float(w), float(h));
  float2 u0val = u0.sample(linearSampler, uv).xy;

  float2 u;
  u.x = dpsi_dx.x * u0val.x + dpsi_dx.y * u0val.y;
  u.y = dpsi_dy.x * u0val.x + dpsi_dy.y * u0val.y;

  u *= dissipation;

  if (any(isnan(u)) || any(isinf(u))) u = float2(0);
  float sp = length(u);
  if (sp > 500.0) u *= 500.0 / sp;

  uOut.write(float4(u, 0, 0), gid);
}

kernel void fluidClearRG(texture2d<float, access::write> t [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
  t.write(float4(0), gid);
}

kernel void fluidClearRGBA(texture2d<float, access::write> t [[texture(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= t.get_width() || gid.y >= t.get_height()) return;
  t.write(float4(0), gid);
}

kernel void fluidCurl(texture2d<float, access::read> velocity [[texture(0)]],
                      texture2d<float, access::write> curlOut [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;
  uint2 L = uint2(max(int(gid.x) - 1, 0),     gid.y);
  uint2 R = uint2(min(int(gid.x) + 1, int(w) - 1), gid.y);
  uint2 D = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 U = uint2(gid.x, min(int(gid.y) + 1, int(h) - 1));
  float dvy_dx = 0.5 * (velocity.read(R).y - velocity.read(L).y);
  float dvx_dy = 0.5 * (velocity.read(U).x - velocity.read(D).x);
  curlOut.write(float4(dvy_dx - dvx_dy, 0, 0, 0), gid);
}

kernel void fluidVorticityConfinement(texture2d<float, access::read> curl [[texture(0)]],
                                      texture2d<float, access::read_write> velocity [[texture(1)]],
                                      constant float &dt [[buffer(0)]],
                                      constant float &epsilon [[buffer(1)]],
                                      uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;
  uint2 L = uint2(max(int(gid.x) - 1, 0),     gid.y);
  uint2 R = uint2(min(int(gid.x) + 1, int(w) - 1), gid.y);
  uint2 D = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 U = uint2(gid.x, min(int(gid.y) + 1, int(h) - 1));

  float cL = abs(curl.read(L).x);
  float cR = abs(curl.read(R).x);
  float cD = abs(curl.read(D).x);
  float cU = abs(curl.read(U).x);
  float cC = curl.read(gid).x;

  float2 grad = float2(0.5 * (cR - cL), 0.5 * (cU - cD));
  float len = length(grad) + 1e-5;
  float2 N = grad / len;
  float2 force = epsilon * float2(N.y, -N.x) * cC;

  float4 vel = velocity.read(gid);
  vel.xy += dt * force;
  velocity.write(vel, gid);
}

kernel void fluidMacCormackCorrect(texture2d<float, access::sample> phiN     [[texture(0)]],
                                   texture2d<float, access::sample> phiHat1  [[texture(1)]],
                                   texture2d<float, access::sample> phiHat0  [[texture(2)]],
                                   texture2d<float, access::read>   velocity [[texture(3)]],
                                   texture2d<float, access::write>  phiOut   [[texture(4)]],
                                   constant float &dt [[buffer(0)]],
                                   constant float &dissipation [[buffer(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
  uint w = phiOut.get_width();
  uint h = phiOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 pos = float2(gid) + 0.5;
  float2 vel = velocity.read(gid).xy;
  float2 backPos = pos - dt * vel;
  float2 invSize = 1.0 / float2(w, h);

  float4 forward = phiHat1.sample(linearSampler, backPos * invSize);
  float4 backward = phiHat0.sample(linearSampler, pos * invSize);
  float4 source = phiN.sample(linearSampler, backPos * invSize);

  float4 corrected = forward + 0.5 * (source - backward);

  int2 base = int2(floor(backPos - 0.5));
  int2 c00 = clamp(base,              int2(0), int2(w - 1, h - 1));
  int2 c10 = clamp(base + int2(1, 0), int2(0), int2(w - 1, h - 1));
  int2 c01 = clamp(base + int2(0, 1), int2(0), int2(w - 1, h - 1));
  int2 c11 = clamp(base + int2(1, 1), int2(0), int2(w - 1, h - 1));
  float4 s00 = phiN.read(uint2(c00));
  float4 s10 = phiN.read(uint2(c10));
  float4 s01 = phiN.read(uint2(c01));
  float4 s11 = phiN.read(uint2(c11));
  float4 lo = min(min(s00, s10), min(s01, s11));
  float4 hi = max(max(s00, s10), max(s01, s11));

  corrected = clamp(corrected, lo, hi);
  corrected *= dissipation;
  phiOut.write(corrected, gid);
}

kernel void fluidDyeDiffuse(texture2d<half, access::read>  dyeIn  [[texture(0)]],
                            texture2d<half, access::write> dyeOut [[texture(1)]],
                            constant float &baseStrengthF [[buffer(0)]],
                            constant float &edgeBoostF    [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = dyeIn.get_width();
  uint h = dyeIn.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 L = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 R = uint2(min(gid.x + 1, w - 1),  gid.y);
  uint2 D = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 U = uint2(gid.x, min(gid.y + 1, h - 1));

  half4 c  = dyeIn.read(gid);
  half4 cL = dyeIn.read(L);
  half4 cR = dyeIn.read(R);
  half4 cD = dyeIn.read(D);
  half4 cU = dyeIn.read(U);
  half4 neighbours = (cL + cR + cD + cU) * 0.25h;

  half3 gradVec = neighbours.xyz - c.xyz;
  half gradMag = length(gradVec);

  half edgeT = min(gradMag * 3.0h, 1.0h);

  half s = half(baseStrengthF) + half(edgeBoostF) * edgeT;
  s = min(s, 0.35h);

  dyeOut.write(mix(c, neighbours, s), gid);
}
