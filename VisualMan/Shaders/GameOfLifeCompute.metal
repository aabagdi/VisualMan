//
//  GameOfLifeCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

#include <metal_stdlib>
using namespace metal;

struct GameOfLifeParams {
  float bass;
  float mid;
  float high;
  float time;
  uint simWidth;
  uint simHeight;
  uint frameCount;
  float spawnRate;
};

inline float hash(uint2 p, uint seed) {
  uint h = p.x * 374761393u + p.y * 668265263u + seed * 1013904223u;
  h = (h ^ (h >> 13)) * 1274126177u;
  return float(h & 0x00FFFFFFu) / float(0x00FFFFFFu);
}

inline float3 ageColor(float age) {
  float t = saturate(age * 8.0);
  float3 light = float3(0.608, 0.737, 0.059);
  float3 midC  = float3(0.545, 0.675, 0.059);
  float3 dark  = float3(0.188, 0.384, 0.188);
  return (t < 0.5) ? mix(light, midC, t * 2.0)
                   : mix(midC,  dark, (t - 0.5) * 2.0);
}

kernel void gameOfLifeStep(texture2d<half, access::read>  input   [[texture(0)]],
                           texture2d<half, access::write> output  [[texture(1)]],
                           constant GameOfLifeParams &params      [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
  const uint w = params.simWidth;
  const uint h = params.simHeight;
  if (gid.x >= w || gid.y >= h) return;

  half4 cell = input.read(gid);
  bool alive = cell.r > 0.5h;
  float age = float(cell.g);

  uint xm1 = select(gid.x - 1u, w - 1u, gid.x == 0u);
  uint xp1 = select(gid.x + 1u, 0u,     gid.x == w - 1u);
  uint ym1 = select(gid.y - 1u, h - 1u, gid.y == 0u);
  uint yp1 = select(gid.y + 1u, 0u,     gid.y == h - 1u);

  uint xs[3] = { xm1, gid.x, xp1 };
  uint ys[3] = { ym1, gid.y, yp1 };

  int neighbors = 0;
  for (uint dy = 0u; dy < 3u; dy++) {
    for (uint dx = 0u; dx < 3u; dx++) {
      if (dx == 1u && dy == 1u) continue;
      half4 n = input.read(uint2(xs[dx], ys[dy]));
      if (n.r > 0.5h) neighbors++;
    }
  }

  bool newAlive = alive ? (neighbors == 2 || neighbors == 3) : (neighbors == 3);

  if (!newAlive && params.bass > 0.15) {
    float rng = hash(gid, params.frameCount);
    float threshold = 1.0 - params.spawnRate * params.bass;
    if (rng > threshold) {
      newAlive = true;
    }
  }

  if (!newAlive && alive && params.mid > 0.3) {
    if (neighbors >= 4 && neighbors <= 6) {
      float rng = hash(gid, params.frameCount + 7777u);
      if (rng < params.mid * 0.3) {
        newAlive = true;
      }
    }
  }

  float newAge = newAlive ? min(age + (1.0 / 32.0), 1.0) : 0.0;

  output.write(half4(half(newAlive ? 1.0 : 0.0), half(newAge), 0.0h, 1.0h), gid);
}

kernel void gameOfLifeRender(texture2d<half, access::read>  sim     [[texture(0)]],
                             texture2d<float, access::write> output  [[texture(1)]],
                             constant GameOfLifeParams &params       [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  const uint outW = output.get_width();
  const uint outH = output.get_height();
  if (gid.x >= outW || gid.y >= outH) return;

  bool landscape = outW > outH;
  uint mapW = landscape ? params.simHeight : params.simWidth;
  uint mapH = landscape ? params.simWidth  : params.simHeight;

  uint cellPx = max(1u, min(outW / mapW, outH / mapH));
  uint gridW = cellPx * mapW;
  uint gridH = cellPx * mapH;
  uint offX = (outW - gridW) / 2u;
  uint offY = (outH - gridH) / 2u;

  float scanline = 1.0 - 0.08 * float(gid.y % 2u);
  float3 bgColor = float3(0.059, 0.220, 0.059) * scanline;

  if (gid.x < offX || gid.y < offY || gid.x >= offX + gridW || gid.y >= offY + gridH) {
    output.write(float4(bgColor, 1.0), gid);
    return;
  }

  uint lx = gid.x - offX;
  uint ly = gid.y - offY;
  uint cx = lx / cellPx;
  uint cy = ly / cellPx;
  uint sx = landscape ? cy : cx;
  uint sy = landscape ? cx : cy;
  sx = min(sx, params.simWidth  - 1u);
  sy = min(sy, params.simHeight - 1u);

  float2 local = float2(float(lx % cellPx), float(ly % cellPx)) / float(cellPx);

  half4 cell = sim.read(uint2(sx, sy));
  bool alive = cell.r > 0.5h;
  float age = float(cell.g);

  const float inset = 0.12;
  bool insideCell = all(local > float2(inset)) && all(local < float2(1.0 - inset));

  float3 color = bgColor;

  if (alive && insideCell) {
    float3 c = ageColor(age);

    float3 light = float3(0.608, 0.737, 0.059);
    c = mix(c, light, saturate(params.bass * 0.4));
    float t = saturate(age * 8.0);
    c *= 1.0 + params.high * (1.0 - t) * 0.2;

    color = saturate(c) * scanline;
  } else if (!insideCell) {
    if (alive) {
      float youth = 1.0 - saturate(age * 24.0);
      if (youth > 0.0) {
        float d = max(abs(local.x - 0.5), abs(local.y - 0.5));
        float gutterT = saturate((d - (0.5 - inset)) / inset);
        float coronaStrength = youth * (1.0 - gutterT) * 0.55;
        color = bgColor + ageColor(age) * coronaStrength * scanline;
      }
    }
  }
  
  output.write(float4(color, 1.0), gid);
}
