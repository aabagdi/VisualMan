//
//  InterferenceShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793

float calculateWave(float2 position,
                    float2 sourcePos,
                    float time,
                    float amplitude,
                    float frequency,
                    float audioLevel,
                    float modIndex) {
  float distance = length(position - sourcePos);
  
  float falloffRate = 0.3;
  float distanceFalloff = exp(-distance * falloffRate);
  
  float audioScale = 0.3 + audioLevel * 0.7;
  
  float tremoloRate = 2.0;
  float tremoloDepth = 0.1;
  float tremolo = 1.0 + tremoloDepth * sin(time * tremoloRate);
  
  float modulatedAmplitude = amplitude * distanceFalloff * audioScale * tremolo;
  
  float carrierFreq = frequency;
  
  float modFreq = 0.5 + audioLevel * 2.0;
  
  float effectiveModIndex = modIndex * audioLevel;
  
  float freqModulation = effectiveModIndex * sin(modFreq * time);
  
  float modulatedFrequency = carrierFreq * (1.0 + freqModulation);
  
  float waveSpeed = 2.0;
  
  float phase = distance * modulatedFrequency - time * waveSpeed;
  
  float wave = modulatedAmplitude * sin(phase);
  
  wave = sign(wave) * pow(abs(wave), 0.7);
  
  float reflection = modulatedAmplitude * 0.3 * sin(phase + PI);
  wave += reflection;
  
  wave = sign(wave) * pow(abs(wave), 0.8);
  
  return wave;
}

float calculateParallaxLayer(float2 uv,
                             float time,
                             float bassLevel,
                             float midLevel,
                             float trebleLevel,
                             float layerDepth,
                             float2 scrollOffset) {
  float2 parallaxUV = uv + scrollOffset * layerDepth;
  
  float depthScale = 1.0 + layerDepth * 2.0;
  parallaxUV *= depthScale;
  
  float angleOffset = layerDepth * 1.5708;
  float2x2 rotation = float2x2(cos(angleOffset), -sin(angleOffset),
                               sin(angleOffset), cos(angleOffset));
  
  float2 source1 = rotation * float2(0.0, 0.5);
  float2 source2 = rotation * float2(-0.5, -0.5);
  float2 source3 = rotation * float2(0.5, -0.5);
  
  float ampScale = 1.0 - layerDepth * 0.5;
  float freqScale = 1.0 + layerDepth * 0.5;
  
  float wave1 = calculateWave(parallaxUV, source1, time,
                              bassLevel * 0.5 * ampScale,
                              10.0 * freqScale,
                              bassLevel, 0.5);
  
  float wave2 = calculateWave(parallaxUV, source2, time,
                              midLevel * 0.4 * ampScale,
                              20.0 * freqScale,
                              midLevel, 0.75);
  
  float wave3 = calculateWave(parallaxUV, source3, time,
                              trebleLevel * 0.3 * ampScale,
                              30.0 * freqScale,
                              trebleLevel, 1.0);
  
  return wave1 + wave2 + wave3;
}

[[ stitchable ]] half4 interference(float2 position,
                                       half4 inputColor,
                                       float time,
                                       float bassLevel,
                                       float midLevel,
                                       float trebleLevel,
                                       float2 viewSize) {
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
 
  float audioIntensity = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  audioIntensity = pow(audioIntensity, 1.5);
  
  float2 scrollBase = float2(sin(time * 0.05), cos(time * 0.07));
  
  half3 finalColor = half3(0.05, 0.05, 0.1);
  
  const int numLayers = 6;
  for (int i = 0; i < numLayers; i++) {
    float depth = float(i) / float(numLayers - 1);
    
    float2 parallaxOffset = scrollBase * depth * (0.5 + audioIntensity * 0.5);
    
    float layerWave = calculateParallaxLayer(uv, time, bassLevel, midLevel, trebleLevel, depth, parallaxOffset);
    
    layerWave = tanh(layerWave * (0.5 - depth * 0.1));

    half3 layerColor;
    
    if (depth < 0.33) {
      layerColor = mix(half3(0.0, 1.0, 1.0),
                       half3(0.2, 0.4, 1.0),
                       depth * 3.0);
    } else if (depth < 0.66) {
      layerColor = mix(half3(0.6, 0.2, 1.0),
                       half3(1.0, 0.0, 0.8),
                       (depth - 0.33) * 3.0);
    } else {
      layerColor = mix(half3(1.0, 0.4, 0.7),
                       half3(1.0, 0.7, 0.2),
                       (depth - 0.66) * 3.0);
    }
    
    float shimmer = sin(layerWave * 5.0 + time * 1.5) * 0.1;
    layerColor *= 1.0 + shimmer;
    
    float fogFactor = 1.0 - depth * 0.5;
    
    float waveContribution = abs(layerWave);

    waveContribution = pow(waveContribution, 1.2);
    
    if (i < 3) {
      finalColor += layerColor * waveContribution * fogFactor * 0.4;
    } else {
      finalColor = mix(finalColor, layerColor, waveContribution * fogFactor * 0.5);
    }
    
    float edgeGlow = max(0.0, layerWave - 0.6) * 1.5;
    finalColor += layerColor * edgeGlow * fogFactor * 0.2;
  }
  
  float vignette = 1.0 - length(uv) * 0.5;
  half3 vignetteColor = half3(0.1, 0.15, 0.3) * vignette;
  finalColor += vignetteColor;
  
  float smoothBass = pow(bassLevel, 1.5);
  float smoothMid = pow(midLevel, 1.5);
  float smoothTreble = pow(trebleLevel, 1.5);
  
  finalColor.r *= 1.0 + smoothBass * 0.3;
  finalColor.g *= 1.0 + smoothMid * 0.25;
  finalColor.b *= 1.0 + smoothTreble * 0.35;
  
  float audioGlow = pow(audioIntensity, 1.2);
  finalColor *= 1.1 + audioGlow * 0.3;
  
  finalColor = tanh(finalColor * 0.8) * 1.25;
  
  return half4(finalColor, 1.0);
}
