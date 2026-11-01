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
  float weight;
};

struct FrameUniforms {
  float bass;
  float mid;
  float high;
  float time;
  float dt;
  float taaBlend;
  uint  historyValid;
  uint  _pad;
  float shading;
  float detail;
  float jitter;
  float thinFade;
};

inline float4 sampleCatmullRom(texture2d<float, access::sample> tex, sampler s,
                               float2 uv, float2 texSize) {
  float2 samplePos = uv * texSize;
  float2 texPos1 = floor(samplePos - 0.5) + 0.5;
  float2 f = samplePos - texPos1;

  float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  float2 w3 = f * f * (-0.5 + 0.5 * f);
  float2 w12 = w1 + w2;
  float2 offset12 = w2 / w12;

  float2 texPos0  = (texPos1 - 1.0) / texSize;
  float2 texPos3  = (texPos1 + 2.0) / texSize;
  float2 texPos12 = (texPos1 + offset12) / texSize;

  float4 result = float4(0.0);
  result += tex.sample(s, float2(texPos0.x,  texPos0.y))  * w0.x  * w0.y;
  result += tex.sample(s, float2(texPos12.x, texPos0.y))  * w12.x * w0.y;
  result += tex.sample(s, float2(texPos3.x,  texPos0.y))  * w3.x  * w0.y;
  result += tex.sample(s, float2(texPos0.x,  texPos12.y)) * w0.x  * w12.y;
  result += tex.sample(s, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
  result += tex.sample(s, float2(texPos3.x,  texPos12.y)) * w3.x  * w12.y;
  result += tex.sample(s, float2(texPos0.x,  texPos3.y))  * w0.x  * w3.y;
  result += tex.sample(s, float2(texPos12.x, texPos3.y))  * w12.x * w3.y;
  result += tex.sample(s, float2(texPos3.x,  texPos3.y))  * w3.x  * w3.y;
  return result;
}

kernel void fluidSplatBatch(texture2d<float, access::read_write> field [[texture(0)]],
                            constant SplatParams *splats [[buffer(0)]],
                            constant uint &splatCount [[buffer(1)]],
                            constant uint2 &regionOrigin [[buffer(2)]],
                            constant uint &velocityMode [[buffer(3)]],
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
    if (velocityMode != 0u) {
      float weight = min(falloff * splats[i].value.z, 1.0);
      current.xy = mix(current.xy, splats[i].value.xy, weight);
    } else {
      current.xyz += splats[i].value * falloff;
      current.w += splats[i].weight * falloff;
    }
  }
  if (!anyHit) return;
  if (velocityMode == 0u) {
    current.xyz = min(current.xyz, float3(1.5));
    current.w = clamp(current.w, -1.5, 1.5);
  }
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
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

  float2 pos = float2(gid) + 0.5;
  float2 vel = velocityIn.read(gid).xy;
  float2 backPos = pos - dt * vel;
  float2 size = float2(w, h);
  float4 result = sampleCatmullRom(fieldIn, linearSampler, backPos / size, size) * dissipation;
  fieldOut.write(result, gid);
}

kernel void fluidDivergence(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::write> divergenceOut [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;

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
  if (gid.x >= w || gid.y >= h) return;

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

inline float dyeDensity(float4 d) {
  return max(d.r, max(d.g, d.b));
}

inline float2 curlNoiseOffset(float2 uv, float t) {
  float a = fast::sin(uv.x * 13.0 + t * 0.7)  + fast::cos(uv.y *  9.0 - t * 0.55);
  float b = fast::cos(uv.x *  7.0 - t * 0.6)  + fast::sin(uv.y * 11.0 + t * 0.45);
  return float2(a, b);
}

kernel void fluidRender(texture2d<float, access::sample> dye [[texture(0)]],
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
  uint w = historyOut.get_width();
  uint h = historyOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 center = (float2(gid) + 0.5) / float2(w, h);
  float2 dyeSize = float2(dye.get_width(), dye.get_height());
  float2 texel = 1.0 / dyeSize;

  float2 jitter = curlNoiseOffset(center, renderTime) * frame.jitter;
  float2 sampleCenter = center + jitter;

  float dL = dyeDensity(dye.sample(bilinear, sampleCenter - float2(1.5, 0.0) * texel));
  float dR = dyeDensity(dye.sample(bilinear, sampleCenter + float2(1.5, 0.0) * texel));
  float dD = dyeDensity(dye.sample(bilinear, sampleCenter - float2(0.0, 1.5) * texel));
  float dU = dyeDensity(dye.sample(bilinear, sampleCenter + float2(0.0, 1.5) * texel));
  float2 grad = float2(dR - dL, dU - dD) / 3.0;
  float gradMag = fast::length(grad);

  float2 detailWarp = curlNoiseOffset(center * 2.5, renderTime * 1.1)
                    * texel * frame.detail * saturate(gradMag * 3.0);

  float4 color = sampleCatmullRom(dye, bilinear, sampleCenter + detailWarp, dyeSize);
  float3 cRGB = max(color.rgb, float3(0.0));

  float thin = pow(saturate(dyeDensity(color) / max(frame.thinFade, 1e-3)), 0.6);
  cRGB *= thin;

  float2 fromCenter = center - 0.5;
  float radialLen = fast::length(fromCenter);
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

  {
    float3 n = normalize(float3(-grad * 6.0, 1.0));
    const float3 lightDir = normalize(float3(-0.45, -0.6, 0.65));
    float diffuse = max(dot(n, lightDir), 0.0);
    float shade = mix(1.0, 0.5 + 0.8 * diffuse, frame.shading);
    c *= shade;
  }

  float lum0 = dot(c, float3(0.299, 0.587, 0.114));
  float saturation = 1.8 + mid * 0.4;
  c = mix(float3(lum0), c, saturation);
  c = max(c, float3(0.0));

  float lum = dot(c, float3(0.299, 0.587, 0.114));
  float whitePoint = 4.0;
  float scaledLum = (lum * (1.0 + lum / (whitePoint * whitePoint))) / (1.0 + lum);
  c = c * (scaledLum / max(lum, 1e-4));
  c = clamp(c, 0.0, 1.0);

  float vDist = fast::length(center - 0.5) * 1.414;
  float vAmount = 0.35 - frame.bass * 0.25;
  c *= 1.0 - vDist * vDist * vAmount;
  c = max(c, float3(0.0));

  float3 finalColor = c;
  if (historyValid != 0u) {
    float3 prev = historyIn.read(gid).rgb;
    finalColor = mix(c, prev, taaBlend);
  }

  historyOut.write(float4(finalColor, 1.0), gid);
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

  float2 forward  = psiHat1.read(gid).xy;
  float2 backward = psiHat1.sample(linearSampler, (pos + dt * vel) * invSize).xy;
  float2 source   = psiN.read(gid).xy;

  float2 corrected = forward + 0.5 * (source - backward);

  int2 base = int2(floor(backPos - 0.5));
  int2 maxCoord = int2(w - 1, h - 1);
  float2 s00 = psiN.read(uint2(clamp(base,              int2(0), maxCoord))).xy;
  float2 s10 = psiN.read(uint2(clamp(base + int2(1, 0), int2(0), maxCoord))).xy;
  float2 s01 = psiN.read(uint2(clamp(base + int2(0, 1), int2(0), maxCoord))).xy;
  float2 s11 = psiN.read(uint2(clamp(base + int2(1, 1), int2(0), maxCoord))).xy;
  float2 lo = min(min(s00, s10), min(s01, s11));
  float2 hi = max(max(s00, s10), max(s01, s11));
  corrected = clamp(corrected, lo, hi);

  psiOut.write(float4(corrected, 0, 0), gid);
}

kernel void fluidCovectorPullback(texture2d<float, access::read>   psi  [[texture(0)]],
                                  texture2d<float, access::sample> u0   [[texture(1)]],
                                  texture2d<float, access::write>  uOut [[texture(2)]],
                                  constant float &dissipation [[buffer(0)]],
                                  device atomic_uint *stats [[buffer(1)]],
                                  constant float &stretchThreshold [[buffer(2)]],
                                  constant float &maxSpeed [[buffer(3)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  int w = int(psi.get_width());
  int h = int(psi.get_height());
  bool inBounds = int(gid.x) < w && int(gid.y) < h;
  uint stretched = 0u;
  uint fast = 0u;

  if (inBounds) {
    int xL = max(int(gid.x) - 1, 0);
    int xR = min(int(gid.x) + 1, w - 1);
    int yD = max(int(gid.y) - 1, 0);
    int yU = min(int(gid.y) + 1, h - 1);

    float2 psiL = psi.read(uint2(uint(xL), gid.y)).xy;
    float2 psiR = psi.read(uint2(uint(xR), gid.y)).xy;
    float2 psiD = psi.read(uint2(gid.x, uint(yD))).xy;
    float2 psiU = psi.read(uint2(gid.x, uint(yU))).xy;
    float2 psiC = psi.read(gid).xy;

    half invDx = (xR != xL) ? half(1.0 / float(xR - xL)) : 0.5h;
    half invDy = (yU != yD) ? half(1.0 / float(yU - yD)) : 0.5h;
    half2 dpsi_dx = half2(psiR - psiL) * invDx;
    half2 dpsi_dy = half2(psiU - psiD) * invDy;

    {
      half2 dev_x = dpsi_dx - half2(1, 0);
      half2 dev_y = dpsi_dy - half2(0, 1);
      half devNorm = max(length(dev_x), length(dev_y));
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
      if (devNorm > 0.5h) {
        half scale = 0.5h / devNorm;
        dpsi_dx = half2(1, 0) + dev_x * scale;
        dpsi_dy = half2(0, 1) + dev_y * scale;
      }
    }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 uv = psiC / float2(float(w), float(h));
    half2 u0val = half2(u0.sample(linearSampler, uv).xy);

    half2 uh;
    uh.x = dpsi_dx.x * u0val.x + dpsi_dx.y * u0val.y;
    uh.y = dpsi_dy.x * u0val.x + dpsi_dy.y * u0val.y;

    float2 u = float2(uh) * dissipation;

    if (any(isnan(u)) || any(isinf(u))) u = float2(0);
    float sp = fast::length(u);
    fast = (sp > 0.5 * maxSpeed) ? 1u : 0u;
    if (sp > maxSpeed) u *= maxSpeed / sp;

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

kernel void fluidVorticityConfinementMerged(texture2d<float, access::read_write> velocity [[texture(0)]],
                                             texture2d<float, access::read> dye [[texture(1)]],
                                             constant float &dt [[buffer(0)]],
                                             constant float &epsilon [[buffer(1)]],
                                             constant float &buoyancy [[buffer(2)]],
                                             constant float &settleSpeed [[buffer(3)]],
                                             uint2 gid [[thread_position_in_grid]],
                                             uint2 tid [[thread_position_in_threadgroup]],
                                             uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();

  constexpr uint TILE = 22;
  threadgroup float2 velTile[TILE * TILE];

  int tileOriginX = int(tgid.x * 16) - 3;
  int tileOriginY = int(tgid.y * 16) - 3;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    uint tx = idx % TILE;
    uint ty = idx / TILE;
    int gx = clamp(tileOriginX + int(tx), 0, int(w) - 1);
    int gy = clamp(tileOriginY + int(ty), 0, int(h) - 1);
    velTile[idx] = velocity.read(uint2(gx, gy)).xy;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  uint lx = tid.x + 3;
  uint ly = tid.y + 3;

  #define CURL_AT(cx, cy) ( \
    0.25f * (velTile[(cy) * TILE + (cx) + 2].y - velTile[(cy) * TILE + (cx) - 2].y) - \
    0.25f * (velTile[((cy) + 2) * TILE + (cx)].x - velTile[((cy) - 2) * TILE + (cx)].x) )

  float curlC = CURL_AT(lx, ly);
  float curlL = CURL_AT(lx - 1, ly);
  float curlR = CURL_AT(lx + 1, ly);
  float curlD = CURL_AT(lx, ly - 1);
  float curlU = CURL_AT(lx, ly + 1);
  #undef CURL_AT

  float2 grad = float2(0.5 * (abs(curlR) - abs(curlL)), 0.5 * (abs(curlU) - abs(curlD)));
  float len = fast::length(grad) + 1e-5;
  float2 N = grad / len;
  float2 force = epsilon * float2(N.y, -N.x) * curlC;

  float4 vel = velocity.read(gid);
  vel.xy += dt * force;
  float settle = 1.0 - saturate(fast::length(vel.xy) / settleSpeed);
  vel.y += dt * buoyancy * dye.read(gid).w * settle;
  velocity.write(vel, gid);
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

kernel void fluidMacCormackCorrect(texture2d<float, access::sample> phiN     [[texture(0)]],
                                   texture2d<float, access::sample> phiHat1  [[texture(1)]],
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

  float4 forward = phiHat1.read(gid);
  float4 backward = phiHat1.sample(linearSampler, (pos + dt * vel) * invSize);
  float4 source = phiN.read(gid);

  float4 corrected = forward + 0.5 * (source - backward);

  int2 base = int2(floor(backPos - 0.5));
  int2 maxCoord = int2(w - 1, h - 1);
  int2 c00 = clamp(base,              int2(0), maxCoord);
  int2 c10 = clamp(base + int2(1, 0), int2(0), maxCoord);
  int2 c01 = clamp(base + int2(0, 1), int2(0), maxCoord);
  int2 c11 = clamp(base + int2(1, 1), int2(0), maxCoord);
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
                            constant float2 &edgeFade     [[buffer(2)]],
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
  out *= half(1.0 - edgeFade.y * (1.0 - inside));

  dyeOut.write(out, gid);
}

template <access A>
inline float mgRead(texture2d<float, A> t, int x, int y, int w, int h, bool neumann) {
  if (neumann) {
    x = clamp(x, 0, w - 1);
    y = clamp(y, 0, h - 1);
  } else if (x < 0 || y < 0 || x >= w || y >= h) {
    return 0.0f;
  }
  return t.read(uint2(uint(x), uint(y))).x;
}

kernel void fluidDivergenceRHS(texture2d<float, access::read>  velocity    [[texture(0)]],
                               texture2d<float, access::write> rhsOut      [[texture(1)]],
                               texture2d<float, access::write> pressureOut [[texture(2)]],
                               uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float div = 0.5 * (velocity.read(right).x - velocity.read(left).x +
                     velocity.read(up).y    - velocity.read(down).y);
  rhsOut.write(float4(div, 0, 0, 0), gid);
  pressureOut.write(float4(0), gid);
}

kernel void fluidVorticityRHS(texture2d<float, access::read> velocity [[texture(0)]],
                              texture2d<float, access::write> rhsOut [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float vR = velocity.read(right).y;
  float vL = velocity.read(left).y;
  float uT = velocity.read(up).x;
  float uB = velocity.read(down).x;

  float omega = 0.5 * (vR - vL) - 0.5 * (uT - uB);
  rhsOut.write(float4(-omega, 0, 0, 0), gid);
}

kernel void fluidMGSmooth(texture2d<float, access::read_write> psi [[texture(0)]],
                          texture2d<float, access::read> rhs [[texture(1)]],
                          constant uint &neumann [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]],
                          uint2 tid [[thread_position_in_threadgroup]],
                          uint2 tgid [[threadgroup_position_in_grid]]) {
  constexpr uint TILE = 18;
  threadgroup float tile[TILE * TILE];

  int w = int(psi.get_width());
  int h = int(psi.get_height());

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    int gx = tileOriginX + int(idx % TILE);
    int gy = tileOriginY + int(idx / TILE);
    tile[idx] = mgRead(psi, gx, gy, w, h, neumann != 0u);
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  bool inBounds = int(gid.x) < w && int(gid.y) < h;
  float f = inBounds ? rhs.read(gid).x : 0.0f;
  uint myIdx = (tid.y + 1) * TILE + (tid.x + 1);
  bool isRed = ((gid.x + gid.y) & 1u) == 0u;

  if (isRed && inBounds) {
    tile[myIdx] = (tile[myIdx - 1] + tile[myIdx + 1] +
                   tile[myIdx - TILE] + tile[myIdx + TILE] - f) * 0.25;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (!isRed && inBounds) {
    tile[myIdx] = (tile[myIdx - 1] + tile[myIdx + 1] +
                   tile[myIdx - TILE] + tile[myIdx + TILE] - f) * 0.25;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (inBounds) {
    psi.write(float4(tile[myIdx], 0, 0, 0), gid);
  }
}

kernel void fluidMGRestrict(texture2d<float, access::read>  psiFine   [[texture(0)]],
                            texture2d<float, access::read>  rhsFine   [[texture(1)]],
                            texture2d<float, access::write> rhsCoarse [[texture(2)]],
                            texture2d<float, access::write> psiCoarse [[texture(3)]],
                            constant uint &neumann [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
  bool nm = neumann != 0u;
  int cw = int(rhsCoarse.get_width());
  int ch = int(rhsCoarse.get_height());
  if (int(gid.x) >= cw || int(gid.y) >= ch) return;

  int fw = int(psiFine.get_width());
  int fh = int(psiFine.get_height());

  float sum = 0.0f;
  for (int dy = 0; dy < 2; dy++) {
    for (int dx = 0; dx < 2; dx++) {
      int x = int(gid.x) * 2 + dx;
      int y = int(gid.y) * 2 + dy;
      if (x >= fw || y >= fh) continue;
      float c = psiFine.read(uint2(uint(x), uint(y))).x;
      float lap = mgRead(psiFine, x - 1, y, fw, fh, nm)
                + mgRead(psiFine, x + 1, y, fw, fh, nm)
                + mgRead(psiFine, x, y - 1, fw, fh, nm)
                + mgRead(psiFine, x, y + 1, fw, fh, nm)
                - 4.0f * c;
      sum += rhsFine.read(uint2(uint(x), uint(y))).x - lap;
    }
  }
  rhsCoarse.write(float4(sum, 0, 0, 0), gid);
  psiCoarse.write(float4(0), gid);
}

kernel void fluidMGProlong(texture2d<float, access::read>       psiCoarse [[texture(0)]],
                           texture2d<float, access::read_write> psiFine   [[texture(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
  int fw = int(psiFine.get_width());
  int fh = int(psiFine.get_height());
  if (int(gid.x) >= fw || int(gid.y) >= fh) return;

  int cw = int(psiCoarse.get_width());
  int ch = int(psiCoarse.get_height());

  float2 cpos = (float2(gid) + 0.5) * 0.5 - 0.5;
  int2 base = int2(floor(cpos));
  float2 fr = cpos - float2(base);

  int x0 = clamp(base.x,     0, cw - 1);
  int x1 = clamp(base.x + 1, 0, cw - 1);
  int y0 = clamp(base.y,     0, ch - 1);
  int y1 = clamp(base.y + 1, 0, ch - 1);

  float c00 = psiCoarse.read(uint2(uint(x0), uint(y0))).x;
  float c10 = psiCoarse.read(uint2(uint(x1), uint(y0))).x;
  float c01 = psiCoarse.read(uint2(uint(x0), uint(y1))).x;
  float c11 = psiCoarse.read(uint2(uint(x1), uint(y1))).x;

  float e = mix(mix(c00, c10, fr.x), mix(c01, c11, fr.x), fr.y);

  float4 p = psiFine.read(gid);
  p.x += e;
  psiFine.write(p, gid);
}

inline float mgLocalRead(threadgroup const float *p, int x, int y, int w, int h, bool neumann) {
  if (neumann) {
    x = clamp(x, 0, w - 1);
    y = clamp(y, 0, h - 1);
  } else if (x < 0 || y < 0 || x >= w || y >= h) {
    return 0.0f;
  }
  return p[y * w + x];
}

kernel void fluidMGCoarseSolve(texture2d<float, access::read_write> psi [[texture(0)]],
                               texture2d<float, access::read> rhs [[texture(1)]],
                               constant uint &neumann [[buffer(0)]],
                               constant uint &sweeps [[buffer(1)]],
                               uint tid [[thread_index_in_threadgroup]],
                               uint threads [[threads_per_threadgroup]]) {
  constexpr uint MAX_CELLS = 2048;
  threadgroup float p[MAX_CELLS];
  threadgroup float f[MAX_CELLS];

  int w = int(psi.get_width());
  int h = int(psi.get_height());
  uint cells = uint(w * h);
  if (cells > MAX_CELLS) return;
  bool nm = neumann != 0u;

  for (uint i = tid; i < cells; i += threads) {
    uint2 c = uint2(i % uint(w), i / uint(w));
    p[i] = psi.read(c).x;
    f[i] = rhs.read(c).x;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  for (uint s = 0; s < sweeps; s++) {
    for (uint colour = 0; colour < 2; colour++) {
      for (uint i = tid; i < cells; i += threads) {
        int x = int(i % uint(w));
        int y = int(i / uint(w));
        if (uint((x + y) & 1) != colour) continue;
        p[i] = (mgLocalRead(p, x - 1, y, w, h, nm) + mgLocalRead(p, x + 1, y, w, h, nm) +
                mgLocalRead(p, x, y - 1, w, h, nm) + mgLocalRead(p, x, y + 1, w, h, nm) - f[i]) * 0.25;
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
  }

  for (uint i = tid; i < cells; i += threads) {
    psi.write(float4(p[i], 0, 0, 0), uint2(i % uint(w), i / uint(w)));
  }
}

kernel void fluidCurlPsi(texture2d<float, access::read>  psi         [[texture(0)]],
                         texture2d<float, access::write> velocityOut [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
  int w = int(psi.get_width());
  int h = int(psi.get_height());
  if (int(gid.x) >= w || int(gid.y) >= h) return;

  int x = int(gid.x);
  int y = int(gid.y);
  float pL = mgRead(psi, x - 1, y, w, h, false);
  float pR = mgRead(psi, x + 1, y, w, h, false);
  float pD = mgRead(psi, x, y - 1, w, h, false);
  float pU = mgRead(psi, x, y + 1, w, h, false);

  float2 u = float2(0.5 * (pU - pD), -0.5 * (pR - pL));

  if (x == 0 || x == w - 1) u.x = 0;
  if (y == 0 || y == h - 1) u.y = 0;
  if (any(isnan(u)) || any(isinf(u))) u = float2(0);

  velocityOut.write(float4(u, 0, 0), gid);
}

kernel void fluidViscosity(texture2d<float, access::read>  velocityIn  [[texture(0)]],
                           texture2d<float, access::write> velocityOut [[texture(1)]],
                           constant float &alpha [[buffer(0)]],
                           constant float &maxSpeed [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]],
                           uint2 tid [[thread_position_in_threadgroup]],
                           uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = velocityIn.get_width();
  uint h = velocityIn.get_height();

  constexpr uint TILE = 18;
  threadgroup float2 tile[TILE * TILE];

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    int gx = clamp(tileOriginX + int(idx % TILE), 0, int(w) - 1);
    int gy = clamp(tileOriginY + int(idx / TILE), 0, int(h) - 1);
    tile[idx] = velocityIn.read(uint2(gx, gy)).xy;
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  uint c = (tid.y + 1) * TILE + (tid.x + 1);
  float2 centre = tile[c];
  float2 blurred =
      (tile[c - TILE - 1] + 2.0 * tile[c - TILE] + tile[c - TILE + 1] +
       2.0 * tile[c - 1]  + 4.0 * centre         + 2.0 * tile[c + 1] +
       tile[c + TILE - 1] + 2.0 * tile[c + TILE] + tile[c + TILE + 1]) * (1.0 / 16.0);

  float2 u = mix(centre, blurred, alpha);

  if (any(isnan(u)) || any(isinf(u))) u = float2(0);
  float sp = fast::length(u);
  if (sp > maxSpeed) u *= maxSpeed / sp;

  if (gid.x == 0u || gid.x == w - 1u) u.x = 0;
  if (gid.y == 0u || gid.y == h - 1u) u.y = 0;

  velocityOut.write(float4(u, 0, 0), gid);
}
