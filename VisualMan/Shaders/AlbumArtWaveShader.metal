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
  
  float pulse = sin(distance * 0.03 - time * 2.5) * bassLevel * 25.0;
  position += direction * pulse;
  
  float wave = sin(position.x * 0.015 + time * 1.8) * midLevel * 12.0;
  float wave2 = sin(position.x * 0.025 - time * 2.5) * midLevel * 8.0;
  position.y += wave + wave2;
  
  float shimmerX = sin(position.y * 0.12 + time * 11.0) * trebleLevel * 8.0;
  float shimmerY = cos(position.x * 0.1 + time * 13.0) * trebleLevel * 8.0;
  position += float2(shimmerX, shimmerY);
  
  return position;
}
