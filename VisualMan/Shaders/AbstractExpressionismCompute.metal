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

  float bristleHeight = mix(0.50, 1.40, bStrength);
  r.heightDelta = widthProfile * impastoLoad * lengthMask * baseOp
                * ridge * strokeWetness * bristleHeight;

  float grainVeryCoarse = shaderNoise(p *   90.0 + center * 5.0)  - 0.5;
  float grainMed        = shaderNoise(p *  300.0 + center * 10.0) - 0.5;
  float grainCoarse     = shaderNoise(p *  650.0 + center * 20.0) - 0.5;
  float grainFine       = shaderNoise(p * 2200.0 + seed * 3.7)    - 0.5;
  float grain = grainVeryCoarse * 0.40
              + grainMed        * 0.28
              + grainCoarse     * 0.20
              + grainFine       * 0.12;

  r.heightDelta *= (1.0 + grain * 0.95);
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
  if (typeRoll < 0.38) {
    mainHeight = 0.04 + typeRoll * 0.28;
  } else if (typeRoll < 0.75) {
    mainHeight = 0.48 + hash11(seed * 3.13) * 0.25;
  } else {
    mainHeight = 0.90 + hash11(seed * 5.71) * 0.30;
  }

  float heightFalloff = 1.0 - smoothstep(effR * 0.80, effR * 1.02, dist);
  float bleedEnd = effR * mix(1.70, 1.35, smoothstep(0.15, 0.70, mainHeight));
  float colorFalloff = 1.0 - smoothstep(effR * 1.02, bleedEnd, dist);

  float coverage = colorFalloff * baseOp;
  float h = heightFalloff * baseOp * mainHeight;

  float satR = radius * 0.20;
  for (int k = 0; k < 4; k++) {
    float kk = float(k) + seed * 3.11;
    float a  = hash11(kk) * 6.283185;
    float ring = radius * (1.3 + hash11(kk + 13.1) * 1.2);
    float sSize = satR * (0.4 + hash11(kk + 7.7) * 1.3);
    float2 sc = center + float2(cos(a), sin(a)) * ring;
    float sd = length(p - sc);

    float sHeight = 1.0 - smoothstep(sSize * 0.70, sSize * 1.00, sd);
    float sBleedEnd = sSize * mix(1.55, 1.25, smoothstep(0.15, 0.70, mainHeight));
    float sColor = 1.0 - smoothstep(sSize * 1.00, sBleedEnd, sd);
    if (sColor * baseOp > coverage) {
      coverage = sColor * baseOp;

      h        = sHeight * baseOp * mainHeight * 0.25;
    }
  }

  r.coverage    = coverage;
  r.acrossT     = dist / max(effR, 0.001);
  r.heightDelta = h;

  float terrainVeryCoarse = shaderNoise(p * 35.0  + seed * 2.3 ) - 0.5;
  float terrainCoarse     = shaderNoise(p * 90.0  + seed * 5.71) - 0.5;
  float splatGrainMed     = shaderNoise(p * 250.0 + seed * 7.0 ) - 0.5;
  float splatGrainFine    = shaderNoise(p * 800.0 + seed * 11.0) - 0.5;

  float heightVar = terrainVeryCoarse * 0.48
                  + terrainCoarse     * 0.30
                  + splatGrainMed     * 0.15
                  + splatGrainFine    * 0.10;

  float varStrength = 0.40 + mainHeight * 0.65;
  r.heightDelta *= (1.0 + heightVar * varStrength);

  float lipCenter = effR * 0.92;
  float lipWidth  = effR * 0.14;
  float lipDist   = abs(dist - lipCenter);
  float edgeLip   = (1.0 - smoothstep(0.0, lipWidth, lipDist))
                  * step(dist, effR * 1.02);
  float lipAmp    = 0.05 + mainHeight * 0.20;
  r.heightDelta  += edgeLip * lipAmp * baseOp;

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
    texture2d<half, access::read>  colorBackIn    [[texture(0)]],
    texture2d<half, access::write> colorBackOut   [[texture(1)]],
    texture2d<half, access::read>  colorMidIn     [[texture(2)]],
    texture2d<half, access::write> colorMidOut    [[texture(3)]],
    texture2d<half, access::read>  colorFrontIn   [[texture(4)]],
    texture2d<half, access::write> colorFrontOut  [[texture(5)]],
    texture2d<half, access::read>  heightBackIn   [[texture(6)]],
    texture2d<half, access::write> heightBackOut  [[texture(7)]],
    texture2d<half, access::read>  heightMFIn     [[texture(8)]],
    texture2d<half, access::write> heightMFOut    [[texture(9)]],
    constant AbExParams &params                   [[buffer(0)]],
    constant AbExStroke *strokes                  [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint w = colorBackOut.get_width();
  uint h = colorBackOut.get_height();
  if (gid.x >= w || gid.y >= h) return;

  float2 uv = (float2(gid) + 0.5) / float2(w, h);
  float2 p = uv - 0.5;

  bool isFirstFrame = params.config.y > 0.5;
  int  strokeCount  = int(params.config.z);
  half dryRate      = half(params.canvas.w);

  half4 back, mid, front;
  half  hBack, hMid, hFront;

  if (isFirstFrame) {
    back   = half4(0);
    mid    = half4(0);
    front  = half4(0);
    hBack  = 0.0h;
    hMid   = 0.0h;
    hFront = 0.0h;
  } else {
    back   = colorBackIn.read(gid);
    mid    = colorMidIn.read(gid);
    front  = colorFrontIn.read(gid);
    hBack  = heightBackIn.read(gid).r;

    half2 hMF = heightMFIn.read(gid).rg;
    hMid   = hMF.r;
    hFront = hMF.g;

    {
      half aPres = smoothstep(0.15h, 0.85h, back.a);
      half tPres = smoothstep(0.05h, 0.40h, hBack);
      half pres  = min(aPres, tPres);
      half df    = 1.0h - dryRate * (1.0h - pres);
      back.a *= df;
      hBack  *= df;
    }
    {
      half aPres = smoothstep(0.15h, 0.85h, mid.a);
      half tPres = smoothstep(0.05h, 0.40h, hMid);
      half pres  = min(aPres, tPres);
      half df    = 1.0h - dryRate * (1.0h - pres);
      mid.a *= df;
      hMid  *= df;
    }
    {
      half aPres = smoothstep(0.15h, 0.85h, front.a);
      half tPres = smoothstep(0.05h, 0.40h, hFront);
      half pres  = min(aPres, tPres);
      half df    = 1.0h - dryRate * (1.0h - pres);
      front.a *= df;
      hFront  *= df;
    }
  }

  for (int i = 0; i < strokeCount && i < 8; i++) {
    float type = strokes[i].sizeOpacity.w;
    StrokeResult sr;
    if (type < 0.5)      sr = evaluateGestural(p, strokes[i]);
    else if (type < 1.5) sr = evaluateWash(p, strokes[i]);
    else                 sr = evaluateSplatter(p, strokes[i]);

    bool isWash     = (type >= 0.5 && type < 1.5);
    bool isGestural = (type < 0.5);

    half totalH = hBack + hMid + hFront;

    if (!isWash) {
      float resistanceMult = isGestural ? 1.6 : 1.0;
      float resistanceCap  = isGestural ? 0.65 : 0.50;
      float resistance     = clamp(float(totalH) * resistanceMult, 0.0, resistanceCap);
      float adhesion       = 1.0 - resistance;

      sr.coverage    *= adhesion;
      sr.heightDelta *= adhesion;

      if (isGestural) {
        float perturb  = float(i) * 17.3 + strokes[i].sizeOpacity.z * 0.03;
        float microVar = shaderNoise(p * 400.0 + float2(perturb * 13.0,
                                                         perturb * 7.0));
        float microMod = 0.78 + microVar * 0.44;
        sr.coverage *= microMod;
      }
    }

    if (sr.coverage < 0.002) continue;

    if (!isWash) {
      float brushId = strokes[i].sizeOpacity.z;
      float heightVar;
      if (isGestural) {

        float sAng = strokes[i].posAngle.z;
        float2 pRel = p - strokes[i].posAngle.xy;
        float cA = cos(sAng);
        float sA = sin(sAng);
        float along  =  pRel.x * cA + pRel.y * sA;
        float across = -pRel.x * sA + pRel.y * cA;

        float n = shaderNoise(float2(across * 520.0 + brushId * 7.0,
                                     along  * 42.0  + brushId * 13.0));
        heightVar = 0.70 + n * 0.60;
      } else {

        float2 spRel = p - strokes[i].posAngle.xy;
        float n = shaderNoise(spRel * 85.0
                              + float2(brushId * 7.0, brushId * 13.0));
        heightVar = 0.80 + n * 0.40;
      }
      sr.heightDelta *= heightVar;
    }

    half3 tint = strokeTint(strokes[i], sr);
    half  cov  = half(sr.coverage);
    half  hd   = half(sr.heightDelta);

    if (isWash) {
      half oldAmount = back.a * (1.0h - cov);
      half total     = oldAmount + cov;
      back.rgb = (back.rgb * oldAmount + tint * cov) / max(total, 0.001h);
      back.a   = total;
      hBack    = min(hBack + hd, 1.0h);
    } else if (isGestural) {
      half oldAmount = mid.a * (1.0h - cov);
      half total     = oldAmount + cov;
      mid.rgb = (mid.rgb * oldAmount + tint * cov) / max(total, 0.001h);
      mid.a   = total;
      hMid    = min(hMid + hd, 1.0h);
    } else {
      half oldAmount = front.a * (1.0h - cov);
      half total     = oldAmount + cov;
      front.rgb = (front.rgb * oldAmount + tint * cov) / max(total, 0.001h);
      front.a   = total;
      hFront    = min(hFront + hd, 1.0h);
    }
  }

  if (hBack  < 0.004h) hBack  = 0.0h;
  if (hMid   < 0.004h) hMid   = 0.0h;
  if (hFront < 0.004h) hFront = 0.0h;

  back.a  = clamp(back.a,  0.0h, 1.0h);
  mid.a   = clamp(mid.a,   0.0h, 1.0h);
  front.a = clamp(front.a, 0.0h, 1.0h);

  colorBackOut.write(back, gid);
  colorMidOut.write(mid, gid);
  colorFrontOut.write(front, gid);
  heightBackOut.write(half4(hBack, 0, 0, 0), gid);
  heightMFOut.write(half4(hMid, hFront, 0, 0), gid);
}

kernel void abexCompose(
    texture2d<half, access::read>  colorBack   [[texture(0)]],
    texture2d<half, access::read>  colorMid    [[texture(1)]],
    texture2d<half, access::read>  colorFront  [[texture(2)]],
    texture2d<half, access::read>  heightBack  [[texture(3)]],
    texture2d<half, access::read>  heightMF    [[texture(4)]],
    texture2d<half, access::write> output      [[texture(5)]],
    constant AbExParams &params                [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
  uint dispW = output.get_width();
  uint dispH = output.get_height();
  if (gid.x >= dispW || gid.y >= dispH) return;

  uint canvW = colorBack.get_width();
  uint canvH = colorBack.get_height();
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

  half4 back  = colorBack.read(pxAll);
  half4 mid   = colorMid.read(pxAll);
  half4 front = colorFront.read(pxAll);

  half3 canvasBase = half3(params.canvas.xyz) - canvasWeave(canvasPx);

  half3 result = canvasBase;
  result = mix(result, back.rgb,  back.a);
  result = mix(result, mid.rgb,   mid.a);
  result = mix(result, front.rgb, front.a);

  int2 hxL = clamp(int2(pxAll) + int2(-1,  0), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxR = clamp(int2(pxAll) + int2( 1,  0), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxD = clamp(int2(pxAll) + int2( 0, -1), int2(0), int2(canvW - 1, canvH - 1));
  int2 hxU = clamp(int2(pxAll) + int2( 0,  1), int2(0), int2(canvW - 1, canvH - 1));

  float bC = float(heightBack.read(pxAll).r);

  half2 mfC = heightMF.read(pxAll).rg;
  half2 mfL = heightMF.read(uint2(hxL)).rg;
  half2 mfR = heightMF.read(uint2(hxR)).rg;
  half2 mfD = heightMF.read(uint2(hxD)).rg;
  half2 mfU = heightMF.read(uint2(hxU)).rg;

  float mC = float(mfC.r), fC = float(mfC.g);
  float mL = float(mfL.r), fL = float(mfL.g);
  float mR = float(mfR.r), fR = float(mfR.g);
  float mD = float(mfD.r), fD = float(mfD.g);
  float mU = float(mfU.r), fU = float(mfU.g);

  float hC = bC + mC + fC;
  float hL = bC + mL + fL;
  float hR = bC + mR + fR;
  float hD = bC + mD + fD;
  float hU = bC + mU + fU;

  float bump = params.config.w;

  half maxGrad = 0.18h;
  half gradX = clamp(half(hR - hL), -maxGrad, maxGrad);
  half gradY = clamp(half(hU - hD), -maxGrad, maxGrad);
  half3 N = normalize(half3(-gradX * half(bump), -gradY * half(bump), 1.0h));

  float2 midGrad = float2(mR - mL, mU - mD);

  half paintMask = smoothstep(0.02h, 0.15h, half(hC));

  float2 ng = canvasPx;

  if (paintMask > 0.005h) {

    half activity   = 0.40h + 0.60h * half(shaderNoise(ng * 0.022 + 313.0));
    half styleRidge = smoothstep(0.30h, 0.75h,
                                 half(shaderNoise(ng * 0.015 + 811.0)));

    float2 warp = float2(
      shaderSimplex2D(ng * 0.040 + 211.0),
      shaderSimplex2D(ng * 0.040 + 397.0)
    ) * 11.0;
    float2 wng = ng + warp;

    float midGmag = length(midGrad);
    float2 gdir = (midGmag > 0.001) ? (midGrad / midGmag) : float2(1.0, 0.0);
    float2 gperp = float2(-gdir.y, gdir.x);
    half dirStrength = half(smoothstep(0.003, 0.05, midGmag));

    float sAlong  = float(mix(1.0h, 1.55h, dirStrength));
    float sAcross = float(mix(1.0h, 0.65h, dirStrength));

    float u = dot(wng, gdir)  * sAlong;
    float v = dot(wng, gperp) * sAcross;
    float2 dng = gdir * u + gperp * v;

    half nx1 = half(shaderSimplex2D(dng * 0.233         )) * 0.5h;
    half ny1 = half(shaderSimplex2D(dng * 0.233 + 173.0 )) * 0.5h;
    half nx2 = half(shaderSimplex2D(dng * 0.547 +  61.0 )) * 0.5h;
    half ny2 = half(shaderSimplex2D(dng * 0.547 + 239.0 )) * 0.5h;

    half rgx = abs(half(shaderSimplex2D(dng * 0.379 + 413.0))) - 0.5h;
    half rgy = abs(half(shaderSimplex2D(dng * 0.379 + 587.0))) - 0.5h;

    half thickScale = smoothstep(0.04h, 0.55h, half(hC));
    half bodyAmp = paintMask * activity * (0.22h + 0.38h * thickScale);

    half smW = mix(0.70h, 0.35h, styleRidge);
    half rgW = mix(0.35h, 0.70h, styleRidge);

    half px = (nx1 * 0.60h + nx2 * 0.40h) * smW + rgx * rgW;
    half py = (ny1 * 0.60h + ny2 * 0.40h) * smW + rgy * rgW;
    N = normalize(N + half3(px, py, 0.0h) * bodyAmp);

    half fn1 = half(shaderNoise(ng * 1.63 + 671.0)) - 0.5h;
    half fn2 = half(shaderNoise(ng * 1.63 + 829.0)) - 0.5h;
    N = normalize(N + half3(fn1, fn2, 0.0h) * paintMask * 0.08h);
  }

  float2 cvGrad = canvasWeaveGradient(ng);
  half cvStrength = 0.35h * (1.0h - paintMask * 0.70h);
  N = normalize(N + half3(half(-cvGrad.x), half(-cvGrad.y), 0.0h) * cvStrength);

  half cg1 = half(shaderNoise(ng * 1.6)        ) - 0.5h;
  half cg2 = half(shaderNoise(ng * 1.6 + 91.0) ) - 0.5h;
  N = normalize(N + half3(cg1, cg2, 0.0h) * 0.045h * (1.0h - paintMask));

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

    half specBroad = pow(ndh, 6.0h)  * 0.18h;
    half specTight = pow(ndh, 16.0h) * 0.14h;
    half spec = (specBroad + specTight) * paintMask;

    half3 specColor = mix(warmLight, result, 0.90h);
    rgb += spec * specColor * 0.40h;
  }

  half gmag = length(half2(half(hR - hL), half(hU - hD)));
  half rim  = smoothstep(0.12h, 0.45h, gmag) * paintMask;
  rgb -= rim * 0.08h * result;

  rgb = saturate(rgb);
  output.write(half4(rgb, 1.0h), gid);
}
