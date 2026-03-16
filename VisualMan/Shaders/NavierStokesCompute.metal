//
//  NavierStokesCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#include <metal_stdlib>
using namespace metal;

kernel void fluidSplat(texture2d<float, access::read_write> field [[texture(0)]],
                       constant float2 &point [[buffer(0)]],
                       constant float3 &value [[buffer(1)]],
                       constant float &radius [[buffer(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= field.get_width() || gid.y >= field.get_height()) return;
  
  float2 pos = float2(gid) + 0.5;
  float2 diff = pos - point;
  float dist2 = dot(diff, diff);
  float r2 = radius * radius;
  float falloff = exp(-dist2 / r2);
  
  float4 current = field.read(gid);
  current.xyz += value * falloff;
  field.write(current, gid);
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
  
  uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, max(int(gid.y) - 1, 0));
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));
  
  float2 gradAbs = 0.5 * float2(abs(vorticity.read(right).x) - abs(vorticity.read(left).x),
                                  abs(vorticity.read(up).x)    - abs(vorticity.read(down).x));
  float len = length(gradAbs);
  if (len < 1e-5) return;
  
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
    uint2 coord = uint2(clamp(int(gid.x) + i * 2, 0, int(w - 1)), gid.y);
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
    uint2 coord = uint2(gid.x, clamp(int(gid.y) + i * 2, 0, int(h - 1)));
    sum += fieldIn.read(coord) * blurWeights[i + 4];
  }
  fieldOut.write(sum, gid);
}

float4 cubicWeights(float t) {
  float t2 = t * t;
  float t3 = t2 * t;
  return float4(
    -0.5*t3 + t2 - 0.5*t,
     1.5*t3 - 2.5*t2 + 1.0,
    -1.5*t3 + 2.0*t2 + 0.5*t,
     0.5*t3 - 0.5*t2
  );
}

float4 sampleBicubic(texture2d<float, access::read> tex, float2 coord) {
  float2 texSize = float2(tex.get_width(), tex.get_height());
  
  float2 pixel = coord * texSize - 0.5;
  float2 origin = floor(pixel);
  float2 frac = pixel - origin;
  
  float4 wx = cubicWeights(frac.x);
  float4 wy = cubicWeights(frac.y);
  
  float4 result = float4(0.0);
  for (int j = -1; j <= 2; j++) {
    float wY = wy[j + 1];
    for (int i = -1; i <= 2; i++) {
      float wX = wx[i + 1];
      int2 sampleCoord = int2(origin) + int2(i, j);
      sampleCoord = clamp(sampleCoord, int2(0), int2(texSize) - 1);
      result += tex.read(uint2(sampleCoord)) * wX * wY;
    }
  }
  return result;
}

kernel void fluidRender(texture2d<float, access::read> dye [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;
  
  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  
  float4 color = sampleBicubic(dye, uv);
  
  float3 bg = float3(0.0, 0.0, 0.02);
  float3 c = bg + color.rgb;
  
  float luminance = dot(c, float3(0.299, 0.587, 0.114));
  c = mix(float3(luminance), c, 1.4);
  
  c = c / (1.0 + c);
  
  c = smoothstep(0.0, 1.0, c);
  
  output.write(float4(c, 1.0), gid);
}
