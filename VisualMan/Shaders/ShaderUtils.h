//
//  ShaderUtils.h
//  VisualMan
//
//  Created by Aadit Bagdi on 4/20/26.
//

#ifndef ShaderUtils_h
#define ShaderUtils_h

#include <metal_stdlib>
using namespace metal;

inline float shaderHash(float2 p) {
  return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

inline float shaderNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  float a = shaderHash(i);
  float b = shaderHash(i + float2(1.0, 0.0));
  float c = shaderHash(i + float2(0.0, 1.0));
  float d = shaderHash(i + float2(1.0, 1.0));

  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline half3 hsv2rgb(float h, float s, float v) {
  float3 p = abs(fract(float3(h, h + 2.0/3.0, h + 1.0/3.0)) * 6.0 - 3.0);
  float3 rgb = v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
  return half3(rgb);
}

#endif
