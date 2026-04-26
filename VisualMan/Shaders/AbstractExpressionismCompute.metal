//
//  AbstractExpressionismCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
using namespace metal;

struct AbExParams {
  float4 audio;
  float4 canvas;
  float4 config;
  float4 camera;
};

struct AbExStroke {
  float4 posAngle;
  float4 sizeOpacity;
  float4 color;
};

inline float hash11(float x) {
  x = fract(x * 0.1031);
  x *= x + 33.33;
  x *= x + x;
  return fract(x);
}

inline half canvasWeave(float2 pixelPos) {
  float threadX = sin(pixelPos.x * 0.85) * 0.5 + 0.5;
  float threadY = sin(pixelPos.y * 0.85) * 0.5 + 0.5;
  float weave = threadX * threadY;
  return half(weave * 0.055);
}

inline float2 canvasWeaveGradient(float2 pixelPos) {
  float cX = 0.85, cY = 0.85;
  float sinX = sin(pixelPos.x * cX);
  float sinY = sin(pixelPos.y * cY);
  float cosX = cos(pixelPos.x * cX);
  float cosY = cos(pixelPos.y * cY);
  float tX = sinX * 0.5 + 0.5;
  float tY = sinY * 0.5 + 0.5;
  float dtX = 0.5 * cX * cosX;
  float dtY = 0.5 * cY * cosY;
  return float2(dtX * tY * 0.045, tX * dtY * 0.045);
}

inline half3 wetMix(half3 c1, half3 c2, half t) {
  half3 a = 1.0h - c1;
  half3 b = 1.0h - c2;
  half3 mixed = mix(a * a, b * b, t);
  return 1.0h - sqrt(max(mixed, half3(0.0h)));
}

struct StrokeResult {
  float coverage;
  float heightDelta;
  float alongNorm;
  float acrossT;
  float bristleTone;
  float strokeWetness;
  float impastoPermanence;
};

inline StrokeResult evaluateGestural(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;
  r.strokeWetness = 1.0; r.impastoPermanence = 0.0;

  float2 center  = s.posAngle.xy;
  float angle    = s.posAngle.z;
  float halfLen  = max(s.posAngle.w, 0.01);
  float halfWd   = max(s.sizeOpacity.x, 0.003);
  float baseOp   = s.sizeOpacity.y;
  float seed     = s.sizeOpacity.z;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);

  float alongT = local.x / halfLen;
  float acrossT = local.y / halfWd;

  if (alongT < -1.15 || alongT > 1.25 || abs(acrossT) > 1.35) return r;

  float wob = sin(alongT * (3.0 + hash11(seed) * 3.0) + seed * 17.0) * 0.15;
  wob += shaderSimplex2D(float2(alongT * 2.2, seed)) * 0.175;
  acrossT += wob;

  float sAlong = (alongT + 1.0) * 0.5;

  float wetRoll = hash11(seed * 2.39);
  float paintLoadScale;
  float strokeWetness;
  float baselineDryness;
  float impastoPermanence;
  if (wetRoll < 0.45) {
    paintLoadScale    = 0.42;
    strokeWetness     = 0.08 + wetRoll * 0.32;
    baselineDryness   = 0.70;
    impastoPermanence = 0.10;
  } else if (wetRoll < 0.78) {
    paintLoadScale    = 0.95 + hash11(seed * 3.71) * 0.10;
    strokeWetness     = 0.65 + hash11(seed * 3.71) * 0.30;
    baselineDryness   = 0.0;
    impastoPermanence = 0.55;
  } else {
    paintLoadScale    = 1.00;
    strokeWetness     = 1.30 + hash11(seed * 5.83) * 0.50;
    baselineDryness   = -0.25;
    impastoPermanence = 0.95;
  }

  float paintLoad = exp(-sAlong * 1.5) + 0.22;
  paintLoad = min(paintLoad * paintLoadScale, 1.0);

  float impastoLoad = exp(-sAlong * 3.2) * 1.55;
  impastoLoad += exp(-sAlong * 9.0) * 0.45;

  float dryness = clamp(smoothstep(0.15, 0.95, sAlong) + baselineDryness, 0.0, 1.0);

  float startTaper = smoothstep(-1.10, -0.88, alongT);
  float endTaper   = smoothstep(1.25, 0.30, alongT);
  float lengthMask = startTaper * endTaper;

  float edgeStart = mix(0.95, 0.55, wetRoll);
  float edgeEnd   = mix(1.02, 1.20, wetRoll);
  float widthProfile = 1.0 - smoothstep(edgeStart, edgeEnd, abs(acrossT));
  float edgeSharpness = mix(2.4, 1.0, wetRoll);
  widthProfile = pow(max(widthProfile, 0.0), edgeSharpness);

  float bristleCount = clamp(halfWd * 900.0, 8.0, 28.0);
  float bristlePhase = acrossT * bristleCount + seed * 53.0;
  float bristleId    = floor(bristlePhase);
  float bInB         = fract(bristlePhase);
  float bStrength    = mix(0.25, 1.0, hash11(bristleId + seed * 7.13));
  float bProfile     = 1.0 - abs(bInB - 0.5) * 2.0;
  bProfile           = pow(max(bProfile, 0.0), 0.55);

  float dryNoise  = shaderNoise(float2(alongT * 5.5 + seed, bristleId * 0.37));
  float dryThresh = mix(0.05, 0.78, dryness);
  float dry       = smoothstep(dryThresh, dryThresh + 0.20, dryNoise);

  float bristleAmount = bStrength * bProfile * dry;

  float core = widthProfile * paintLoad * lengthMask * baseOp
  * (1.0 - smoothstep(0.45, 0.92, abs(acrossT))) * 0.40;
  float bristleCov = widthProfile * paintLoad * lengthMask * baseOp * bristleAmount;
  float coverage = max(core, bristleCov);

  if (coverage < 0.002) return r;

  r.coverage          = coverage;
  r.alongNorm         = sAlong;
  r.acrossT           = acrossT;
  r.bristleTone       = (bStrength - 0.65) * 1.4;
  r.strokeWetness     = strokeWetness;
  r.impastoPermanence = impastoPermanence;

  float ridge = 0.32 + 1.30 * pow(bProfile, 0.65);

  float bristleHeight = mix(0.45, 1.95, bStrength);
  r.heightDelta = widthProfile * impastoLoad * lengthMask * baseOp
  * ridge * strokeWetness * bristleHeight;

  float grainVeryCoarse = shaderNoise(p *   90.0 + center * 5.0)  - 0.5;
  float grainMed        = shaderNoise(p *  300.0 + center * 10.0) - 0.5;
  float grainCoarse     = shaderNoise(p *  650.0 + center * 20.0) - 0.5;
  float grainFine       = shaderNoise(p * 2200.0 + seed * 3.7)    - 0.5;
  float grain = grainVeryCoarse * 0.45
  + grainMed        * 0.32
  + grainCoarse     * 0.24
  + grainFine       * 0.16;

  float bristleNoise = shaderNoise(float2(local.y * 520.0 + seed * 7.0,
                                          local.x * 42.0  + seed * 13.0)) - 0.5;
  r.heightDelta *= 1.0 + bristleNoise * 0.65;
  r.heightDelta *= (1.0 + grain * 0.85);
  r.heightDelta = max(r.heightDelta, 0.0);

  return r;
}

inline StrokeResult evaluateWash(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;
  r.strokeWetness = 1.5;
  r.impastoPermanence = 0.05;

  float2 center = s.posAngle.xy;
  float angle   = s.posAngle.z;
  float halfLen = max(s.posAngle.w, 0.01);
  float halfWd  = max(s.sizeOpacity.x, 0.01);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);

  float modeRoll = hash11(seed * 5.13);
  float uniformFactor = (modeRoll < 0.35) ? 1.0 : 0.0;
  float noisyFactor = 1.0 - uniformFactor;

  float2 scaled = local / float2(halfLen, halfWd);
  float2 warp1 = float2(
    shaderSimplex2D(scaled * 1.0 + center * 3.0),
    shaderSimplex2D(scaled * 1.0 + center * 3.0 + float2(137.0, 173.0))
  );
  float2 warp2 = float2(
    shaderSimplex2D(scaled * 3.5 + center * 7.0 + 89.0),
    shaderSimplex2D(scaled * 3.5 + center * 7.0 + float2(211.0, 47.0))
  );
  scaled = scaled + warp1 * 0.85 + warp2 * 0.30;
  float rr = length(scaled);

  if (rr > 2.8) return r;

  float ang = atan2(scaled.y, scaled.x);

  float b1 = shaderSimplex2D(p * 6.5 + center * 5.0);
  float b2 = shaderSimplex2D(p * 14.0 + center * 11.0 + seed);
  float b3 = shaderNoise(p * 32.0 + seed * 7.0) - 0.5;

  float tendrilRaw = shaderSimplex2D(scaled * 4.5 + seed * 3.7);
  float tendril = smoothstep(0.10, 0.55, tendrilRaw) * 0.85 * noisyFactor;

  float nLobe = 3.0 + floor(hash11(seed * 1.41) * 4.0);
  float lobeAmp = mix(0.12, 1.0, noisyFactor);
  float washLobes = (sin(ang * nLobe + seed * 5.7) * 0.42
                  + cos(ang * (nLobe + 1.0) + seed * 9.3) * 0.28
                  + sin(ang * (nLobe * 2.0) + seed * 3.1) * 0.18) * lobeAmp;

  float asymmetry = sin(ang + seed * 2.7) * 0.35;

  float boundary = 1.0 + b1 * mix(0.25, 1.0, noisyFactor)
                       + b2 * 0.50 * noisyFactor
                       + b3 * 0.25 * noisyFactor
                       + tendril + washLobes + asymmetry;
  boundary = max(boundary, 0.25);

  float thickness = smoothstep(0.08, 0.55, baseOp);
  float normR = rr / boundary;
  float innerEdge = mix(0.25, 0.82, thickness);
  float outerEdge = mix(1.05, 1.02, thickness);
  float falloff = 1.0 - smoothstep(innerEdge, outerEdge, normR);
  falloff = pow(max(falloff, 0.0), 1.2);

  float densA = shaderNoise(p * 4.5 + center * 3.0);
  float densB = shaderNoise(p * 13.0 + seed * 2.3);
  float density = 1.0 + (densA * 0.45 + densB * 0.18 - 0.32) * noisyFactor;
  falloff *= density;

  float edgeZone = smoothstep(0.55, 0.82, normR) * (1.0 - smoothstep(0.88, 1.10, normR));
  float poolNoise = shaderNoise(p * 28.0 + seed) * 0.5 + 0.5;
  float washExists = smoothstep(0.02, 0.25, falloff);
  falloff += edgeZone * poolNoise * 0.60 * washExists * noisyFactor;

  float grain = shaderNoise(p * 380.0 + seed) - 0.5;
  falloff *= (1.0 + grain * 0.20 * noisyFactor);

  float grain2 = shaderNoise(p * 1200.0 + seed * 3.7) - 0.5;
  falloff *= (1.0 + grain2 * 0.10 * noisyFactor);

  falloff = clamp(falloff, 0.0, 1.35);

  float opacityRidge = smoothstep(0.45, 0.80, baseOp);

  float ridgeAmount = mix(0.005, 0.55, hash11(seed * 2.17)) * thickness;

  r.coverage    = falloff * baseOp;
  r.alongNorm   = 0.5;
  r.acrossT     = normR;

  float tideMarkZone = smoothstep(0.78, 0.96, normR)
                     * (1.0 - smoothstep(0.96, 1.12, normR));
  float tideMarkVar = shaderNoise(p * 18.0 + seed * 4.7) * 0.6 + 0.7;
  float tideMark = tideMarkZone * thickness * tideMarkVar * washExists;

  r.bristleTone = grain * 0.4 * noisyFactor - tideMark * (1.4 + opacityRidge * 1.8);

  r.heightDelta = edgeZone * poolNoise * ridgeAmount * washExists * noisyFactor;
  r.heightDelta += tideMark * thickness * (0.18 + opacityRidge * 0.65);
  return r;
}

inline StrokeResult evaluateSplatter(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;
  r.strokeWetness = 1.0; r.impastoPermanence = 0.0;

  float2 center = s.posAngle.xy;
  float radius  = max(s.posAngle.w, 0.002);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;
  float packedW = s.color.w;
  int shapeI    = int(floor(packedW));

  float2 d = p - center;

  if (shapeI == 1) {
    float sA = s.posAngle.z;
    float cs = cos(sA), sn = sin(sA);
    float2 localD = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);
    localD.x *= 0.22;
    d = localD;
  }

  float dist = length(d);

  if (dist > radius * 1.6) return r;

  float ang = atan2(d.y, d.x);

  float effR;
  if (shapeI == 2) {
    effR = radius;
  } else {
    float nLobe = 3.0 + floor(hash11(seed * 1.31) * 5.0);
    float lobe = sin(ang * nLobe + seed * 11.0) * 0.32
               + cos(ang * (nLobe + 2.0) + seed * 7.0) * 0.20;
    float en   = shaderSimplex2D(float2(ang * 2.0, seed * 3.0)) * 0.22;
    effR = radius * (1.0 + lobe + en);
  }

  float typeRoll = clamp(s.sizeOpacity.x, 0.0, 1.0);
  float mainHeight;
  float impastoPermanence;
  if (typeRoll < 0.15) {
    mainHeight        = 0.05 + hash11(seed * 1.77) * 0.20;
    impastoPermanence = 0.10;
  } else if (typeRoll < 0.40) {
    mainHeight        = 0.55 + hash11(seed * 3.13) * 0.40;
    impastoPermanence = 0.65;
  } else {
    mainHeight        = 1.80 + hash11(seed * 5.71) * 1.10;
    impastoPermanence = 0.95;
  }

  float normDist = clamp(dist / (effR * 1.05), 0.0, 1.0);
  float invDist = 1.0 - normDist;
  float heightFalloff;
  float colorFalloff;

  if (mainHeight > 0.85) {
    heightFalloff = invDist * invDist;
    colorFalloff  = 1.0 - smoothstep(0.997, 1.000, normDist);
  } else if (mainHeight > 0.35) {
    heightFalloff = invDist * invDist;
    colorFalloff  = 1.0 - smoothstep(0.997, 1.000, normDist);
  } else {
    heightFalloff = 1.0 - smoothstep(0.85, 1.00, normDist);
    colorFalloff  = 1.0 - smoothstep(0.997, 1.000, normDist);
  }

  float coverage = colorFalloff * baseOp;
  float h = heightFalloff * baseOp * mainHeight;

  r.coverage    = coverage;
  r.acrossT     = dist / max(effR, 0.001);
  r.heightDelta = h;

  float terrainVeryCoarse = shaderNoise(p * 35.0  + seed * 2.3 ) - 0.5;
  float terrainCoarse     = shaderNoise(p * 90.0  + seed * 5.71) - 0.5;
  float splatGrainMed     = shaderNoise(p * 250.0 + seed * 7.0 ) - 0.5;

  float heightVar = terrainVeryCoarse * 0.30
  + terrainCoarse     * 0.18
  + splatGrainMed     * 0.10;

  float varStrength = (mainHeight < 0.35)
      ? (0.06 + mainHeight * 0.20)
      : (0.30 + mainHeight * 0.45);
  r.heightDelta *= (1.0 + heightVar * varStrength);

  if (mainHeight > 0.85) {
    float crater = shaderSimplex2D(p * 50.0 + seed * 3.7);
    crater = crater * 0.5 + 0.5;
    crater = pow(crater, 1.6);
    r.heightDelta *= 0.90 + crater * 0.25;
  }

  r.heightDelta = max(r.heightDelta, 0.0);

  r.strokeWetness     = 0.0;
  r.impastoPermanence = impastoPermanence;

  return r;
}

inline StrokeResult evaluateDrip(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;
  r.strokeWetness = 0.0;
  r.impastoPermanence = 0.30;

  float2 top      = s.posAngle.xy;
  float angle     = s.posAngle.z;
  float dripLen   = max(s.posAngle.w, 0.02);
  float topWidth  = max(s.sizeOpacity.x, 0.003);
  float baseOp    = s.sizeOpacity.y;
  float seed      = s.sizeOpacity.z;

  float2 dirAlong  = float2(cos(angle), sin(angle));
  float2 dirAcross = float2(-dirAlong.y, dirAlong.x);
  float2 d = p - top;
  float along = dot(d, dirAlong);
  float across = dot(d, dirAcross);

  float maxOffset = dripLen * 0.13 + topWidth * 2.0;
  if (along < -dripLen * 0.04 || along > dripLen * 1.04) return r;
  if (abs(across) > maxOffset) return r;

  float t = along / dripLen;

  float wobble = shaderSimplex2D(float2(t * 1.0, seed * 0.7))      * dripLen * 0.07
              +  shaderSimplex2D(float2(t * 3.5, seed * 1.3 + 11)) * dripLen * 0.025;
  float dx = across - wobble;

  float widthMod = 0.95 + shaderSimplex2D(float2(t * 2.5, seed * 2.1)) * 0.20;
  widthMod = clamp(widthMod, 0.75, 1.15);
  float endTaperStart = 1.0 - smoothstep(0.92, 1.04, t);
  float startTaper    = smoothstep(-0.04, 0.04, t);
  float widthProfile  = widthMod * startTaper * endTaperStart;
  float halfW = topWidth * widthProfile;
  float acrossT = dx / max(halfW, 0.001);

  float widthMask = 1.0 - smoothstep(0.80, 1.05, abs(acrossT));
  widthMask = pow(max(widthMask, 0.0), 1.2);

  float coreCov = widthMask * startTaper * endTaperStart;

  float beadCov = 0.0, beadH = 0.0;
  for (int b = 0; b < 3; b++) {
    float bSeed = seed * (1.7 + float(b) * 2.3);
    float bt = 0.10 + hash11(bSeed) * 0.85;
    float bWobble = shaderSimplex2D(float2(bt * 1.0, seed * 0.7)) * dripLen * 0.08;
    float2 bc = top + dirAlong * (bt * dripLen) + dirAcross * bWobble;
    float br = topWidth * (0.40 + hash11(bSeed + 1.7) * 0.35);
    float bd = length(p - bc);
    float bNormDist = clamp(bd / (br * 1.05), 0.0, 1.0);
    float bm = pow(1.0 - bNormDist, 0.85);
    float bc_color = 1.0 - smoothstep(0.97, 1.000, bNormDist);
    if (bc_color > beadCov) { beadCov = bc_color; beadH = bm * 0.50; }
  }

  float coverage = max(coreCov, beadCov) * baseOp;
  if (coverage < 0.002) return r;

  float h = (coreCov * 0.32 + beadH) * baseOp;

  float grain = shaderNoise(p * 220.0 + seed * 3.0) - 0.5;
  h *= 1.0 + grain * 0.18;

  r.coverage    = coverage;
  r.heightDelta = max(h, 0.0);
  r.alongNorm   = clamp(t, 0.0, 1.0);
  r.acrossT     = acrossT;
  r.impastoPermanence = 0.75 + clamp(beadH * 0.6, 0.0, 0.20);
  return r;
}

inline StrokeResult evaluateKnife(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;
  r.strokeWetness = 1.0;
  r.impastoPermanence = 0.55;

  float2 center = s.posAngle.xy;
  float angle   = s.posAngle.z;
  float halfLen = max(s.posAngle.w, 0.01);
  float halfWd  = max(s.sizeOpacity.x, 0.002);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);
  float alongT  = local.x / halfLen;
  float acrossT = local.y / halfWd;
  if (abs(alongT) > 1.05 || abs(acrossT) > 1.5) return r;

  float lengthMask = 1.0 - smoothstep(0.92, 1.04, abs(alongT));
  float widthMask  = 1.0 - smoothstep(0.78, 1.02, abs(acrossT));
  float coverage = lengthMask * widthMask * baseOp;

  float striation = shaderNoise(float2(local.x * 80.0 + seed * 3.0,
                                       local.y * 400.0 + seed * 7.0)) - 0.5;
  coverage *= 1.0 + striation * 0.18;

  float sideRidge = smoothstep(0.85, 1.0, abs(acrossT))
                  * (1.0 - smoothstep(1.0, 1.18, abs(acrossT)))
                  * lengthMask;

  if (coverage < 0.002 && sideRidge < 0.05) return r;

  r.coverage = coverage;
  r.heightDelta = -coverage * 0.50 + sideRidge * 0.22;
  r.alongNorm = (alongT + 1.0) * 0.5;
  r.acrossT = acrossT;
  return r;
}

inline half3 strokeTint(constant AbExStroke &s, StrokeResult sr) {
  half3 base = half3(s.color.xyz);
  half tonal     = 1.0h + half(sr.bristleTone) * 0.18h;
  half hueShift  = half(sr.bristleTone) * 0.16h;

  half3 tint = base * tonal;
  tint.r += hueShift * 0.10h;
  tint.g -= hueShift * 0.08h;
  tint.b += hueShift * 0.14h;

  half along = half(sr.alongNorm - 0.5) * 0.22h;
  tint += half3(along, -along * 0.5h, along * 0.65h);

  return clamp(tint, 0.0h, 1.0h);
}

kernel void abexPaint(
                      texture2d<half, access::read>  colorIn      [[texture(0)]],
                      texture2d<half, access::write> colorOut     [[texture(1)]],
                      texture2d<half, access::read>  heightWetIn  [[texture(2)]],
                      texture2d<half, access::write> heightWetOut [[texture(3)]],
                      constant AbExParams &params                 [[buffer(0)]],
                      constant AbExStroke *strokes                [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]])
{
  uint w = colorOut.get_width();
  uint h = colorOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 p = uv - 0.5;

  bool isFirstFrame = params.config.y > 0.5;
  int  strokeCount  = int(params.config.z);
  half dryRate      = half(params.canvas.w);

  const half HEIGHT_MAX = 3.0h;

  half4 color;
  half height, wetness, permHeight, washDom;

  if (isFirstFrame) {
    color = half4(0); height = 0.0h; wetness = 0.0h;
    permHeight = 0.0h; washDom = 0.0h;
  } else {
    color = colorIn.read(gid);
    half4 hw = heightWetIn.read(gid);
    height = hw.r; wetness = hw.g; permHeight = hw.b; washDom = hw.a;

    if (color.a > 0.001h || height > 0.001h) {
      half aPres = smoothstep(0.15h, 0.85h, color.a);
      half tPres = smoothstep(0.05h, 0.40h, height);
      half pres  = min(aPres, tPres);
      half df    = 1.0h - dryRate * (1.0h - pres);
      color.a *= df;
      height  *= df;
    }
    half wetDecay = saturate(1.0h - dryRate * 6.0h);
    wetness *= wetDecay;
  }

  for (int i = 0; i < strokeCount && i < 12; i++) {
    float type = strokes[i].sizeOpacity.w;

    bool isGestural = (type < 0.5);
    bool isWash     = (type >= 0.5 && type < 1.5);
    bool isSplatter = (type >= 1.5 && type < 2.5);
    bool isDrip     = (type >= 2.5 && type < 3.5);
    bool isKnife    = (type >= 3.5);

    StrokeResult sr;
    if      (isGestural) sr = evaluateGestural(p, strokes[i]);
    else if (isWash)     sr = evaluateWash(p, strokes[i]);
    else if (isSplatter) sr = evaluateSplatter(p, strokes[i]);
    else if (isDrip)     sr = evaluateDrip(p, strokes[i]);
    else /* knife */     sr = evaluateKnife(p, strokes[i]);

    if (isKnife) {
      half kCov = half(max(sr.coverage, 0.0));
      if (kCov < 0.005h && abs(sr.heightDelta) < 0.005) continue;

      float kAngle = strokes[i].posAngle.z;
      float2 kdir = float2(cos(kAngle), sin(kAngle));
      int2 stepPx = int2(round(kdir * 5.0));
      int2 upGid = clamp(int2(gid) - stepPx, int2(0), int2(int(w) - 1, int(h) - 1));
      half4 upColor = colorIn.read(uint2(upGid));

      half drag = kCov * 0.70h * upColor.a;
      color.rgb = mix(color.rgb, upColor.rgb, drag);

      half3 kTint = half3(strokes[i].color.xyz);
      color.rgb = mix(color.rgb, kTint, kCov * 0.45h);

      half stainAlpha   = kCov * 0.70h;
      half draggedAlpha = drag * upColor.a * 0.8h;
      color.a = max(color.a, max(stainAlpha, draggedAlpha));

      half hd = half(sr.heightDelta);
      height = clamp(height + hd, 0.0h, HEIGHT_MAX);
      half permDelta = hd * half(sr.impastoPermanence);
      permHeight = clamp(permHeight + permDelta, 0.0h, HEIGHT_MAX);

      wetness = max(wetness, kCov * 0.60h);
      washDom *= clamp(1.0h - smoothstep(0.30h, 0.85h, kCov), 0.0h, 1.0h);
      continue;
    }

    if (!isWash) {
      half effH = max(height, permHeight);
      float resistanceMult = isGestural ? 0.8 : 1.0;
      float resistanceCap;
      if (isSplatter || isDrip) resistanceCap = 0.0;
      else if (isGestural)      resistanceCap = 0.15;
      else                      resistanceCap = 0.30;
      float resistance     = clamp(float(effH) * resistanceMult, 0.0, resistanceCap);
      float adhesion       = 1.0 - resistance;

      sr.coverage    *= adhesion;
      sr.heightDelta *= adhesion;

      if (isSplatter) {
        float prot = smoothstep(0.10, 0.40, float(permHeight)) * 0.75;
        sr.coverage *= 1.0 - prot;
      }

      if (isGestural) {
        float perturb  = float(i) * 17.3 + strokes[i].sizeOpacity.z * 0.03;
        float microVar = shaderNoise(p * 400.0 + float2(perturb * 13.0,
                                                        perturb * 7.0));
        float microMod = 0.78 + microVar * 0.44;
        sr.coverage *= microMod;
      }
    }

    if (sr.coverage < 0.002) continue;

    if (isSplatter || isDrip) {
      float brushId = strokes[i].sizeOpacity.z;
      float2 spRel = p - strokes[i].posAngle.xy;
      float n = shaderNoise(spRel * 85.0 + float2(brushId * 7.0, brushId * 13.0));
      sr.heightDelta *= 0.85 + n * 0.25;
    }

    float durability = (isGestural || isSplatter) ? fract(strokes[i].color.w) : 0.0;
    if (durability > 0.01 && sr.coverage > 0.15) {
      sr.coverage    = max(sr.coverage,    durability * 0.92);
      sr.heightDelta = max(sr.heightDelta, durability * 0.55);
    }

    half3 tint = strokeTint(strokes[i], sr);
    half  cov  = half(sr.coverage);
    half  hd   = half(max(sr.heightDelta, 0.0));

    half rawWet = clamp(wetness * half(sr.strokeWetness), 0.0h, 1.0h);
    half effectiveWet = pow(rawWet, 1.6h);

    half oldAmount = color.a * (1.0h - cov);
    half total     = oldAmount + cov;
    half tNew      = cov / max(total, 0.001h);
    half3 dryBlend = (color.rgb * oldAmount + tint * cov) / max(total, 0.001h);
    half3 wetBlend = wetMix(color.rgb, tint, tNew);
    color.rgb = mix(dryBlend, wetBlend, effectiveWet);
    color.a   = total;
    height    = min(height + hd, HEIGHT_MAX);

    half permDelta = hd * half(sr.impastoPermanence);
    permHeight = min(HEIGHT_MAX, permHeight + permDelta);

    wetness = max(wetness, cov * clamp(half(sr.strokeWetness), 0.0h, 1.0h));

    if (isWash) {
      half washContrib = smoothstep(0.005h, 0.05h, cov);
      washDom = max(washDom, washContrib);
    } else {
      half displace = smoothstep(0.30h, 0.85h, cov);
      washDom *= clamp(1.0h - displace, 0.0h, 1.0h);
    }
  }

  if (height     < 0.004h) height     = 0.0h;
  if (wetness    < 0.005h) wetness    = 0.0h;
  if (permHeight < 0.003h) permHeight = 0.0h;
  if (washDom    < 0.005h) washDom    = 0.0h;
  color.a = clamp(color.a, 0.0h, 1.0h);

  colorOut.write(color, gid);
  heightWetOut.write(half4(height, wetness, permHeight, washDom), gid);
}

kernel void abexCompose(
                        texture2d<half, access::read>  color     [[texture(0)]],
                        texture2d<half, access::read>  heightWet [[texture(1)]],
                        texture2d<half, access::write> output    [[texture(2)]],
                        constant AbExParams &params              [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
  uint dispW = output.get_width();
  uint dispH = output.get_height();
  if (gid.x >= dispW || gid.y >= dispH) return;

  uint canvW = color.get_width();
  uint canvH = color.get_height();
  float2 canvSize = float2(canvW, canvH);
  float2 dispSize = float2(dispW, dispH);

  float2 displayPx = float2(gid) + 0.5;
  float2 canvasPx  = displayPx + (canvSize - dispSize) * 0.5;
  float2 uv = canvasPx / canvSize;
  float2 centered = uv - 0.5;

  float panX = params.camera.x;
  float panY = params.camera.y;
  float zoom = params.camera.z;
  centered /= zoom;

  float2 uvAll = clamp(centered + float2(panX, panY) + 0.5, 0.0, 1.0);
  uint2 pxAll  = min(uint2(uvAll * canvSize), uint2(canvW - 1, canvH - 1));

  half4 c = color.read(pxAll);
  half4 hwC = heightWet.read(pxAll);
  float hC = max(float(hwC.r), float(hwC.b));
  half wetTotal = clamp(hwC.g, 0.0h, 1.0h);
  half washAmt  = clamp(hwC.a, 0.0h, 1.0h);

  half surfaceTexture     = max(0.02h, 1.0h - washAmt * 0.98h);
  half bumpSurfaceTexture = max(0.10h, 1.0h - washAmt * 0.90h);
  float bumpSurfaceF = float(bumpSurfaceTexture);

  half3 canvasBase = half3(params.canvas.xyz) - canvasWeave(canvasPx);

  if (c.a < 0.005h && hC < 0.005) {
    output.write(half4(canvasBase, 1.0h), gid);
    return;
  }

  half3 normalLayer = mix(canvasBase, c.rgb, c.a);
  half3 stainLayer  = canvasBase * mix(half3(1.0h), c.rgb, c.a * 0.7h);
  half3 result = mix(stainLayer, normalLayer, smoothstep(0.05h, 0.15h, c.a));

  half3 N;
  half  paintMask;
  float2 totalGrad;
  half  gmag;

  paintMask = smoothstep(0.05h, 0.30h, c.a);

  int2 hxL = clamp(int2(pxAll) + int2(-1,  0), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxR = clamp(int2(pxAll) + int2( 1,  0), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxD = clamp(int2(pxAll) + int2( 0, -1), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxU = clamp(int2(pxAll) + int2( 0,  1), int2(0), int2(canvW - 1, canvH - 1));

  half4 hwL = heightWet.read(uint2(hxL));
  half4 hwR = heightWet.read(uint2(hxR));
  half4 hwD = heightWet.read(uint2(hxD));
  half4 hwU = heightWet.read(uint2(hxU));

  float pL = float(hwL.b);
  float pR = float(hwR.b);
  float pD = float(hwD.b);
  float pU = float(hwU.b);
  float pC = float(hwC.b);

  totalGrad = float2(pR - pL, pU - pD);
  gmag      = length(half2(half(pR - pL), half(pU - pD)));

  float gradFactor   = float(smoothstep(0.005h, 0.05h, gmag));
  float heightFactor = float(smoothstep(0.005h, 0.30h, half(pC)));
  float adaptiveBumpScale = mix(0.40, 1.0, gradFactor)
                          * mix(0.20, 1.0, heightFactor);
  float bump = params.config.w * bumpSurfaceF * adaptiveBumpScale;

  half maxGrad = 0.30h;
  half gradX = clamp(half(pR - pL), -maxGrad, maxGrad);
  half gradY = clamp(half(pU - pD), -maxGrad, maxGrad);
  N = normalize(half3(-gradX * half(bump), -gradY * half(bump), 1.0h));

  float2 ng = canvasPx;
  float gradMag = length(totalGrad);
  float2 gdir  = (gradMag > 0.001) ? (totalGrad / gradMag) : float2(1.0, 0.0);
  float2 gperp = float2(-gdir.y, gdir.x);

  half dirStrength = half(smoothstep(0.02, 0.10, gradMag));

  if (paintMask > 0.04h) {
    float sAlong  = float(mix(1.0h, 1.20h, dirStrength));
    float sAcross = float(mix(1.0h, 0.85h, dirStrength));

    float u = dot(ng, gdir)  * sAlong;
    float v = dot(ng, gperp) * sAcross;
    float2 dng = gdir * u + gperp * v;

    half nx1 = half(shaderSimplex2D(dng * 0.025         )) * 0.30h;
    half ny1 = half(shaderSimplex2D(dng * 0.025 + 173.0 )) * 0.30h;
    half nx2 = half(shaderSimplex2D(dng * 0.12  + 41.0  )) * 0.15h;
    half ny2 = half(shaderSimplex2D(dng * 0.12  + 217.0 )) * 0.15h;

    half thickScale = pow(smoothstep(0.20h, 1.20h, half(hC)), 1.4h);
    half bodyAmp = paintMask * (0.10h + 0.50h * thickScale) * surfaceTexture;

    half px = nx1 + nx2;
    half py = ny1 + ny2;
    N = normalize(N + half3(px, py, 0.0h) * bodyAmp);
  }

  float2 cvGrad = canvasWeaveGradient(ng);
  half cvStrength = 0.35h * (1.0h - paintMask * 0.70h);
  N = normalize(N + half3(half(-cvGrad.x), half(-cvGrad.y), 0.0h) * cvStrength);

  const half3 Ldir = normalize(half3(-0.45h, 0.60h, 0.65h));
  const half3 V    = half3(0.0h, 0.0h, 1.0h);
  const half3 H    = normalize(Ldir + V);

  half ndl = max(0.0h, dot(N, Ldir));
  half hl  = 0.72h + 0.28h * ndl;

  const half3 warmLight  = half3(1.00h, 0.95h, 0.82h);
  const half3 coolShadow = half3(0.82h, 0.86h, 0.96h);
  half3 lightTint  = mix(coolShadow, warmLight, hl);

  half3 rgb = result * lightTint * hl;

  if (paintMask > 0.005h) {
    half ndh = max(0.0h, dot(N, H));

    half expBroad  = 6.0h;
    half expTight  = 16.0h;
    half intensity = 1.0h;

    if (dirStrength > 0.05h) {
      float2 Hxy = float2(float(H.x), float(H.y));
      float HxyLen = length(Hxy);
      float2 HxyDir = (HxyLen > 0.001) ? Hxy / HxyLen : float2(1.0, 0.0);

      float perpAmt  = abs(dot(HxyDir, gdir));
      float alongAmt = abs(dot(HxyDir, gperp));

      expTight  = mix(12.0h, 36.0h, half(perpAmt)  * dirStrength);
      expBroad  = mix(4.0h,   8.0h, half(alongAmt) * dirStrength);
      intensity = mix(1.0h,  1.35h, dirStrength);
    }

    expTight *= (1.0h + wetTotal * 0.6h);
    half wetGain = 1.0h + wetTotal * 0.9h;

    half specBroad = pow(ndh, expBroad) * 0.22h;
    half specTight = pow(ndh, expTight) * 0.18h;
    half spec = (specBroad + specTight) * paintMask * intensity * wetGain * surfaceTexture;

    half3 specColor = mix(warmLight, result, 0.40h);
    rgb += spec * specColor * 0.55h;
  }

  rgb = saturate(rgb);
  output.write(half4(rgb, 1.0h), gid);
}
