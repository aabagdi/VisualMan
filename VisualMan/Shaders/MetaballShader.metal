//
//  MetaballShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

#define NUM_BLOBS 7

struct Blob {
  float2 position;
  float stretch;
  float radius;
};

static Blob blobState(int index, float time, float midTime, float bass) {
  float i = float(index);
  float cycleTime = time * 0.22 + midTime * 0.25;
  float period = 0.55 + i * 0.09;
  float phase = cycleTime * period + i * 1.9;

  float y = sin(phase) * 0.42;
  float vy = cos(phase) * period * 0.42;

  float swayPhase = time * (0.11 + i * 0.03) + i * 2.7;
  float x = (i - float(NUM_BLOBS - 1) * 0.5) * 0.11 + sin(swayPhase) * 0.14;

  Blob b;
  b.position = float2(x, y);
  b.stretch = 1.0 + saturate(abs(vy) * 4.0) * 0.9;
  b.radius = 0.075 + i * 0.011 + bass * 0.08;
  return b;
}

[[ stitchable ]] half4 metaball(float2 position,
                                 half4 inputColor,
                                 float time,
                                 float bassLevel,
                                 float midLevel,
                                 float trebleLevel,
                                 float3 bandTime,
                                 float2 viewSize) {
  float2 uv = normalizedUV(position, viewSize);
  uv.y = -uv.y;

  float energy = audioEnergy(bassLevel, midLevel, trebleLevel);

  const float3 waxCool = float3(0.95, 0.22, 0.05);
  const float3 waxHot = float3(1.0, 0.62, 0.12);
  const float3 liquidTop = float3(0.05, 0.005, 0.04);
  const float3 liquidBottom = float3(0.22, 0.03, 0.06);

  const float falloffPower = 1.6;

  float field = 0.0;
  float2 fieldGrad = float2(0.0);
  float heatAccum = 0.0;
  float totalWeight = 0.0;

  for (int i = 0; i < NUM_BLOBS; i++) {
    Blob b = blobState(i, time, bandTime.y, bassLevel);
    float2 d = uv - b.position;
    d.y /= b.stretch;
    float dist2 = dot(d, d) + 0.001;

    float contribution = pow((b.radius * b.radius) / dist2, falloffPower);
    field += contribution;
    fieldGrad += -2.0 * falloffPower * contribution / dist2 * float2(d.x, d.y / b.stretch);

    float heat = saturate(0.5 - b.position.y) * 0.6 + (b.stretch - 1.0) * 0.4;
    float w = contribution * contribution;
    heatAccum += heat * w;
    totalWeight += w;
  }

  float heat = heatAccum / max(totalWeight, 0.001);
  heat = saturate(heat + trebleLevel * 0.25);
  float3 waxColor = mix(waxCool, waxHot, heat);

  float threshold = 1.0;
  float px = 1.0 / min(viewSize.x, viewSize.y);
  float edgeWidth = max(length(fieldGrad) * px * 1.5, 1e-4);
  float edge = smoothstep(threshold - edgeWidth, threshold + edgeWidth, field);

  float2 heightGrad = fieldGrad / ((1.0 + field) * (1.0 + field));
  float3 normal = normalize(float3(-heightGrad * 0.07, 1.0));

  const float3 lightDir = normalize(float3(-0.45, 0.6, 0.65));
  const float3 viewDir = float3(0.0, 0.0, 1.0);
  float diffuse = max(dot(normal, lightDir), 0.0);
  float3 halfVec = normalize(lightDir + viewDir);
  float specular = pow(max(dot(normal, halfVec), 0.0), 24.0);
  float rim = pow(1.0 - max(normal.z, 0.0), 2.0);

  float3 wax = waxColor * (0.7 + 0.3 * diffuse)
             + waxHot * rim * 0.2
             + float3(1.0, 0.92, 0.8) * specular * 0.15;
  wax *= 0.9 + energy * 0.3;

  float halo = smoothstep(threshold - 0.3, threshold, field) * (1.0 - edge);

  float2 bulb = uv - float2(0.0, -0.62);
  float bulbGlow = exp(-dot(bulb, bulb) * 6.0) * (0.35 + bassLevel * 0.5);
  float3 liquid = mix(liquidBottom, liquidTop, saturate(uv.y + 0.5));
  liquid += waxHot * bulbGlow * 0.45;
  liquid += waxColor * halo * 0.12;

  float3 finalColor = mix(liquid, wax, edge);

  finalColor *= 1.0 - dot(uv, uv) * 0.35;

  return half4(half3(finalColor), 1.0);
}
