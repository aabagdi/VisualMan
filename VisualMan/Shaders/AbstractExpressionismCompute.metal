//
//  AbstractExpressionismCompute.metal
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#include <metal_stdlib>
#include "ShaderUtils.h"
#include "../Mixbox/Mixbox.metal"
using namespace metal;
#define MIXBOX_COLORSPACE_LINEAR 1

#define ABEX_ADDITIVE_HIGHLIGHTS 1
#define ABEX_HIGHLIGHT_SCALE     0.25h
#define ABEX_CRACK_DARKENING     1

inline mixbox_latent toLatent(texture2d<float, access::sample> lut,
                              half3 linearRgb) {
  return mixbox_rgb_to_latent(lut, float3(linearRgb));
}

inline half3 fromLatent(mixbox_latent z) {
  return half3(mixbox_latent_to_rgb(z));
}

inline mixbox_latent lerpLatent(mixbox_latent a, mixbox_latent b, float t) {
  return (1.0 - t) * a + t * b;
}

inline void ensureLatent(texture2d<float, access::sample> lut, half3 rgb,
                         thread mixbox_latent &z, thread bool &valid) {
  if (!valid) {
    z = toLatent(lut, rgb);
    valid = true;
  }
}

inline half4 upstreamPickup(texture2d<half, access::sample> canvas,
                            texture2d<half, access::sample> heightWet,
                            sampler s, float2 uv, float2 dir,
                            thread half &upstreamHeight) {
  const float dists[3] = { 0.006, 0.014, 0.025 };
  const half  wts[3]   = { 0.50h, 0.30h, 0.20h };
  half3 rgbSum = half3(0.0h);
  half  wSum   = 0.0h;
  half  hSum   = 0.0h;
  for (int k = 0; k < 3; k++) {
    float2 suv = saturate(uv - dir * dists[k]);
    half4 c   = canvas.sample(s, suv);
    half4 hw  = heightWet.sample(s, suv);
    half  wet = smoothstep(0.02h, 0.22h, hw.g);
    half  w   = c.a * wet * wts[k];
    rgbSum += c.rgb * w;
    wSum   += w;
    hSum   += max(hw.r, hw.b) * wet * wts[k];
  }
  half3 rgb = wSum > 0.001h ? rgbSum / wSum : half3(0.0h);
  upstreamHeight = hSum;
  return half4(rgb, saturate(wSum));
}

inline half4 upstreamPickupWide(texture2d<half, access::sample> canvas,
                                texture2d<half, access::sample> heightWet,
                                sampler s, float2 uv, float2 dir, float2 perp,
                                float halfWidth, half4 centre, half centreHeight,
                                thread half &upstreamHeight) {
  half hL = 0.0h, hR = 0.0h;
  half4 cL = upstreamPickup(canvas, heightWet, s, uv - perp * (0.6 * halfWidth), dir, hL);
  half4 cR = upstreamPickup(canvas, heightWet, s, uv + perp * (0.6 * halfWidth), dir, hR);
  half aSum = cL.a + centre.a + cR.a;
  half3 rgb = aSum > 0.001h
            ? (cL.rgb * cL.a + centre.rgb * centre.a + cR.rgb * cR.a) / aSum
            : half3(0.0h);
  upstreamHeight = (hL + centreHeight + hR) / 3.0h;
  return half4(rgb, saturate(aSum / 3.0h));
}

inline half bristleLaneShare(float lane, float along, float seed) {
  float n = shaderSimplex2D(float2(lane * 0.73 + seed * 0.11,
                                   along * 2.5 + seed));
  return half(saturate(0.5 + n * 0.6));
}

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

inline float canvasWeaveIrregularity(float2 pixelPos) {
  return 0.80 + 0.40 * (shaderSimplex2D(pixelPos * 0.013) * 0.5 + 0.5);
}

inline half canvasWeave(float2 pixelPos, float irregular) {
  float threadX = sin(pixelPos.x * 0.85) * 0.5 + 0.5;
  float threadY = sin(pixelPos.y * 0.85) * 0.5 + 0.5;
  return half(threadX * threadY * irregular * 0.075);
}

inline half canvasWeave(float2 pixelPos) {
  float threadX = sin(pixelPos.x * 0.85) * 0.5 + 0.5;
  float threadY = sin(pixelPos.y * 0.85) * 0.5 + 0.5;
  float weave = threadX * threadY * canvasWeaveIrregularity(pixelPos);
  return half(weave * 0.075);
}

inline float2 canvasWeaveGradient(float2 pixelPos, float irregular) {
  float c = 0.85;
  float tX = sin(pixelPos.x * c) * 0.5 + 0.5;
  float tY = sin(pixelPos.y * c) * 0.5 + 0.5;
  float dtX = 0.5 * c * cos(pixelPos.x * c);
  float dtY = 0.5 * c * cos(pixelPos.y * c);
  return float2(dtX * tY, tX * dtY) * (0.055 * irregular);
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
  float irregular = canvasWeaveIrregularity(pixelPos);
  return float2(dtX * tY, tX * dtY) * (0.055 * irregular);
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
  float radialNorm;
};

inline StrokeResult evaluateGestural(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
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
  float endTaper   = smoothstep(1.25, 0.60, alongT);
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
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
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

  float poolField = shaderSimplex2D(scaled * 0.5 + seed * 8.3);
  float spreadField = shaderSimplex2D(scaled * 1.4 + seed * 17.1) * 0.45;
  float densityField = poolField + spreadField;
  float interiorWeight = 1.0 - smoothstep(0.0, 0.85, normR);
  float densityClamped = clamp(densityField, -1.4, 1.4);
  float densityRaw = mix(0.75, 1.20, (densityClamped + 1.4) / 2.8);
  float densityMult = mix(1.0, densityRaw, interiorWeight);
  falloff *= densityMult;

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

  float dirX = (rr > 0.001) ? (scaled.x / rr) : 0.0;
  float flowBias = -dirX * 0.20;
  r.radialNorm  = saturate(normR + flowBias);
  r.acrossT     = normR;

  r.bristleTone = 0.0;
  r.heightDelta = 0.0;

  return r;
}

inline StrokeResult evaluateSplatter(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
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
  
  if (typeRoll < 0.33) {
    mainHeight        = 0.0 + hash11(seed * 1.77) * 0.05;
    impastoPermanence = 0.0;
  } else if (typeRoll < 0.66) {
    mainHeight        = 0.30 + hash11(seed * 3.13) * 0.30;
    impastoPermanence = 0.50;
  } else if (typeRoll < 0.88) {
    mainHeight        = 0.80 + hash11(seed * 5.71) * 0.60;
    impastoPermanence = 1.0;
  } else {
    mainHeight        = 1.80 + hash11(seed * 7.13) * 0.70;
    impastoPermanence = 1.0;
  }
  r.impastoPermanence = impastoPermanence;

  float normDist = clamp(dist / (effR * 1.05), 0.0, 1.0);
  float colorFalloff = 1.0 - smoothstep(0.997, 1.000, normDist);
  float heightFalloff;

  if (mainHeight > 0.35) {
    float dome   = pow(max(1.0 - normDist * normDist, 0.0), 0.65);
    float rimAmt = (mainHeight > 0.85) ? 0.18 : 0.08;
    float crater = (1.0 - smoothstep(0.0, 0.50, normDist)) * rimAmt * 0.5;
    float rim    = exp(-pow((normDist - 0.66) / 0.14, 2.0)) * rimAmt;
    float edge   = 1.0 - smoothstep(0.90, 1.00, normDist);
    heightFalloff = max(dome * (1.0 - crater) + rim, 0.0) * edge;
  } else {
    heightFalloff = 1.0 - smoothstep(0.85, 1.00, normDist);
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
      ? (0.04 + mainHeight * 0.10)
      : (0.10 + mainHeight * 0.12);
  r.heightDelta *= (1.0 + heightVar * varStrength);

  if (mainHeight > 0.85) {
    float crater = shaderSimplex2D(p * 50.0 + seed * 3.7);
    crater = crater * 0.5 + 0.5;
    crater = pow(crater, 1.6);
    r.heightDelta *= 0.95 + crater * 0.10;
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
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
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

  float midWidthLow  = shaderSimplex2D(float2(t * 1.8, seed * 2.1)) * 0.32;
  float midWidthHigh = shaderSimplex2D(float2(t * 5.5, seed * 4.7)) * 0.12;
  float midWidth = 0.85 + midWidthLow + midWidthHigh;

  float landingWidth = landingWidthScale;

  float widthMod = launchWidth * launchT
                 + midWidth * midT
                 + landingWidth * landingT;
  widthMod = clamp(widthMod, 0.25, 1.85);

  float wobbleBase = shaderSimplex2D(float2(t * 1.0, seed * 0.7))      * dripLen * 0.10
                   + shaderSimplex2D(float2(t * 3.5, seed * 1.3 + 11)) * dripLen * 0.035;
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
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
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
  float widthMask  = 1.0 - smoothstep(0.88, 1.02, abs(acrossT));

  float edgeBias = sign(acrossT) * sign(hash11(seed * 31.7) - 0.5);

  float pressureNoise = shaderNoise(float2(local.x * 6.0  + seed * 11.0,
                                            seed * 19.0));
  float pressureMod   = 0.65 + pressureNoise * 0.50;

  float coverage = lengthMask * widthMask * baseOp * pressureMod;

  float striation = shaderNoise(float2(local.x *  80.0 + seed * 3.0,
                                       local.y * 400.0 + seed * 7.0)) - 0.5;
  float fineGrain = shaderNoise(float2(local.x * 240.0 + seed * 13.0,
                                       local.y * 700.0 + seed * 17.0)) - 0.5;
  coverage *= 1.0 + striation * 0.36 + fineGrain * 0.16;

  float ridgeBoost = 1.0 + max(0.0, edgeBias) * 0.50;
  float sideRidge = smoothstep(0.85, 1.0, abs(acrossT))
                  * (1.0 - smoothstep(1.0, 1.18, abs(acrossT)))
                  * lengthMask
                  * ridgeBoost;

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
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;

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
  r.alongNorm   = saturate(0.5 + 0.5 * local.x / halfLen);
  r.acrossT     = scaled.y;

  r.bristleTone = density * 0.20;
  return r;
}

inline StrokeResult evaluateLine(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0; r.radialNorm = 0;
  r.strokeWetness = 0.10;
  r.impastoPermanence = 0.0;

  float2 center = s.posAngle.xy;
  float angle   = s.posAngle.z;
  float halfLen = max(s.posAngle.w, 0.01);
  float halfWd  = max(s.sizeOpacity.x, 0.001);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;
  float curvature = s.animation.w;

  float cs = cos(angle), sn = sin(angle);
  float2 d = p - center;
  float2 local = float2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs);

  float alongT = local.x / halfLen;
  float curveOffset = curvature * (1.0 - alongT * alongT) * halfLen * 0.35;
  local.y -= curveOffset;

  float wobble = shaderSimplex2D(float2(alongT * 4.0, seed * 2.3))
                 * halfWd * 0.7;
  local.y -= wobble;

  if (abs(local.x) > halfLen * 1.05) return r;
  if (abs(local.y) > halfWd * 3.0)   return r;

  float distToLine = abs(local.y);
  if (abs(local.x) > halfLen) {
    float2 endpt = float2(local.x > 0 ? halfLen : -halfLen, 0);
    distToLine = length(local - endpt);
  }

  float coverage = 1.0 - smoothstep(halfWd * 0.6, halfWd * 1.4,
                                     distToLine);

  float skipNoiseLow = shaderSimplex2D(float2(alongT * 2.2, seed * 7.1));
  float skipNoiseHigh = shaderSimplex2D(float2(alongT * 18.0, seed * 11.3));
  float skipFactor = smoothstep(-0.5, 0.4, skipNoiseLow);
  coverage *= mix(0.20, 1.0, skipFactor);
  coverage *= 0.78 + skipNoiseHigh * 0.22;

  float crossT = local.y / halfWd;
  float crossGrain = shaderNoise(float2(alongT * 50.0, crossT * 12.0
                                          + seed * 3.1)) - 0.5;
  coverage *= 1.0 + crossGrain * 0.30;

  float endTaper = 1.0 - smoothstep(0.85, 1.0, abs(alongT));
  coverage *= endTaper;

  r.coverage    = clamp(coverage * baseOp, 0.0, 1.0);
  r.alongNorm   = saturate(alongT * 0.5 + 0.5);
  r.acrossT     = local.y / halfWd;

  r.bristleTone = 0.0;
  r.heightDelta = 0.0;

  return r;
}

inline half3 strokeTint(constant AbExStroke &s, StrokeResult sr) {
  return half3(s.color.xyz);
}

inline mixbox_latent bristleShade(texture2d<float, access::sample> lut,
                                  mixbox_latent tint, float tone) {
  float amount = clamp(abs(tone) * 0.06, 0.0, 0.08);
  if (amount < 0.002) return tint;
  half3 target = tone > 0.0 ? half3(1.0h) : half3(0.0h);
  return lerpLatent(tint, toLatent(lut, target), amount);
}

#define ABEX_TILE_GRID_DIM 16
#define ABEX_MAX_STROKES_PER_TILE 8

kernel void abexPaint(
                      texture2d<half, access::sample> colorIn      [[texture(0)]],
                      texture2d<half, access::write>  colorOut     [[texture(1)]],
                      texture2d<half, access::sample> heightWetIn  [[texture(2)]],
                      texture2d<half, access::write>  heightWetOut [[texture(3)]],
                      texture2d<half, access::sample> velocityIn   [[texture(4)]],
                      texture2d<half, access::read>   dryColorIn   [[texture(5)]],
                      texture2d<half, access::write>  dryColorOut  [[texture(6)]],
                      texture2d<half, access::read>   substrateIn  [[texture(7)]],
                      texture2d<half, access::write>  substrateOut [[texture(8)]],
                      texture2d<float, access::sample> mixboxLUT   [[texture(9)]],
                      constant AbExParams &params                 [[buffer(0)]],
                      constant AbExStroke *strokes                [[buffer(1)]],
                      constant uint *tileCounts                   [[buffer(2)]],
                      constant uint *tileIndices                  [[buffer(3)]],
                      constant uint2 &regionOrigin                [[buffer(4)]],
                      uint2 tid [[thread_position_in_grid]])
{
  uint2 gid = tid + regionOrigin;
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
  half4 dryColor;
  half4 substrate;
  bool skipDecay = params.atmosphere.w > 0.5;

  mixbox_latent colorLatent = mixbox_latent(float3(0.0), float3(0.0), float3(0.0));
  bool colorLatentValid = false;
  mixbox_latent dryLatent = mixbox_latent(float3(0.0), float3(0.0), float3(0.0));
  bool dryLatentValid = false;

  if (isFirstFrame) {
    color = half4(0); height = 0.0h; wetness = 0.0h;
    permHeight = 0.0h; crackVis = 0.0h;
    dryColor = half4(0);
    substrate = half4(0);
  } else {

    color = colorIn.read(gid);
    half4 hw = heightWetIn.read(hgid);
    height = hw.r; wetness = hw.g; permHeight = hw.b; crackVis = hw.a;
    dryColor = dryColorIn.read(hgid);
    substrate = substrateIn.read(hgid);

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
      half dryScale    = mix(14.0h, 0.9h, thinMix)
                       - thickMix * 0.6h;
      dryScale = max(dryScale, 0.25h);
      half wetDecay = saturate(1.0h - dryRate * dryScale);
      half wetnessOld = wetness;
      wetness *= wetDecay;

      half wetGradMag = 0.0h;
      if (simd_any(wetness > 0.005h || wetnessOld > 0.005h)) {
        float2 hwSize = float2(heightWetIn.get_width(),
                                heightWetIn.get_height());
        float2 hwStep = 1.0 / hwSize;
        float2 hwUv = (float2(hgid) + 0.5) * hwStep;
        half4 nL = heightWetIn.sample(advSampler, hwUv - float2(hwStep.x, 0.0));
        half4 nR = heightWetIn.sample(advSampler, hwUv + float2(hwStep.x, 0.0));
        half4 nD = heightWetIn.sample(advSampler, hwUv - float2(0.0, hwStep.y));
        half4 nU = heightWetIn.sample(advSampler, hwUv + float2(0.0, hwStep.y));

        half neighbWet = (nL.g + nR.g + nD.g + nU.g) * 0.25h;
        half viscosityGate = 1.0h
                           - smoothstep(0.10h, 0.55h, permHeight) * 0.85h;
        half substrateGate = 1.0h - substrate.r * 0.95h;
        half flowRate = 0.18h * viscosityGate * substrateGate
                       * deltaT * 60.0h;
        flowRate = clamp(flowRate, 0.0h, 0.40h);
        wetness = mix(wetness, neighbWet, flowRate);

        wetGradMag = abs(nR.g - nL.g) + abs(nU.g - nD.g);
      }

      if (color.a > 0.005h && wetnessOld > 0.005h) {
        half wetnessLost = max(wetnessOld - wetness, 0.0h);
        half dryShare = saturate(wetnessLost / wetnessOld);
        half stainGate = smoothstep(0.0h, 0.05h, permHeight);
        half edgeBoost = 1.0h
                       + smoothstep(0.05h, 0.30h, wetGradMag) * 0.6h
                       * stainGate;
        half incomingAlpha = saturate(color.a * dryShare * edgeBoost);
        if (incomingAlpha > 0.0001h) {
          half a_w    = color.a;
          half a_d    = dryColor.a;
          half inc    = min(incomingAlpha, a_w);
          half a_wNew = a_w - inc;
          half outA   = 1.0h - (1.0h - a_d) * (1.0h - a_w)
                              / max(1.0h - a_wNew, 0.001h);
          outA = clamp(outA, a_d, 1.0h);
          if (inc > 0.0001h) {
            half mixT = inc / max(a_d + inc, 0.001h);
            ensureLatent(mixboxLUT, dryColor.rgb, dryLatent, dryLatentValid);
            dryLatent = lerpLatent(dryLatent, toLatent(mixboxLUT, color.rgb),
                                   float(mixT));
            dryColor.a = outA;
          }
          color.a = a_wNew;
        }
      }

      {
        half skinGate = smoothstep(0.10h, 0.60h, height)
                      * smoothstep(0.02h, 0.20h, color.a + permHeight);
        half skinRate = dryRate * 3.5h * skinGate * (1.0h - wetness * 0.35h);
        half skin = saturate(substrate.g + (1.0h - substrate.g) * skinRate);
        skin = max(skin, (1.0h - smoothstep(0.0h, 0.06h, wetness)) * skinGate);
        substrate.g = skin;
      }

      half permThickCrack = smoothstep(0.20h, 0.55h, permHeight);
      if (permThickCrack > 0.001h) {
        half drynessCrack = 1.0h - smoothstep(0.02h, 0.22h, wetness);
        half wetOnDryCrack = wetness * permThickCrack;
        half crackBoost = 1.0h + wetOnDryCrack * 2.0h;
        half thickBonus = 1.0h
                        + smoothstep(0.40h, 0.90h, permHeight) * 1.5h;
        half crackGrowth = permThickCrack * drynessCrack * crackBoost
                         * thickBonus
                         * deltaT * 0.18h;
        crackVis = min(1.0h, crackVis + crackGrowth);
      }
    }

    if (skipDecay) {
      half3 velSample = velocityIn.read(hgid).rgb;
      half2 velocity = velSample.rg;
      half knifeFlag = velSample.b;
      half velMag = length(velocity);
      advFraction = smoothstep(0.001h, 0.006h, velMag);

      half drainRate = smoothstep(0.001h, 0.012h, velMag) * 0.08h;
      wetness = max(0.0h, wetness - drainRate);

      if (simd_any(advFraction > 0.005h)) {
        if (advFraction > 0.005h) {
          float2 srcUv = saturate(uv - float2(velocity));
          half4 advColor = colorIn.sample(advSampler, srcUv);
          half4 advHW    = heightWetIn.sample(advSampler, srcUv);

          bool isKnifeSmear = knifeFlag > 0.5h;
          if (isKnifeSmear) {
            float2 velDir = float2(velocity) / max(velMag, 0.001h);
            float2 velPerp = float2(-velDir.y, velDir.x);

            float pAlong  = dot(float2(gid), velDir);
            float pAcross = dot(float2(gid), velPerp);

            float streakN = shaderSimplex2D(
              float2(pAcross * 1.20, pAlong * 0.025));

            float streakIntensity = 0.30 + 0.70
              * smoothstep(-0.40, 0.40, streakN);

            half upstreamPaint = saturate(advColor.a * 1.2h);

            half mixStrength = clamp(advFraction
                                      * half(streakIntensity)
                                      * upstreamPaint * 0.45h,
                                      0.0h, 1.0h);
            if (simd_any(mixStrength > 0.004h)) {
              ensureLatent(mixboxLUT, color.rgb, colorLatent, colorLatentValid);
              colorLatent = lerpLatent(colorLatent,
                                       toLatent(mixboxLUT, advColor.rgb),
                                       float(mixStrength));
            }
          } else {

            float2 velDir = float2(velocity) / max(velMag, 0.001h);
            float2 velPerp = float2(-velDir.y, velDir.x);

            float pAlong  = dot(float2(gid), velDir);
            float pAcross = dot(float2(gid), velPerp);

            float bristleN = shaderSimplex2D(
              float2(pAcross * 0.55, pAlong * 0.045));

            float groove = smoothstep(-0.15, 0.15, bristleN);

            half wAdv = advFraction * mix(0.06h, 0.45h, half(groove)) * advColor.a
                      * 0.30h;
            half wOld = color.a * (1.0h - advFraction);
            half grooveT = wAdv / max(wAdv + wOld, 0.001h);
            ensureLatent(mixboxLUT, color.rgb, colorLatent, colorLatentValid);
            colorLatent = lerpLatent(colorLatent,
                                     toLatent(mixboxLUT, advColor.rgb),
                                     float(grooveT));
          }

          color.a    = mix(color.a,    advColor.a, advFraction);
          height     = mix(height,     advHW.r,    advFraction);
          permHeight = mix(permHeight, advHW.b,    advFraction);
          crackVis   = mix(crackVis,   advHW.a,    advFraction);

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
    bool isScumble  = (type >= 4.5 && type < 5.5);
    bool isLine     = (type >= 5.5);

    StrokeResult sr;
    if      (isGestural) sr = evaluateGestural(p, strokes[i]);
    else if (isWash)     sr = evaluateWash(p, strokes[i]);
    else if (isSplatter) sr = evaluateSplatter(p, strokes[i]);
    else if (isDrip)     sr = evaluateDrip(p, strokes[i]);
    else if (isKnife)    sr = evaluateKnife(p, strokes[i]);
    else if (isScumble)  sr = evaluateScumble(p, strokes[i]);
    else                 sr = evaluateLine(p, strokes[i]);

    if (!simd_any(sr.coverage > 0.001)) continue;

    half drawnMask = 1.0h;
    half newness = 1.0h;
    bool isAnimating = strokes[i].animation.z > 0.5;
    if (isAnimating) {
      float progressMin = strokes[i].animation.x;
      float progressMax = strokes[i].animation.y;
      float softEdge = 0.025;
      float progressCoord = isWash ? sr.radialNorm : sr.alongNorm;
      drawnMask = half(1.0 - smoothstep(progressMax - softEdge,
                                         progressMax + softEdge,
                                         progressCoord));
      newness = (progressMin <= 0.001)
              ? 1.0h
              : half(smoothstep(progressMin - softEdge,
                                progressMin + softEdge, progressCoord));
      sr.coverage *= float(drawnMask);
      sr.heightDelta *= float(drawnMask);
    }

    if (isKnife) {
      float kAngle = strokes[i].posAngle.z;
      float2 kdir = float2(cos(kAngle), sin(kAngle));
      float2 kperp = float2(-kdir.y, kdir.x);

      half kCov = half(max(sr.coverage, 0.0));
      if (kCov < 0.001h && sr.heightDelta <= 0.0h) continue;

      half scrapeAmount = min(permHeight, kCov * 0.08h * newness);
      permHeight -= scrapeAmount;
      height += scrapeAmount;

      if (permHeight > 0.05h) {
        float scrapeStreakNoise = shaderNoise(p * 280.0
                                                + permHeight * 17.0);
        half streakModulation = 0.75h + half(scrapeStreakNoise) * 0.40h;
        half permInfluence = smoothstep(0.05h, 0.50h, permHeight);
        half effectiveStreak = mix(1.0h, streakModulation, permInfluence);
        kCov *= effectiveStreak;
      }

      float kPerpCoord = dot(p, kperp);
      float kBristleSeed = kPerpCoord * 540.0;
      float kBristleNoise = fract(sin(kBristleSeed * 12.9898)
                                   * 43758.5453) - 0.5;
      half bristleVar = half(kBristleNoise) * 0.30h;

      half3 kTint = half3(strokes[i].color.xyz);
      half paintGate = saturate(color.a * 2.5h);
      ensureLatent(mixboxLUT, color.rgb, colorLatent, colorLatentValid);
      mixbox_latent kTintLatent = toLatent(mixboxLUT, kTint);

      half kWetGate   = smoothstep(0.02h, 0.22h, wetness);
      half skin       = substrate.g;
      half skinResist = skin * smoothstep(0.10h, 0.50h, height) * kWetGate;
      half tear       = smoothstep(0.40h, 0.80h, kCov) * skinResist * newness;
      half skinHold   = skinResist * (1.0h - smoothstep(0.40h, 0.80h, kCov));
      half kUpHeight  = 0.0h;
      half4 carried   = half4(0.0h);
      half band       = 0.5h;
      half thickHere  = smoothstep(0.10h, 0.80h, height);
      {
        carried = upstreamPickup(colorIn, heightWetIn, advSampler, uv, kdir,
                                 kUpHeight);
        float seed = strokes[i].sizeOpacity.z;
        float along = dot(p, kdir);
        half fine   = bristleLaneShare(floor(kPerpCoord * 180.0), along * 6.0, seed);
        half coarse = bristleLaneShare(floor(kPerpCoord * 55.0), along * 3.0,
                                       seed * 1.7 + 11.0);
        band = smoothstep(0.30h, 0.70h, mix(coarse, fine, 0.45h));
        half massFactor = 0.75h + 0.25h * smoothstep(0.10h, 1.0h, kUpHeight);
        half pickup = saturate(carried.a * band * 0.90h * massFactor
                               * (1.0h + tear * 0.8h));
        if (pickup > 0.005h) {
          kTintLatent = lerpLatent(kTintLatent,
                                   toLatent(mixboxLUT, carried.rgb),
                                   float(pickup));
        }
      }

      half kCover  = clamp(kCov * 0.95h, 0.0h, 1.0h);
      half kLayerT = kCover / max(color.a * (1.0h - kCover) + kCover, 0.001h);
      half resist  = thickHere * kWetGate * 0.15h;
      half laneCut = band * 0.85h * kWetGate;
      half kDepositT = kLayerT * (1.0h - (resist + laneCut) * paintGate);
      mixbox_latent cleanLatent = lerpLatent(colorLatent, kTintLatent,
                                             float(kDepositT));
      half kNewA = max(color.a, smoothstep(0.04h, 0.30h, kCov));
      half kAdded = max(0.0h, kNewA - color.a) / max(kNewA, 0.001h);
      colorLatent = lerpLatent(colorLatent, cleanLatent,
                               float(max(newness, kAdded)));
      color.a = kNewA;

      half acrossAbs = half(abs(sr.acrossT));
      half ridgeMask = smoothstep(0.80h, 1.00h, acrossAbs)
                     * (1.0h - smoothstep(1.02h, 1.25h, acrossAbs));
      half displacedNearby = max(height, kUpHeight) * kWetGate;
      half ridgeAdd = ridgeMask * 0.55h * displacedNearby * newness
                    * (1.0h + tear * 1.2h);
      if (ridgeAdd > 0.002h && carried.a > 0.01h) {
        half ridgeA = saturate(ridgeMask * carried.a);
        half added  = max(0.0h, ridgeA - color.a) / max(ridgeA, 0.001h);
        half ridgeT = max(ridgeMask * kWetGate * 0.5h * newness, added);
        colorLatent = lerpLatent(colorLatent, toLatent(mixboxLUT, carried.rgb),
                                 float(ridgeT));
        color.a = max(color.a, ridgeA);
      }

      half presenceGate = max(max(smoothstep(0.02h, 0.30h, color.a),
                                   smoothstep(0.05h, 0.40h, wetness)),
                               smoothstep(0.02h, 0.20h, permHeight));
      half impastoGateF = smoothstep(0.03h, 0.20h, permHeight);
      half flattenStrength = clamp(kCov * 1.80h
                                     * presenceGate * impastoGateF
                                     * max(kWetGate, 0.25h) * newness,
                                   0.0h, 0.95h);
      flattenStrength *= (1.0h - 0.65h * skinHold);

      half heightBefore   = height;
      half settlingHeight = max(0.0h, height - permHeight);
      half kStainFloor    = kCov * 0.05h * (1.0h + bristleVar * 1.6h);
      half plateauLevel   = max(kStainFloor,
                                0.20h * max(heightBefore, kUpHeight * kWetGate));
      half shearedPerm    = min(permHeight, plateauLevel);
      half newPerm        = mix(permHeight, shearedPerm, flattenStrength);
      half settleTarget   = max(0.0h, plateauLevel - newPerm);
      half newSettling    = mix(settlingHeight, settleTarget, flattenStrength);

      half fillTarget   = kUpHeight * 0.60h;
      half fillStrength = clamp(kCov * kWetGate * newness
                                  * smoothstep(0.10h, 0.60h, kUpHeight),
                                0.0h, 0.90h);
      if (heightBefore < fillTarget) {
        newSettling = mix(newSettling, max(0.0h, fillTarget - newPerm),
                          fillStrength);
      }

      half hd = half(sr.heightDelta);
      half kPermDelta = max(hd, 0.0h) * half(sr.impastoPermanence);
      half bristleRidge = bristleVar * kCov * 0.20h;

      half wrinkle = tear * 0.35h
                   * half(shaderNoise(float2(dot(p, kdir) * 900.0
                                               + strokes[i].sizeOpacity.z,
                                             kPerpCoord * 60.0)) - 0.5);

      permHeight = clamp(max(newPerm + kPermDelta + bristleRidge,
                              kStainFloor),
                          0.0h, HEIGHT_MAX);
      height = clamp(permHeight + newSettling + ridgeAdd + wrinkle
                      + min(hd, 0.0h) * newness,
                      0.0h, HEIGHT_MAX);
      substrate.g = skin * (1.0h - max(tear, kCov * 0.5h * newness));

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

      sr.coverage *= float(newness);

      half wcov = half(sr.coverage);
      if (wcov > 0.005h) {
        half3 wtint = strokeTint(strokes[i], sr);

        half a_dst = dryColor.a;
        half a_src = wcov;
        half outA = a_dst + a_src * (1.0h - a_dst);
        if (outA > 0.001h) {
          half mixT = a_src * (1.0h - a_dst) / outA;
          ensureLatent(mixboxLUT, dryColor.rgb, dryLatent, dryLatentValid);
          dryLatent = lerpLatent(dryLatent, toLatent(mixboxLUT, wtint),
                                 float(mixT));
          dryColor.a = outA;
        }

        half availableCapacity = 1.0h - substrate.r;
        half saturationGain = wcov * availableCapacity * 0.06h;
        substrate.r = saturate(substrate.r + saturationGain);
      }
      continue;
    }

    if (isLine) {
      half lcov = half(sr.coverage);
      if (lcov > 0.005h) {
        half3 ltint = half3(strokes[i].color.xyz);

        half a_dst = dryColor.a;
        half a_src = lcov;
        half outA = a_dst + a_src * (1.0h - a_dst);
        if (outA > 0.001h) {
          half mixT = a_src * (1.0h - a_dst) / outA;
          ensureLatent(mixboxLUT, dryColor.rgb, dryLatent, dryLatentValid);
          dryLatent = lerpLatent(dryLatent, toLatent(mixboxLUT, ltint),
                                 float(mixT));
          dryColor.a = outA;
        }
      }
      continue;
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
      half gWet = smoothstep(0.02h, 0.22h, wetness);
      half gImpastoGate = smoothstep(0.15h, 0.45h, permHeight);
      half gFlatten = half(sr.coverage) * mix(0.25h, 0.60h, gWet)
                    * gPresence * gImpastoGate * newness;
      half gSettling = max(0.0h, height - permHeight);
      half gNewSettling = gSettling * (1.0h - gFlatten);
      half gNewPerm = permHeight * (1.0h - gFlatten * 0.50h);
      permHeight = gNewPerm;
      height = permHeight + gNewSettling;

      half gScrape = min(permHeight, half(sr.coverage) * mix(0.03h, 0.08h, gWet)
                                       * newness * gImpastoGate);
      permHeight -= gScrape;
      height += gScrape;
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

    if (!isGestural && !isKnife && permHeight > 0.05h) {
      float texNoise = shaderNoise(p * 320.0 + permHeight * 11.0);
      half textureModulation = 0.65h + half(texNoise) * 0.5h;
      half permInfluence = smoothstep(0.05h, 0.50h, permHeight);
      half effectiveModulation = mix(1.0h, textureModulation, permInfluence);
      cov *= effectiveModulation;
      hd  *= effectiveModulation;
    }

    half oldAmount = color.a * (1.0h - cov);
    half total     = oldAmount + cov;
    half surfaceDryness = 1.0h - smoothstep(0.02h, 0.22h, wetness);
    half layerWeight;
    if (isWash) {
      layerWeight = 0.0h;
    } else if (isSplatter) {
      layerWeight = cov * 0.85h;
    } else if (isScumble) {

      layerWeight = cov;
    } else if (isKnife) {
      layerWeight = max(surfaceDryness, 0.50h);
    } else {
      layerWeight = max(surfaceDryness, 0.20h);
    }

    const half kFilm = 0.15h;
    half expectedH = hd * (isAnimating ? 12.0h : 1.0h);
    half newVol = cov * (kFilm + expectedH);
    half oldVol = color.a * (kFilm + height);
    half wetMixT  = newVol / max(oldVol + newVol, 0.001h);
    half layerT   = cov / max(total, 0.001h);
    mixbox_latent tintLatent = bristleShade(mixboxLUT,
                                            toLatent(mixboxLUT, tint),
                                            sr.bristleTone);

    half wetGate = 1.0h - surfaceDryness;
    half skinHere = substrate.g * smoothstep(0.10h, 0.50h, height)
                  * (1.0h - smoothstep(0.50h, 0.90h, cov) * 0.6h);
    wetGate *= (1.0h - skinHere * 0.7h);
    if (isGestural) {
      layerWeight = max(layerWeight, skinHere * 0.6h);
      float gAngle = strokes[i].posAngle.z;
      float2 gdir  = float2(cos(gAngle), sin(gAngle));
      float  seed  = strokes[i].sizeOpacity.z;
      half fine   = bristleLaneShare(floor((sr.acrossT + 1.35) * 6.0),
                                     sr.alongNorm, seed);
      half coarse = bristleLaneShare(floor((sr.acrossT + 1.35) * 2.2),
                                     sr.alongNorm * 0.6, seed * 1.7 + 11.0);
      half band = smoothstep(0.25h, 0.75h, mix(coarse, fine, 0.5h));
      half gUpHeight = 0.0h, gUpHeightWide = 0.0h;
      float2 gperp = float2(-gdir.y, gdir.x);
      half4 laneCarried = upstreamPickup(colorIn, heightWetIn, advSampler, uv,
                                         gdir, gUpHeight);
      half4 wideCarried = upstreamPickupWide(colorIn, heightWetIn, advSampler,
                                             uv, gdir, gperp,
                                             strokes[i].sizeOpacity.x,
                                             laneCarried, gUpHeight,
                                             gUpHeightWide);
      half wLane = laneCarried.a * 0.5h, wWide = wideCarried.a * 0.5h;
      half4 carried = half4(0.0h);
      if (wLane + wWide > 0.001h) {
        carried.rgb = (laneCarried.rgb * wLane + wideCarried.rgb * wWide)
                    / (wLane + wWide);
        carried.a = max(laneCarried.a, wideCarried.a);
      }
      gUpHeight = max(gUpHeight, gUpHeightWide);
      half massFactor = 0.65h + 0.35h * smoothstep(0.10h, 1.0h, gUpHeight);
      half localWet   = saturate(color.a * 2.5h) * wetGate;
      half pickup = saturate(carried.a * mix(0.05h, 0.75h, band)
                             * massFactor * (1.0h - localWet));
      if (pickup > 0.005h) {
        tintLatent = lerpLatent(tintLatent,
                                toLatent(mixboxLUT, carried.rgb),
                                float(pickup));
      }
      half laneCover = mix(1.10h, 0.78h, band);
      wetMixT = saturate(wetMixT * mix(1.0h, laneCover, wetGate));
    }

    half covA = isGestural ? smoothstep(0.04h, 0.30h, cov) : cov;
    half mixedAlpha = color.a * (1.0h - covA) + covA;
    half layeredAlpha = max(color.a, covA);
    half newAlpha = mix(mixedAlpha, layeredAlpha, layerWeight);

    half addedShare = max(0.0h, newAlpha - color.a) / max(newAlpha, 0.001h);
    half depositT = max(mix(wetMixT, layerT, layerWeight) * newness, addedShare);
    ensureLatent(mixboxLUT, color.rgb, colorLatent, colorLatentValid);
    colorLatent = lerpLatent(colorLatent, tintLatent, float(depositT));
    substrate.g *= (1.0h - cov * newness);

    color.a = newAlpha;
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

    half depositLoad = cov * clamp(half(sr.strokeWetness), 0.0h, 1.0h);
    if (depositLoad > 0.005h) {
      half absorbencyRate;
      if      (isWash)     absorbencyRate = 0.10h;
      else if (isSplatter) absorbencyRate = 0.08h;
      else if (isDrip)     absorbencyRate = 0.06h;
      else if (isScumble)  absorbencyRate = 0.05h;
      else if (isKnife)    absorbencyRate = 0.01h;
      else                 absorbencyRate = 0.05h;
      half availableCapacity = 1.0h - substrate.r;
      half saturationGain = depositLoad * availableCapacity * absorbencyRate;
      substrate.r = saturate(substrate.r + saturationGain);
    }

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

  if (colorLatentValid) color.rgb = fromLatent(colorLatent);
  if (dryLatentValid)   dryColor.rgb = fromLatent(dryLatent);

  colorOut.write(color, gid);
  if (hwOwner) {
    heightWetOut.write(half4(height, wetness, permHeight, crackVis), hgid);
    dryColorOut.write(dryColor, hgid);
    substrateOut.write(substrate, hgid);
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
    constant uint2 &regionOrigin               [[buffer(4)]],
    uint2 tid [[thread_position_in_grid]])
{
  uint2 gid = tid + regionOrigin;
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

    float trailMask = smoothstep(-1.30, -0.50, alongT);
    float leadMask  = 1.0 - smoothstep(0.85, 1.30, alongT);
    float lengthMask = trailMask * leadMask;
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

    if (!simd_any(coverage > 0.01)) continue;

    if (coverage < 0.01) continue;

    float dy_dx = isS
                ?  amp * M_PI_F        * cos(alongT * M_PI_F)       * 0.5
                : -amp * M_PI_F * 0.5  * sin(alongT * M_PI_F * 0.5) * 0.5;
    float invNorm = rsqrt(1.0 + dy_dx * dy_dx);
    float2 tangentLocal = float2(1.0, dy_dx) * invNorm;
    float2 kdir = float2(tangentLocal.x * cs - tangentLocal.y * sn,
                         tangentLocal.x * sn + tangentLocal.y * cs);
    float2 kperpStraight = float2(-sn, cs);

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
    if (!isKnife) {
      if (wetGate < 0.01h) continue;
    }

    float speed = isKnife ? 0.0050 : 0.0025;

    float kPerpCoord = dot(p, kperpStraight);
    float kBristleSeed = kPerpCoord * 540.0;
    float kBristleNoise = fract(sin(kBristleSeed * 12.9898)
                                 * 43758.5453);
    float bristleMod = 0.55 + 0.45 * kBristleNoise;

    float2 kperpCurve = float2(-kdir.y, kdir.x);
    half edgeFactor = smoothstep(0.6h, 1.0h, half(abs(effAcrossT)));
    float fanSign = (effAcrossT > 0.0) ? 1.0 : -1.0;
    float2 fanVel = kperpCurve * (fanSign * 0.25 * float(edgeFactor));

    half velGate = isKnife ? 1.0h : wetGate;
    velocity += half2((kdir + fanVel) * speed * coverage
                      * float(velGate) * bristleMod);

    if (isKnife) {
      half kFlag = half(coverage * bristleMod);
      vSample.b = max(vSample.b, kFlag);
    }
  }

  half knifeFlag = vSample.b * 0.40h;

  half velMag = length(velocity);
  if (velMag > 0.012h) {
    velocity = velocity * (0.012h / velMag);
  }

  velocityOut.write(half4(velocity.x, velocity.y, knifeFlag, 0), gid);
}

kernel void abexResample(
    texture2d<half, access::sample> colorSrc     [[texture(0)]],
    texture2d<half, access::write>  colorDst     [[texture(1)]],
    texture2d<half, access::sample> hwSrc        [[texture(2)]],
    texture2d<half, access::write>  hwDst        [[texture(3)]],
    texture2d<half, access::sample> drySrc       [[texture(4)]],
    texture2d<half, access::write>  dryDst       [[texture(5)]],
    texture2d<half, access::sample> subSrc       [[texture(6)]],
    texture2d<half, access::write>  subDst       [[texture(7)]],
    texture2d<half, access::write>  velDst       [[texture(8)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint w = colorDst.get_width();
  uint h = colorDst.get_height();
  if (gid.x >= w || gid.y >= h) return;

  constexpr sampler s(coord::normalized,
                      address::clamp_to_edge,
                      filter::linear);

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  colorDst.write(colorSrc.sample(s, uv), gid);

  if ((gid.x & 1u) == 0u && (gid.y & 1u) == 0u) {
    uint2 hgid = gid >> 1;
    uint hw_w = hwDst.get_width();
    uint hw_h = hwDst.get_height();
    if (hgid.x < hw_w && hgid.y < hw_h) {
      float2 huv = (float2(hgid) + 0.5) / float2(hw_w, hw_h);
      hwDst.write(hwSrc.sample(s, huv), hgid);
      dryDst.write(drySrc.sample(s, huv), hgid);
      subDst.write(subSrc.sample(s, huv), hgid);
      velDst.write(half4(0.0h), hgid);
    }
  }
}

kernel void abexPigment(
    texture2d<half, access::read>    wet        [[texture(0)]],
    texture2d<half, access::sample>  dry        [[texture(1)]],
    texture2d<half, access::write>   pigmentOut [[texture(2)]],
    texture2d<float, access::sample> mixboxLUT  [[texture(3)]],
    constant AbExParams &params                 [[buffer(0)]],
    constant uint2 &regionOrigin                [[buffer(1)]],
    uint2 tid [[thread_position_in_grid]])
{
  uint2 gid = tid + regionOrigin;
  uint w = pigmentOut.get_width(), h = pigmentOut.get_height();
  if (gid.x >= w || gid.y >= h) return;
  constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

  half4 c  = wet.read(gid);
  half4 dc = dry.sample(s, (float2(gid) + 0.5) / float2(w, h));
  half3 ground = half3(params.canvas.xyz);
  half3 result = ground;
  if (dc.a > 0.002h || c.a > 0.002h) {
    mixbox_latent z = toLatent(mixboxLUT, ground);
    if (dc.a > 0.002h) {
      z = lerpLatent(z, toLatent(mixboxLUT, dc.rgb), float(saturate(dc.a)));
    }
    if (c.a > 0.002h) {
      z = lerpLatent(z, toLatent(mixboxLUT, c.rgb), float(saturate(c.a)));
    }
    result = fromLatent(z);
  }
  pigmentOut.write(half4(result, 1.0h), gid);
}

kernel void abexCompose(
                        texture2d<half, access::sample> color     [[texture(0)]],
                        texture2d<half, access::sample> heightWet [[texture(1)]],
                        texture2d<half, access::write>  output    [[texture(2)]],
                        texture2d<half, access::sample> dryColor  [[texture(3)]],
                        texture2d<half, access::sample> substrate [[texture(4)]],
                        texture2d<float, access::sample> mixboxLUT [[texture(5)]],
                        texture2d<half, access::sample>  crackTex  [[texture(6)]],
                        texture2d<half, access::sample>  pigment   [[texture(7)]],
                        constant AbExParams &params              [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{

  constexpr sampler hwSampler(coord::normalized,
                              address::clamp_to_edge,
                              filter::linear);

  uint dispW = output.get_width();
  uint dispH = output.get_height();
  if (gid.x >= dispW || gid.y >= dispH) return;

  float2 dispSize = float2(dispW, dispH);

  float2 displayPx = float2(gid) + 0.5;
  float2 dispUV = displayPx / dispSize;

  float2 coverScale = (dispSize.x >= dispSize.y)
                    ? float2(1.0, dispSize.y / dispSize.x)
                    : float2(dispSize.x / dispSize.y, 1.0);
  float2 uv = (dispUV - 0.5) * coverScale + 0.5;
  float2 centered = uv - 0.5;

  float panX = params.camera.x;
  float panY = params.camera.y;
  float zoom = params.camera.z;
  centered /= zoom;

  float2 uvAll = clamp(centered + float2(panX, panY) + 0.5, 0.0, 1.0);

  half4 c = color.sample(hwSampler, uvAll);

  float2 canvasPx = displayPx;

  half4 hwC = heightWet.sample(hwSampler, uvAll);
  half skin = substrate.sample(hwSampler, uvAll).g;
  half4 dc  = dryColor.sample(hwSampler, uvAll);
  float hC = max(float(hwC.r), float(hwC.b));
  half wetTotal = clamp(hwC.g, 0.0h, 1.0h);

  half totalA = saturate(c.a + dc.a * (1.0h - c.a));
  half hasPigment = smoothstep(0.02h, 0.15h, totalA);
  half lowImpasto = 1.0h - smoothstep(0.02h, 0.10h, half(hwC.b));
  half washAmt    = clamp(hasPigment * lowImpasto, 0.0h, 1.0h);

  half surfaceTexture     = max(0.02h, 1.0h - washAmt * 0.98h);
  half bumpSurfaceTexture = max(0.10h, 1.0h - washAmt * 0.90h);
  float bumpSurfaceF = float(bumpSurfaceTexture);

  float weaveIrr = canvasWeaveIrregularity(canvasPx);
  half  weave    = canvasWeave(canvasPx, weaveIrr);
  half3 canvasBaseRaw = half3(params.canvas.xyz) - weave;

  half3 result;
  if (dc.a <= 0.002h && c.a <= 0.002h) {
    result = canvasBaseRaw;
  } else {
    result = pigment.sample(hwSampler, uvAll).rgb - weave * (1.0h - totalA);
  }

  if (c.a < 0.005h && hC < 0.005) {
    output.write(half4(linearToSrgb(result), 1.0h), gid);
    return;
  }

  half setDryness = 1.0h - smoothstep(0.02h, 0.22h, wetTotal);
  result *= (1.0h - setDryness * 0.06h * smoothstep(0.05h, 0.30h, totalA));

  half granPaintMask = smoothstep(0.05h, 0.30h, c.a);
  if (granPaintMask > 0.005h) {
    half clumpNoise = half(shaderSimplex2D(canvasPx * 0.030));
    half grainNoise = half(shaderSimplex2D(canvasPx * 0.180));
    half wetSmoothness = smoothstep(0.05h, 0.45h, wetTotal);
    half granGate = granPaintMask * (1.0h - wetSmoothness * 0.65h);
    result *= 1.0h + (clumpNoise * 0.02h + grainNoise * 0.01h) * granGate;
  }

  half3 N;
  half  paintMask;
  float2 totalGrad;
  half  gmag;

  paintMask = smoothstep(0.05h, 0.30h, totalA);

  half dryness = 1.0h - clamp(wetTotal * 1.5h, 0.0h, 1.0h);
  half wetEffect = (1.0h - dryness) * paintMask;

  half weaveThroughPaint = weave * paintMask
                         * (1.0h - smoothstep(0.05h, 0.30h, half(hC)));
  result *= (1.0h - weaveThroughPaint * 0.6h);

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
  half ao = 1.0h - cavity * 0.08h * paintMask;
  result *= ao;

#if ABEX_CRACK_DARKENING
  half permH = half(hwC.b);
  half crackVis = clamp(hwC.a, 0.0h, 1.0h);
  if (crackVis > 0.04h && permH > 0.25h) {

    half regionA = half(shaderSimplex2D(canvasPx * 0.0008));
    half regionB = half(shaderSimplex2D(canvasPx * 0.0014 + 247.0));
    half maskA = smoothstep(0.10h, 0.50h, regionA);
    half maskB = smoothstep(0.05h, 0.45h, regionB);
    half crackProne = maskA * maskB;

    if (crackProne > 0.01h) {

      float n1 = shaderSimplex2D(canvasPx * 0.012);
      float n2 = shaderSimplex2D(canvasPx * 0.038 + 51.0) * 0.5;
      float crackField = n1 + n2;
      half crackLine = 1.0h - smoothstep(0.0h, 0.06h, half(abs(crackField)));

      half crackDepth = 0.5h
                     + 0.5h * half(shaderSimplex2D(canvasPx * 0.005 + 31.0));

      half coverFactor = mix(1.0h, 0.30h, wetTotal);

      half permEmphasis = 1.0h
                        + smoothstep(0.25h, 0.55h, permH) * 0.6h;

      half crackStrength = saturate(crackVis * crackLine * crackProne);
      if (crackStrength > 0.005h) {
        half darkenAmount = crackStrength * 0.75h * crackDepth
                          * coverFactor * permEmphasis;
        result *= (1.0h - darkenAmount * 0.30h);
      }
    }

    half hairGate = smoothstep(0.45h, 0.90h, permH)
                  * (1.0h - smoothstep(0.10h, 0.45h, wetTotal))
                  * smoothstep(0.50h, 0.90h, skin);
    if (hairGate > 0.01h) {
      constexpr sampler crackSampler(coord::normalized, address::repeat,
                                     filter::linear);
      float repeats = float(color.get_width()) / 512.0;
      float2 cuv = uvAll * float2(1.0, 0.72) * repeats;
      half2 edges = crackTex.sample(crackSampler, cuv).rg * 0.5h;
      half crackP = 1.0h - smoothstep(0.0h, 0.045h, edges.r);
      half crackS = 1.0h - smoothstep(0.0h, 0.070h, edges.g);
      half cured  = smoothstep(0.70h, 0.95h, skin);
      half network = max(crackP * 0.28h, crackS * 0.13h * cured);
      result *= (1.0h - network * hairGate);
    }
  }
#endif

  totalGrad = float2(pR - pL, pU - pD);
  gmag      = length(half2(half(pR - pL), half(pU - pD)));

  float gradFactor   = float(smoothstep(0.005h, 0.05h, gmag));
  float heightFactor = float(smoothstep(0.005h, 0.30h, half(pC)));
  float adaptiveBumpScale = mix(0.40, 1.0, gradFactor)
                          * mix(0.20, 1.0, heightFactor);
  float bump = params.config.w * bumpSurfaceF * adaptiveBumpScale
             * float(smoothstep(0.02h, 0.12h, totalA));

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

    half nx1 = half(shaderSimplex2D(dng * 0.025         )) * 0.38h;
    half ny1 = half(shaderSimplex2D(dng * 0.025 + 173.0 )) * 0.38h;

    half thickScale = pow(smoothstep(0.20h, 1.20h, half(hC)), 1.4h);
    half bodyAmp = paintMask * (0.10h + 0.50h * thickScale) * surfaceTexture;

    half skinAmp = skin * thickScale * paintMask * 0.08h;
    half wx = half(shaderSimplex2D(dng * 0.11 + 311.0));
    half wy = half(shaderSimplex2D(dng * 0.11 + 457.0));

    N = normalize(N + half3(nx1, ny1, 0.0h) * bodyAmp
                    + half3(wx, wy, 0.0h) * skinAmp);
  }

  float2 cvGrad = canvasWeaveGradient(ng, weaveIrr);
  half cvStrength = 0.45h * (1.0h - paintMask * 0.35h)
                  * (1.0h - smoothstep(0.05h, 0.35h, half(hC)));
  N = normalize(N + half3(half(-cvGrad.x), half(-cvGrad.y), 0.0h) * cvStrength);

  const half3 Ldir = normalize(half3(-0.45h, 0.60h, 0.65h));

  half ndl = max(0.0h, dot(N, Ldir));
  half hl  = 0.90h + 0.10h * ndl;

  const half3 warmLight  = half3(1.00h, 0.95h, 0.82h);
  const half3 coolShadow = half3(0.82h, 0.86h, 0.96h);
  half3 lightTint  = mix(coolShadow, warmLight, hl);

  half hl0 = 0.90h + 0.10h * Ldir.z;
  half3 flatResponse = mix(coolShadow, warmLight, hl0) * hl0;
  half3 rgb = result * (lightTint * hl) / flatResponse;

#if ABEX_ADDITIVE_HIGHLIGHTS
  const half3 V = half3(0.0h, 0.0h, 1.0h);
  const half3 H = normalize(Ldir + V);
  if (paintMask > 0.005h) {
    half ndh   = max(0.0h, dot(N, H));
    half NdotV = max(0.001h, N.z);
    half fresnel = pow(1.0h - NdotV, 5.0h);

    half expBroad  = 24.0h;
    half expTight  = 64.0h;
    half intensity = 1.0h;

    if (dirStrength > 0.05h) {
      float2 Hxy = float2(float(H.x), float(H.y));
      float HxyLen = length(Hxy);
      float2 HxyDir = (HxyLen > 0.001) ? Hxy / HxyLen : float2(1.0, 0.0);

      float perpAmt  = abs(dot(HxyDir, gdir));
      float alongAmt = abs(dot(HxyDir, gperp));

      expTight  = mix(48.0h, 140.0h, half(perpAmt)  * dirStrength);
      expBroad  = mix(16.0h,  32.0h, half(alongAmt) * dirStrength);
      intensity = mix(1.0h,  1.35h, dirStrength);
    }

    expTight *= (1.0h + wetTotal * 1.0h);
    half wetGain = 1.0h + wetTotal * 0.8h;

    half specGate = 1.0h - washAmt;

    half specBroad = pow(ndh, expBroad) * 0.05h;
    half specTight = pow(ndh, expTight) * 0.14h;
    half skinMatte = 1.0h - skin * 0.55h;
    half spec = (specBroad + specTight) * paintMask * intensity * wetGain
              * surfaceTexture * specGate * skinMatte;

    half3 specColor = mix(warmLight, result, 0.40h);
    rgb += spec * specColor * 0.55h * ABEX_HIGHLIGHT_SCALE;

    half F0 = mix(0.025h, 0.14h, wetTotal);
    half F  = (1.0h - F0) * fresnel;
    half grazingSheen = F * wetTotal * 0.35h * paintMask * surfaceTexture * specGate
                      * skinMatte;
    rgb += grazingSheen * warmLight * ABEX_HIGHLIGHT_SCALE;
  }
#endif

  int debugMode = int(params.camera.w + 0.5);
  if (debugMode == 1) {
    half wetLum = dot(c.rgb,  half3(0.2126h, 0.7152h, 0.0722h));
    half dryLum = dot(dc.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    half g = dot(saturate(rgb), half3(0.2126h, 0.7152h, 0.0722h));
    half3 flag = half3(g);
    if (dc.a > 0.03h && dryLum < 0.02h) flag = half3(0.0h, 1.0h, 1.0h);
    if (c.a  > 0.03h && wetLum < 0.02h) flag = half3(1.0h, 0.0h, 0.0h);
    rgb = flag;
  } else if (debugMode == 2) {
    rgb = half3(c.a, dc.a, wetTotal);
  }
  rgb = linearToSrgb(saturate(rgb));
  output.write(half4(rgb, 1.0h), gid);
}
