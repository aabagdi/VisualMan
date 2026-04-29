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
  float4 atmosphere;
};

struct AbExStroke {
  float4 posAngle;
  float4 sizeOpacity;
  float4 color;
  float4 animation;
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

inline half3 acesNarkowicz(half3 x) {
  const half a = 2.51h, b = 0.03h, c = 2.43h, d = 0.59h, e = 0.14h;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

inline void evaluateAtmosphere(float2 p, float time, half intensity,
                               float songSeed, float hue,
                               thread half3 &outColor, thread half &outDensity) {

  if (intensity < 0.05h) {
    outColor   = half3(0.0h);
    outDensity = 0.0h;
    return;
  }

  float flowAngle = songSeed * 6.28 + time * 0.04;
  float2 flowDir  = float2(cos(flowAngle), sin(flowAngle));
  float2 flowPerp = float2(-flowDir.y, flowDir.x);

  float2 animatedPos = p + flowDir * time * 0.025;

  float cloudShape = shaderSimplex2D(animatedPos * 1.5 + songSeed * 1.3);

  float alongFlow  = dot(p, flowDir);
  float acrossFlow = dot(p, flowPerp);
  float bands = shaderSimplex2D(float2(alongFlow * 3.0, acrossFlow * 12.0)
                                + time * 0.08 + songSeed * 5.7);

  float density = (cloudShape * 0.40 + bands * 0.60) * 0.5 + 0.5;
  density = max(density, 0.0);
  density *= float(intensity);

  float spatialHueShift = cloudShape * 0.05;
  float finalHue = fract(hue + spatialHueShift);

  float saturation = 0.25 + float(intensity) * 0.15;

  float value = 0.20 + cloudShape * 0.85;

  half3 atmSrgb = hsv2rgb(finalHue, saturation, value);

  half3 atmLinear = atmSrgb * atmSrgb;

  outColor   = atmLinear;
  outDensity = half(density);
}

inline half3 linearToSrgb(half3 x) {
  half3 lo = x * 12.92h;
  half3 hi = 1.055h * pow(max(x, 0.0h), 1.0h / 2.4h) - 0.055h;
  return select(hi, lo, x < 0.0031308h);
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

  float w_curve = s.animation.w;
  bool isS = abs(w_curve) >= 1.0;
  float amp_curve = isS ? sign(w_curve) * (abs(w_curve) - 1.0) : w_curve;
  float yCurve = isS
               ? amp_curve * sin(alongT * M_PI_F) * halfLen * 0.5
               : amp_curve * cos(alongT * M_PI_F * 0.5) * halfLen * 0.5;
  float acrossT = (local.y - yCurve) / halfWd;

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
  r.impastoPermanence = 0.0;

  float2 center = s.posAngle.xy;
  float angle   = s.posAngle.z;
  float halfLen = max(s.posAngle.w, 0.01);
  float halfWd  = max(s.sizeOpacity.x, 0.01);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);

  float2 scaled = local / float2(halfLen, halfWd);
  float rr = length(scaled);

  if (rr > 1.8) return r;

  float ang = atan2(scaled.y, scaled.x);

  float nLobe = 2.0 + floor(hash11(seed * 1.41) * 3.0);
  float lobePhase = seed * 5.7;
  float lobes = sin(ang * nLobe + lobePhase) * 0.18
              + cos(ang * (nLobe + 1.0) + lobePhase * 1.3) * 0.10;

  float boundaryNoise = shaderSimplex2D(scaled * 0.9 + seed * 3.1) * 0.18;

  float asymmetry = sin(ang + seed * 2.7) * 0.12;

  float boundary = 1.0 + lobes + boundaryNoise + asymmetry;
  boundary = max(boundary, 0.55);

  float thickness = smoothstep(0.08, 0.55, baseOp);
  float normR = rr / boundary;

  float innerEdge = mix(0.55, 0.85, thickness);
  float outerEdge = 1.0;
  float falloff = 1.0 - smoothstep(innerEdge, outerEdge, normR);

  falloff = pow(max(falloff, 0.0), 0.6);

  falloff = clamp(falloff, 0.0, 1.0);

  float intensityRoll = hash11(seed * 4.13);
  float intensity;
  if (intensityRoll < 0.20) {
    intensity = 1.05 + hash11(seed * 7.71) * 0.20;
  } else if (intensityRoll < 0.35) {
    intensity = 0.55 + hash11(seed * 9.31) * 0.20;
  } else {
    intensity = 0.85 + hash11(seed * 5.83) * 0.15;
  }

  r.coverage    = min(1.0, falloff * baseOp * intensity);
  r.alongNorm   = 0.5;
  r.acrossT     = normR;

  r.bristleTone = 0.0;
  r.heightDelta = 0.0;

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
  if (typeRoll < 0.30) {

    mainHeight        = 0.05 + hash11(seed * 1.77) * 0.20;
    impastoPermanence = 0.50;
  } else if (typeRoll < 0.70) {
    mainHeight        = 0.45 + hash11(seed * 3.13) * 0.40;
    impastoPermanence = 0.65;
  } else {
    mainHeight        = 0.95 + hash11(seed * 5.71) * 0.55;
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

  if (mainHeight < 0.35) {
    r.strokeWetness = 0.20;
  } else if (mainHeight < 0.85) {
    r.strokeWetness = 0.65;
  } else {
    r.strokeWetness = 1.00;
  }
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

  float launchT  = 1.0 - smoothstep(0.0,  0.18, t);
  float landingT = smoothstep(0.82, 1.0,  t);
  float midT     = (1.0 - launchT) * (1.0 - landingT);

  float landingPersonality = hash11(seed * 11.3) * 2.0 - 1.0;
  float landingWidthScale = mix(0.35, 1.55, hash11(seed * 11.3));

  float launchSprayNoise = shaderNoise(float2(t * 35.0, seed * 1.7)) - 0.5;
  float launchWidth = 1.10 + launchSprayNoise * 0.45;

  float midWidth = 0.95 + shaderSimplex2D(float2(t * 2.5, seed * 2.1)) * 0.18;

  float landingWidth = landingWidthScale;

  float widthMod = launchWidth * launchT
                 + midWidth * midT
                 + landingWidth * landingT;
  widthMod = clamp(widthMod, 0.30, 1.85);

  float wobbleBase = shaderSimplex2D(float2(t * 1.0, seed * 0.7))      * dripLen * 0.07
                   + shaderSimplex2D(float2(t * 3.5, seed * 1.3 + 11)) * dripLen * 0.025;
  float launchSprayLateral = (shaderNoise(float2(t * 50.0, seed * 3.7)) - 0.5)
                              * dripLen * 0.04 * launchT;
  float wobble = wobbleBase + launchSprayLateral;
  float dx = across - wobble;

  float endTaperStart = 1.0 - smoothstep(0.92, 1.04, t);
  float startTaper    = smoothstep(-0.04, 0.04, t);
  float widthProfile  = widthMod * startTaper * endTaperStart;
  float halfW = topWidth * widthProfile;
  float acrossT = dx / max(halfW, 0.001);

  float edgeSharpness = mix(1.5, 1.0, launchT);
  float widthMask = 1.0 - smoothstep(0.80, 1.05, abs(acrossT));
  widthMask = pow(max(widthMask, 0.0), edgeSharpness);

  float landingFade = (landingPersonality < 0.0)
                    ? (1.0 - landingT * 0.20)
                    : 1.0;

  float coreCov = widthMask * startTaper * endTaperStart * landingFade;

  float beadCov = 0.0, beadH = 0.0;
  for (int b = 0; b < 3; b++) {
    float bSeed = seed * (1.7 + float(b) * 2.3);

    float bt = 0.55 + hash11(bSeed) * 0.40;
    float bWobble = shaderSimplex2D(float2(bt * 1.0, seed * 0.7)) * dripLen * 0.08;
    float2 bc = top + dirAlong * (bt * dripLen) + dirAcross * bWobble;

    float poolBoost = (landingPersonality > 0.0) ? (1.0 + landingPersonality * 0.6) : 1.0;
    float br = topWidth * (0.40 + hash11(bSeed + 1.7) * 0.45) * poolBoost;
    float bd = length(p - bc);
    float bNormDist = clamp(bd / (br * 1.05), 0.0, 1.0);
    float bm = pow(1.0 - bNormDist, 0.85);
    float bc_color = 1.0 - smoothstep(0.97, 1.000, bNormDist);
    if (bc_color > beadCov) { beadCov = bc_color; beadH = bm * 0.50 * poolBoost; }
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

  float w_curve = s.animation.w;
  bool isS = abs(w_curve) >= 1.0;
  float amp = isS ? sign(w_curve) * (abs(w_curve) - 1.0) : w_curve;
  float yCurve = isS
               ? amp * sin(alongT * M_PI_F) * halfLen * 0.5
               : amp * cos(alongT * M_PI_F * 0.5) * halfLen * 0.5;
  float acrossT = (local.y - yCurve) / halfWd;

  if (abs(alongT) > 1.05 || abs(acrossT) > 1.5) return r;

  float lengthMask = 1.0 - smoothstep(0.92, 1.04, abs(alongT));
  float widthMask  = 1.0 - smoothstep(0.78, 1.02, abs(acrossT));

  float pressureNoise = shaderNoise(float2(local.x * 6.0  + seed * 11.0,
                                            seed * 19.0));
  float pressureMod   = 0.65 + pressureNoise * 0.50;

  float coverage = lengthMask * widthMask * baseOp * pressureMod;

  float striation = shaderNoise(float2(local.x *  80.0 + seed * 3.0,
                                       local.y * 400.0 + seed * 7.0)) - 0.5;
  float fineGrain = shaderNoise(float2(local.x * 240.0 + seed * 13.0,
                                       local.y * 700.0 + seed * 17.0)) - 0.5;
  coverage *= 1.0 + striation * 0.36 + fineGrain * 0.16;

  float sideRidge = smoothstep(0.85, 1.0, abs(acrossT))
                  * (1.0 - smoothstep(1.0, 1.18, abs(acrossT)))
                  * lengthMask;

  float leadEdge   = smoothstep(0.55, 0.92, alongT) * widthMask;
  float leadAmount = 0.55 + pressureNoise * 0.40;
  leadAmount      *= 1.0 + fineGrain * 0.45;
  float leadImpasto = leadEdge * leadAmount;

  if (coverage < 0.002 && sideRidge < 0.05 && leadImpasto < 0.05) return r;

  float bodyHeight = (-coverage * 0.50 + sideRidge * 0.22)
                   * (1.0 - leadEdge);
  float endHeight  = leadImpasto * 1.40;

  r.coverage = coverage;
  r.heightDelta = bodyHeight + endHeight;
  r.alongNorm = (alongT + 1.0) * 0.5;
  r.acrossT = acrossT;
  return r;
}

inline StrokeResult evaluateScumble(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;

  r.strokeWetness = 0.40;

  r.impastoPermanence = 0.30;

  float2 center = s.posAngle.xy;
  float angle   = s.posAngle.z;
  float halfLen = max(s.posAngle.w, 0.01);
  float halfWd  = max(s.sizeOpacity.x, 0.01);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);

  float2 scaled = local / float2(halfLen, halfWd);
  float rr = length(scaled);
  if (rr > 1.05) return r;

  float regionFalloff = 1.0 - smoothstep(0.30, 1.10, rr);
  regionFalloff = pow(max(regionFalloff, 0.0), 0.75);

  float warpX = shaderSimplex2D(local * 3.5 + seed * 1.3) * halfLen * 0.06;
  float warpY = shaderSimplex2D(local * 3.5 + seed * 4.7) * halfWd  * 0.18;
  float2 warped = local + float2(warpX, warpY);

  float ridge1 = 1.0 - abs(shaderSimplex2D(float2(warped.x * 4.0, warped.y * 50.0)
                                           + seed * 2.7));
  float ridge2 = 1.0 - abs(shaderSimplex2D(float2(warped.x * 7.5, warped.y * 30.0)
                                           + seed * 5.3));
  float bristleRidges = max(ridge1, ridge2);

  bristleRidges = pow(max(bristleRidges, 0.0), 0.3);

  float tonalField = shaderSimplex2D(warped * 1.8 + seed * 7.9) * 0.5 + 0.5;

  float density = bristleRidges * 0.90 + tonalField * 0.10;
  float coverageMod = clamp(density, 0.0, 1.0);

  float pressureT = (local.x / halfLen + 1.0) * 0.5;
  pressureT = clamp(pressureT, 0.0, 1.0);
  float profileSeed = hash11(seed * 13.7);
  float pressureMod;
  if (profileSeed < 0.33) {
    pressureMod = mix(1.0, 0.40, pressureT);
  } else if (profileSeed < 0.66) {
    pressureMod = mix(0.40, 1.0, pressureT);
  } else {
    pressureMod = 1.0 - abs(pressureT - 0.5) * 1.10;
    pressureMod = max(pressureMod, 0.30);
  }

  float coverage = regionFalloff * coverageMod * pressureMod * baseOp * 0.85;
  if (coverage < 0.002) return r;

  r.coverage    = coverage;
  r.heightDelta = coverage * 0.04;
  r.alongNorm   = 0.5;
  r.acrossT     = scaled.y;

  r.bristleTone = density * 0.20;
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

#define ABEX_TILE_GRID_DIM 16
#define ABEX_MAX_STROKES_PER_TILE 12

kernel void abexPaint(
                      texture2d<half, access::sample> colorIn      [[texture(0)]],
                      texture2d<half, access::write>  colorOut     [[texture(1)]],
                      texture2d<half, access::sample> heightWetIn  [[texture(2)]],
                      texture2d<half, access::write>  heightWetOut [[texture(3)]],
                      texture2d<half, access::sample> velocityIn   [[texture(4)]],
                      constant AbExParams &params                 [[buffer(0)]],
                      constant AbExStroke *strokes                [[buffer(1)]],
                      constant uint *tileCounts                   [[buffer(2)]],
                      constant uint *tileIndices                  [[buffer(3)]],
                      uint2 gid [[thread_position_in_grid]])
{
  constexpr sampler advSampler(coord::normalized,
                                address::clamp_to_edge,
                                filter::linear);

  uint w = colorOut.get_width();
  uint h = colorOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 hgid = gid >> 1;
  bool hwOwner = (gid.x & 1u) == 0 && (gid.y & 1u) == 0;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 p = uv - 0.5;

  bool isFirstFrame = params.config.y > 0.5;
  half dryRate      = half(params.canvas.w);

  half deltaT       = clamp(half(params.config.x), 0.0h, 0.05h);

  const half HEIGHT_MAX = 5.0h;

  half4 color;

  half height, wetness, permHeight, crackVis;

  half advFraction = 0.0h;

  if (isFirstFrame) {
    color = half4(0); height = 0.0h; wetness = 0.0h;
    permHeight = 0.0h; crackVis = 0.0h;
  } else {
    bool skipDecay = params.atmosphere.w > 0.5;

    color = colorIn.read(gid);
    half4 hw = heightWetIn.read(hgid);
    height = hw.r; wetness = hw.g; permHeight = hw.b; crackVis = hw.a;

    if (!skipDecay && (color.a > 0.001h || height > 0.001h)) {

      half thickness = smoothstep(0.05h, 0.60h, height);

      half stainCommit = smoothstep(0.05h, 0.60h, color.a);

      half aPres = smoothstep(0.05h, 0.75h, color.a);
      half tPres = smoothstep(0.05h, 0.40h, height);
      half pres  = max(aPres, tPres);

      half washFloor = smoothstep(0.0h, 0.04h, color.a) * 0.55h;

      half alphaProtect = 1.0h - max(max(thickness, stainCommit), washFloor)
                                * 0.92h;
      half df = 1.0h - dryRate * (1.0h - pres) * alphaProtect;
      color.a *= df;

      half settlingHeight = max(0.0h, height - permHeight);
      half thicknessSlowdown = mix(10.0h, 1.0h, thickness);
      half settleRate = clamp(dryRate * thicknessSlowdown, 0.0h, 1.0h);

      half settleLoss = settlingHeight * settleRate;
      half crossover = settleLoss * thickness * 0.65h;
      settlingHeight -= settleLoss;
      permHeight += crossover;

      half permDecay = dryRate * mix(0.20h, 0.025h, thickness);
      permHeight *= (1.0h - permDecay);
      permHeight = min(permHeight, HEIGHT_MAX);

      height = permHeight + settlingHeight;
    }

    if (!skipDecay) {
      half effThickness = max(height, permHeight);
      half thinMix     = smoothstep(0.05h, 0.50h, effThickness);
      half thickMix    = smoothstep(0.80h, 1.50h, effThickness);
      half dryScale    = mix(14.0h, 1.5h, thinMix)
                       - thickMix * 1.0h;
      dryScale = max(dryScale, 0.3h);
      half wetDecay = saturate(1.0h - dryRate * dryScale);
      wetness *= wetDecay;

      half permThickCrack = smoothstep(0.20h, 0.55h, permHeight);
      if (permThickCrack > 0.001h) {
        half drynessCrack = 1.0h - smoothstep(0.05h, 0.40h, wetness);
        half wetOnDryCrack = wetness * permThickCrack;
        half crackBoost = 1.0h + wetOnDryCrack * 2.0h;
        half crackGrowth = permThickCrack * drynessCrack * crackBoost
                         * deltaT * 0.04h;
        crackVis = min(1.0h, crackVis + crackGrowth);
      }
    }

    if (skipDecay) {
      half2 velocity = velocityIn.read(hgid).rg;
      half velMag = length(velocity);
      advFraction = smoothstep(0.001h, 0.006h, velMag);

      if (simd_any(advFraction > 0.005h)) {
        if (advFraction > 0.005h) {
          float2 srcUv = saturate(uv - float2(velocity));
          half4 advColor = colorIn.sample(advSampler, srcUv);
          half4 advHW    = heightWetIn.sample(advSampler, srcUv);

          color.rgb = mix(color.rgb, advColor.rgb, advFraction);
          color.a   = mix(color.a,   advColor.a,   advFraction);

          height     = mix(height,     advHW.r, advFraction);
          permHeight = mix(permHeight, advHW.b, advFraction);
          crackVis   = mix(crackVis,   advHW.a, advFraction);

          wetness = max(wetness, advHW.g);
        }
      }
    }
  }

  uint tileX = (gid.x * ABEX_TILE_GRID_DIM) / w;
  uint tileY = (gid.y * ABEX_TILE_GRID_DIM) / h;
  if (tileX >= ABEX_TILE_GRID_DIM) tileX = ABEX_TILE_GRID_DIM - 1;
  if (tileY >= ABEX_TILE_GRID_DIM) tileY = ABEX_TILE_GRID_DIM - 1;
  uint tileIdx = tileY * ABEX_TILE_GRID_DIM + tileX;
  uint tileStrokeCount = tileCounts[tileIdx];
  constant uint *tileStrokeList = tileIndices
                                + tileIdx * ABEX_MAX_STROKES_PER_TILE;

  for (uint k = 0; k < tileStrokeCount && k < ABEX_MAX_STROKES_PER_TILE; k++) {
    int i = int(tileStrokeList[k]);
    float type = strokes[i].sizeOpacity.w;

    bool isGestural = (type < 0.5);
    bool isWash     = (type >= 0.5 && type < 1.5);
    bool isSplatter = (type >= 1.5 && type < 2.5);
    bool isDrip     = (type >= 2.5 && type < 3.5);
    bool isKnife    = (type >= 3.5 && type < 4.5);
    bool isScumble  = (type >= 4.5);

    StrokeResult sr;
    if      (isGestural) sr = evaluateGestural(p, strokes[i]);
    else if (isWash)     sr = evaluateWash(p, strokes[i]);
    else if (isSplatter) sr = evaluateSplatter(p, strokes[i]);
    else if (isDrip)     sr = evaluateDrip(p, strokes[i]);
    else if (isKnife)    sr = evaluateKnife(p, strokes[i]);
    else                 sr = evaluateScumble(p, strokes[i]);

    half drawnMask = 1.0h;
    half newness = 1.0h;
    bool isAnimating = strokes[i].animation.z > 0.5;
    if (isAnimating) {
      float progressMin = strokes[i].animation.x;
      float progressMax = strokes[i].animation.y;
      float softEdge = 0.025;
      drawnMask = half(1.0 - smoothstep(progressMax - softEdge,
                                         progressMax + softEdge,
                                         sr.alongNorm));
      newness = half(smoothstep(progressMin - softEdge,
                                 progressMin + softEdge, sr.alongNorm));
      sr.coverage *= float(drawnMask);
      sr.heightDelta *= float(drawnMask);
    }

    if (isKnife) {
      float kAngle = strokes[i].posAngle.z;
      float2 kdir = float2(cos(kAngle), sin(kAngle));
      float2 kperp = float2(-kdir.y, kdir.x);

      half kCov = half(max(sr.coverage, 0.0));
      if (kCov < 0.001h) continue;

      float kPerpCoord = dot(p, kperp);
      float kBristleSeed = kPerpCoord * 540.0;
      float kBristleNoise = fract(sin(kBristleSeed * 12.9898)
                                   * 43758.5453) - 0.5;
      half bristleVar = half(kBristleNoise) * 0.30h;

      half3 kTint = half3(strokes[i].color.xyz);
      half stainStrength = kCov * 0.90h * (1.0h + bristleVar * 0.7h);
      stainStrength *= (1.0h - advFraction * 0.75h);
      color.rgb = mix(color.rgb, kTint,
                       clamp(stainStrength, 0.0h, 1.0h));
      color.a = max(color.a, kCov * 0.98h);

      half presenceGate = max(max(smoothstep(0.02h, 0.30h, color.a),
                                   smoothstep(0.05h, 0.40h, wetness)),
                               smoothstep(0.02h, 0.20h, permHeight));
      half impastoGateF = smoothstep(0.05h, 0.30h, permHeight);
      half flattenStrength = kCov * 0.98h * presenceGate * impastoGateF
                           * newness;

      half settlingHeight = max(0.0h, height - permHeight);
      half newSettling = settlingHeight * (1.0h - flattenStrength);
      half newPerm = permHeight * (1.0h - flattenStrength);

      half hd = half(sr.heightDelta);
      half kPermDelta = max(hd, 0.0h) * half(sr.impastoPermanence);
      half kStainFloor = kCov * 0.05h * (1.0h + bristleVar * 1.6h);
      permHeight = clamp(max(newPerm + kPermDelta, kStainFloor),
                          0.0h, HEIGHT_MAX);
      height = clamp(permHeight + newSettling
                      + min(hd, 0.0h) * newness,
                      0.0h, HEIGHT_MAX);

      wetness = max(wetness, kCov * 0.65h);

      if (crackVis > 0.001h) {
        half kFill = kCov * 0.35h * newness;
        crackVis = max(0.0h, crackVis - kFill);
      }
      continue;
    }

    if (isWash) {
      float impastoResist = smoothstep(0.20, 0.80, float(permHeight));
      sr.coverage *= 1.0 - impastoResist * 0.85;
    }

    if (!isWash) {
      half effH = max(height, permHeight);
      float resistanceMult = isGestural ? 0.8 : 1.0;
      float resistanceCap;
      if (isSplatter || isDrip) resistanceCap = 0.0;
      else if (isScumble)       resistanceCap = 0.0;
      else if (isGestural)      resistanceCap = 0.04;
      else                      resistanceCap = 0.08;
      float resistance     = clamp(float(effH) * resistanceMult, 0.0, resistanceCap);
      float adhesion       = 1.0 - resistance;

      sr.coverage *= adhesion;

      if (isGestural) {
        float perturb  = float(i) * 17.3 + strokes[i].sizeOpacity.z * 0.03;
        float microVar = shaderNoise(p * 400.0 + float2(perturb * 13.0,
                                                        perturb * 7.0));
        float microMod = 0.78 + microVar * 0.44;
        sr.coverage *= microMod;
      }
    }

    if (sr.coverage < 0.002) continue;

    if (isGestural) {
      half gPresence = max(max(smoothstep(0.02h, 0.30h, color.a),
                                smoothstep(0.05h, 0.40h, wetness)),
                            smoothstep(0.05h, 0.30h, permHeight));
      half gImpastoGate = smoothstep(0.35h, 0.65h, permHeight);
      half gFlatten = half(sr.coverage) * 0.25h * gPresence * gImpastoGate
                    * newness;
      half gSettling = max(0.0h, height - permHeight);
      half gNewSettling = gSettling * (1.0h - gFlatten);
      half gNewPerm = permHeight * (1.0h - gFlatten * 0.50h);
      permHeight = gNewPerm;
      height = permHeight + gNewSettling;
    }

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
    half3 mixedResult = mix(dryBlend, wetBlend, effectiveWet);

    half3 layeredResult = mix(color.rgb, tint, cov);

    half surfaceDryness = 1.0h - smoothstep(0.05h, 0.40h, wetness);
    half layerWeight;
    if (isWash) {
      layerWeight = min(1.0h, cov * 1.5h);
    } else if (isSplatter) {
      layerWeight = cov;
    } else if (isScumble) {

      layerWeight = cov;
    } else if (isKnife) {
      layerWeight = max(surfaceDryness, 0.50h);
    } else {
      layerWeight = max(surfaceDryness, 0.30h);
    }
    color.rgb = mix(mixedResult, layeredResult, layerWeight);

    half mixedAlpha = total;
    half layeredAlpha = max(color.a, cov);
    color.a = mix(mixedAlpha, layeredAlpha, layerWeight);
    height = min(height + hd, HEIGHT_MAX);

    half thicknessGate = smoothstep(0.08h, 0.45h, hd);
    half permDelta = hd * half(sr.impastoPermanence) * thicknessGate;

    if (isScumble) {
      permDelta = max(permDelta, cov * 0.20h);
    }
    if (isSplatter) {
      half buryFactor = clamp(cov * 0.85h, 0.0h, 0.85h);
      permHeight = permHeight * (1.0h - buryFactor);
    }
    permHeight = min(HEIGHT_MAX, permHeight + permDelta);

    wetness = max(wetness, cov * clamp(half(sr.strokeWetness), 0.0h, 1.0h));

    if (!isWash && crackVis > 0.001h) {
      half fillStrength = cov * clamp(half(sr.strokeWetness), 0.0h, 1.0h) * 0.55h;
      crackVis = max(0.0h, crackVis - fillStrength);
    }
  }

  if (height     < 0.004h) height     = 0.0h;
  if (wetness    < 0.005h) wetness    = 0.0h;
  if (permHeight < 0.003h) permHeight = 0.0h;
  if (crackVis   < 0.003h) crackVis   = 0.0h;
  color.a = clamp(color.a, 0.0h, 1.0h);

  colorOut.write(color, gid);
  if (hwOwner) {
    heightWetOut.write(half4(height, wetness, permHeight, crackVis), hgid);
  }
}

kernel void abexVelocityDeposit(
    texture2d<half, access::read>  velocityIn  [[texture(0)]],
    texture2d<half, access::write> velocityOut [[texture(1)]],
    texture2d<half, access::read>  heightWetIn [[texture(2)]],
    constant AbExParams &params                [[buffer(0)]],
    constant AbExStroke *strokes               [[buffer(1)]],
    constant uint *tileCounts                  [[buffer(2)]],
    constant uint *tileIndices                 [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint w = velocityOut.get_width();
  uint h = velocityOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  bool isFirstFrame = params.config.y > 0.5;

  half4 vSample = isFirstFrame ? half4(0) : velocityIn.read(gid);
  half2 velocity = vSample.rg * 0.40h;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 p = uv - 0.5;

  uint tileX = (gid.x * ABEX_TILE_GRID_DIM) / w;
  uint tileY = (gid.y * ABEX_TILE_GRID_DIM) / h;
  if (tileX >= ABEX_TILE_GRID_DIM) tileX = ABEX_TILE_GRID_DIM - 1;
  if (tileY >= ABEX_TILE_GRID_DIM) tileY = ABEX_TILE_GRID_DIM - 1;
  uint tileIdx = tileY * ABEX_TILE_GRID_DIM + tileX;
  uint tileStrokeCount = tileCounts[tileIdx];
  constant uint *tileStrokeList = tileIndices
                                + tileIdx * ABEX_MAX_STROKES_PER_TILE;

  for (uint k = 0; k < tileStrokeCount && k < ABEX_MAX_STROKES_PER_TILE; k++) {
    int i = int(tileStrokeList[k]);
    float type = strokes[i].sizeOpacity.w;
    bool isGestural = (type < 0.5);
    bool isKnife    = (type >= 3.5 && type < 4.5);
    if (!isKnife && !isGestural) continue;

    float2 center = strokes[i].posAngle.xy;
    float angle   = strokes[i].posAngle.z;
    float halfLen = max(strokes[i].posAngle.w, 0.01);
    float halfWd  = max(strokes[i].sizeOpacity.x, 0.002);

    float cs = cos(angle), sn = sin(angle);
    float2 d = p - center;
    float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);
    float alongT  = local.x / halfLen;

    float w_curve = strokes[i].animation.w;
    bool isS = abs(w_curve) >= 1.0;
    float amp = isS ? sign(w_curve) * (abs(w_curve) - 1.0) : w_curve;
    float yCurve = isS
                 ? amp * sin(alongT * M_PI_F) * halfLen * 0.5
                 : amp * cos(alongT * M_PI_F * 0.5) * halfLen * 0.5;
    float effAcrossT = (local.y - yCurve) / halfWd;

    if (abs(alongT) > 1.30 || abs(effAcrossT) > 1.50) continue;

    float lengthMask = 1.0 - smoothstep(0.85, 1.30, abs(alongT));
    float widthMask  = 1.0 - smoothstep(0.80, 1.50, abs(effAcrossT));
    float coverage = lengthMask * widthMask;

    bool isAnimating = strokes[i].animation.z > 0.5;
    float alongNorm = (alongT + 1.0) * 0.5;
    if (isAnimating) {
      float progressMax = strokes[i].animation.y;
      float windowMask = 1.0 - smoothstep(progressMax,
                                           progressMax + 0.06, alongNorm);
      coverage *= windowMask;
    }

    if (coverage < 0.01) continue;

    float dy_dx = isS
                ?  amp * M_PI_F        * cos(alongT * M_PI_F)       * 0.5
                : -amp * M_PI_F * 0.5  * sin(alongT * M_PI_F * 0.5) * 0.5;
    float invNorm = rsqrt(1.0 + dy_dx * dy_dx);
    float2 tangentLocal = float2(1.0, dy_dx) * invNorm;
    float2 kdir = float2(tangentLocal.x * cs - tangentLocal.y * sn,
                         tangentLocal.x * sn + tangentLocal.y * cs);

    int2 nearOff = int2(round(-kdir * 2.0));
    int2 farOff  = int2(round(-kdir * 5.0));
    uint2 nearGid = uint2(clamp(int2(gid) + nearOff,
                                 int2(0), int2(int(w)-1, int(h)-1)));
    uint2 farGid  = uint2(clamp(int2(gid) + farOff,
                                 int2(0), int2(int(w)-1, int(h)-1)));
    half wLocal = heightWetIn.read(gid).g;
    half wNear  = heightWetIn.read(nearGid).g;
    half wFar   = heightWetIn.read(farGid).g;
    half wetMax = max(max(wLocal, wNear), wFar);
    half wetGate = smoothstep(0.05h, 0.30h, wetMax);
    if (wetGate < 0.01h) continue;

    float speed = isKnife ? 0.0050 : 0.0025;

    velocity += half2(kdir * speed * coverage * float(wetGate));
  }

  half velMag = length(velocity);
  if (velMag > 0.012h) {
    velocity = velocity * (0.012h / velMag);
  }

  velocityOut.write(half4(velocity.x, velocity.y, 0, 0), gid);
}

kernel void abexCompose(
                        texture2d<half, access::read>   color     [[texture(0)]],
                        texture2d<half, access::sample> heightWet [[texture(1)]],
                        texture2d<half, access::write>  output    [[texture(2)]],
                        constant AbExParams &params              [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{

  constexpr sampler hwSampler(coord::normalized,
                              address::clamp_to_edge,
                              filter::linear);

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

  half4 hwC = heightWet.sample(hwSampler, uvAll);
  float hC = max(float(hwC.r), float(hwC.b));
  half wetTotal = clamp(hwC.g, 0.0h, 1.0h);

  half crackVis = clamp(hwC.a, 0.0h, 1.0h);

  half hasPigment = smoothstep(0.02h, 0.15h, c.a);
  half lowImpasto = 1.0h - smoothstep(0.02h, 0.10h, half(hwC.b));
  half washAmt    = clamp(hasPigment * lowImpasto, 0.0h, 1.0h);

  half surfaceTexture     = max(0.02h, 1.0h - washAmt * 0.98h);
  half bumpSurfaceTexture = max(0.10h, 1.0h - washAmt * 0.90h);
  float bumpSurfaceF = float(bumpSurfaceTexture);

  half3 canvasBase = half3(params.canvas.xyz) - canvasWeave(canvasPx);

  if (c.a < 0.005h && hC < 0.005) {
    half3 bare = acesNarkowicz(canvasBase);
    bare = linearToSrgb(bare);
    output.write(half4(bare, 1.0h), gid);
    return;
  }

  half3 normalLayer = mix(canvasBase, c.rgb, c.a);
  half3 stainLayer  = canvasBase * mix(half3(1.0h), c.rgb, c.a * 0.7h);
  half3 brushedResult = mix(stainLayer, normalLayer, smoothstep(0.05h, 0.15h, c.a));

  half stainMix = pow(c.a, 0.85h) * 0.95h;
  half3 soakResult = mix(canvasBase, c.rgb, stainMix);

  soakResult = mix(soakResult, canvasBase, washAmt * 0.12h);

  half3 result = mix(brushedResult, soakResult, washAmt);

  half3 N;
  half  paintMask;
  float2 totalGrad;
  half  gmag;

  paintMask = smoothstep(0.05h, 0.30h, c.a);

  half permThickness = smoothstep(0.05h, 0.45h, half(hwC.b));
  half thinFactor = 1.0h - permThickness;

  half dryness = 1.0h - clamp(wetTotal * 1.5h, 0.0h, 1.0h);
  half dryEffect = dryness * paintMask * thinFactor;
  half wetEffect = (1.0h - dryness) * paintMask;

  half nonWashFactor = 1.0h - washAmt;

  half3 dryShift = mix(half3(1.0h, 1.0h, 1.0h),
                       half3(0.74h, 0.80h, 0.93h),
                       dryEffect * mix(0.55h, 1.0h, nonWashFactor));
  result *= dryShift;

  half lum = dot(result, half3(0.2126h, 0.7152h, 0.0722h));
  half desatAmount = dryEffect * 0.55h * nonWashFactor;
  result = mix(result, half3(lum, lum, lum), desatAmount);

  half3 wetRichen = mix(half3(1.0h, 1.0h, 1.0h),
                        half3(0.92h, 0.93h, 0.96h),
                        wetEffect * 0.50h);
  result *= wetRichen;

  float2 hwSize = float2(heightWet.get_width(), heightWet.get_height());
  float2 pxStep = 1.0 / hwSize;
  half4 hwL = heightWet.sample(hwSampler, uvAll - float2(pxStep.x, 0.0));
  half4 hwR = heightWet.sample(hwSampler, uvAll + float2(pxStep.x, 0.0));
  half4 hwD = heightWet.sample(hwSampler, uvAll - float2(0.0, pxStep.y));
  half4 hwU = heightWet.sample(hwSampler, uvAll + float2(0.0, pxStep.y));

  float pL = float(hwL.b);
  float pR = float(hwR.b);
  float pD = float(hwD.b);
  float pU = float(hwU.b);
  float pC = float(hwC.b);

  half neighMax = max(max(half(pL), half(pR)), max(half(pD), half(pU)));
  neighMax = max(neighMax, half(pC));
  half cavity = saturate((neighMax - half(pC)) * 4.0h);
  half ao = 1.0h - cavity * 0.35h * paintMask;
  result *= ao;

  half permH = half(hwC.b);
  if (crackVis > 0.04h && permH > 0.05h) {

    half regionA = half(shaderSimplex2D(canvasPx * 0.0008));
    half regionB = half(shaderSimplex2D(canvasPx * 0.0014 + 247.0));
    half maskA = smoothstep(0.30h, 0.55h, regionA);
    half maskB = smoothstep(0.20h, 0.50h, regionB);
    half crackProne = maskA * maskB;

    if (crackProne > 0.01h) {

      float n1 = shaderSimplex2D(canvasPx * 0.012);
      float n2 = shaderSimplex2D(canvasPx * 0.038 + 51.0) * 0.5;
      float crackField = n1 + n2;
      half crackLine = 1.0h - smoothstep(0.0h, 0.06h, half(abs(crackField)));

      half crackDepth = 0.5h
                     + 0.5h * half(shaderSimplex2D(canvasPx * 0.005 + 31.0));

      half coverFactor = mix(1.0h, 0.30h, wetTotal);

      half crackStrength = saturate(crackVis * crackLine * crackProne);
      if (crackStrength > 0.005h) {
        half3 crackTint = canvasBase * 0.5h;
        half darkenAmount = crackStrength * 0.45h * crackDepth * coverFactor;
        result = mix(result, crackTint, darkenAmount);
      }
    }
  }

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
    half ndh   = max(0.0h, dot(N, H));
    half NdotV = max(0.001h, N.z);
    half fresnel = pow(1.0h - NdotV, 5.0h);

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

    expTight *= (1.0h + wetTotal * 1.0h);
    half wetGain = 1.0h + wetTotal * 1.8h;

    half specGate = 1.0h - washAmt;

    half specBroad = pow(ndh, expBroad) * 0.22h;
    half specTight = pow(ndh, expTight) * 0.18h;
    half spec = (specBroad + specTight) * paintMask * intensity * wetGain
              * surfaceTexture * specGate;

    half3 specColor = mix(warmLight, result, 0.40h);
    rgb += spec * specColor * 0.55h;

    half F0 = mix(0.025h, 0.14h, wetTotal);
    half F  = F0 + (1.0h - F0) * fresnel;
    half grazingSheen = F * wetTotal * 0.75h * paintMask * surfaceTexture * specGate;
    rgb += grazingSheen * warmLight;
  }

  half atmIntensity = half(params.atmosphere.x);
  if (atmIntensity > 0.05h) {
    half3 atmColor; half atmDensity;
    evaluateAtmosphere(centered, params.audio.x,
                       atmIntensity,
                       params.atmosphere.y,
                       params.atmosphere.z,
                       atmColor, atmDensity);

    half paintMass = clamp(permH * 0.45h + c.a * 0.30h, 0.0h, 1.0h);
    half atmStrength = 1.0h - paintMass * 0.15h;

    rgb = mix(rgb, atmColor, clamp(atmDensity * atmStrength, 0.0h, 1.0h));
  }

  rgb = acesNarkowicz(rgb);
  rgb = linearToSrgb(rgb);
  output.write(half4(rgb, 1.0h), gid);
}
