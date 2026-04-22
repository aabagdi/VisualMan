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

constant float PI = 3.14159265358979323846;

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

inline float3 shaderRand3(float seed) {
  float2 seed2 = float2(seed, seed * 1.371);
  float3 p = float3(dot(seed2, float2(127.1, 311.7)),
                    dot(seed2, float2(269.5, 183.3)),
                    dot(seed2, float2(419.2, 371.9)));
  return fract(sin(p) * 43758.5453);
}

inline float2 shaderHash22(float2 p) {
  float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

inline float shaderHash21(float2 p) {
  float3 p3 = fract(float3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

inline float audioEnergy(float bass, float mid, float treble) {
  return (bass + mid + treble) * (1.0 / 3.0);
}

inline float2 normalizedUV(float2 position, float2 viewSize) {
  return (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
}

inline float shaderFBM(float2 p, int octaves, float2x2 rot = float2x2(1,0,0,1), float2 offset = float2(0)) {
  float value = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < octaves; i++) {
    value += amplitude * shaderNoise(p);
    p = rot * p * 2.0 + offset;
    amplitude *= 0.5;
  }
  return value;
}

#endif
