//
//  LiquidLightCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#include <metal_stdlib>
using namespace metal;

struct LiquidLightParams {
  float time;
  float bass;
  float mid;
  float high;
};

struct BlurParams {
  float innerRadius;
  float outerRadius;
  float maxBlurRadius;
  float texWidth;
  float texHeight;
  float bass;
};

inline float2 hash22(float2 p) {
  float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

inline float hash21(float2 p) {
  float3 p3 = fract(float3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

inline float2x2 rot2(float a) {
  float c = cos(a), s = sin(a);
  return float2x2(c, s, -s, c);
}

constant float2x2 ROT1 = float2x2( 0.7974,  0.6034, -0.6034,  0.7974);
constant float2x2 ROT2 = float2x2(-0.4161,  0.9093, -0.9093, -0.4161);
constant float2x2 ROT3 = float2x2( 0.2837, -0.9589,  0.9589,  0.2837);

constant float2 OS2_GRAD[24] = {
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
};

inline int os2_gradIndex(int ix, int iy) {
  int h = ix * 0x27d4eb2d ^ iy * 0x6b8b4567;
  h ^= h >> 15;
  h *= 0x2c1b3c6d;
  h ^= h >> 12;
  h *= 0xd168aaad;
  h ^= h >> 16;
  int idx = h % 24;
  return idx < 0 ? idx + 24 : idx;
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
    snoise(pX1 + float2(0.0, 0.0) + time * 0.04)
      + 0.5 * snoise(ROT3 * p * 2.0 + float2(3.0, 7.0) + time * 0.06),
    snoise(pY1 + float2(5.2, 1.3) + time * 0.035)
      + 0.5 * snoise(ROT1 * p * 2.1 + float2(8.1, 2.5) + time * 0.05)
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

struct VoronoiResult {
  float dist1;
  float edgeDist;
  float cellID;
};

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
      float2 o = hash22(n + g);
      float2 delta = g + o - f;
      float d = dot(delta, delta);
      if (d < dist1) {
        dist2 = dist1;
        secondDelta = nearestDelta;
        dist1 = d;
        nearestDelta = delta;
        cellID = hash21(n + g);
      } else if (d < dist2) {
        dist2 = d;
        secondDelta = delta;
      }
    }
  }

  float2 midpoint = 0.5 * (nearestDelta + secondDelta);
  float2 edgeDir = normalize(secondDelta - nearestDelta);

  VoronoiResult r;
  r.dist1 = sqrt(dist1);
  r.edgeDist = dot(midpoint, edgeDir);
  r.cellID = cellID;
  return r;
}

inline float3 liquidColor(float id, float time) {
  float h = fract(id * 5.0 + time);
  float3 color;
  if (h < 0.18)
    color = mix(float3(0.6, 0.0, 0.02), float3(0.85, 0.02, 0.1), h / 0.18);
  else if (h < 0.35)
    color = mix(float3(0.85, 0.02, 0.1), float3(0.6, 0.0, 0.55), (h - 0.18) / 0.17);
  else if (h < 0.52)
    color = mix(float3(0.6, 0.0, 0.55), float3(0.02, 0.06, 0.7), (h - 0.35) / 0.17);
  else if (h < 0.68)
    color = mix(float3(0.02, 0.06, 0.7), float3(0.0, 0.5, 0.6), (h - 0.52) / 0.16);
  else if (h < 0.84)
    color = mix(float3(0.0, 0.5, 0.6), float3(0.7, 0.35, 0.0), (h - 0.68) / 0.16);
  else
    color = mix(float3(0.7, 0.35, 0.0), float3(0.6, 0.0, 0.02), (h - 0.84) / 0.16);
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

  float2 warped = liquidWarp(coords, time, warpIntensity);

  VoronoiResult v1 = voronoi(warped * 0.9 + flowSpeed * 0.25);
  VoronoiResult v2 = voronoi(warped * 1.4 + float2(4.0, 8.0) + flowSpeed * 0.18);

  float3 color1 = liquidColor(v1.cellID, colorShift);
  float3 color2 = liquidColor(v2.cellID + 0.33, colorShift + 1.5);

  float edge1 = 1.0 - exp(-v1.edgeDist * edgeSharpness);
  float edge2 = 1.0 - exp(-v2.edgeDist * (edgeSharpness * 0.7));

  float3 result = color1 * edge1;
  float blend2 = smoothstep(0.12, 0.5, v2.dist1) * 0.55;
  result = mix(result, color2 * edge2, blend2);

  float minEdge = min(v1.edgeDist, v2.edgeDist * 1.3);
  float darkBorder = smoothstep(0.06, 0.0, minEdge);
  result *= (1.0 - darkBorder * 0.85);

  float fringe = smoothstep(0.0, 0.04, minEdge) * smoothstep(0.10, 0.04, minEdge);
  float3 fringeColor = (color1 + color2) * 0.5 + float3(0.2, 0.1, 0.2);
  result += fringeColor * fringe * 0.35;

  float spec = snoise(ROT2 * warped * 2.5 + time * 0.08);
  spec = pow(max(spec, 0.0), 10.0);
  float specMask = edge1 * smoothstep(0.0, 0.25, v1.dist1);
  result += float3(1.0, 0.95, 0.9) * spec * 0.4 * specMask;

  result *= 1.0 + bass * 0.45;
  float shimmer = snoise(ROT3 * coords * 4.0 + time * 1.2);
  shimmer = pow(max(shimmer, 0.0), 6.0) * high * 0.35;
  result += float3(0.35, 0.25, 0.45) * shimmer * specMask;

  float2 vigUV = p * float2(1.0, 1.1);
  float dist = length(vigUV);
  float vignette = 1.0 - smoothstep(0.55, 1.2, dist);
  result *= vignette;

  {
    float3 x = result;
    float a = 2.51, b = 0.03, d = 0.59, e = 0.14;
    result = clamp((x * (a * x + b)) / (x * (2.43 * x + d) + e), 0.0, 1.0);
  }

  result = pow(result, float3(0.95, 1.0, 1.05));

  output.write(float4(result, 1.0), gid);
}

kernel void liquidGlassBlur(texture2d<float, access::read>  input   [[texture(0)]],
                             texture2d<float, access::write> output  [[texture(1)]],
                             constant BlurParams &params             [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
  uint w = input.get_width();
  uint h = input.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);

  float2 norm = (uv - 0.5) * 2.0;
  float dist = length(norm);

  float dynamicInner = params.innerRadius - params.bass * 0.15;
  float dynamicOuter = params.outerRadius - params.bass * 0.1;

  float blurStrength = smoothstep(dynamicInner, dynamicOuter, dist);

  if (blurStrength < 0.001) {
    output.write(input.read(gid), gid);
    return;
  }

  float radius = blurStrength * params.maxBlurRadius * (1.0 + params.bass * 0.3);

  const int SAMPLES = 28;
  const float goldenAngle = 2.39996323;

  float4 accum = float4(0.0);
  float totalWeight = 0.0;

  for (int i = 0; i < SAMPLES; i++) {
    float fi = float(i) + 0.5;
    float t = fi / float(SAMPLES);
    float r = sqrt(t) * radius;
    float theta = fi * goldenAngle;
    float2 offset = float2(cos(theta), sin(theta)) * r;

    int2 samplePos = int2(float2(gid) + offset);
    samplePos = clamp(samplePos, int2(0), int2(w - 1, h - 1));

    float weight = exp(-2.5 * t * t);
    accum += input.read(uint2(samplePos)) * weight;
    totalWeight += weight;
  }

  if (totalWeight < 1e-4) {
    output.write(input.read(gid), gid);
    return;
  }
  float4 blurred = accum / totalWeight;
  float4 sharp = input.read(gid);
  float4 result = mix(sharp, blurred, blurStrength);

  float luma = dot(result.rgb, float3(0.2126, 0.7152, 0.0722));
  result.rgb = mix(result.rgb, float3(luma), blurStrength * 0.2);

  result.rgb += float3(0.02, 0.02, 0.03) * blurStrength;

  output.write(result, gid);
}
