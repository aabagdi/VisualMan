//
//  NavierStokesCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
using namespace metal;

struct SplatParams {
  float2 position;
  float radius;
  float _pad;
  float3 value;
  float _pad2;
};

kernel void fluidSplatBatch(texture2d<float, access::read_write> field [[texture(0)]],
                            constant SplatParams *splats [[buffer(0)]],
                            constant uint &splatCount [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = field.get_width();
  uint h = field.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float2 pos = float2(gid) + 0.5;
  
  bool anyNearby = false;
  for (uint i = 0; i < splatCount; i++) {
    float2 diff = pos - splats[i].position;
    if (dot(diff, diff) < 6.0 * splats[i].radius * splats[i].radius) {
      anyNearby = true;
      break;
    }
  }
  if (!anyNearby) return;
  
  float4 current = field.read(gid);
  for (uint i = 0; i < splatCount; i++) {
    float2 diff = pos - splats[i].position;
    float dist2 = dot(diff, diff);
    float r2 = splats[i].radius * splats[i].radius;
    float falloff = exp(-dist2 / r2);
    current.xyz += splats[i].value * falloff;
  }
  field.write(current, gid);
}

kernel void fluidDiffuse(texture2d<float, access::read> fieldIn [[texture(0)]],
                         texture2d<float, access::write> fieldOut [[texture(1)]],
                         constant float &alpha [[buffer(0)]],
                         constant float &rBeta [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float4 center = fieldIn.read(gid);
  float4 sum = fieldIn.read(left) + fieldIn.read(right) +
               fieldIn.read(down) + fieldIn.read(up);
  
  float4 result = (center + alpha * sum) * rBeta;
  fieldOut.write(result, gid);
}

kernel void fluidAdvect(texture2d<float, access::read> velocityIn [[texture(0)]],
                        texture2d<float, access::sample> fieldIn [[texture(1)]],
                        texture2d<float, access::write> fieldOut [[texture(2)]],
                        constant float &dt [[buffer(0)]],
                        constant float &dissipation [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldOut.get_width();
  uint h = fieldOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
  
  float2 pos = float2(gid) + 0.5;
  float4 vel = velocityIn.read(gid);
  
  if (any(isnan(vel.xy)) || any(isinf(vel.xy))) {
    vel = float4(0);
  }
  float speed = length(vel.xy);
  if (speed > 500.0) {
    vel.xy *= 500.0 / speed;
  }
  float2 backPos = pos - dt * vel.xy;
  
  float2 uv = backPos / float2(w, h);
  float4 result = fieldIn.sample(linearSampler, uv);
  result *= dissipation;
  
  fieldOut.write(result, gid);
}

kernel void fluidDivergence(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::write> divergenceOut [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float vR = velocity.read(right).x;
  float vL = velocity.read(left).x;
  float vT = velocity.read(up).y;
  float vB = velocity.read(down).y;
  
  float div = 0.5 * (vR - vL + vT - vB);
  divergenceOut.write(float4(-div, 0, 0, 0), gid);
}

kernel void fluidJacobi(texture2d<float, access::read> pressureIn [[texture(0)]],
                        texture2d<float, access::read> divergence [[texture(1)]],
                        texture2d<float, access::write> pressureOut [[texture(2)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = pressureIn.get_width();
  uint h = pressureIn.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float pL = pressureIn.read(left).x;
  float pR = pressureIn.read(right).x;
  float pB = pressureIn.read(down).x;
  float pT = pressureIn.read(up).x;
  float div = divergence.read(gid).x;
  
  float pressure = (pL + pR + pB + pT + div) * 0.25;
  pressureOut.write(float4(pressure, 0, 0, 0), gid);
}

kernel void fluidGradientSubtract(texture2d<float, access::read> pressure [[texture(0)]],
                                  texture2d<float, access::read_write> velocity [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
  uint w = pressure.get_width();
  uint h = pressure.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float pL = pressure.read(left).x;
  float pR = pressure.read(right).x;
  float pB = pressure.read(down).x;
  float pT = pressure.read(up).x;
  
  float4 vel = velocity.read(gid);
  vel.x -= 0.5 * (pR - pL);
  vel.y -= 0.5 * (pT - pB);
  velocity.write(vel, gid);
}

kernel void fluidVorticity(texture2d<float, access::read> velocity [[texture(0)]],
                           texture2d<float, access::write> vorticityOut [[texture(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float curl = 0.5 * (velocity.read(right).y - velocity.read(left).y
                     - velocity.read(up).x    + velocity.read(down).x);
  vorticityOut.write(float4(curl, 0, 0, 0), gid);
}

kernel void fluidVorticityForce(texture2d<float, access::read> vorticity [[texture(0)]],
                                texture2d<float, access::read_write> velocity [[texture(1)]],
                                constant float &strength [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
  uint w = vorticity.get_width();
  uint h = vorticity.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  uint2 left  = uint2(max(int(gid.x) - 2, 0), gid.y);
  uint2 right = uint2(min(gid.x + 2, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 2, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 2, h - 1));
  
  float2 gradAbs = 0.25 * float2(abs(vorticity.read(right).x) - abs(vorticity.read(left).x),
                                   abs(vorticity.read(up).x)    - abs(vorticity.read(down).x));
  float len = length(gradAbs);
  if (len < 1e-4) return;
  
  float2 N = gradAbs / len;
  float curl = vorticity.read(gid).x;
  
  float2 force = strength * float2(N.y, -N.x) * curl;
  
  float4 vel = velocity.read(gid);
  vel.xy += force;
  
  float newSpeed = length(vel.xy);
  if (newSpeed > 400.0) {
    vel.xy *= 400.0 / newSpeed;
  }
  velocity.write(vel, gid);
}

constant float blurWeights[9] = { 0.026, 0.066, 0.121, 0.176, 0.222, 0.176, 0.121, 0.066, 0.026 };

kernel void fluidBlurH(texture2d<float, access::read> fieldIn [[texture(0)]],
                       texture2d<float, access::write> fieldOut [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float4 sum = float4(0.0);
  for (int i = -4; i <= 4; i++) {
    uint2 coord = uint2(clamp(int(gid.x) + i, 0, int(w - 1)), gid.y);
    sum += fieldIn.read(coord) * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

kernel void fluidBlurV(texture2d<float, access::read> fieldIn [[texture(0)]],
                       texture2d<float, access::write> fieldOut [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float4 sum = float4(0.0);
  for (int i = -4; i <= 4; i++) {
    uint2 coord = uint2(gid.x, clamp(int(gid.y) + i, 0, int(h - 1)));
    sum += fieldIn.read(coord) * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

kernel void fluidRender(texture2d<float, access::sample> dye [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        constant float &bass [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
  float2 center = (float2(gid) + 0.5) / float2(w, h);
  float2 texel = 1.0 / float2(dye.get_width(), dye.get_height());
  
  float4 color = float4(0);
  color += dye.sample(bilinear, center + float2(-0.25, -0.75) * texel);
  color += dye.sample(bilinear, center + float2( 0.75, -0.25) * texel);
  color += dye.sample(bilinear, center + float2(-0.75,  0.25) * texel);
  color += dye.sample(bilinear, center + float2( 0.25,  0.75) * texel);
  color *= 0.25;
  
  float3 bg = float3(0.0, 0.0, 0.02);
  float3 c = bg + max(color.rgb, float3(0.0));
  
  float luminance = dot(c, float3(0.299, 0.587, 0.114));
  c = mix(float3(luminance), c, 1.5 + bass * 0.5);
  
  c *= 1.8 * (1.0 + bass * 1.2);
  
  float peak = max(c.r, max(c.g, c.b));
  if (peak > 0.0) {
    float mappedPeak = peak / (1.0 + peak);
    c *= mappedPeak / peak;
  }
  
  output.write(float4(c, 1.0), gid);
}
