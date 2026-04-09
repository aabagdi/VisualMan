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
  current.xyz = min(current.xyz, float3(1.5));
  field.write(current, gid);
}

kernel void fluidDiffuse(texture2d<float, access::read> fieldIn [[texture(0)]],
                         texture2d<float, access::write> fieldOut [[texture(1)]],
                         constant float &alpha [[buffer(0)]],
                         constant float &rBeta [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float4 center = fieldIn.read(gid);
  float4 sum = fieldIn.read(left) + fieldIn.read(right) +
               fieldIn.read(down) + fieldIn.read(up);
  
  float4 result = (center + alpha * sum) * rBeta;
  if (any(isnan(result)) || any(isinf(result))) {
    result = float4(0);
  }
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

kernel void fluidAdvectCovector(texture2d<float, access::read> velocityIn [[texture(0)]],
                                texture2d<float, access::write> covectorOut [[texture(1)]],
                                constant float &dt [[buffer(0)]],
                                constant float &dissipation [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
  int w = int(velocityIn.get_width());
  int h = int(velocityIn.get_height());
  
  float2 pos = float2(gid) + 0.5;
  float2 vel = velocityIn.read(gid).xy;
  
  if (any(isnan(vel)) || any(isinf(vel))) vel = float2(0);
  float speed = length(vel);
  if (speed > 500.0) vel *= 500.0 / speed;
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(int(gid.x) + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(int(gid.y) + 1, h - 1));
  
  float2 vL = velocityIn.read(left).xy;
  float2 vR = velocityIn.read(right).xy;
  float2 vD = velocityIn.read(down).xy;
  float2 vU = velocityIn.read(up).xy;
  
  float dvx_dx = 0.5 * (vR.x - vL.x);
  float dvx_dy = 0.5 * (vU.x - vD.x);
  float dvy_dx = 0.5 * (vR.y - vL.y);
  float dvy_dy = 0.5 * (vU.y - vD.y);

  constexpr float maxJ = 0.45;
  float g00 = clamp(dt * dvx_dx, -maxJ, maxJ);
  float g01 = clamp(dt * dvx_dy, -maxJ, maxJ);
  float g10 = clamp(dt * dvy_dx, -maxJ, maxJ);
  float g11 = clamp(dt * dvy_dy, -maxJ, maxJ);
  
  float2 backPos = pos - dt * vel;
  float2 sp = backPos - 0.5;
  int2 base = int2(floor(sp));
  float2 f = sp - float2(base);
  
  int2 c00 = clamp(base,             int2(0), int2(w - 1, h - 1));
  int2 c10 = clamp(base + int2(1,0), int2(0), int2(w - 1, h - 1));
  int2 c01 = clamp(base + int2(0,1), int2(0), int2(w - 1, h - 1));
  int2 c11 = clamp(base + int2(1,1), int2(0), int2(w - 1, h - 1));
  
  float2 v00 = velocityIn.read(uint2(c00)).xy;
  float2 v10 = velocityIn.read(uint2(c10)).xy;
  float2 v01 = velocityIn.read(uint2(c01)).xy;
  float2 v11 = velocityIn.read(uint2(c11)).xy;
  
  float2 vBack = mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
  
  float2 covector;
  covector.x = (1.0 - g00) * vBack.x + (-g10) * vBack.y;
  covector.y = (-g01) * vBack.x + (1.0 - g11) * vBack.y;
  
  covector *= dissipation;
  
  // Stability clamp
  float covSpeed = length(covector);
  if (covSpeed > 500.0) covector *= 500.0 / covSpeed;
  if (any(isnan(covector)) || any(isinf(covector))) covector = float2(0);
  
  covectorOut.write(float4(covector, 0, 0), gid);
}

kernel void fluidDivergence(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::write> divergenceOut [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  
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

inline float computeCurl(texture2d<float, access::read_write> velocity,
                         uint2 pos, uint w, uint h) {
  uint2 left  = uint2(max(int(pos.x) - 1, 0), pos.y);
  uint2 right = uint2(min(pos.x + 1, w - 1), pos.y);
  uint2 down  = uint2(pos.x, max(int(pos.y) - 1, 0));
  uint2 up    = uint2(pos.x, min(pos.y + 1, h - 1));
  return 0.5 * (velocity.read(right).y - velocity.read(left).y
              - velocity.read(up).x    + velocity.read(down).x);
}

kernel void fluidVorticityConfine(texture2d<float, access::read_write> velocity [[texture(0)]],
                                   constant float &strength [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
  uint w = velocity.get_width();
  uint h = velocity.get_height();
  
  float curl = computeCurl(velocity, gid, w, h);
  
  uint2 left2  = uint2(max(int(gid.x) - 2, 0), gid.y);
  uint2 right2 = uint2(min(gid.x + 2, w - 1), gid.y);
  uint2 down2  = uint2(gid.x, max(int(gid.y) - 2, 0));
  uint2 up2    = uint2(gid.x, min(gid.y + 2, h - 1));
  
  float2 gradAbs = 0.25 * float2(
    abs(computeCurl(velocity, right2, w, h)) - abs(computeCurl(velocity, left2, w, h)),
    abs(computeCurl(velocity, up2, w, h))    - abs(computeCurl(velocity, down2, w, h))
  );
  
  float len = length(gradAbs);
  if (len < 1e-4) return;
  
  float2 N = gradAbs / len;
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
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tid [[thread_position_in_threadgroup]],
                       uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  
  constexpr uint TILE_W = 24;
  threadgroup float4 tile[TILE_W * 16];
  
  int tileOriginX = int(tgid.x * 16) - 4;
  int tileOriginY = int(tgid.y * 16);
  
  uint localIdx = tid.y * 16 + tid.x;
  if (localIdx < TILE_W * 16) {
    uint tileX = localIdx % TILE_W;
    uint tileY = localIdx / TILE_W;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[localIdx] = fieldIn.read(uint2(gx, gy));
  }
  uint secondIdx = localIdx + 256;
  if (secondIdx < TILE_W * 16) {
    uint tileX = secondIdx % TILE_W;
    uint tileY = secondIdx / TILE_W;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[secondIdx] = fieldIn.read(uint2(gx, gy));
  }
  
  threadgroup_barrier(mem_flags::mem_threadgroup);
  
  if (gid.x >= w || gid.y >= h) return;
  
  float4 sum = float4(0.0);
  for (int i = -4; i <= 4; i++) {
    uint tileCol = uint(int(tid.x) + 4 + i);
    sum += tile[tid.y * TILE_W + tileCol] * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

kernel void fluidBlurV(texture2d<float, access::read> fieldIn [[texture(0)]],
                       texture2d<float, access::write> fieldOut [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tid [[thread_position_in_threadgroup]],
                       uint2 tgid [[threadgroup_position_in_grid]]) {
  uint w = fieldIn.get_width();
  uint h = fieldIn.get_height();
  
  constexpr uint TILE_H = 24;
  threadgroup float4 tile[16 * TILE_H];
  
  int tileOriginX = int(tgid.x * 16);
  int tileOriginY = int(tgid.y * 16) - 4;
  
  uint localIdx = tid.y * 16 + tid.x;
  if (localIdx < 16 * TILE_H) {
    uint tileX = localIdx % 16;
    uint tileY = localIdx / 16;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[localIdx] = fieldIn.read(uint2(gx, gy));
  }
  uint secondIdx = localIdx + 256;
  if (secondIdx < 16 * TILE_H) {
    uint tileX = secondIdx % 16;
    uint tileY = secondIdx / 16;
    int gx = clamp(tileOriginX + int(tileX), 0, int(w - 1));
    int gy = clamp(tileOriginY + int(tileY), 0, int(h - 1));
    tile[secondIdx] = fieldIn.read(uint2(gx, gy));
  }
  
  threadgroup_barrier(mem_flags::mem_threadgroup);
  
  if (gid.x >= w || gid.y >= h) return;
  
  float4 sum = float4(0.0);
  for (int i = -4; i <= 4; i++) {
    uint tileRow = uint(int(tid.y) + 4 + i);
    sum += tile[tileRow * 16 + tid.x] * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

kernel void fluidBloomThreshold(texture2d<float, access::read> dye [[texture(0)]],
                                 texture2d<float, access::write> bloomOut [[texture(1)]],
                                 constant float &threshold [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
  float4 color = dye.read(gid);
  float brightness = dot(color.rgb, float3(0.299, 0.587, 0.114));
  float contrib = max(brightness - threshold, 0.0);
  float factor = contrib / max(brightness, 1e-4);
  bloomOut.write(float4(color.rgb * factor, 0.0), gid);
}

kernel void fluidRender(texture2d<float, access::sample> dye [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        texture2d<float, access::read> bloom [[texture(2)]],
                        constant float &bass [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = output.get_width();
  uint h = output.get_height();
  
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
  
  uint2 bloomCoord = uint2(float2(gid) * float2(bloom.get_width(), bloom.get_height()) / float2(w, h));
  bloomCoord = min(bloomCoord, uint2(bloom.get_width() - 1, bloom.get_height() - 1));
  c += bloom.read(bloomCoord).rgb * 0.3;
  
  c *= 1.0 + bass * 0.4;
  
  c = c / (1.0 + c);

  constexpr float maxBrightness = 0.88;
  float peak = max(c.r, max(c.g, c.b));
  if (peak > maxBrightness) {
    c *= maxBrightness / peak;
  }
  
  float lum = dot(c, float3(0.299, 0.587, 0.114));
  c = mix(float3(lum), c, 1.7);
  c = clamp(c, 0.0, maxBrightness);
  
  output.write(float4(c, 1.0), gid);
}
