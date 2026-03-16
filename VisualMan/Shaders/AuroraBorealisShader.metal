//
//  AuroraBorealisShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
using namespace metal;

float auroraHash(float2 p) {
  return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float auroraNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  
  float a = auroraHash(i);
  float b = auroraHash(i + float2(1.0, 0.0));
  float c = auroraHash(i + float2(0.0, 1.0));
  float d = auroraHash(i + float2(1.0, 1.0));
  
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float auroraFBM(float2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  float2 pos = p;
  
  for (int i = 0; i < 4; i++) {
    value += amplitude * auroraNoise(pos);
    pos *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

half3 auroraColor(float t, float time, float bass, float treble) {
  float hueShift = time * 0.05 + bass * 0.3;
  float phase = t + hueShift;
  
  half3 green = half3(0.1, 0.8, 0.3);
  half3 cyan = half3(0.1, 0.7, 0.8);
  half3 magenta = half3(0.7, 0.2, 0.8);
  half3 violet = half3(0.4, 0.1, 0.7);
  
  float s = fract(phase);
  int segment = int(fract(phase * 0.25) * 4.0);
  
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
                                       float2 viewSize) {
  float2 uv = position / viewSize;
  uv.y = 1.0 - uv.y;
  
  half3 skyTop = half3(0.0, 0.02, 0.08);
  half3 skyBottom = half3(0.0, 0.0, 0.02);
  half3 skyColor = mix(skyBottom, skyTop, uv.y);
  
  float starNoise = auroraHash(floor(uv * 300.0));
  float starBrightness = step(0.995, starNoise) * (0.3 + 0.7 * fract(starNoise * 100.0));
  skyColor += half3(starBrightness * 0.4);
  
  float audioIntensity = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  half3 auroraAccum = half3(0.0);
  
  for (int layer = 0; layer < 4; layer++) {
    float layerF = float(layer);
    float layerOffset = layerF * 0.7;
    
    float speed = (0.3 + layerF * 0.12) * (1.0 + bassLevel * 0.4);
    
    float waveX = uv.x * (1.5 + layerF * 0.8) + time * speed + layerOffset;
    float noiseVal = auroraFBM(float2(waveX, time * 0.08 + layerOffset));
    
    float baseCurtainY = 0.55 + layerF * 0.08;
    float curtainCenter = baseCurtainY + noiseVal * 0.12 * (1.0 + bassLevel * 0.4);
    
    float curtainWidth = 0.06 + midLevel * 0.05 + layerF * 0.015;
    
    float dy = uv.y - curtainCenter;
    float curtainStrength = exp(-(dy * dy) / (2.0 * curtainWidth * curtainWidth));
    
    float streakFreq = 15.0 + layerF * 8.0;
    float streak = 0.7 + 0.3 * sin(uv.x * streakFreq + time * 0.5 + layerF * 1.5);
    curtainStrength *= streak;
    
    float ripple = sin(uv.x * 40.0 + time * 4.0 + layerF * 2.0) * trebleLevel * 0.2;
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
