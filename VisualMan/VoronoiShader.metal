//
//  VoronoiShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793
#define GOLD 1.618033988749895
#define MAX_SEEDS 20

float2 rand2(float2 p) {
  p = float2(dot(p, float2(127.1, 311.7)),
             dot(p, float2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

half3 hsv2rgb(float3 hsv) {
  float h = fract(hsv.x) * 6.0;
  float s = hsv.y;
  float v = hsv.z;
  
  float c = v * s;
  float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
  float m = v - c;
  
  half3 rgb;
  if (h < 1.0) rgb = half3(c, x, 0.0);
  else if (h < 2.0) rgb = half3(x, c, 0.0);
  else if (h < 3.0) rgb = half3(0.0, c, x);
  else if (h < 4.0) rgb = half3(0.0, x, c);
  else if (h < 5.0) rgb = half3(x, 0.0, c);
  else rgb = half3(c, 0.0, x);
  
  return rgb + m;
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
  
  return color;
}

[[ stitchable ]] half4 voronoi(float2 position,
                               half4 inputColor,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  
  float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
  int numSeeds = int(mix(8.0, float(MAX_SEEDS), audioEnergy));
  
  float minDist = 1000.0;
  float secondMinDist = 1000.0;
  int closestSeed = 0;
  int secondClosestSeed = 0;
  
  for (int i = 0; i < numSeeds; i++) {
    float2 seedPos = getSeedPosition(i, time, bassLevel, midLevel, trebleLevel, viewSize);
    float dist = length(uv - seedPos);
    
    if (dist < minDist) {
      secondMinDist = minDist;
      secondClosestSeed = closestSeed;
      minDist = dist;
      closestSeed = i;
    } else if (dist < secondMinDist) {
      secondMinDist = dist;
      secondClosestSeed = i;
    }
  }
  
  float edgeFactor = smoothstep(0.0, 0.05, secondMinDist - minDist);
  
  half3 cellColor = getSeedColor(closestSeed, bassLevel, midLevel, trebleLevel, time, numSeeds);
  
  float gradient = 1.0 - smoothstep(0.0, 0.5, minDist);
  cellColor *= 0.7 + gradient * 0.3;
  
  float edgeGlow = 1.0 - edgeFactor;
  edgeGlow = pow(edgeGlow, 3.0);
  
  half3 edgeColor = half3(1.0, 1.0, 1.0) * edgeGlow * audioEnergy;
  
  half3 finalColor = cellColor + edgeColor * 0.5;
  
  finalColor += half3(0.05, 0.05, 0.1) * (1.0 - minDist);
  
  finalColor *= 0.8 + audioEnergy * 0.4;
  
  return half4(finalColor, 1.0);
}
