//
//  JuliaShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/24/25.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

[[ stitchable ]] half4 julia(float2 position,
                             half4 color,
                             float time,
                             float bassLevel,
                             float midLevel,
                             float trebleLevel,
                             float2 viewSize) {
  half3 finalColor = half3(0.0);
  const int aa = 2;

  float energy = audioEnergy(bassLevel, midLevel, trebleLevel);
  float cReal = -0.4 + bassLevel * 0.3 * sin(time * 0.5);
  float cImag = 0.6 + trebleLevel * 0.2 * cos(time * 0.7);
  float rotation = midLevel * time * 0.2;
  float cosR = fast::cos(rotation);
  float sinR = fast::sin(rotation);

  for (int sx = 0; sx < aa; sx++) {
    for (int sy = 0; sy < aa; sy++) {
      float2 offset = (float2(float(sx), float(sy)) + 0.5) / float(aa) - 0.5;
      float2 samplePos = position + offset;

      float2 uv = normalizedUV(samplePos, viewSize) * 4.0;

      float2 rotatedUV = float2(
                                uv.x * cosR - uv.y * sinR,
                                uv.x * sinR + uv.y * cosR
                                );

      float2 z = rotatedUV;
      float minDist = 1000.0;
      float orbitTrap = 1000.0;
      
      int maxIterations = int(50 + energy * 50);
      int iterations = 0;

      for (int i = 0; i < 100; i++) {
        if (i >= maxIterations) break;
        
        float x = z.x * z.x - z.y * z.y + cReal;
        float y = 2.0 * z.x * z.y + cImag;
        z = float2(x, y);
        
        float dist = length(z);
        minDist = min(minDist, dist);
        orbitTrap = min(orbitTrap, length(z - float2(0.25, 0.5)));
        
        if (dist > 4.0) break;
        iterations++;
      }
      
      half3 sampleColor;
      
      if (iterations == maxIterations) {
        float interior = 1.0 - minDist;
        sampleColor = half3(0.0, interior * 0.1, interior * 0.2 + bassLevel * 0.3);
      } else {
        float dist = length(z);
        float smoothIter = float(iterations) - log2(max(log2(max(dist, 1.0)), 1e-6));
        smoothIter = max(0.0, smoothIter);
        
        float t = smoothIter / float(maxIterations);
        
        float phase1 = t * 6.28318 + time * 0.1;
        float phase2 = t * 4.0 + time * 0.05;
        float phase3 = orbitTrap * 2.0 + time * 0.15;
        
        half3 gradient1 = half3(sin(phase1 * (1.0 + bassLevel * 0.5)) * 0.5 + 0.5,
                                sin(phase1 + 2.094) * 0.5 + 0.5,
                                sin(phase1 + 4.189) * 0.5 + 0.5);
        
        half3 gradient2 = half3(sin(phase2) * 0.5 + 0.5,
                                sin(phase2 + 1.571) * 0.5 + 0.5,
                                sin(phase2 + 3.142) * 0.5 + 0.5);
        
        half3 gradient3 = half3(sin(phase3) * 0.3 + 0.5,
                                sin(phase3 + 2.618) * 0.3 + 0.5,
                                sin(phase3 + 5.236) * 0.3 + 0.5);
        
        sampleColor = gradient1 * (0.5 + bassLevel * 0.5);
        sampleColor = mix(sampleColor, gradient2, midLevel * 0.7);
        sampleColor = mix(sampleColor, gradient3, trebleLevel * 0.5);
        
        float edgeFactor = exp(-smoothIter * 0.1);
        half3 glowColor = half3(0.4, 0.6, 1.0) * edgeFactor * energy;
        sampleColor += glowColor;
        
        float noise = shaderHash(samplePos + float2(float(sx) * 7.23, float(sy) * 3.77));
        sampleColor += (noise - 0.5) * 0.02;
      }
      
      finalColor += sampleColor;
    }
  }
  
  finalColor /= float(aa * aa);
  
  finalColor = pow(finalColor, half3(0.9));
  
  return half4(finalColor, 1.0);
}
