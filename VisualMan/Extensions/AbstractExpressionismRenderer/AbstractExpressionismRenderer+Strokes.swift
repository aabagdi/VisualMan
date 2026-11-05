//
//  AbstractExpressionismRenderer+Strokes.swift
//  VisualMan
//
//  Created by on 4/24/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  func appendGesturalStroke(to strokes: inout [AbExStroke],
                            energy: Float,
                            focus: SIMD2<Float>,
                            spread: Float) {
    let isOutlier = nextSeed() < 0.28
    var pos: SIMD2<Float>
    if isOutlier {
      pos = SIMD2((nextSeed() - 0.5) * 1.00, (nextSeed() - 0.5) * 1.05)
    } else {
      let suggested = SIMD2(focus.x + (nextSeed() - 0.5) * 0.88 * spread,
                            focus.y + (nextSeed() - 0.5) * 0.92 * spread)
      pos = applyDensityBias(at: suggested, dispersion: 0.30)
    }
    if !isOutlier {
      guard attentionStrength(at: pos) > 0.45 else { return }
    }
    lastGesturalTime = wallClock
    let local = localStrokeAngle(at: pos)
    let suggestedAngle = (nextSeed() < 0.78)
      ? local + (nextSeed() - 0.5) * 0.5
      : nextSeed() * .pi * 2

    let gestured: (pos: SIMD2<Float>, angle: Float)
    if isOutlier {
      gestured = (pos: pos, angle: suggestedAngle)
      currentGestureRemaining = 0
    } else {
      gestured = sampleGesturedStroke(suggestedPos: pos,
                                       suggestedAngle: suggestedAngle,
                                       continueProb: 0.70)
    }
    let x = gestured.pos.x, y = gestured.pos.y
    let angle = gestured.angle
    let halfLen = 0.13 + energy * 0.22 + nextSeed() * 0.09
    let halfWidth = 0.012 + energy * 0.016 + nextSeed() * 0.008
    let opacity = 0.84 + energy * 0.16
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased(at: SIMD2(x, y))
    let dur = pickDurability(permanentChance: 0.03, stickyChance: 0.15)
    let curvature = pickCurvature(zeroChance: 0.30, midThreshold: 0.65,
                                   ampBase: 0.25, ampJitter: 0.40)
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: 0, durability: dur)),
      animation: SIMD4(0, 1, 0, curvature)))
    depositFlow(at: gestured.pos, angle: angle, weight: 0.5 + energy * 0.5)
    depositDensity(at: gestured.pos, weight: 0.85 + energy * 0.4)
  }

  func appendRogueStroke(to strokes: inout [AbExStroke], energy: Float) {
    guard strokes.count < Self.maxStrokesPerFrame, nextSeed() < perFrameChance(0.0012) else { return }
    let x = (nextSeed() - 0.5) * 1.05
    let y = (nextSeed() - 0.5) * 1.10
    let angle = nextSeed() * .pi * 2
    let typeRoll = nextSeed()
    let color = pickColorBiased(at: SIMD2(x, y))
    if typeRoll < 0.55 {
      let halfLen = 0.10 + nextSeed() * 0.22
      let halfWidth = 0.009 + nextSeed() * 0.010
      let opacity: Float = 0.70 + nextSeed() * 0.20
      let bristleSeed = nextSeed() * 100
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, halfLen),
        sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
        color: SIMD4(color.x, color.y, color.z, 0),
        animation: SIMD4(0, 1, 0, 0)))
    } else {
      let radius = 0.006 + nextSeed() * 0.014
      let opacity: Float = 0.85 + nextSeed() * 0.15
      let bristleSeed = nextSeed() * 100
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, 0, radius),
        sizeOpacity: SIMD4(radius, opacity, bristleSeed, 2),
        color: SIMD4(color.x, color.y, color.z, 0),
        animation: SIMD4(0, 1, 0, 0)))
    }
  }

  func appendPollockTrails(to strokes: inout [AbExStroke],
                           energy: Float,
                           focus: SIMD2<Float>) {
    guard energy > 0.04, strokes.count < Self.maxStrokesPerFrame,
          (wallClock - lastPollockTime) > 3.2 else { return }
    lastPollockTime = wallClock
    pollockEventCounter &+= 1
    let canvasIsEmpty = wallClock < 5.0
    let trailColor: SIMD3<Float>
    if canvasIsEmpty {
      trailColor = Self.srgbToLinear(SIMD3(0.02, 0.02, 0.02))
    } else {
      switch pollockEventCounter % 3 {
      case 0:  trailColor = Self.srgbToLinear(SIMD3(0.02, 0.02, 0.02))
      case 1:  trailColor = Self.srgbToLinear(SIMD3(0.98, 0.98, 0.96))
      default: trailColor = Self.srgbToLinear(SIMD3(0.92, 0.10, 0.08))
      }
    }

    let count = energy > 0.18 ? 2 : 1
    let eventID = UInt32(bitPattern: Int32(pollockEventCounter))
    for trailIdx in 0..<count where strokes.count < Self.maxStrokesPerFrame {
      let tIdx = UInt32(trailIdx)
      let x = (trailHash(eventID, tIdx &* 0x9e3779b9) - 0.5) * 0.40
      let y = (trailHash(eventID, tIdx &* 0xc6a4a793) - 0.5) * 0.90
      let angle = trailHash(eventID, tIdx &* 0x85ebca77) * .pi * 2
      let widthRoll = nextSeed()
      let topWidth: Float
      let length: Float
      if widthRoll < 0.80 {
        topWidth = 0.002 + nextSeed() * 0.004
        length   = 0.65 + nextSeed() * 0.55
      } else if widthRoll < 0.97 {
        topWidth = 0.006 + nextSeed() * 0.006
        length   = 0.50 + nextSeed() * 0.40
      } else {
        topWidth = 0.012 + nextSeed() * 0.006
        length   = 0.35 + nextSeed() * 0.30
      }

      let opacity: Float = 0.95 + nextSeed() * 0.05
      let bristleSeed = nextSeed() * 100
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, length),
        sizeOpacity: SIMD4(topWidth, opacity, bristleSeed, 3),
        color: SIMD4(trailColor.x, trailColor.y, trailColor.z, 0),
        animation: SIMD4(0, 1, 0, 0)))
    }
  }

  func appendWash(to strokes: inout [AbExStroke], mid: Float, focus: SIMD2<Float>) {
    guard mid > 0.06, (wallClock - lastWashTime) > 4.0, strokes.count < Self.maxStrokesPerFrame else { return }
    let suggested = SIMD2(focus.x * 0.6 + (nextSeed() - 0.5) * 1.00,
                          focus.y * 0.6 + (nextSeed() - 0.5) * 1.05)
    let pos = applyDensityBias(at: suggested, dispersion: 0.40)
    guard attentionStrength(at: pos) > 0.45 else { return }
    lastWashTime = wallClock
    let x = pos.x, y = pos.y
    let angle = nextSeed() * .pi
    let concentrationRoll = nextSeed()
    let opacity: Float
    let sizeMult: Float
    if concentrationRoll < 0.18 {
      opacity  = 0.55 + mid * 0.35 + nextSeed() * 0.08
      sizeMult = 1.4 + nextSeed() * 0.45
    } else if concentrationRoll < 0.60 {
      opacity  = 0.18 + mid * 0.18 + nextSeed() * 0.06
      sizeMult = 1.0
    } else {
      opacity  = 0.06 + mid * 0.10 + nextSeed() * 0.04
      sizeMult = 0.85
    }
    let halfLen = (0.18 + mid * 0.25) * sizeMult
    let halfWidth = (0.12 + mid * 0.18) * sizeMult
    let bristleSeed = nextSeed() * 100
    let color = pickStainColor()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: pos, weight: 1.4 * sizeMult)
  }

  func appendAmbientWash(to strokes: inout [AbExStroke],
                         energy: Float,
                         focus: SIMD2<Float>) {
    guard energy > 0.01, strokes.count < Self.maxStrokesPerFrame, nextSeed() < perFrameChance(0.0012) else { return }
    let suggested = SIMD2(focus.x + (nextSeed() - 0.5) * 0.95,
                          focus.y + (nextSeed() - 0.5) * 1.00)
    let pos = applyDensityBias(at: suggested, dispersion: 0.40)
    guard attentionStrength(at: pos) > 0.45 else { return }
    let x = pos.x, y = pos.y
    let angle = time * 0.1 + nextSeed() * .pi
    let halfLen = 0.20 + nextSeed() * 0.15
    let halfWidth = 0.14 + nextSeed() * 0.10
    let opacity: Float = 0.04 + energy * 0.05
    let bristleSeed = nextSeed() * 100
    let color = pickStainColor()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: pos, weight: 0.6)
  }

  func appendKnifeStroke(to strokes: inout [AbExStroke],
                         energy: Float,
                         focus: SIMD2<Float>) {
    guard energy > 0.05,
          (wallClock - lastKnifeTime) > 1.3,
          strokes.count < Self.maxStrokesPerFrame,
          nextSeed() < 0.55 else { return }

    let isOutlier = nextSeed() < 0.05
    var pos: SIMD2<Float>
    if isOutlier {
      pos = SIMD2((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    } else {
      guard let target = findStrongestTarget(minDensity: 0.25) else { return }
      pos = target.pos
    }
    lastKnifeTime = wallClock

    let flow = sampleFlow(at: pos)
    let flowMag = simd_length(flow)
    let angleRoll = nextSeed()
    let suggestedAngle: Float
    if flowMag > 0.05 && angleRoll < 0.60 {
      let flowAngle = atan2(flow.y, flow.x)
      suggestedAngle = flowAngle + (nextSeed() - 0.5) * 0.4
    } else if flowMag > 0.05 && angleRoll < 0.85 {
      let flowAngle = atan2(flow.y, flow.x)
      suggestedAngle = flowAngle + .pi / 2 + (nextSeed() - 0.5) * 0.4
    } else {
      let local = localStrokeAngle(at: pos)
      suggestedAngle = (nextSeed() < 0.65)
        ? local + (nextSeed() - 0.5) * 0.6
        : nextSeed() * .pi * 2
    }

    currentGestureRemaining = 0
    let x = pos.x, y = pos.y
    let angle = suggestedAngle
    let halfLen = 0.10 + nextSeed() * 0.12 + energy * 0.08
    let halfWidth = 0.011 + nextSeed() * 0.010
    let opacity: Float = 0.78 + nextSeed() * 0.20 + energy * 0.05
    let bristleSeed = nextSeed() * 100
    let color = pickKnifeColor(at: SIMD2(x, y))
    let curvature = pickCurvature(zeroChance: 0.40, midThreshold: 0.75,
                                   ampBase: 0.20, ampJitter: 0.35)
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 4),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, curvature)))
    depositFlow(at: pos, angle: angle, weight: 1.0 + energy * 0.4)
    depositDensity(at: pos, weight: 0.15)
    consumeDensity(at: pos, amount: 1.8)
  }

  func appendScumble(to strokes: inout [AbExStroke],
                     mid: Float,
                     energy: Float,
                     focus: SIMD2<Float>) {
    guard mid > 0.10,
          (wallClock - lastScumbleTime) > 2.5,
          strokes.count < Self.maxStrokesPerFrame,
          nextSeed() < 0.45 else { return }
    let x = focus.x + (nextSeed() - 0.5) * 0.55
    let y = focus.y + (nextSeed() - 0.5) * 0.55
    guard attentionStrength(at: SIMD2(x, y)) > 0.45 else { return }
    lastScumbleTime = wallClock
    let angle = nextSeed() * .pi * 2
    let halfLen   = 0.32 + nextSeed() * 0.22 + energy * 0.08
    let halfWidth = 0.06 + nextSeed() * 0.06 + energy * 0.02
    let opacity: Float = 0.60 + nextSeed() * 0.30
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased(at: SIMD2(x, y))
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 5),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: SIMD2(x, y), weight: 1.0)
  }
}

#endif
