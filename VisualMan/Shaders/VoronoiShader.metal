//
//  VoronoiShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;
#define GOLD 1.618033988749895
#define MAX_SEEDS 20


float2 getSeedPosition(int index,
                       float time,
                       float bassLevel,
                       float midLevel,
                       float trebleLevel) {
  float t = time + float(index) * GOLD;
  
  float angle = t * 0.5 + float(index) * PI * 2.0 / float(MAX_SEEDS);
  float radius = 0.3 + 0.2 * sin(t * 0.3 + float(index));
  
  radius *= 1.0 + bassLevel * 0.5;
  angle += midLevel * sin(t * 2.0) * 0.5;
  
  float2 pos = float2(cos(angle), sin(angle)) * radius;
  
  float jitterTime = time * 0.8 + float(index) * 5.731;
  float2 jitter = float2(sin(jitterTime * 1.3 + float(index) * 2.17),
                          cos(jitterTime * 0.9 + float(index) * 3.51));
  pos += jitter * trebleLevel * 0.05;
  
  return pos;
}

half3 getSeedColor(int index,
                   float bassLevel,
                   float midLevel,
                   float trebleLevel,
                   float time) {
  int band = index % 3;

  half3 color;
  if (band == 0) {
    color = half3(1.0, 0.3, 0.1) * (0.5 + bassLevel * 0.5);
  } else if (band == 1) {
    color = half3(0.2, 1.0, 0.5) * (0.5 + midLevel * 0.5);
  } else {
    color = half3(0.3, 0.5, 1.0) * (0.5 + trebleLevel * 0.5);
  }
  
  float hueShift = time * 0.1;
  float cosH = cos(hueShift), sinH = sin(hueShift);
  float3 c = float3(color);
  float3 shifted = float3(
    c.r * (0.667 * cosH + 0.333) + c.g * (0.333 - 0.333 * cosH - 0.577 * sinH) + c.b * (0.333 - 0.333 * cosH + 0.577 * sinH),
    c.r * (0.333 - 0.333 * cosH + 0.577 * sinH) + c.g * (0.667 * cosH + 0.333) + c.b * (0.333 - 0.333 * cosH - 0.577 * sinH),
    c.r * (0.333 - 0.333 * cosH - 0.577 * sinH) + c.g * (0.333 - 0.333 * cosH + 0.577 * sinH) + c.b * (0.667 * cosH + 0.333)
  );

  return half3(mix(c, shifted, 0.3));
}

[[ stitchable ]] half4 voronoi(float2 position,
                               half4 inputColor,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float3 bandTime,
                               float2 viewSize) {
  float2 uv = normalizedUV(position, viewSize);

  float energy = audioEnergy(bassLevel, midLevel, trebleLevel);

  const int baseSeeds = 8;
  const float extraSeeds = float(MAX_SEEDS - baseSeeds);
  const float parkedRadius = 3.0;

  float3 powers = float3(1e9);
  float2 pos1 = float2(0.0), pos2 = float2(0.0), pos3 = float2(0.0);
  int closestSeed = 0;

  for (int i = 0; i < MAX_SEEDS; i++) {
    float2 seedPos = getSeedPosition(i, time, bassLevel, midLevel, trebleLevel);
    if (i >= baseSeeds) {
      float threshold = 0.12 + (float(i - baseSeeds) / extraSeeds) * 0.6;
      float activation = smoothstep(threshold - 0.1, threshold + 0.1, energy);
      if (activation <= 0.0) continue;
      float2 outward = length(seedPos) > 1e-4 ? normalize(seedPos) : float2(1.0, 0.0);
      seedPos = mix(outward * parkedRadius, seedPos, activation);
    }
    float2 d = uv - seedPos;
    float power = dot(d, d);

    if (power < powers.x) {
      powers = float3(power, powers.x, powers.y);
      pos3 = pos2; pos2 = pos1; pos1 = seedPos;
      closestSeed = i;
    } else if (power < powers.y) {
      powers.yz = float2(power, powers.y);
      pos3 = pos2; pos2 = seedPos;
    } else if (power < powers.z) {
      powers.z = power;
      pos3 = seedPos;
    }
  }

  float gap2 = max(length(pos2 - pos1), 1e-4);
  float gap3 = max(length(pos3 - pos1), 1e-4);
  float edgeDist = min((powers.y - powers.x) / (2.0 * gap2),
                       (powers.z - powers.x) / (2.0 * gap3));

  half3 cellColor = getSeedColor(closestSeed, bassLevel, midLevel, trebleLevel, time);
  cellColor *= 0.82 + 0.28 * fract(float(closestSeed) * GOLD);

  float minDist = length(uv - pos1);
  float gradient = 1.0 - smoothstep(0.0, 0.5, minDist);
  cellColor *= 0.7 + gradient * 0.3;

  float px = 1.0 / min(viewSize.x, viewSize.y);
  float wall = 1.0 - smoothstep(1.5 * px, 3.0 * px, edgeDist);
  float edgeGlow = pow(1.0 - smoothstep(0.0, 0.025, edgeDist), 3.0);

  half3 wallColor = half3(0.92, 0.94, 1.0) * (0.55 + energy * 0.45);
  half3 finalColor = cellColor + half3(1.0) * edgeGlow * energy * 0.5;
  finalColor = mix(finalColor, wallColor, wall * 0.9);

  finalColor += half3(0.05, 0.05, 0.1) * max(1.0 - minDist, 0.0);

  finalColor *= 0.8 + energy * 0.4;

  return half4(finalColor, 1.0);
}
