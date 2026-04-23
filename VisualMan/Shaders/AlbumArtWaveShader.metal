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
  float scale = min(viewSize.x, viewSize.y);
  float2 center = viewSize * 0.5;
  float2 toCenter = position - center;
  float distance = length(toCenter);
  float normDist = distance / scale;
  float2 direction = distance > 1e-4 ? toCenter / distance : float2(0.0);

  float pulse = sin(normDist * 12.0 - time * 2.5) * bassLevel * scale * 0.06;
  position += direction * pulse;

  float normX = position.x / scale;
  float wave = sin(normX * 6.0 + time * 1.8) * midLevel * scale * 0.03;
  float wave2 = sin(normX * 10.0 - time * 2.5) * midLevel * scale * 0.02;
  position.y += wave + wave2;

  float normY = position.y / scale;
  float shimmerX = sin(normY * 48.0 + time * 11.0) * trebleLevel * scale * 0.02;
  float shimmerY = cos(normX * 40.0 + time * 13.0) * trebleLevel * scale * 0.02;
  position += float2(shimmerX, shimmerY);
  
  return position;
}
