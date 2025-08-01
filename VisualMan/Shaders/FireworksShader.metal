//
//  FireworksShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793

float3 rand3(float seed) {
  float2 seed2 = float2(seed, seed * 1.371);
  
  float3 p = float3(dot(seed2, float2(127.1, 311.7)),
                    dot(seed2, float2(269.5, 183.3)),
                    dot(seed2, float2(419.2, 371.9)));
  return fract(sin(p) * 43758.5453);
}

[[stitchable]] half4 fireworks(float2 position,
                               half4 color,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float peakLevel,
                               float2 viewSize) {
  float t = fmod(time + 10.0, 7200.0);
  float aspectRatio = viewSize.x / viewSize.y;
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  float3 col = float3(0.0);
  
  uint numExplosions = uint(clamp(floor(peakLevel * 10.0 + 5.0), 5.0, 15.0));
  uint bassParticles = uint(clamp(floor(bassLevel * 15.0), 1.0, 15.0));
  uint midParticles = uint(clamp(floor(midLevel * 12.0), 1.0, 12.0));
  uint trebleParticles = uint(clamp(floor(trebleLevel * 10.0), 1.0, 10.0));
  
  float3 bassColor = float3(1.0, 0.3, 0.1);
  float3 midColor = float3(0.3, 1.0, 0.3);
  float3 trebleColor = float3(0.4, 0.6, 1.0);
  
  col = float3(0.05, 0.03, 0.08) * (1.0 - uv.y * 0.5);
  
  if (peakLevel < 0.05) {
    return half4(col.r, col.g, col.b, 1.0);
  }
  
  for (uint i = 0; i < numExplosions; i++) {
    float3 r0 = rand3((float(i) + 1234.1939) + 641.6974);
    
    float2 origin = (float2(r0.x, r0.y) - 0.5) * 1.2;
    origin.x *= aspectRatio;
    
    float localTime = t + (float(i) + 1.0) * 9.6491 * r0.z;
    float explosionPhase = fmod(localTime * 0.5, 3.0);
    
    if (explosionPhase < 0.2) continue;
    
    if (bassLevel > 0.1) {
      for (uint b = 0; b < bassParticles; b += 3) {
        float3 rand = rand3(float(i) * 963.31 + float(b) + 497.8943);
        float a1 = rand.x * PI * 2.0;
        float rScale1 = rand.y * 0.3;
        
        float r1 = explosionPhase * rScale1;
        float2 sparkPos1 = origin + float2(r1 * cos(a1), r1 * sin(a1));
        
        sparkPos1.y += r1 * r1 * 0.03;
        
        float dist = length(uv - sparkPos1);
        if (dist < 0.4) {
          float spark = 0.015 / (dist + 0.015);
          spark = spark * spark;
          float fade = max(0.0, 1.0 - (r1 / rScale1));
          col += spark * fade * bassColor * bassLevel * 2.0;
        }
      }
    }
    
    if (midLevel > 0.1) {
      for (uint m = 0; m < midParticles; m += 3) {
        float3 rand = rand3(float(i) * 753.31 + float(m) + 297.8943);
        float a2 = rand.x * PI * 2.0;
        float rScale2 = rand.y * 0.25;
        
        float r2 = explosionPhase * rScale2;
        float2 sparkPos2 = origin + float2(r2 * cos(a2), r2 * sin(a2));
        
        sparkPos2.y += r2 * r2 * 0.025;
        
        float dist = length(uv - sparkPos2);
        if (dist < 0.35) {
          float spark = 0.012 / (dist + 0.012);
          spark = spark * spark;
          float fade = max(0.0, 1.0 - (r2 / rScale2));
          col += spark * fade * midColor * midLevel * 2.0;
        }
      }
    }
    
    if (trebleLevel > 0.1) {
      for (uint tr = 0; tr < trebleParticles; tr += 3) {
        float3 rand = rand3(float(i) * 563.31 + float(tr) + 197.8943);
        float a3 = rand.x * PI * 2.0;
        float rScale3 = rand.y * 0.2;
        
        float r3 = explosionPhase * rScale3;
        float2 sparkPos3 = origin + float2(r3 * cos(a3), r3 * sin(a3));
        
        sparkPos3.y += r3 * r3 * 0.02;
        
        float dist = length(uv - sparkPos3);
        if (dist < 0.25) {
          float spark = 0.008 / (dist + 0.008);
          spark = spark * spark * spark;
          float fade = max(0.0, 1.0 - (r3 / rScale3));
          
          float sparkle = 1.0 + 0.4 * sin(localTime * 15.0);
          
          col += spark * fade * trebleColor * trebleLevel * sparkle * 2.5;
        }
      }
    }
  }
  
  col = clamp(col, 0.0, 3.0);
  
  return half4(col.r, col.g, col.b, 1.0);
}
