//
//  CRTShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/20/26.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 crtEffect(float2 position,
                                  SwiftUI::Layer layer,
                                  float2 viewSize,
                                  float curvature,
                                  float scanlineIntensity,
                                  float vignetteStrength) {
  float2 uv = position / viewSize;
  float2 centered = uv * 2.0 - 1.0;

  float r2 = dot(centered, centered);
  float2 distorted = centered * (1.0 + curvature * r2);

  float cornerDistortion = 1.0 + curvature * 2.0;
  distorted /= cornerDistortion;

  float2 screenUV = (distorted + 1.0) * 0.5;
  float2 samplePos = screenUV * viewSize;

  half4 color = layer.sample(samplePos);

  float scanline = 0.5 + 0.5 * cos(fract(position.y * 0.5) * 6.28318530);
  scanline = mix(1.0, scanline, scanlineIntensity);
  color.rgb *= half(scanline);

  float vignette = 1.0 - r2 * vignetteStrength;
  vignette = clamp(vignette, 0.0, 1.0);
  color.rgb *= half(vignette);

  return color;
}
