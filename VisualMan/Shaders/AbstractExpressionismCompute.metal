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
  float fiber = shaderNoise(pixelPos * 0.18);
  float irregular = shaderNoise(pixelPos * 0.04);
  return half(weave * 0.045 + fiber * 0.020 + irregular * 0.012);
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

struct StrokeResult {
  float coverage;
  float heightDelta;
  float alongNorm;
  float acrossT;
  float bristleTone;
};

inline StrokeResult evaluateGestural(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;

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
  wob += (shaderNoise(float2(alongT * 2.2, seed)) - 0.5) * 0.35;
  acrossT += wob;

  float sAlong = (alongT + 1.0) * 0.5;

  float wetRoll = hash11(seed * 2.39);
  float paintLoadScale;
  float strokeWetness;
  float baselineDryness;
  if (wetRoll < 0.35) {
    paintLoadScale  = 0.55;
    strokeWetness   = 0.12 + wetRoll * 0.48;
    baselineDryness = 0.55;
  } else if (wetRoll < 0.75) {
    paintLoadScale  = 0.95 + hash11(seed * 3.71) * 0.10;
    strokeWetness   = 0.70 + hash11(seed * 3.71) * 0.35;
    baselineDryness = 0.0;
  } else {
    paintLoadScale  = 1.00;
    strokeWetness   = 1.15 + hash11(seed * 5.83) * 0.40;
    baselineDryness = -0.20;
  }

  float paintLoad = exp(-sAlong * 1.5) + 0.22;
  paintLoad = min(paintLoad * paintLoadScale, 1.0);

  float impastoLoad = exp(-sAlong * 3.8);
  impastoLoad += exp(-sAlong * 10.0) * 0.25;

  float dryness = clamp(smoothstep(0.15, 0.95, sAlong) + baselineDryness, 0.0, 1.0);

  float startTaper = smoothstep(-1.10, -0.88, alongT);
  float endTaper   = smoothstep(1.25, 0.30, alongT);
  float lengthMask = startTaper * endTaper;

  float widthProfile = 1.0 - smoothstep(0.70, 1.10, abs(acrossT));
  widthProfile *= widthProfile;

  float bristleCount = clamp(halfWd * 900.0, 8.0, 28.0);
  float bristlePhase = acrossT * bristleCount + seed * 53.0;
  float bristleId    = floor(bristlePhase);
  float bInB         = fract(bristlePhase);
  float bStrength    = mix(0.3, 1.0, hash11(bristleId + seed * 7.13));
  float bProfile     = 1.0 - abs(bInB - 0.5) * 2.0;
  bProfile           = pow(max(bProfile, 0.0), 0.55);

  float dryNoise  = shaderNoise(float2(alongT * 5.5 + seed, bristleId * 0.37));
  float dryThresh = mix(0.12, 0.62, dryness);
  float dry       = smoothstep(dryThresh, dryThresh + 0.25, dryNoise);

  float bristleAmount = bStrength * bProfile * dry;

  float core = widthProfile * paintLoad * lengthMask * baseOp
             * (1.0 - smoothstep(0.45, 0.92, abs(acrossT))) * 0.40;
  float bristleCov = widthProfile * paintLoad * lengthMask * baseOp * bristleAmount;
  float coverage = max(core, bristleCov);

  if (coverage < 0.002) return r;

  r.coverage    = coverage;
  r.alongNorm   = sAlong;
  r.acrossT     = acrossT;
  r.bristleTone = (bStrength - 0.65) * 1.4;

  float ridge = 0.30 + 0.9 * pow(bProfile, 0.75);
  r.heightDelta = widthProfile * impastoLoad * lengthMask * baseOp * ridge * strokeWetness;

  float grainMed    = shaderNoise(p * 300.0  + center * 10.0) - 0.5;
  float grainCoarse = shaderNoise(p * 650.0  + center * 20.0) - 0.5;
  float grainFine   = shaderNoise(p * 2200.0 + seed * 3.7)    - 0.5;
  float grain = grainMed * 0.40 + grainCoarse * 0.40 + grainFine * 0.30;

  r.heightDelta *= (1.0 + grain * 0.80);
  r.heightDelta = max(r.heightDelta, 0.0);

  return r;
}

inline StrokeResult evaluateWash(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;

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

  if (rr > 1.5) return r;

  float n1 = shaderNoise(p * 2.5 + center * 5.0) - 0.5;
  float n2 = shaderNoise(p * 7.0 + center * 11.0 + seed) - 0.5;
  float n3 = shaderNoise(p * 18.0 + seed * 7.0) - 0.5;
  float boundary = 1.0 + n1 * 0.50 + n2 * 0.28 + n3 * 0.14;

  float normR = rr / max(boundary, 0.01);
  float falloff = 1.0 - smoothstep(0.25, 1.05, normR);
  falloff = pow(max(falloff, 0.0), 1.2);

  float densA = shaderNoise(p * 4.5 + center * 3.0);
  float densB = shaderNoise(p * 13.0 + seed * 2.3);
  float density = 0.65 + densA * 0.45 + densB * 0.18;
  falloff *= density;

  float edgeZone = smoothstep(0.55, 0.82, normR) * (1.0 - smoothstep(0.88, 1.10, normR));
  float poolNoise = shaderNoise(p * 28.0 + seed) * 0.5 + 0.5;
  float washExists = smoothstep(0.02, 0.25, falloff);
  falloff += edgeZone * poolNoise * 0.40 * washExists;

  float grain = shaderNoise(p * 380.0 + seed) - 0.5;
  falloff *= (1.0 + grain * 0.20);

  float grain2 = shaderNoise(p * 1200.0 + seed * 3.7) - 0.5;
  falloff *= (1.0 + grain2 * 0.10);

  falloff = clamp(falloff, 0.0, 1.35);

  r.coverage    = falloff * baseOp;
  r.alongNorm   = 0.5;
  r.acrossT     = normR;
  r.bristleTone = grain * 0.4;
  r.heightDelta = 0;
  return r;
}

inline StrokeResult evaluateSplatter(float2 p, constant AbExStroke &s) {
  StrokeResult r; r.coverage = 0; r.heightDelta = 0;
  r.alongNorm = 0; r.acrossT = 0; r.bristleTone = 0;

  float2 center = s.posAngle.xy;
  float radius  = max(s.posAngle.w, 0.002);
  float baseOp  = s.sizeOpacity.y;
  float seed    = s.sizeOpacity.z;

  float2 d = p - center;
  float dist = length(d);

  if (dist > radius * 3.0) return r;

  float ang = atan2(d.y, d.x);
  float nLobe = 3.0 + floor(hash11(seed * 1.31) * 4.0);
  float lobe = sin(ang * nLobe + seed * 11.0) * 0.18
             + cos(ang * (nLobe + 2.0) + seed * 7.0) * 0.10;
  float en = (shaderNoise(float2(ang * 2.0, seed * 3.0)) - 0.5) * 0.3;
  float effR = radius * (1.0 + lobe + en);

  float typeRoll = hash11(seed * 1.77);
  float mainHeight;
  float grainAmount;
  if (typeRoll < 0.38) {
    mainHeight  = 0.04 + typeRoll * 0.28;
    grainAmount = 0.90;
  } else if (typeRoll < 0.75) {
    mainHeight  = 0.48 + hash11(seed * 3.13) * 0.25;
    grainAmount = 0.65;
  } else {
    mainHeight  = 0.90 + hash11(seed * 5.71) * 0.30;
    grainAmount = 0.30;
  }

  float falloff = 1.0 - smoothstep(effR * 0.80, effR * 1.02, dist);
  float coverage = falloff * baseOp;
  float h = coverage * mainHeight;

  float satR = radius * 0.20;
  for (int k = 0; k < 4; k++) {
    float kk = float(k) + seed * 3.11;
    float a  = hash11(kk) * 6.283185;
    float ring = radius * (1.3 + hash11(kk + 13.1) * 1.2);
    float sSize = satR * (0.4 + hash11(kk + 7.7) * 1.3);
    float2 sc = center + float2(cos(a), sin(a)) * ring;
    float sd = length(p - sc);
    float sf = 1.0 - smoothstep(sSize * 0.70, sSize * 1.0, sd);
    if (sf * baseOp > coverage) {
      coverage = sf * baseOp;
      h        = coverage * mainHeight * 0.80;
    }
  }

  r.coverage    = coverage;
  r.acrossT     = dist / max(effR, 0.001);
  r.heightDelta = h;

  float splatGrainCoarse = shaderNoise(p * 250.0 + seed * 7.0)  - 0.5;
  float splatGrainFine   = shaderNoise(p * 800.0 + seed * 11.0) - 0.5;
  float splatGrain = splatGrainCoarse * 0.55 + splatGrainFine * 0.45;
  r.heightDelta *= (1.0 + splatGrain * grainAmount);
  r.heightDelta = max(r.heightDelta, 0.0);

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
    texture2d<half, access::read>  colorBackIn   [[texture(0)]],
    texture2d<half, access::write> colorBackOut  [[texture(1)]],
    texture2d<half, access::read>  colorMidIn    [[texture(2)]],
    texture2d<half, access::write> colorMidOut   [[texture(3)]],
    texture2d<half, access::read>  colorFrontIn  [[texture(4)]],
    texture2d<half, access::write> colorFrontOut [[texture(5)]],
    texture2d<half, access::read>  heightIn      [[texture(6)]],
    texture2d<half, access::write> heightOut     [[texture(7)]],
    constant AbExParams &params                  [[buffer(0)]],
    constant AbExStroke *strokes                 [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint w = colorBackOut.get_width();
  uint h = colorBackOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float aspect = float(w) / float(h);
  float2 p = (uv - 0.5) * float2(aspect, 1.0);

  bool isFirstFrame = params.config.y > 0.5;
  int  strokeCount  = int(params.config.z);
  half dryRate      = half(params.canvas.w);

  half4 back, mid, front;
  half  height;

  if (isFirstFrame) {
    back  = half4(0);
    mid   = half4(0);
    front = half4(0);
    height = 0.0h;
  } else {
    back   = colorBackIn.read(gid);
    mid    = colorMidIn.read(gid);
    front  = colorFrontIn.read(gid);
    height = heightIn.read(gid).r;

    half decay = 1.0h - dryRate;
    back  *= decay;
    mid   *= decay;
    front *= decay;

    half preservation = 0.9994h + smoothstep(0.0h, 0.7h, height) * 0.0005h;
    height *= preservation;
  }

  for (int i = 0; i < strokeCount && i < 8; i++) {
    float type = strokes[i].sizeOpacity.w;
    StrokeResult sr;
    if (type < 0.5)      sr = evaluateGestural(p, strokes[i]);
    else if (type < 1.5) sr = evaluateWash(p, strokes[i]);
    else                 sr = evaluateSplatter(p, strokes[i]);

    bool isWash = (type >= 0.5 && type < 1.5);

    if (!isWash) {
      bool isGestural = (type < 0.5);
      float resistanceMult = isGestural ? 1.6 : 1.0;
      float resistanceCap  = isGestural ? 0.65 : 0.50;
      float resistance     = clamp(float(height) * resistanceMult, 0.0, resistanceCap);
      float adhesion       = 1.0 - resistance;

      float perturb  = float(i) * 17.3 + strokes[i].sizeOpacity.z * 0.03;
      float microVar = shaderNoise(p * 400.0 + float2(perturb * 13.0,
                                                       perturb * 7.0));
      float microMod = 0.78 + microVar * 0.44;

      sr.coverage    *= adhesion * microMod;
      sr.heightDelta *= adhesion;
    }

    if (sr.coverage < 0.002) continue;

    half3 tint = strokeTint(strokes[i], sr);
    half  cov  = half(sr.coverage);

    if (isWash) {
      half effective = cov * (1.0h - back.a);
      back.rgb += tint * effective;
      back.a   += effective;
    } else if (type < 0.5) {
      half effective = cov * (1.0h - mid.a);
      mid.rgb += tint * effective;
      mid.a   += effective;
    } else {
      half effective = cov * (1.0h - front.a);
      front.rgb += tint * effective;
      front.a   += effective;
    }

    height = min(height + half(sr.heightDelta), 1.0h);
  }

  if (height < 0.004h) height = 0.0h;

  back.a  = clamp(back.a,  0.0h, 1.0h);
  mid.a   = clamp(mid.a,   0.0h, 1.0h);
  front.a = clamp(front.a, 0.0h, 1.0h);

  colorBackOut.write(back, gid);
  colorMidOut.write(mid, gid);
  colorFrontOut.write(front, gid);
  heightOut.write(half4(height, 0, 0, 0), gid);
}

kernel void abexCompose(
    texture2d<half, access::read>  colorBack  [[texture(0)]],
    texture2d<half, access::read>  colorMid   [[texture(1)]],
    texture2d<half, access::read>  colorFront [[texture(2)]],
    texture2d<half, access::read>  heightTex  [[texture(3)]],
    texture2d<half, access::write> output     [[texture(4)]],
    constant AbExParams &params               [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint w = output.get_width();
  uint h = output.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 size = float2(w, h);
  float2 uv = (float2(gid) + 0.5) / size;
  float2 centered = uv - 0.5;

  float panX = params.camera.x;
  float panY = params.camera.y;
  float zoom = params.camera.z;
  centered /= zoom;

  const float pBack   = 0.25;
  const float pMid    = 0.55;
  const float pFront  = 1.00;
  const float pHeight = 0.70;

  float2 uvBack   = clamp(centered + float2(panX, panY) * pBack   + 0.5, 0.0, 1.0);
  float2 uvMid    = clamp(centered + float2(panX, panY) * pMid    + 0.5, 0.0, 1.0);
  float2 uvFront  = clamp(centered + float2(panX, panY) * pFront  + 0.5, 0.0, 1.0);
  float2 uvHeight = clamp(centered + float2(panX, panY) * pHeight + 0.5, 0.0, 1.0);

  uint2 pxBack   = min(uint2(uvBack   * size), uint2(w - 1, h - 1));
  uint2 pxMid    = min(uint2(uvMid    * size), uint2(w - 1, h - 1));
  uint2 pxFront  = min(uint2(uvFront  * size), uint2(w - 1, h - 1));
  uint2 pxHeight = min(uint2(uvHeight * size), uint2(w - 1, h - 1));

  half4 back  = colorBack.read(pxBack);
  half4 mid   = colorMid.read(pxMid);
  half4 front = colorFront.read(pxFront);

  half3 canvasBase = half3(params.canvas.xyz) - canvasWeave(float2(gid));

  half3 result = canvasBase;
  result = back.rgb  + result * (1.0h - back.a);
  result = mid.rgb   + result * (1.0h - mid.a);
  result = front.rgb + result * (1.0h - front.a);

  float hC = float(heightTex.read(pxHeight).r);
  int2 hxL = clamp(int2(pxHeight) + int2(-1,  0), int2(0), int2(w - 1, h - 1));
  int2 hxR = clamp(int2(pxHeight) + int2( 1,  0), int2(0), int2(w - 1, h - 1));
  int2 hxD = clamp(int2(pxHeight) + int2( 0, -1), int2(0), int2(w - 1, h - 1));
  int2 hxU = clamp(int2(pxHeight) + int2( 0,  1), int2(0), int2(w - 1, h - 1));

  float hL = float(heightTex.read(uint2(hxL)).r);
  float hR = float(heightTex.read(uint2(hxR)).r);
  float hD = float(heightTex.read(uint2(hxD)).r);
  float hU = float(heightTex.read(uint2(hxU)).r);

  float bump = params.config.w;
  float3 N = normalize(float3((hL - hR) * bump, (hD - hU) * bump, 1.0));

  float paintMask = smoothstep(0.06, 0.32, hC);

  float2 ng = float2(gid);
  float dn1 = shaderNoise(ng * 0.42)         - 0.5;
  float dn2 = shaderNoise(ng * 0.42 + 173.0) - 0.5;
  N = normalize(N + float3(dn1, dn2, 0.0) * (paintMask * 0.45));

  float thickMask = smoothstep(0.40, 0.85, hC);
  float cr1 = shaderNoise(ng * 1.15 + 37.0) - 0.5;
  float cr2 = shaderNoise(ng * 2.70 + 91.0) - 0.5;
  N = normalize(N + float3(cr1, cr2, 0.0) * (thickMask * 0.38));

  float2 cvGrad = canvasWeaveGradient(ng);
  float cvStrength = 0.35 * (1.0 - paintMask * 0.70);
  N = normalize(N + float3(-cvGrad.x, -cvGrad.y, 0.0) * cvStrength);

  float cg1 = shaderNoise(ng * 1.6)        - 0.5;
  float cg2 = shaderNoise(ng * 1.6 + 91.0) - 0.5;
  N = normalize(N + float3(cg1, cg2, 0.0) * 0.045 * (1.0 - paintMask));

  float3 Ldir = normalize(float3(-0.45, 0.60, 0.65));
  float3 V    = float3(0.0, 0.0, 1.0);
  float3 H    = normalize(Ldir + V);

  float ndl = max(0.0, dot(N, Ldir));
  float hl  = 0.55 + 0.45 * ndl;
  float ndh = max(0.0, dot(N, H));

  float specBroad = pow(ndh, 8.0)  * 0.35;
  float specTight = pow(ndh, 64.0) * 0.45;
  float spec = (specBroad + specTight) * paintMask;

  float3 warmLight  = float3(1.00, 0.95, 0.82);
  float3 coolShadow = float3(0.82, 0.86, 0.96);
  float3 lightTint  = mix(coolShadow, warmLight, hl);

  float3 rgb = float3(result) * lightTint * hl;
  rgb += spec * warmLight * 0.55;

  float gmag = length(float2(hR - hL, hU - hD));
  float rim  = smoothstep(0.12, 0.45, gmag) * paintMask;
  rgb -= rim * 0.08 * float3(result);

  rgb = saturate(rgb);
  output.write(half4(half3(rgb), 1.0h), gid);
}
