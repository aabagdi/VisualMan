//
//  LiquidLightCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

struct LiquidLightParams {
  float time;
  float bass;
  float mid;
  float high;
  float4 drops[4];
  float4 dropPrecomp[4];
  float4 dropColors[4];
};

struct BlurParams {
  float innerRadius;
  float outerRadius;
  float maxBlurRadius;
  float texWidth;
  float texHeight;
  float bass;
  float mid;
};

struct VoronoiResult {
  float dist1;
  float edgeDist;
  float cellID;
};

inline float vnoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  float2 u = f * f * (3.0 - 2.0 * f);
  float a = shaderHash21(i);
  float b = shaderHash21(i + float2(1.0, 0.0));
  float c = shaderHash21(i + float2(0.0, 1.0));
  float d = shaderHash21(i + float2(1.0, 1.0));
  float n = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  return n * 2.0 - 1.0;
}

inline float2x2 rot2(float a) {
  float c = fast::cos(a), s = fast::sin(a);
  return float2x2(c, s, -s, c);
}

constant float2x2 ROT1 = float2x2( 0.7974,  0.6034, -0.6034,  0.7974);
constant float2x2 ROT2 = float2x2(-0.4161,  0.9093, -0.9093, -0.4161);
constant float2x2 ROT3 = float2x2( 0.2837, -0.9589,  0.9589,  0.2837);

constant float2 OS2_GRAD[32] = {
  float2( 0.130526192220052,  0.991444861373810),
  float2( 0.382683432365090,  0.923879532511287),
  float2( 0.608761429008721,  0.793353340291235),
  float2( 0.793353340291235,  0.608761429008721),
  float2( 0.923879532511287,  0.382683432365090),
  float2( 0.991444861373810,  0.130526192220052),
  float2( 0.991444861373810, -0.130526192220052),
  float2( 0.923879532511287, -0.382683432365090),
  float2( 0.793353340291235, -0.608761429008721),
  float2( 0.608761429008721, -0.793353340291235),
  float2( 0.382683432365090, -0.923879532511287),
  float2( 0.130526192220052, -0.991444861373810),
  float2(-0.130526192220052, -0.991444861373810),
  float2(-0.382683432365090, -0.923879532511287),
  float2(-0.608761429008721, -0.793353340291235),
  float2(-0.793353340291235, -0.608761429008721),
  float2(-0.923879532511287, -0.382683432365090),
  float2(-0.991444861373810, -0.130526192220052),
  float2(-0.991444861373810,  0.130526192220052),
  float2(-0.923879532511287,  0.382683432365090),
  float2(-0.793353340291235,  0.608761429008721),
  float2(-0.608761429008721,  0.793353340291235),
  float2(-0.382683432365090,  0.923879532511287),
  float2(-0.130526192220052,  0.991444861373810),
  float2( 0.130526192220052,  0.991444861373810),
  float2( 0.382683432365090,  0.923879532511287),
  float2( 0.608761429008721,  0.793353340291235),
  float2( 0.793353340291235,  0.608761429008721),
  float2( 0.923879532511287,  0.382683432365090),
  float2( 0.991444861373810,  0.130526192220052),
  float2( 0.991444861373810, -0.130526192220052),
  float2( 0.923879532511287, -0.382683432365090),
};

inline int os2_gradIndex(int ix, int iy) {
  int h = ix * 0x27d4eb2d ^ iy * 0x6b8b4567;
  h ^= h >> 15;
  h *= 0x2c1b3c6d;
  h ^= h >> 12;
  h *= 0xd168aaad;
  h ^= h >> 16;
  return h & 31;
}

inline float os2_contrib(int ix, int iy, float dx, float dy) {
  float a = 2.0 / 3.0 - dx * dx - dy * dy;
  if (a <= 0.0) return 0.0;
  float a2 = a * a;
  float2 g = OS2_GRAD[os2_gradIndex(ix, iy)];
  return a2 * a2 * (g.x * dx + g.y * dy);
}

inline float snoise(float2 pos) {
  const float SKEW   = 0.366025403784439;
  const float UNSKEW = 0.211324865405187;

  float s = (pos.x + pos.y) * SKEW;
  float xs = pos.x + s;
  float ys = pos.y + s;

  int xsb = int(floor(xs));
  int ysb = int(floor(ys));

  float xsi = xs - float(xsb);
  float ysi = ys - float(ysb);

  float ti = float(xsb + ysb) * UNSKEW;
  float dx0 = pos.x - (float(xsb) - ti);
  float dy0 = pos.y - (float(ysb) - ti);

  float value = 0.0;

  value += os2_contrib(xsb, ysb, dx0, dy0);

  value += os2_contrib(xsb + 1, ysb,
                       dx0 - 1.0 + UNSKEW, dy0 + UNSKEW);

  value += os2_contrib(xsb, ysb + 1,
                       dx0 + UNSKEW, dy0 - 1.0 + UNSKEW);

  value += os2_contrib(xsb + 1, ysb + 1,
                       dx0 - 1.0 + 2.0 * UNSKEW, dy0 - 1.0 + 2.0 * UNSKEW);

  if (xsi + ysi > 1.0) {
    value += os2_contrib(xsb + 2, ysb + 1,
                         dx0 - 2.0 + 3.0 * UNSKEW, dy0 - 1.0 + 3.0 * UNSKEW);
    value += os2_contrib(xsb + 1, ysb + 2,
                         dx0 - 1.0 + 3.0 * UNSKEW, dy0 - 2.0 + 3.0 * UNSKEW);
  } else {
    value += os2_contrib(xsb - 1, ysb,
                         dx0 + 1.0 - UNSKEW, dy0 - UNSKEW);
    value += os2_contrib(xsb, ysb - 1,
                         dx0 - UNSKEW, dy0 + 1.0 - UNSKEW);
  }

  return 18.24196194486065 * value;
}

inline float2 liquidWarp(float2 p, float time, float intensity) {
  float2 pX1 = ROT1 * p;
  float2 pY1 = ROT2 * p;
  float2 q = float2(
    snoise(pX1 + time * 0.04),
    snoise(pY1 + float2(5.2, 1.3) + time * 0.035)
  );

  float2 warped = p + 3.0 * q;
  float2 rX = ROT2 * warped;
  float2 rY = ROT3 * warped;
  float2 r = float2(
    snoise(rX + float2(1.7, 9.2) + time * 0.025),
    snoise(rY + float2(8.3, 2.8) + time * 0.03)
  );

  return p + r * intensity;
}

inline VoronoiResult voronoi(float2 p) {
  float2 n = floor(p);
  float2 f = fract(p);

  float dist1 = 8.0;
  float dist2 = 8.0;
  float2 nearestDelta = float2(0.0);
  float2 secondDelta = float2(0.0);
  float cellID = 0.0;

  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      float2 g = float2(float(i), float(j));
      float2 o = shaderHash22(n + g);
      float2 delta = g + o - f;
      float d = dot(delta, delta);
      if (d < dist1) {
        dist2 = dist1;
        secondDelta = nearestDelta;
        dist1 = d;
        nearestDelta = delta;
        cellID = shaderHash21(n + g);
      } else if (d < dist2) {
        dist2 = d;
        secondDelta = delta;
      }
    }
  }

  float2 midpoint = 0.5 * (nearestDelta + secondDelta);
  float2 diff = secondDelta - nearestDelta;
  float diffLen = fast::length(diff);
  float2 edgeDir = diffLen > 1e-6 ? diff / diffLen : float2(1.0, 0.0);

  VoronoiResult r;
  r.dist1 = fast::sqrt(dist1);
  r.edgeDist = dot(midpoint, edgeDir);
  r.cellID = cellID;
  return r;
}

inline half3 liquidColor(float id, float time) {
  half h = half(fract(id * 5.0 + time));
  half3 color;
  if (h < 0.18h)
    color = mix(half3(0.6h, 0.0h, 0.02h), half3(0.85h, 0.02h, 0.1h), h / 0.18h);
  else if (h < 0.35h)
    color = mix(half3(0.85h, 0.02h, 0.1h), half3(0.6h, 0.0h, 0.55h), (h - 0.18h) / 0.17h);
  else if (h < 0.52h)
    color = mix(half3(0.6h, 0.0h, 0.55h), half3(0.02h, 0.06h, 0.7h), (h - 0.35h) / 0.17h);
  else if (h < 0.68h)
    color = mix(half3(0.02h, 0.06h, 0.7h), half3(0.0h, 0.5h, 0.6h), (h - 0.52h) / 0.16h);
  else if (h < 0.84h)
    color = mix(half3(0.0h, 0.5h, 0.6h), half3(0.7h, 0.35h, 0.0h), (h - 0.68h) / 0.16h);
  else
    color = mix(half3(0.7h, 0.35h, 0.0h), half3(0.6h, 0.0h, 0.02h), (h - 0.84h) / 0.16h);
  return color;
}

kernel void liquidLightRender(texture2d<float, access::write> output [[texture(0)]],
                               constant LiquidLightParams &params  [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float aspect = float(w) / float(h);
  float2 p = (uv - 0.5) * float2(aspect, 1.0);

  float time = params.time;
  float bass = params.bass;
  float mid  = params.mid;
  float high = params.high;

  float warpIntensity = 0.55 + bass * 0.35;
  float flowSpeed     = time * (0.05 + mid * 0.02);
  float colorShift    = time * 0.015 + mid * 0.08;
  float edgeSharpness = 10.0 + high * 6.0;

  float2 coords = p * 1.8;

  float breath = 1.0 + 0.08 * fast::sin(time * 0.35) + bass * 0.1;
  float2 drift = float2(fast::cos(time * 0.07), fast::sin(time * 0.09)) * time * 0.015;
  coords = coords * breath + drift;

  half3 dropTint = half3(0.0h);
  half  dropTintWeight = 0.0h;
  for (int i = 0; i < 4; i++) {
    float4 pre = params.dropPrecomp[i];
    if (pre.z < 0.5) continue;

    float4 drop = params.drops[i];
    float2 toCenter = p - drop.xy;
    float d = fast::length(toCenter);
    float2 dir = d > 1e-4 ? toCenter / d : float2(0.0);

    float e = (d - pre.x) * 4.0;
    float pulse = fast::exp(-e * e);
    float pf = pulse * pre.y;

    coords += dir * pf * 0.18;

    half washStrength = half(pf);
    dropTint += half3(params.dropColors[i].rgb) * washStrength;
    dropTintWeight += washStrength;
  }

  float2 warped = liquidWarp(coords, time, warpIntensity);

  float scaleField = snoise(p * 1.2 + time * 0.015) * 0.45 + 1.0;

  VoronoiResult v1 = voronoi(warped * (0.9 * scaleField) + flowSpeed * 0.25);
  VoronoiResult v2 = voronoi(warped * (1.4 * scaleField) + float2(4.0, 8.0) + flowSpeed * 0.18);

  float paletteField = snoise(p * 0.6 + time * 0.02) * 0.5 + 0.5;
  float cellVariation1 = v1.cellID * 0.25;
  float cellVariation2 = v2.cellID * 0.25;
  float cellPhase1 = colorShift * (0.3 + v1.cellID * 0.7);
  float cellPhase2 = colorShift * (0.3 + v2.cellID * 0.7) + 1.5;
  half3 color1 = liquidColor(paletteField + cellVariation1, cellPhase1);
  half3 color2 = liquidColor(paletteField + cellVariation2 + 0.15, cellPhase2);

  half edge1 = half(1.0 - fast::exp(-v1.edgeDist * edgeSharpness));
  half edge2 = half(1.0 - fast::exp(-v2.edgeDist * (edgeSharpness * 0.7)));

  half cellFill1 = mix(0.78h, 1.0h, edge1);
  half cellFill2 = mix(0.78h, 1.0h, edge2);

  half3 result = color1 * cellFill1;
  half blend2 = half(smoothstep(0.18, 0.55, v2.dist1) * 0.32);
  result = mix(result, color2 * cellFill2, blend2);

  float minEdge = min(v1.edgeDist, v2.edgeDist * 1.3);

  float rimMask = fast::exp(-minEdge * 40.0);
  float thicknessJitter = vnoise(warped * 4.0 + time * 0.08) * 0.2;
  half thickness = half(rimMask * (1.0 + thicknessJitter));

  half3 filmPhase = half3(5.5h, 7.0h, 8.5h) * thickness * half(1.0 + bass * 0.25);
  half3 iridescence = 0.5h + 0.18h * cos(filmPhase + half3(0.0h, 2.094h, 4.188h));

  float edgeAA = 1.62 / float(h) * 1.5;
  float rimOuter = 1.0 - smoothstep(0.0, 0.05, minEdge);
  float rimInner = smoothstep(0.0, max(0.012, edgeAA), minEdge);
  half rimIntensity = half(rimOuter * rimInner);

  half cellSizeScale = half(0.45 + 0.55 * smoothstep(0.05, 0.25, v1.dist1));
  half contactLine = half(smoothstep(0.065, 0.008, minEdge)) * cellSizeScale;
  result *= (1.0h - contactLine * 0.45h);

  half3 tint = iridescence * 2.0h;
  result *= mix(half3(1.0h), tint, rimIntensity * 0.55h);

  float specf = vnoise(ROT2 * warped * 2.5 + time * 0.08);
  specf = max(specf, 0.0f);
  float s2 = specf * specf;
  float s4 = s2 * s2;
  float s8 = s4 * s4;
  specf = s8 * s2;
  half spec = half(specf);
  half specMask = edge1 * half(smoothstep(0.0, 0.25, v1.dist1));
  result += half3(1.0h, 0.95h, 0.9h) * spec * 0.4h * specMask;

  result *= 1.0h + half(bass) * 0.45h;
  float shimmerf = vnoise(ROT3 * coords * 4.0 + time * 1.2);
  shimmerf = max(shimmerf, 0.0f);
  float sh2 = shimmerf * shimmerf;
  float sh4 = sh2 * sh2;
  shimmerf = sh4 * sh2 * high * 0.35;
  half shimmer = half(shimmerf);
  result += half3(0.35h, 0.25h, 0.45h) * shimmer * specMask;

  float2 hotUV = p * float2(1.0, 1.1);
  float hotDist = fast::length(hotUV);
  float falloff = 1.0 - smoothstep(0.2, 1.0, hotDist);
  float hotspot = fast::exp(-hotDist * hotDist * 2.2);
  result *= half(mix(0.55, 1.0, falloff) * (1.0 + hotspot * 0.30));
  result += half3(0.22h, 0.15h, 0.07h) * half(hotspot * 0.35);

  if (dropTintWeight > 0.0h) {
    half3 avgTint = dropTint / max(dropTintWeight, 1.0h);
    half luma = dot(result, half3(0.2126h, 0.7152h, 0.0722h));
    half3 tinted = avgTint * max(luma * 1.6h, 0.15h);
    half blend = saturate(dropTintWeight * 0.35h);
    result = mix(result, tinted, blend);
  }

  {
    half3 x = result;
    half a = 2.51h, b = 0.03h, d = 0.59h, e = 0.14h;
    result = clamp((x * (a * x + b)) / (x * (2.43h * x + d) + e), 0.0h, 1.0h);
  }

  result.r = result.r * (1.0h - 0.05h * (1.0h - result.r));
  result.b = result.b * (1.0h + 0.05h * (1.0h - result.b));

  output.write(float4(float3(result), 1.0), gid);
}

constant float4 BLUR_SAMPLES[16] = {
  float4( 0.697581f,  0.716505f, 0.176777f, 0.992218f),
  float4(-0.840742f, -0.541437f, 0.306186f, 0.931558f),
  float4( 0.211276f, -0.977432f, 0.395285f, 0.824084f),
  float4( 0.642915f,  0.765938f, 0.467707f, 0.680319f),
  float4(-0.999893f, -0.014610f, 0.529150f, 0.522046f),
  float4( 0.758020f, -0.652232f, 0.583095f, 0.371577f),
  float4(-0.119523f,  0.992831f, 0.631614f, 0.243117f),
  float4(-0.582199f, -0.813048f, 0.676123f, 0.144862f),
  float4( 0.970273f,  0.242007f, 0.717137f, 0.078662f),
  float4(-0.813781f,  0.581171f, 0.755190f, 0.038988f),
  float4( 0.274818f, -0.961502f, 0.790569f, 0.017639f),
  float4( 0.478860f,  0.877891f, 0.823754f, 0.007262f),
  float4(-0.988253f,  0.152809f, 0.854990f, 0.002714f),
  float4( 0.865665f, -0.500622f, 0.884529f, 0.000921f),
  float4(-0.329257f,  0.944240f, 0.912576f, 0.000283f),
  float4(-0.406217f,  0.913776f, 0.939150f, 0.000079f),
};

kernel void liquidGlassBlur(texture2d<float, access::read>  input   [[texture(0)]],
                             texture2d<float, access::write> output  [[texture(1)]],
                             constant BlurParams &params             [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  const int w = int(input.get_width());
  const int h = int(input.get_height());
  if (int(gid.x) >= w || int(gid.y) >= h) return;

  const int2 maxXY = int2(w - 1, h - 1);
  const half4 sharp_h = half4(saturate(input.read(gid)));

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 norm = (uv - 0.5) * 2.0;
  float dist = length(norm);

  float dynamicInner = params.innerRadius - params.bass * 0.15;
  float dynamicOuter = params.outerRadius - params.bass * 0.1;

  float blurStrength = smoothstep(dynamicInner, dynamicOuter, dist);
  blurStrength *= blurStrength;

  if (blurStrength < 0.001) {
    output.write(float4(sharp_h), gid);
    return;
  }

  float radius = blurStrength * params.maxBlurRadius * (1.0 + params.bass * 0.3);

  float rndAngle = fract(sin(dot(float2(gid), float2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
  float rc = fast::cos(rndAngle), rs = fast::sin(rndAngle);

  half4 accum = half4(0.0h);
  half  totalWeight = 0.0h;

  const int2 centeri = int2(gid);
  for (int i = 0; i < 16; i++) {
    float4 s = BLUR_SAMPLES[i];
    float2 o = float2(s.x * rc - s.y * rs, s.x * rs + s.y * rc);
    float2 offset = o * (s.z * radius);

    int2 sp = clamp(centeri + int2(round(offset)), int2(0), maxXY);

    half weight = half(s.w);
    accum += half4(input.read(uint2(sp))) * weight;
    totalWeight += weight;
  }

  if (totalWeight < 1e-4h) {
    output.write(float4(sharp_h), gid);
    return;
  }
  half4 blurred_h = accum / totalWeight;
  half4 result_h = mix(sharp_h, blurred_h, half(blurStrength));

  float rimCA = blurStrength * (1.0 - blurStrength) * 4.0;
  if (rimCA > 0.01) {
    float2 radialDir = dist > 1e-4 ? norm / dist : float2(1.0, 0.0);
    int2 offR = clamp(centeri + int2(round(radialDir *  1.5)), int2(0), maxXY);
    int2 offB = clamp(centeri - int2(round(radialDir *  1.5)), int2(0), maxXY);
    half rCh = half(input.read(uint2(offR)).r);
    half bCh = half(input.read(uint2(offB)).b);
    half mixAmt = half(rimCA * 0.35);
    result_h.r = mix(result_h.r, rCh, mixAmt);
    result_h.b = mix(result_h.b, bCh, mixAmt);
  }

  half luma = dot(result_h.rgb, half3(0.2126h, 0.7152h, 0.0722h));
  half desatAmount = half(blurStrength * max(0.2 - params.mid * 0.15, 0.05));
  result_h.rgb = mix(result_h.rgb, half3(luma), desatAmount);

  result_h.rgb += half3(0.02h, 0.02h, 0.03h) * half(blurStrength);

  output.write(float4(saturate(result_h)), gid);
}
