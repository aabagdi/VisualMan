//
//  FireworksShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

static inline void addSparks(thread float3 &col, float2 uv, float2 origin,
                             float explosionPhase, float localTime,
                             uint particleCount, float rScaleBase,
                             float sparkRadius, float sparkExp,
                             float3 particleColor, float audioLevel,
                             float colorScale, float seedBase, float seedOffset,
                             bool useSparkle) {
  for (uint p = 0; p < particleCount; p += 3) {
    float3 rand = shaderRand3(seedBase + float(p) + seedOffset);
    float a = rand.x * PI * 2.0;
    float rScale = max(rand.y * rScaleBase, 0.001);

    float r = explosionPhase * rScale;
    float2 sparkPos = origin + float2(r * cos(a), r * sin(a));
    sparkPos.y += r * r * (rScaleBase * 0.1);

    float2 diff = uv - sparkPos;
    float dist2 = dot(diff, diff);
    float maxDist2 = rScaleBase * rScaleBase * 4.0;
    if (dist2 < maxDist2) {
      float dist = sqrt(dist2);
      float spark = sparkRadius / (dist + sparkRadius);
      for (int e = 0; e < int(sparkExp); e++) spark *= spark;
      float fade = max(0.0, 1.0 - (r / rScale));
      float sparkle = useSparkle ? (1.0 + 0.4 * sin(localTime * 15.0)) : 1.0;
      col += spark * fade * particleColor * audioLevel * sparkle * colorScale;
    }
  }
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
  float aspectRatio = viewSize.x / viewSize.y;
  float2 uv = normalizedUV(position, viewSize);
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
    float3 r0 = shaderRand3((float(i) + 1234.1939) + 641.6974);
    
    float2 origin = (float2(r0.x, r0.y) - 0.5) * 1.2;
    origin.x *= aspectRatio;
    
    float localTime = t + (float(i) + 1.0) * 9.6491 * r0.z;
    float explosionPhase = fmod(localTime * 0.5, 3.0);
    
    if (explosionPhase < 0.2) continue;
    
    if (bassLevel > 0.1) {
      addSparks(col, uv, origin, explosionPhase, localTime,
                bassParticles, 0.3, 0.015, 1.0,
                bassColor, bassLevel, 2.0,
                float(i) * 963.31, 497.8943, false);
    }

    if (midLevel > 0.1) {
      addSparks(col, uv, origin, explosionPhase, localTime,
                midParticles, 0.25, 0.012, 1.0,
                midColor, midLevel, 2.0,
                float(i) * 753.31, 297.8943, false);
    }

    if (trebleLevel > 0.1) {
      addSparks(col, uv, origin, explosionPhase, localTime,
                trebleParticles, 0.2, 0.008, 1.5,
                trebleColor, trebleLevel, 2.5,
                float(i) * 563.31, 197.8943, true);
    }
  }
  
  col = clamp(col, 0.0, 3.0);
  
  return half4(col.r, col.g, col.b, 1.0);
}
