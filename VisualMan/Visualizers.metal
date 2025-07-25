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
    
    float bassWave1 = sin(uv.x * 5.0 + time * 1.0 + bassLevel * 10.0) * bassLevel;
    float bassWave2 = sin(uv.y * 4.0 - time * 0.8 + bassLevel * 8.0) * bassLevel;
    
    float midWave1 = sin((uv.x + uv.y) * 15.0 + time * 3.0) * midLevel;
    float midWave2 = sin((uv.x - uv.y) * 12.0 - time * 2.5) * midLevel;
    
    float highWave1 = sin(uv.x * 30.0 + time * 5.0) * highLevel * 0.3;
    float highWave2 = sin(uv.y * 25.0 - time * 4.0) * highLevel * 0.3;
    
    float plasma = bassWave1 + bassWave2 + midWave1 + midWave2 + highWave1 + highWave2;
    
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    float peakWave = sin(dist * 20.0 - time * 10.0 * (1.0 + peakLevel)) * peakLevel;
    plasma += peakWave;
    
    plasma = plasma * 0.5 + 0.5;
    
    half3 bassColor = half3(1.0, 0.2, 0.1);  // Red/orange for bass
    half3 midColor = half3(0.2, 0.6, 1.0);   // Blue for mids
    half3 highColor = half3(0.8, 0.4, 1.0);  // Purple for highs
    
    half3 finalColor = bassColor * bassLevel +
                      midColor * midLevel +
                      highColor * highLevel;
    finalColor = normalize(finalColor + 0.001) * plasma;
    
    float energy = (bassLevel + midLevel + highLevel) / 3.0;
    finalColor *= (0.3 + energy * 1.5);
    
    if (peakLevel > 0.7) {
        finalColor += half3(0.2, 0.2, 0.3) * peakLevel;
    }
    
    return half4(finalColor, 1.0);
}

