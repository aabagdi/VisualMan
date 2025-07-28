//
//  Visualizers.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/24/25.
//

#include <metal_stdlib>
using namespace metal;

#define PI 3.141592653589793

float3 rand3(float seed) {
  float2 seed2 = float2(seed, seed * 1.371);
  
  float3 p = float3(dot(seed2, float2(127.1, 311.7)),
                    dot(seed2, float2(269.5, 183.3)),
                    dot(seed2, float2(419.2, 371.9)));
  return fract(sin(p) * 43758.5453);
}

[[ stitchable ]] half4 julia(float2 position,
                             half4 color,
                             float time,
                             float bassLevel,
                             float midLevel,
                             float trebleLevel,
                             float2 viewSize) {
  half3 finalColor = half3(0.0);
  float aa = 2.0;
  
  for (float sx = 0.0; sx < aa; sx++) {
    for (float sy = 0.0; sy < aa; sy++) {
      float2 offset = float2(sx, sy) / aa - 0.5;
      float2 samplePos = position + offset;
      
      float2 uv = (samplePos - viewSize * 0.5) / min(viewSize.x, viewSize.y) * 4.0;
      
      float audioEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
      float cReal = -0.4 + bassLevel * 0.3 * sin(time * 0.5);
      float cImag = 0.6 + trebleLevel * 0.2 * cos(time * 0.7);
      
      float rotation = midLevel * time * 0.2;
      float cosR = cos(rotation);
      float sinR = sin(rotation);
      float2 rotatedUV = float2(
                                uv.x * cosR - uv.y * sinR,
                                uv.x * sinR + uv.y * cosR
                                );
      
      float2 z = rotatedUV;
      float minDist = 1000.0;
      float orbitTrap = 1000.0;
      
      int maxIterations = int(50 + audioEnergy * 50);
      int iterations = 0;
      
      for (int i = 0; i < 100; i++) {
        if (i >= maxIterations) break;
        
        float x = z.x * z.x - z.y * z.y + cReal;
        float y = 2.0 * z.x * z.y + cImag;
        z = float2(x, y);
        
        float dist = length(z);
        minDist = min(minDist, dist);
        orbitTrap = min(orbitTrap, length(z - float2(0.25, 0.5)));
        
        if (dist > 4.0) break;
        iterations++;
      }
      
      half3 sampleColor;
      
      if (iterations == maxIterations) {
        float interior = 1.0 - minDist;
        sampleColor = half3(0.0, interior * 0.1, interior * 0.2 + bassLevel * 0.3);
      } else {
        float dist = length(z);
        float smoothIter = float(iterations) - log2(log2(dist));
        smoothIter = max(0.0, smoothIter);
        
        float t = smoothIter / float(maxIterations);
        
        float phase1 = t * 6.28318 + time * 0.1;
        float phase2 = t * 4.0 + time * 0.05;
        float phase3 = orbitTrap * 2.0 + time * 0.15;
        
        half3 gradient1 = half3(
                                sin(phase1 * (1.0 + bassLevel * 0.5)) * 0.5 + 0.5,
                                sin(phase1 + 2.094) * 0.5 + 0.5,
                                sin(phase1 + 4.189) * 0.5 + 0.5
                                );
        
        half3 gradient2 = half3(
                                sin(phase2) * 0.5 + 0.5,
                                sin(phase2 + 1.571) * 0.5 + 0.5,
                                sin(phase2 + 3.142) * 0.5 + 0.5
                                );
        
        half3 gradient3 = half3(
                                sin(phase3) * 0.3 + 0.5,
                                sin(phase3 + 2.618) * 0.3 + 0.5,
                                sin(phase3 + 5.236) * 0.3 + 0.5
                                );
        
        sampleColor = gradient1 * (0.5 + bassLevel * 0.5);
        sampleColor = mix(sampleColor, gradient2, midLevel * 0.7);
        sampleColor = mix(sampleColor, gradient3, trebleLevel * 0.5);
        
        float edgeFactor = exp(-smoothIter * 0.1);
        half3 glowColor = half3(0.4, 0.6, 1.0) * edgeFactor * audioEnergy;
        sampleColor += glowColor;
        
        float noise = fract(sin(dot(samplePos, float2(12.9898, 78.233))) * 43758.5453);
        sampleColor += (noise - 0.5) * 0.02;
      }
      
      finalColor += sampleColor;
    }
  }
  
  finalColor /= (aa * aa);
  
  finalColor = pow(finalColor, half3(0.9));
  
  return half4(finalColor, 1.0);
}

[[stitchable]] half4 fireworks(float2 position,
                               half4 color,
                               float time,
                               float bassLevel,
                               float midLevel,
                               float trebleLevel,
                               float peakLevel,
                               float2 viewSize) {
  float t = fmod(time + 10.0, 7200.0);
  float aspectRatio = viewSize.x / viewSize.y;
  float2 uv = (position - viewSize * 0.5) / min(viewSize.x, viewSize.y);
  float3 col = float3(0.0);
  
  uint numExplosions = uint(clamp(floor(peakLevel * 10.0), 1.0, 10.0));
  uint bassParticles = uint(clamp(floor(bassLevel * 15.0), 1.0, 15.0));
  uint midParticles = uint(clamp(floor(midLevel * 12.0), 1.0, 12.0));
  uint trebleParticles = uint(clamp(floor(trebleLevel * 10.0), 1.0, 10.0));
  
  float3 bassColor = float3(1.0, 0.3, 0.1);
  float3 midColor = float3(0.3, 1.0, 0.3);
  float3 trebleColor = float3(0.4, 0.6, 1.0);
  
  col = float3(0.05, 0.03, 0.08) * (1.0 - uv.y * 0.5);
  
  if (peakLevel < 0.05) {
    return half4(col.r, col.g, col.b, 1.0);
  }
  
  for (uint i = 0; i < numExplosions; i++) {
    float3 r0 = rand3((float(i) + 1234.1939) + 641.6974);
    
    float2 origin = (float2(r0.x, r0.y) - 0.5) * 1.2;
    origin.x *= aspectRatio;
    
    float localTime = t + (float(i) + 1.0) * 9.6491 * r0.z;
    float explosionPhase = fmod(localTime * 0.5, 3.0);
    
    if (explosionPhase < 0.2) continue;
    
    if (bassLevel > 0.1) {
      for (uint b = 0; b < bassParticles; b += 3) {
        float3 rand = rand3(float(i) * 963.31 + float(b) + 497.8943);
        float a1 = rand.x * PI * 2.0;
        float rScale1 = rand.y * 0.3;
        
        float r1 = explosionPhase * rScale1;
        float2 sparkPos1 = origin + float2(r1 * cos(a1), r1 * sin(a1));
        
        sparkPos1.y += r1 * r1 * 0.03;
        
        float dist = length(uv - sparkPos1);
        if (dist < 0.4) {
          float spark = 0.015 / (dist + 0.015);
          spark = spark * spark;
          float fade = max(0.0, 1.0 - (r1 / rScale1));
          col += spark * fade * bassColor * bassLevel * 2.0;
        }
      }
    }
    
    if (midLevel > 0.1) {
      for (uint m = 0; m < midParticles; m += 3) {
        float3 rand = rand3(float(i) * 753.31 + float(m) + 297.8943);
        float a2 = rand.x * PI * 2.0;
        float rScale2 = rand.y * 0.25;
        
        float r2 = explosionPhase * rScale2;
        float2 sparkPos2 = origin + float2(r2 * cos(a2), r2 * sin(a2));
        
        sparkPos2.y += r2 * r2 * 0.025;
        
        float dist = length(uv - sparkPos2);
        if (dist < 0.35) {
          float spark = 0.012 / (dist + 0.012);
          spark = spark * spark;
          float fade = max(0.0, 1.0 - (r2 / rScale2));
          col += spark * fade * midColor * midLevel * 2.0;
        }
      }
    }
    
    if (trebleLevel > 0.1) {
      for (uint tr = 0; tr < trebleParticles; tr += 3) {
        float3 rand = rand3(float(i) * 563.31 + float(tr) + 197.8943);
        float a3 = rand.x * PI * 2.0;
        float rScale3 = rand.y * 0.2;
        
        float r3 = explosionPhase * rScale3;
        float2 sparkPos3 = origin + float2(r3 * cos(a3), r3 * sin(a3));
        
        sparkPos3.y += r3 * r3 * 0.02;
        
        float dist = length(uv - sparkPos3);
        if (dist < 0.25) {
          float spark = 0.008 / (dist + 0.008);
          spark = spark * spark * spark;
          float fade = max(0.0, 1.0 - (r3 / rScale3));
          
          float sparkle = 1.0 + 0.4 * sin(localTime * 15.0);
          
          col += spark * fade * trebleColor * trebleLevel * sparkle * 2.5;
        }
      }
    }
  }
  
  col = clamp(col, 0.0, 3.0);
  
  return half4(col.r, col.g, col.b, 1.0);
}

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
  
  float2 scrollBase = float2(sin(time * 0.1), cos(time * 0.15));
  float audioIntensity = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  half3 finalColor = half3(0.05, 0.05, 0.1);
  
  const int numLayers = 6;
  for (int i = 0; i < numLayers; i++) {
    float depth = float(i) / float(numLayers - 1);
    
    float2 parallaxOffset = scrollBase * depth * (1.0 + audioIntensity * 2.0);
    
    float layerWave = calculateParallaxLayer(uv, time, bassLevel, midLevel, trebleLevel, depth, parallaxOffset);
    
    layerWave = tanh(layerWave * (0.8 - depth * 0.2));
    
    half3 layerColor;
    
    if (depth < 0.33) {
      layerColor = mix(half3(0.0, 1.0, 1.0),
                       half3(0.2, 0.4, 1.0),
                       depth * 3.0
                       );
    } else if (depth < 0.66) {
      layerColor = mix(half3(0.6, 0.2, 1.0),
                       half3(1.0, 0.0, 0.8),
                       (depth - 0.33) * 3.0
                       );
    } else {
      layerColor = mix(half3(1.0, 0.4, 0.7),
                       half3(1.0, 0.7, 0.2),
                       (depth - 0.66) * 3.0
                       );
    }
    
    float shimmer = sin(layerWave * 10.0 + time * 3.0) * 0.2;
    layerColor *= 1.0 + shimmer;
    
    float fogFactor = 1.0 - depth * 0.5;
    
    if (i < 3) {
      finalColor += layerColor * abs(layerWave) * fogFactor * 0.5;
    } else {
      finalColor = mix(finalColor, layerColor, abs(layerWave) * fogFactor * 0.6);
    }
    
    float edgeGlow = max(0.0, layerWave - 0.5) * 2.0;
    finalColor += layerColor * edgeGlow * fogFactor * 0.3;
  }
  
  float vignette = 1.0 - length(uv) * 0.5;
  half3 vignetteColor = half3(0.1, 0.15, 0.3) * vignette;
  finalColor += vignetteColor;
  
  float audioGlow = (bassLevel + midLevel + trebleLevel) / 3.0;
  
  finalColor.r *= 1.0 + bassLevel * 0.5;
  finalColor.g *= 1.0 + midLevel * 0.4;
  finalColor.b *= 1.0 + trebleLevel * 0.6;
  
  finalColor *= 1.2 + audioGlow * 0.6;
  
  finalColor = tanh(finalColor * 0.7) * 1.4;
  
  return half4(finalColor, 1.0);
}
