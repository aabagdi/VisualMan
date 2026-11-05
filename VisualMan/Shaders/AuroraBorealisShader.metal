//
//  AuroraBorealisShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

inline float auroraFBM(float2 p) {
  return shaderFBM(p, 4);
}

half3 auroraColor(float t, float time, float bass, float treble) {
  float hueShift = time * 0.15 + bass * 0.3;
  float phase = t + hueShift;
  
  half3 green = half3(0.1, 0.8, 0.3);
  half3 cyan = half3(0.1, 0.7, 0.8);
  half3 magenta = half3(0.7, 0.2, 0.8);
  half3 violet = half3(0.4, 0.1, 0.7);
  
  float wrapped = fract(phase * 0.25) * 4.0;
  int segment = int(wrapped);
  float s = fract(wrapped);

  if (segment == 0) return mix(green, cyan, s);
  if (segment == 1) return mix(cyan, magenta, s);
  if (segment == 2) return mix(magenta, violet, s);
  return mix(violet, green, s);
}

[[ stitchable ]] half4 auroraBorealis(float2 position,
                                       half4 inputColor,
                                       float time,
                                       float bassLevel,
                                       float midLevel,
                                       float trebleLevel,
                                       float3 bandTime,
                                       float2 viewSize) {
  float2 uv = position / viewSize;
  uv.y = 1.0 - uv.y;

  float aspect = viewSize.x / viewSize.y;
  float ux = uv.x * aspect;

  half3 skyTop = half3(0.0, 0.02, 0.08);
  half3 skyBottom = half3(0.0, 0.0, 0.02);
  half3 skyColor = mix(skyBottom, skyTop, uv.y);

  float starNoise = shaderHash(floor(float2(ux, uv.y) * 300.0));
  float twinkle = 0.6 + 0.4 * sin(time * 3.0 + starNoise * 200.0);
  float starBrightness = step(0.995, starNoise) * (0.3 + 0.7 * fract(starNoise * 100.0)) * twinkle;
  skyColor += half3(starBrightness * 0.4);
  
  float audioIntensity = audioEnergy(bassLevel, midLevel, trebleLevel);
  
  half3 auroraAccum = half3(0.0);
  
  for (int layer = 0; layer < 4; layer++) {
    float layerF = float(layer);
    float layerOffset = layerF * 0.7;
    
    float layerTime = (0.3 + layerF * 0.12) * (time + bandTime.x * 0.4);

    float waveX = ux * (1.5 + layerF * 0.8) + layerTime + layerOffset;
    float noiseVal = auroraFBM(float2(waveX, time * 0.08 + layerOffset));
    
    float baseCurtainY = 0.55 + layerF * 0.08;
    float curtainCenter = baseCurtainY + noiseVal * 0.12 * (1.0 + bassLevel * 0.4);
    
    float curtainWidth = 0.06 + midLevel * 0.05 + layerF * 0.015;
    
    float dy = uv.y - curtainCenter;
    float curtainStrength = exp(-(dy * dy) / (2.0 * curtainWidth * curtainWidth));
    
    float streakFreq = 15.0 + layerF * 8.0;
    float streak = 0.7 + 0.3 * sin(ux * streakFreq + time * 0.5 + layerF * 1.5);
    curtainStrength *= streak;

    float ripple = sin(ux * 40.0 + time * 4.0 + layerF * 2.0) * trebleLevel * 0.2;
    curtainStrength *= (1.0 + ripple);
    
    float downFade = smoothstep(curtainCenter - curtainWidth * 3.0, curtainCenter, uv.y);
    curtainStrength *= downFade;
    
    half3 layerColor = auroraColor(layerF / 4.0 + 0.15 * layerF, time, bassLevel, trebleLevel);
    
    float brightness = 0.5 + audioIntensity * 0.5;
    
    auroraAccum += layerColor * curtainStrength * brightness * (0.6 - layerF * 0.08);
  }
  
  half3 finalColor = skyColor + auroraAccum;
  
  float glowY = smoothstep(0.3, 0.7, uv.y);
  finalColor += half3(0.0, 0.03, 0.02) * glowY * audioIntensity;
  
  finalColor = tanh(finalColor * 1.2);
  
  return half4(finalColor, 1.0);
}
