//
//  FireworksShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

static inline float3 bassColor(uint palette, uint variant) {
  uint idx = (palette * 3 + variant) % 9;
  switch (idx) {
    case 0: return float3(1.0, 0.25, 0.05);
    case 1: return float3(1.0, 0.6, 0.1);
    case 2: return float3(1.0, 0.85, 0.2);
    case 3: return float3(0.9, 0.1, 0.1);
    case 4: return float3(1.0, 0.45, 0.0);
    case 5: return float3(0.95, 0.75, 0.4);
    case 6: return float3(0.8, 0.15, 0.0);
    case 7: return float3(1.0, 0.5, 0.2);
    default: return float3(1.0, 0.95, 0.5);
  }
}

static inline float3 midColor(uint palette, uint variant) {
  uint idx = (palette * 3 + variant) % 9;
  switch (idx) {
    case 0: return float3(0.2, 1.0, 0.3);
    case 1: return float3(0.1, 0.9, 0.7);
    case 2: return float3(0.8, 1.0, 0.2);
    case 3: return float3(0.0, 0.8, 0.5);
    case 4: return float3(0.4, 1.0, 0.8);
    case 5: return float3(0.6, 0.9, 0.1);
    case 6: return float3(0.0, 0.7, 0.4);
    case 7: return float3(0.3, 1.0, 0.6);
    default: return float3(0.9, 1.0, 0.7);
  }
}

static inline float3 trebleColor(uint palette, uint variant) {
  uint idx = (palette * 3 + variant) % 9;
  switch (idx) {
    case 0: return float3(0.3, 0.4, 1.0);
    case 1: return float3(0.7, 0.3, 1.0);
    case 2: return float3(1.0, 0.3, 0.8);
    case 3: return float3(0.2, 0.6, 1.0);
    case 4: return float3(0.5, 0.1, 0.9);
    case 5: return float3(1.0, 0.5, 0.7);
    case 6: return float3(0.1, 0.3, 0.9);
    case 7: return float3(0.8, 0.2, 0.9);
    default: return float3(0.7, 0.7, 1.0);
  }
}

static inline float3 bandColor(uint band, uint palette, uint variant) {
  if (band == 0) return bassColor(palette, variant);
  if (band == 1) return midColor(palette, variant);
  return trebleColor(palette, variant);
}

static inline void addExplosion(thread float3 &col, float2 uv, float2 origin,
                                float phase, uint particleCount, float spread,
                                uint band, uint palette, float intensity,
                                float seed) {
  float maxReach = spread * 1.2 + phase * phase * 0.06;
  float2 diff0 = uv - origin;
  if (abs(diff0.x) > maxReach || abs(diff0.y) > maxReach) return;

  if (phase < 0.1) {
    float flashDist = length(diff0);
    float3 flashCol = bandColor(band, palette, 0);
    float flash = exp(-flashDist * 600.0) * (1.0 - phase / 0.1) * intensity * 1.5;
    col += flash * mix(float3(1.0), flashCol, 0.3);
  }

  float drag = 3.0;
  float gravity = 0.12;

  for (uint p = 0; p < particleCount; p++) {
    float3 rand = shaderRand3(seed + float(p) * 1.618);
    float angle = rand.x * PI * 2.0;
    float speed = (0.3 + rand.y * 0.7) * spread;

    float dragFactor = (1.0 - exp(-drag * phase)) / drag;
    float2 vel = float2(cos(angle), sin(angle)) * speed;
    float2 sparkPos = origin + vel * dragFactor;
    sparkPos.y += gravity * (phase * phase * 0.5);

    float2 diff = uv - sparkPos;
    float dist2 = dot(diff, diff);
    if (dist2 > 0.04) continue;

    float dist = sqrt(dist2);
    float glow = pow(0.008 / (dist + 0.008), 2.0);

    float lifetime = 1.8 + rand.z * 1.2;
    float life = clamp(phase / lifetime, 0.0, 1.0);
    float fade = (1.0 - life) * (1.0 - life);

    float sparkle = 1.0 + 0.3 * sin(phase * 18.0 + float(p) * 5.3);

    float3 baseColor = bandColor(band, palette, p);

    float3 pCol = mix(float3(1.0, 0.95, 0.8), baseColor, clamp(life * 8.0, 0.0, 1.0));

    col += glow * fade * pCol * intensity * sparkle;
  }
}

static inline void addLaunchTrail(thread float3 &col, float2 uv,
                                  float2 launchPos, float2 target,
                                  float progress, float3 trailColor) {
  float2 tip = mix(launchPos, target, progress);

  float tipDist = length(uv - tip);
  float tipCore = exp(-tipDist * 500.0) * 2.5;
  float tipGlow = exp(-tipDist * 120.0) * 0.25;
  col += tipCore * trailColor;
  col += tipGlow * mix(trailColor, float3(1.0), 0.3);

  float tailFrac = max(0.0, progress - 0.35);
  float2 tail = mix(launchPos, target, tailFrac);

  float2 center = (tip + tail) * 0.5;
  float halfLen = length(tip - tail) * 0.5 + 0.01;
  if (abs(uv.x - center.x) > halfLen || abs(uv.y - center.y) > halfLen) return;

  float2 seg = tip - tail;
  float segLen = length(seg);
  if (segLen < 0.001) return;
  float2 dir = seg / segLen;
  float proj = clamp(dot(uv - tail, dir), 0.0, segLen);
  float2 closest = tail + dir * proj;
  float dist = length(uv - closest);

  float brightness = exp(-dist * 600.0);
  float along = proj / segLen;
  brightness *= along * along;
  col += brightness * trailColor;
}

[[stitchable]] half4 fireworks(float2 position,
                               half4 color,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float peakLevel,
                               float2 viewSize) {
  float t = fmod(time + 10.0, 36000.0);
  float2 uv = normalizedUV(position, viewSize);
  float3 col = float3(0.0);

  uint numSlots = 10;

  col = float3(0.03, 0.015, 0.06) * (1.0 - uv.y * 0.3);

  if (peakLevel < 0.03) {
    return half4(half3(col), 1.0h);
  }

  float minDim = min(viewSize.x, viewSize.y);
  float halfW = viewSize.x / (2.0 * minDim);
  float halfH = viewSize.y / (2.0 * minDim);

  float2 launchPos = float2(0.0, halfH);

  float launchDuration = 0.7;
  float explosionDuration = 3.0;
  float cycleDuration = launchDuration + explosionDuration;

  float fanHalfAngle = atan2(halfW * 0.8, halfH);

  float margin = 0.1;
  float safeW = halfW - margin;
  float safeH = halfH - margin;

  for (uint i = 0; i < numSlots; i++) {
    float fanAngle = -fanHalfAngle + (float(i) / float(numSlots - 1u)) * 2.0 * fanHalfAngle;

    float localTime = t + (float(i) + 1.0) * 7.319;
    float cycle = floor(localTime * 0.28 / cycleDuration);
    float phase = fmod(localTime * 0.28, cycleDuration);

    float3 r0 = shaderRand3(float(i) * 347.77 + cycle * 519.43 + 1234.19);

    float maxDist = halfH * 1.8;
    float dist = maxDist * 0.35 + r0.y * maxDist * 0.6;

    float2 dir = float2(sin(fanAngle), -cos(fanAngle));
    float2 target = launchPos + dir * dist;
    target.x = clamp(target.x, -safeW, safeW);
    target.y = clamp(target.y, -safeH, safeH);

    uint band = i % 3;
    float bandLevel;
    if (band == 0) {
      bandLevel = bassLevel;
    } else if (band == 1) {
      bandLevel = midLevel;
    } else {
      bandLevel = trebleLevel;
    }

    uint numParticles = uint(clamp(floor(bandLevel * 16.0 + 6.0), 6.0, 18.0));
    float intensity = 0.6 + bandLevel * 2.0;
    float spread = 0.25 + bandLevel * 0.15;

    uint palette = uint(cycle) % 3;

    if (phase < launchDuration) {
      float progress = phase / launchDuration;
      float3 trailCol = mix(float3(1.0, 0.9, 0.6), bandColor(band, palette, 0), 0.3);
      addLaunchTrail(col, uv, launchPos, target, progress, trailCol);
      continue;
    }

    float explosionPhase = phase - launchDuration;

    addExplosion(col, uv, target, explosionPhase, numParticles, spread,
                 band, palette, intensity, float(i) * 963.31 + cycle * 127.7);
  }

  col = clamp(col, 0.0, 3.0);

  return half4(half3(col), 1.0h);
}
