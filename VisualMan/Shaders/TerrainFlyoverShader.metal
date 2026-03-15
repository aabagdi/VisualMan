//
//  TerrainFlyoverShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
using namespace metal;

float terrainHash(float2 p) {
  return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float terrainNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  
  float a = terrainHash(i);
  float b = terrainHash(i + float2(1.0, 0.0));
  float c = terrainHash(i + float2(0.0, 1.0));
  float d = terrainHash(i + float2(1.0, 1.0));
  
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float terrainFBM(float2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  float2 pos = p;
  
  for (int i = 0; i < 4; i++) {
    value += amplitude * terrainNoise(pos);
    pos *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

float terrainHeight(float2 p, float time, float bass, float mid, float treble) {
  float h = terrainFBM(p * 0.4) * 1.2;
  
  float freqPos = clamp((p.x + 3.0) / 6.0, 0.0, 1.0);
  
  h += bass * 0.8 * exp(-pow((freqPos - 0.2) * 4.0, 2.0));
  
  h += mid * 0.6 * exp(-pow((freqPos - 0.5) * 3.5, 2.0));
  
  h += treble * 0.5 * exp(-pow((freqPos - 0.8) * 5.0, 2.0));
  
  h += sin(p.y * 2.0 + time * 1.5) * bass * 0.12;
  
  return h;
}

half3 terrainColor(float h, float bass, float treble) {
  half3 deep = half3(0.05, 0.08, 0.25);
  half3 low = half3(0.1, 0.35, 0.15);
  half3 mid = half3(0.35, 0.55, 0.15);
  half3 high = half3(0.6, 0.45, 0.2);
  half3 peak = half3(0.9, 0.85, 0.8);
  
  half3 color;
  if (h < 0.15) {
    color = mix(deep, low, half(h / 0.15));
  } else if (h < 0.4) {
    color = mix(low, mid, half((h - 0.15) / 0.25));
  } else if (h < 0.7) {
    color = mix(mid, high, half((h - 0.4) / 0.3));
  } else {
    color = mix(high, peak, half(min((h - 0.7) / 0.4, 1.0)));
  }
  
  color.r *= 1.0 + bass * 0.25;
  color.b *= 1.0 + treble * 0.3;
  
  return color;
}

[[ stitchable ]] half4 terrainFlyover(float2 position,
                                       half4 inputColor,
                                       float time,
                                       float bassLevel,
                                       float midLevel,
                                       float trebleLevel,
                                       float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  uv.y = -uv.y;
  
  float flySpeed = 0.5 + bassLevel * 0.3;
  float camZ = time * flySpeed;
  float camY = 1.8 + bassLevel * 0.4;
  float3 ro = float3(0.0, camY, camZ);
  
  float pitch = -0.4 - midLevel * 0.08;
  float3 forward = normalize(float3(0.0, sin(pitch), cos(pitch)));
  float3 right = float3(1.0, 0.0, 0.0);
  float3 up = normalize(cross(forward, right));
  float3 rd = normalize(uv.x * right + uv.y * up + 1.2 * forward);
  
  half3 skyColorLow = half3(0.05, 0.05, 0.15);
  half3 skyColorHigh = half3(0.02, 0.02, 0.08);
  float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  float t = 0.1;
  bool hit = false;
  float3 hitPos = float3(0.0);
  
  for (int i = 0; i < 80; i++) {
    float3 p = ro + rd * t;
    
    if (t > 30.0 || p.y < -1.0) break;
    
    float h = terrainHeight(float2(p.x, p.z), time, bassLevel, midLevel, trebleLevel);
    
    if (p.y < h) {
      float lo = t - max(0.02, (p.y - h) * 0.5);
      float hi = t;
      for (int j = 0; j < 4; j++) {
        float m = (lo + hi) * 0.5;
        float3 mp = ro + rd * m;
        float mh = terrainHeight(float2(mp.x, mp.z), time, bassLevel, midLevel, trebleLevel);
        if (mp.y < mh) {
          hi = m;
        } else {
          lo = m;
        }
      }
      hitPos = ro + rd * ((lo + hi) * 0.5);
      hit = true;
      break;
    }
    
    t += max(0.03, (p.y - h) * 0.4);
  }
  
  half3 color;
  if (hit) {
    float2 hp = float2(hitPos.x, hitPos.z);
    float eps = 0.02;
    float hL = terrainHeight(hp - float2(eps, 0.0), time, bassLevel, midLevel, trebleLevel);
    float hR = terrainHeight(hp + float2(eps, 0.0), time, bassLevel, midLevel, trebleLevel);
    float hD = terrainHeight(hp - float2(0.0, eps), time, bassLevel, midLevel, trebleLevel);
    float hU = terrainHeight(hp + float2(0.0, eps), time, bassLevel, midLevel, trebleLevel);
    float3 normal = normalize(float3(hL - hR, 2.0 * eps, hD - hU));
    
    float3 lightDir = normalize(float3(0.4, 0.8, -0.3));
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.25;
    
    float h = terrainHeight(hp, time, bassLevel, midLevel, trebleLevel);
    half3 tColor = terrainColor(h, bassLevel, trebleLevel);
    
    color = tColor * (ambient + diffuse * 0.75);
    
    float fogDist = length(hitPos - ro);
    float fog = 1.0 - exp(-fogDist * 0.06);
    half3 fogColor = half3(0.04, 0.04, 0.12);
    color = mix(color, fogColor, fog);
  } else {
    float skyGrad = clamp(uv.y + 0.3, 0.0, 1.0);
    color = mix(skyColorLow, skyColorHigh, skyGrad);
    color += half3(0.08, 0.04, 0.15) * audioEnergy * (skyGrad + 0.2);
  }
  
  return half4(color, 1.0);
}
