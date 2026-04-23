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

inline float lcdDarkness(float age) {
  float t = saturate(age * 6.0);
  return mix(0.55, 0.92, t);
}

kernel void gameOfLifeStep(texture2d<half, access::read>  input   [[texture(0)]],
                           texture2d<half, access::write> output  [[texture(1)]],
                           constant GameOfLifeParams &params      [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]],
                           uint2 tid [[thread_position_in_threadgroup]],
                           uint2 tgid [[threadgroup_position_in_grid]]) {
  const uint w = params.simWidth;
  const uint h = params.simHeight;

  constexpr uint TILE = 18;
  threadgroup half2 tile[TILE * TILE];

  int tileOriginX = int(tgid.x * 16) - 1;
  int tileOriginY = int(tgid.y * 16) - 1;

  uint localIdx = tid.y * 16 + tid.x;
  for (uint idx = localIdx; idx < TILE * TILE; idx += 256) {
    uint tx = idx % TILE;
    uint ty = idx / TILE;
    int gx = tileOriginX + int(tx);
    int gy = tileOriginY + int(ty);
    gx = ((gx % int(w)) + int(w)) % int(w);
    gy = ((gy % int(h)) + int(h)) % int(h);
    half4 c = input.read(uint2(uint(gx), uint(gy)));
    tile[idx] = half2(c.r, c.g);
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (gid.x >= w || gid.y >= h) return;

  uint lx = tid.x + 1;
  uint ly = tid.y + 1;
  uint myIdx = ly * TILE + lx;

  half2 cell = tile[myIdx];
  bool alive = cell.x > 0.5h;
  float age = float(cell.y);

  int neighbors = 0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      half2 n = tile[(ly + dy) * TILE + (lx + dx)];
      if (n.x > 0.5h) neighbors++;
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

inline float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
  float2 d = abs(p) - halfSize + float2(radius);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
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

  const float3 backlight   = float3(0.605, 0.680, 0.295);
  const float3 pixelDark   = float3(0.180, 0.210, 0.110);
  const float3 gridLine    = float3(0.480, 0.540, 0.240);
  const float3 shadowTint  = float3(0.380, 0.430, 0.190);
  const float3 bezelColor  = float3(0.350, 0.400, 0.180);

  float2 screenUV = float2(float(gid.x), float(gid.y)) / float2(float(outW), float(outH));
  float2 vD = screenUV - float2(0.5, 0.5);
  float vignette = 1.0 - 0.35 * dot(vD, vD) * 4.0;
  vignette = saturate(vignette);

  if (gid.x < offX || gid.y < offY || gid.x >= offX + gridW || gid.y >= offY + gridH) {
    output.write(float4(bezelColor * vignette * 0.8, 1.0), gid);
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

  uint lpx = lx % cellPx;
  uint lpy = ly % cellPx;
  float cellPxF = float(cellPx);

  bool onGridLine = (lpx == 0u) || (lpy == 0u);

  half4 cell = sim.read(uint2(sx, sy));
  bool alive = cell.r > 0.5h;
  float age = float(cell.g);

  if (onGridLine) {
    output.write(float4(gridLine * vignette, 1.0), gid);
    return;
  }

  float3 color;

  if (alive) {
    float darkness = lcdDarkness(age);
    darkness = min(darkness + params.bass * 0.08, 0.95);
    float3 segColor = mix(backlight, pixelDark, darkness);

    float2 inner = float2(float(lpx), float(lpy)) / cellPxF;
    float depthShade = 1.0 - saturate((inner.x + inner.y - 1.0) * 0.8) * 0.20;
    float depthLight = saturate((1.0 - inner.x - inner.y) * 0.6) * 0.08;
    segColor *= depthShade;
    segColor += depthLight;

    color = segColor * vignette;
  } else {
    // Only compute shadows for dead cells (alive cells don't use shadowStrength)
    const uint shadowPx = max(2u, cellPx / 3u);
    float shadowStrength = 0.0;

    if (lpx < shadowPx) {
      uint ncx = (cx > 0u) ? cx - 1u : mapW - 1u;
      uint nsx = landscape ? cy : ncx;
      uint nsy = landscape ? ncx : cy;
      nsx = min(nsx, params.simWidth - 1u);
      nsy = min(nsy, params.simHeight - 1u);
      half4 leftCell = sim.read(uint2(nsx, nsy));
      if (leftCell.r > 0.5h) {
        float fade = 1.0 - float(lpx) / float(shadowPx);
        shadowStrength = max(shadowStrength, fade * 0.55);
      }
    }

    if (lpy < shadowPx) {
      uint ncy = (cy > 0u) ? cy - 1u : mapH - 1u;
      uint nsx = landscape ? ncy : cx;
      uint nsy = landscape ? cx  : ncy;
      nsx = min(nsx, params.simWidth - 1u);
      nsy = min(nsy, params.simHeight - 1u);
      half4 aboveCell = sim.read(uint2(nsx, nsy));
      if (aboveCell.r > 0.5h) {
        float fade = 1.0 - float(lpy) / float(shadowPx);
        shadowStrength = max(shadowStrength, fade * 0.55);
      }
    }

    if (lpx < shadowPx && lpy < shadowPx) {
      uint ncx = (cx > 0u) ? cx - 1u : mapW - 1u;
      uint ncy = (cy > 0u) ? cy - 1u : mapH - 1u;
      uint nsx = landscape ? ncy : ncx;
      uint nsy = landscape ? ncx : ncy;
      nsx = min(nsx, params.simWidth - 1u);
      nsy = min(nsy, params.simHeight - 1u);
      half4 diagCell = sim.read(uint2(nsx, nsy));
      if (diagCell.r > 0.5h) {
        float fadeX = 1.0 - float(lpx) / float(shadowPx);
        float fadeY = 1.0 - float(lpy) / float(shadowPx);
        shadowStrength = max(shadowStrength, min(fadeX, fadeY) * 0.45);
      }
    }

    float3 baseColor = backlight * (1.0 - 0.025) * vignette;
    color = mix(baseColor, shadowTint * vignette, shadowStrength);
  }

  float rowLine = 1.0 - 0.012 * float(gid.y % 2u);
  color *= rowLine;

  output.write(float4(saturate(color), 1.0), gid);
}
