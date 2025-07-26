//
//  Visualizers.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/24/25.
//

#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 wave(float2 position,
                            half4 color,
                            float time,
                            float bassLevel,
                            float midLevel,
                            float highLevel,
                            float peakLevel) {
  float2 uv = position / 400.0;
  
  // Scale up the normalized levels for visual impact
  // Adjusted for A-weighted response
  float scaledBass = min(bassLevel * 8.0, 1.0);   // Increased due to A-weighting reduction
  float scaledMid = min(midLevel * 6.0, 1.0);     // Reduced due to A-weighting boost
  float scaledHigh = min(highLevel * 8.0, 1.0);   // Moderate scaling
  
  // Create dynamic waves with scaled intensities
  float bassWave1 = sin(uv.x * 3.0 + time * 0.8 + scaledBass * 5.0) * scaledBass * 0.5;
  float bassWave2 = sin(uv.y * 2.5 - time * 0.6 + scaledBass * 4.0) * scaledBass * 0.5;
  
  float midWave1 = sin((uv.x + uv.y) * 8.0 + time * 2.0) * scaledMid * 0.4;
  float midWave2 = sin((uv.x - uv.y) * 6.0 - time * 1.5) * scaledMid * 0.4;
  
  float highWave1 = sin(uv.x * 20.0 + time * 3.0) * scaledHigh * 0.2;
  float highWave2 = sin(uv.y * 18.0 - time * 2.5) * scaledHigh * 0.2;
  
  float plasma = bassWave1 + bassWave2 + midWave1 + midWave2 + highWave1 + highWave2;
  
  // Center ripple effect with peak
  float2 center = float2(0.5, 0.5);
  float dist = length(uv - center);
  float peakWave = sin(dist * 15.0 - time * 5.0 * (1.0 + peakLevel * 2.0)) * peakLevel * 0.3;
  plasma += peakWave;
  
  // Normalize plasma to 0-1 range
  plasma = plasma * 0.5 + 0.5;
  
  // Define frequency colors - softer, more pastel tones
  half3 bassColor = half3(0.8, 0.4, 0.3);   // Softer coral for bass
  half3 midColor = half3(0.3, 0.7, 0.5);    // Softer teal for mids
  half3 highColor = half3(0.5, 0.6, 0.9);   // Softer periwinkle for highs
  
  // Base ambient color - darker and more muted
  half3 ambientColor = half3(0.05, 0.05, 0.08);
  
  // Mix colors based on scaled frequency levels with smoother blending
  half3 finalColor = ambientColor +
  bassColor * scaledBass * 0.6 +
  midColor * scaledMid * 0.6 +
  highColor * scaledHigh * 0.6;
  
  // Apply plasma effect with less intensity
  finalColor *= (0.7 + plasma * 0.3);
  
  // Add overall brightness based on audio energy - more subtle
  float energy = (scaledBass + scaledMid + scaledHigh) / 3.0;
  finalColor *= (0.85 + energy * 0.3);
  
  // Peak flash effect - much more subtle
  if (peakLevel > 0.6) {
    finalColor += half3(0.15, 0.15, 0.18) * (peakLevel - 0.6) * 0.5;
  }
  
  // Clamp to valid range
  finalColor = clamp(finalColor, 0.0, 1.0);
  
  return half4(finalColor, 1.0);
}


/*[[ stitchable ]] half4 circles(float2 position,
 half4 color,
 float time,
 float bassLevel,
 float midLevel,
 float highLevel,
 float peakLevel) {
 
 }*/
