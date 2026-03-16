//
//  MetaballShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793
#define NUM_BLOBS 7

float2 blobPosition(int index, float time, float bass, float mid) {
  float i = float(index);
  float speed = 0.3 + mid * 0.5;
  
  float x = sin(time * speed * (0.4 + i * 0.15) + i * 2.0) * (0.3 + i * 0.05);
  float y = cos(time * speed * (0.3 + i * 0.12) + i * 1.7) * (0.35 + i * 0.04);
  
  float expand = 1.0 + bass * 3.0;
  return float2(x, y) * expand;
}

[[ stitchable ]] half4 metaball(float2 position,
                                 half4 inputColor,
                                 float time,
                                 float bassLevel,
                                 float midLevel,
                                 float trebleLevel,
                                 float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  
  float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  float baseRadius = 0.08 + bassLevel * 0.5;
  
  float field = 0.0;
  float3 weightedColor = float3(0.0);
  float totalWeight = 0.0;
  
  float hues[NUM_BLOBS] = {0.0, 0.04, 0.08, 0.95, 0.97, 0.02, 0.06};
  
  for (int i = 0; i < NUM_BLOBS; i++) {
    float2 bPos = blobPosition(i, time, bassLevel, midLevel);
    float dist = length(uv - bPos);
    
    float r = baseRadius + float(i) * 0.01;
    float contribution = (r * r) / (dist * dist + 0.001);
    field += contribution;
    
    float hue = fract(hues[i] + time * 0.02 + audioEnergy * 0.1);
    float sat = 0.7 + trebleLevel * 0.3;
    float3 p = abs(fract(float3(hue, hue + 2.0/3.0, hue + 1.0/3.0)) * 6.0 - 3.0);
    float3 blobColor = mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), sat);
    
    float w = contribution * contribution;
    weightedColor += blobColor * w;
    totalWeight += w;
  }
  
  float3 rgb = weightedColor / max(totalWeight, 0.001);
  
  float threshold = 1.0;
  float edge = smoothstep(threshold - 0.15, threshold + 0.05, field);
  
  float val = edge * (0.7 + audioEnergy * 0.5);
  rgb *= val;
  
  float glow = smoothstep(threshold - 0.6, threshold - 0.1, field);
  rgb += float3(0.08, 0.02, 0.01) * glow * (0.3 + audioEnergy * 0.7);
  
  float3 bg = float3(0.02, 0.01, 0.03);
  float3 finalColor = mix(bg, rgb, max(edge, glow * 0.3));
  
  return half4(half3(finalColor), 1.0);
}
