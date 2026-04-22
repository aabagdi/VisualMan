//
//  BlitShader.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/21/26.
//

#include <metal_stdlib>
using namespace metal;

struct BlitVertexOut {
  float4 position [[position]];
  float2 uv;
};

[[vertex]]
BlitVertexOut blitVertex(uint vid [[vertex_id]]) {
  BlitVertexOut out;
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2( 3.0, -1.0),
    float2(-1.0,  3.0)
  };
  out.position = float4(positions[vid], 0.0, 1.0);
  out.uv = float2(positions[vid].x * 0.5 + 0.5,
                   1.0 - (positions[vid].y * 0.5 + 0.5));
  return out;
}

[[fragment]]
half4 blitFragment(BlitVertexOut in [[stage_in]],
                   texture2d<half> src [[texture(0)]]) {
  constexpr sampler s(filter::linear, address::clamp_to_edge);
  return src.sample(s, in.uv);
}
