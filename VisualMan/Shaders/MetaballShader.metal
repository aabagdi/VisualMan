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
  b.radius = 0.075 + i * 0.011 + bass * 0.11;
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

  float field = 0.0;
  float heatAccum = 0.0;
  float totalWeight = 0.0;

  for (int i = 0; i < NUM_BLOBS; i++) {
    Blob b = blobState(i, time, bandTime.y, bassLevel);
    float2 d = uv - b.position;
    d.y /= b.stretch;
    float dist2 = dot(d, d);

    float contribution = (b.radius * b.radius) / (dist2 + 0.001);
    field += contribution;

    float heat = saturate(0.5 - b.position.y) * 0.6 + (b.stretch - 1.0) * 0.4;
    float w = contribution * contribution;
    heatAccum += heat * w;
    totalWeight += w;
  }

  float heat = heatAccum / max(totalWeight, 0.001);
  heat = saturate(heat + trebleLevel * 0.25);
  float3 waxColor = mix(waxCool, waxHot, heat);

  float threshold = 1.0;
  float edge = smoothstep(threshold - 0.12, threshold + 0.04, field);
  float body = smoothstep(threshold, threshold + 1.5, field);
  float3 wax = waxColor * (0.55 + 0.45 * body) * (0.85 + energy * 0.3);

  float halo = smoothstep(threshold - 0.6, threshold - 0.1, field) * (1.0 - edge);

  float2 bulb = uv - float2(0.0, -0.62);
  float bulbGlow = exp(-dot(bulb, bulb) * 6.0) * (0.35 + bassLevel * 0.5);
  float3 liquid = mix(liquidBottom, liquidTop, saturate(uv.y + 0.5));
  liquid += waxHot * bulbGlow * 0.45;
  liquid += waxColor * halo * 0.18;

  float3 finalColor = mix(liquid, wax, edge);

  finalColor *= 1.0 - dot(uv, uv) * 0.35;

  return half4(half3(finalColor), 1.0);
}
