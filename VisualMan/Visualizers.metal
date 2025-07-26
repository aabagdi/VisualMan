//
//  Visualizers.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/24/25.
//

#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 julia(float2 position,
                             half4 color,
                             float time,
                             float bassLevel,
                             float midLevel,
                             float trebleLevel,
                             float2 viewSize
                             ) {
  half3 finalColor = half3(0.0);
  float aa = 2.0;
  
  for (float sx = 0.0; sx < aa; sx++) {
    for (float sy = 0.0; sy < aa; sy++) {
      float2 offset = float2(sx, sy) / aa - 0.5;
      float2 samplePos = position + offset;
      
      float2 uv = (samplePos - viewSize * 0.5) / min(viewSize.x, viewSize.y) * 4.0;
      
      float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
      float cReal = -0.4 + bassLevel * 0.3 * sin(time * 0.5);
      float cImag = 0.6 + trebleLevel * 0.2 * cos(time * 0.7);
      
      float rotation = midLevel * time * 0.2;
      float cosR = cos(rotation);
      float sinR = sin(rotation);
      float2 rotatedUV = float2(
                                uv.x * cosR - uv.y * sinR,
                                uv.x * sinR + uv.y * cosR
                                );
      
      float2 z = rotatedUV;
      float minDist = 1000.0;
      float orbitTrap = 1000.0;
      
      int maxIterations = int(50 + audioEnergy * 50);
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
        float smoothIter = float(iterations) - log2(log2(dist));
        smoothIter = max(0.0, smoothIter);
        
        float t = smoothIter / float(maxIterations);
        
        float phase1 = t * 6.28318 + time * 0.1;
        float phase2 = t * 4.0 + time * 0.05;
        float phase3 = orbitTrap * 2.0 + time * 0.15;
        
        half3 gradient1 = half3(
                                sin(phase1 * (1.0 + bassLevel * 0.5)) * 0.5 + 0.5,
                                sin(phase1 + 2.094) * 0.5 + 0.5,
                                sin(phase1 + 4.189) * 0.5 + 0.5
                                );
        
        half3 gradient2 = half3(
                                sin(phase2) * 0.5 + 0.5,
                                sin(phase2 + 1.571) * 0.5 + 0.5,
                                sin(phase2 + 3.142) * 0.5 + 0.5
                                );
        
        half3 gradient3 = half3(
                                sin(phase3) * 0.3 + 0.5,
                                sin(phase3 + 2.618) * 0.3 + 0.5,
                                sin(phase3 + 5.236) * 0.3 + 0.5
                                );
        
        sampleColor = gradient1 * (0.5 + bassLevel * 0.5);
        sampleColor = mix(sampleColor, gradient2, midLevel * 0.7);
        sampleColor = mix(sampleColor, gradient3, trebleLevel * 0.5);
        
        float edgeFactor = exp(-smoothIter * 0.1);
        half3 glowColor = half3(0.4, 0.6, 1.0) * edgeFactor * audioEnergy;
        sampleColor += glowColor;
        
        float noise = fract(sin(dot(samplePos, float2(12.9898, 78.233))) * 43758.5453);
        sampleColor += (noise - 0.5) * 0.02;
      }
      
      finalColor += sampleColor;
    }
  }
  
  finalColor /= (aa * aa);
  
  finalColor = pow(finalColor, half3(0.9));
  
  return half4(finalColor, 1.0);
}
