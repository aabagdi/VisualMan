//
//  AlbumArtWaveShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 7/31/25.
//

#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] float2 albumArtWave(float2 position,
                                 float time,
                                 float bassLevel,
                                 float midLevel,
                                 float trebleLevel,
                                 float2 viewSize) {
  float2 center = viewSize * 0.5;
  float2 toCenter = position - center;
  float distance = length(toCenter);
  float2 direction = normalize(toCenter);
  
  float ripple = sin(distance * 0.05 - time * 3.0) * bassLevel * 20.0;
  
  float wobble = sin(position.y * 0.01 + time * 2.0) * midLevel * 15.0;
  
  float vibration = sin(distance * 0.1 + time * 10.0) * trebleLevel * 5.0;
  
  float totalDisplacement = ripple + wobble + vibration;
  
  position += direction * totalDisplacement;
  
  return position;
}
