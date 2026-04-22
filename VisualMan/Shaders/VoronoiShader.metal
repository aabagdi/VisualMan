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

float2 rand2(float2 p) {
  p = float2(dot(p, float2(127.1, 311.7)),
             dot(p, float2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float2 getSeedPosition(int index,
                       float time,
                       float bassLevel,
                       float midLevel,
                       float trebleLevel,
                       float2 viewSize) {
  float t = time + float(index) * GOLD;
  
  float angle = t * 0.5 + float(index) * PI * 2.0 / float(MAX_SEEDS);
  float radius = 0.3 + 0.2 * sin(t * 0.3 + float(index));
  
  radius *= 1.0 + bassLevel * 0.5;
  angle += midLevel * sin(t * 2.0) * 0.5;
  
  float2 pos = float2(cos(angle), sin(angle)) * radius;
  
  pos += rand2(float2(index, floor(time * 10.0))) * trebleLevel * 0.05;
  
  return pos;
}

half3 getSeedColor(int index,
                   float bassLevel,
                   float midLevel,
                   float trebleLevel,
                   float time,
                   int numSeeds) {
  float band = float(index) / float(numSeeds);
  
  half3 color;
  if (band < 0.33) {
    color = half3(1.0, 0.3, 0.1) * (0.5 + bassLevel * 0.5);
  } else if (band < 0.66) {
    color = half3(0.2, 1.0, 0.5) * (0.5 + midLevel * 0.5);
  } else {
    color = half3(0.3, 0.5, 1.0) * (0.5 + trebleLevel * 0.5);
  }
  
  half3 baseColor = color;
  
  float hueShift = time * 0.1;
  half3 shiftedColor = half3(color.r * cos(hueShift) - color.g * sin(hueShift),
                             color.r * sin(hueShift) + color.g * cos(hueShift),
                             color.b);
  
  return mix(baseColor, shiftedColor, 0.3);
}

[[ stitchable ]] half4 voronoi(float2 position,
                               half4 inputColor,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float2 viewSize) {
  float2 uv = normalizedUV(position, viewSize);

  float energy = audioEnergy(bassLevel, midLevel, trebleLevel);
  int numSeeds = int(mix(8.0, float(MAX_SEEDS), energy));
  
  float minDist = 1000.0;
  float secondMinDist = 1000.0;
  int closestSeed = 0;
  
  for (int i = 0; i < numSeeds; i++) {
    float2 seedPos = getSeedPosition(i, time, bassLevel, midLevel, trebleLevel, viewSize);
    float dist = length(uv - seedPos);
    
    if (dist < minDist) {
      secondMinDist = minDist;
      minDist = dist;
      closestSeed = i;
    } else if (dist < secondMinDist) {
      secondMinDist = dist;
    }
  }
  
  float edgeFactor = smoothstep(0.0, 0.05, secondMinDist - minDist);
  
  half3 cellColor = getSeedColor(closestSeed, bassLevel, midLevel, trebleLevel, time, numSeeds);
  
  float gradient = 1.0 - smoothstep(0.0, 0.5, minDist);
  cellColor *= 0.7 + gradient * 0.3;
  
  float edgeGlow = 1.0 - edgeFactor;
  edgeGlow = pow(edgeGlow, 3.0);
  
  half3 edgeColor = half3(1.0, 1.0, 1.0) * edgeGlow * energy;

  half3 finalColor = cellColor + edgeColor * 0.5;

  finalColor += half3(0.05, 0.05, 0.1) * (1.0 - minDist);

  finalColor *= 0.8 + energy * 0.4;
  
  return half4(finalColor, 1.0);
}
