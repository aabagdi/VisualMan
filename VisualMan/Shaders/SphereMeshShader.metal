//
//  SphereMeshShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

static float sphereDisplacement(float3 p, float time, float bass, float mid, float treble) {
  float d = sin(p.x * 3.0 + time * 0.8) * sin(p.y * 3.0 + time * 0.6) * sin(p.z * 2.5 + time * 0.7) * bass * 0.3;
  
  d += sin(p.x * 7.0 + time * 1.3) * sin(p.z * 7.0 + time * 1.1) * mid * 0.15;
  
  d += sin(p.y * 18.0 + time * 2.5) * sin(p.z * 18.0 + time * 2.0) * sin(p.x * 15.0 + time * 1.8) * treble * 0.06;
  
  return d;
}

static float sphereMap(float3 p, float time, float bass, float mid, float treble) {
  float sphere = length(p) - 1.0;
  float disp = sphereDisplacement(p, time, bass, mid, treble);
  return sphere + disp;
}

static float3 sphereNormal(float3 p, float time, float bass, float mid, float treble) {
  float eps = 0.002;
  float3 n = float3(
    sphereMap(p + float3(eps, 0, 0), time, bass, mid, treble) -
    sphereMap(p - float3(eps, 0, 0), time, bass, mid, treble),
    sphereMap(p + float3(0, eps, 0), time, bass, mid, treble) -
    sphereMap(p - float3(0, eps, 0), time, bass, mid, treble),
    sphereMap(p + float3(0, 0, eps), time, bass, mid, treble) -
    sphereMap(p - float3(0, 0, eps), time, bass, mid, treble)
  );
  float len = length(n);
  return len > 1e-6 ? n / len : float3(0.0, 1.0, 0.0);
}

[[ stitchable ]] half4 sphereMesh(float2 position,
                                   half4 inputColor,
                                   float time,
                                   float bassLevel,
                                   float midLevel,
                                   float trebleLevel,
                                   float2 viewSize) {
  float2 uv = normalizedUV(position, viewSize);
  uv.y = -uv.y;
  
  float camAngle = time * 0.2;
  float3 ro = float3(sin(camAngle) * 3.8, 0.8 + sin(time * 0.15) * 0.3, cos(camAngle) * 3.8);
  float3 target = float3(0.0);
  
  float3 fwd = normalize(target - ro);
  float3 right = normalize(cross(float3(0.0, 1.0, 0.0), fwd));
  float3 up = cross(fwd, right);
  float3 rd = normalize(uv.x * right + uv.y * up + 1.5 * fwd);
  
  float totalDist = 0.0;
  float3 p = ro;
  bool hit = false;
  
  for (int i = 0; i < 48; i++) {
    p = ro + rd * totalDist;
    float d = sphereMap(p, time, bassLevel, midLevel, trebleLevel);
    if (d < 0.001) {
      hit = true;
      break;
    }
    if (totalDist > 8.0) break;
    totalDist += d;
  }
  
  half3 color;
  float energy = audioEnergy(bassLevel, midLevel, trebleLevel);

  if (hit) {
    float3 normal = sphereNormal(p, time, bassLevel, midLevel, trebleLevel);

    float3 lightDir = normalize(float3(1.0, 1.0, -0.5));
    float diffuse = max(dot(normal, lightDir), 0.0);

    float3 halfVec = normalize(lightDir - rd);
    float specular = pow(max(dot(normal, halfVec), 0.0), 32.0);

    float fresnel = pow(1.0 - max(dot(normal, -rd), 0.0), 3.0);

    half3 baseColor = half3(
      0.3 + 0.7 * sin(normal.x * 3.0 + time + bassLevel * 2.0),
      0.3 + 0.7 * sin(normal.y * 3.0 + time * 1.3 + midLevel * 2.0),
      0.3 + 0.7 * sin(normal.z * 3.0 + time * 0.7 + trebleLevel * 2.0)
    );

    baseColor = max(baseColor, half3(0.05));

    half3 rimColor = half3(0.4, 0.6, 1.0) * fresnel * (1.0 + energy * 2.0);

    color = baseColor * (0.15 + diffuse * 0.7) + specular * half3(0.6) + rimColor;

    float ao = 0.5 + 0.5 * sphereMap(p + normal * 0.1, time, bassLevel, midLevel, trebleLevel) / 0.1;
    ao = clamp(ao, 0.3, 1.0);
    color *= ao;
  } else {
    float bgGlow = exp(-length(uv) * 2.0) * 0.15;
    color = half3(0.01, 0.01, 0.03) + half3(0.08, 0.12, 0.25) * bgGlow * (1.0 + energy);

    float2 gridUV = fract(uv * 20.0) - 0.5;
    float dotBrightness = smoothstep(0.02, 0.0, length(gridUV));
    color += half3(0.05, 0.08, 0.15) * dotBrightness * energy * 0.3;
  }
  
  color = tanh(color * 1.1);
  
  return half4(color, 1.0);
}
