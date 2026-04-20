//
//  InkShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

float inkFBM(float2 p, int octaves) {
  float value = 0.0;
  float amplitude = 0.5;
  float2 pos = p;
  float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8);
  
  for (int i = 0; i < octaves; i++) {
    value += amplitude * shaderNoise(pos);
    pos = rot * pos * 2.0 + float2(3.7, 1.3);
    amplitude *= 0.5;
  }
  return value;
}

float2 inkWarp(float2 p, float time, float intensity) {
  float2 q = float2(
    inkFBM(p + float2(0.0, 0.0) + time * 0.15, 4),
    inkFBM(p + float2(5.2, 1.3) + time * 0.12, 4)
  );
  
  float2 r = float2(
    inkFBM(p + 4.0 * q + float2(1.7, 9.2) + time * 0.1, 4),
    inkFBM(p + 4.0 * q + float2(8.3, 2.8) + time * 0.08, 4)
  );
  
  return p + intensity * r;
}

half3 inkPalette(float t, float bass, float treble) {
  half3 a = half3(0.15, 0.1, 0.3);
  half3 b = half3(0.4, 0.3, 0.4);
  half3 c = half3(1.0, 1.0, 1.0);
  half3 d = half3(0.0, 0.15, 0.35);
  
  d.r += bass * 0.15;
  d.b += treble * 0.1;
  
  half3 color = a + b * cos(6.28318 * (c * t + half3(d)));
  return color;
}

[[ stitchable ]] half4 ink(float2 position,
                            half4 inputColor,
                            float time,
                            float bassLevel,
                            float midLevel,
                            float trebleLevel,
                            float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  
  float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  float warpStrength = 1.5 + bassLevel * 1.5;
  
  float2 warped = inkWarp(uv * 2.0, time * (0.8 + midLevel * 0.4), warpStrength);
  
  float pattern = inkFBM(warped, 5);
  
  float2 warped2 = inkWarp(uv * 3.5 + float2(10.0, 10.0), time * 1.2, warpStrength * 0.7);
  float detail = inkFBM(warped2, 4);
  
  float combined = pattern * 0.65 + detail * 0.35;
  
  float2 toCenter = uv;
  float dist = length(toCenter);
  float angle = atan2(toCenter.y, toCenter.x);
  float vortex = sin(angle * 3.0 + dist * 5.0 - time * (1.0 + bassLevel) * 1.5) * 0.5 + 0.5;
  combined = mix(combined, vortex, 0.2 * audioEnergy);
  
  half3 color = inkPalette(combined, bassLevel, trebleLevel);
  
  color *= 0.7 + audioEnergy * 0.5;
  
  float flowGrad = abs(inkFBM(warped + 0.01, 4) - pattern) * 30.0;
  flowGrad = clamp(flowGrad, 0.0, 1.0);
  half3 streakColor = half3(0.6, 0.7, 1.0) * flowGrad * (0.3 + trebleLevel * 0.5);
  color += streakColor;
  
  float vignette = 1.0 - dot(uv, uv) * 0.4;
  color *= vignette;
  
  color = tanh(color * 1.1);
  
  return half4(color, 1.0);
}
