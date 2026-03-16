//
//  PlasmaShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793

half3 hsv2rgb(float h, float s, float v) {
  float3 p = abs(fract(float3(h, h + 2.0/3.0, h + 1.0/3.0)) * 6.0 - 3.0);
  float3 rgb = v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
  return half3(rgb);
}

[[ stitchable ]] half4 plasma(float2 position,
                               half4 inputColor,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  
  float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  float v1 = sin(uv.x * 6.0 + time * 1.2 + bassLevel * 8.0);
  
  float v2 = sin((uv.x * 4.0 + uv.y * 4.0) + time * 0.8 + midLevel * 6.0);
  
  float dist = length(uv);
  float v3 = sin(dist * 10.0 - time * 2.0 + trebleLevel * 10.0);
  
  float angle = atan2(uv.y, uv.x);
  float v4 = sin(angle * 3.0 + dist * 5.0 + time * 0.6 + audioEnergy * 5.0);
  
  float plasma = (v1 + v2 + v3 + v4) * 0.25;
  
  float hue = fract(plasma * 0.5 + 0.5 + time * 0.03);
  float sat = 0.6 + audioEnergy * 0.4;
  float val = 0.4 + 0.4 * (plasma * 0.5 + 0.5) + audioEnergy * 0.3;
  
  half3 color = hsv2rgb(hue, sat, val);
  
  return half4(color, 1.0);
}
