//
//  AbstractExpressionismRenderer+Strokes.swift
//  VisualMan
//
//  Created by on 4/24/26.
//

import Metal

extension AbstractExpressionismRenderer {
  func appendGesturalStroke(to strokes: inout [AbExStroke],
                            energy: Float, focus: SIMD2<Float>, spread: Float) {
    lastGesturalTime = wallClock
    let isOutlier = nextSeed() < 0.28
    var pos: SIMD2<Float>
    if isOutlier {
      pos = SIMD2((nextSeed() - 0.5) * 1.00, (nextSeed() - 0.5) * 1.05)
    } else {
      let suggested = SIMD2(focus.x + (nextSeed() - 0.5) * 0.88 * spread,
                            focus.y + (nextSeed() - 0.5) * 0.92 * spread)
      pos = applyDensityBias(at: suggested, dispersion: 0.30)
    }
    let x = pos.x, y = pos.y
    let local = localStrokeAngle(at: pos)
    let angle = (nextSeed() < 0.78)
      ? local + (nextSeed() - 0.5) * 0.5
      : nextSeed() * .pi * 2
    let halfLen = 0.13 + energy * 0.22 + nextSeed() * 0.09
    let halfWidth = 0.012 + energy * 0.016 + nextSeed() * 0.008
    let opacity = 0.84 + energy * 0.16
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    let dur = pickDurability(permanentChance: 0.03, stickyChance: 0.15)
    let curveRoll = nextSeed()
    let curvature: Float
    if curveRoll < 0.30 {
      curvature = 0
    } else if curveRoll < 0.65 {
      let amp = 0.25 + nextSeed() * 0.40
      let dir: Float = nextSeed() < 0.5 ? 1 : -1
      curvature = amp * dir
    } else {
      let amp = 0.25 + nextSeed() * 0.40
      let dir: Float = nextSeed() < 0.5 ? 1 : -1
      curvature = (1.0 + amp) * dir
    }
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: 0, durability: dur)),
      animation: SIMD4(0, 1, 0, curvature)))
    depositFlow(at: pos, angle: angle, weight: 0.5 + energy * 0.5)
    depositDensity(at: pos, weight: 0.85 + energy * 0.4)
  }

  func appendRogueStroke(to strokes: inout [AbExStroke], energy: Float) {
    guard strokes.count < 12, nextSeed() < 0.0035 else { return }
    let x = (nextSeed() - 0.5) * 1.05
    let y = (nextSeed() - 0.5) * 1.10
    let angle = nextSeed() * .pi * 2
    let typeRoll = nextSeed()
    let color = pickColorBiased()
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
                           energy: Float, focus: SIMD2<Float>) {
    guard energy > 0.04, strokes.count < 12,
          (wallClock - lastPollockTime) > 1.0 else { return }
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
    for trailIdx in 0..<count where strokes.count < 12 {
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
    guard mid > 0.06, (wallClock - lastWashTime) > 2.0, strokes.count < 12 else { return }
    lastWashTime = wallClock
    let suggested = SIMD2(focus.x * 0.6 + (nextSeed() - 0.5) * 1.00,
                          focus.y * 0.6 + (nextSeed() - 0.5) * 1.05)
    let pos = applyDensityBias(at: suggested, dispersion: 0.40)
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
    let color = pickColorBiased()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: pos, weight: 1.4 * sizeMult)
  }

  func appendAmbientWash(to strokes: inout [AbExStroke],
                         energy: Float, focus: SIMD2<Float>) {
    guard energy > 0.01, strokes.count < 12, nextSeed() < 0.0025 else { return }
    let suggested = SIMD2(focus.x + (nextSeed() - 0.5) * 0.95,
                          focus.y + (nextSeed() - 0.5) * 1.00)
    let pos = applyDensityBias(at: suggested, dispersion: 0.40)
    let x = pos.x, y = pos.y
    let angle = time * 0.1 + nextSeed() * .pi
    let halfLen = 0.20 + nextSeed() * 0.15
    let halfWidth = 0.14 + nextSeed() * 0.10
    let opacity: Float = 0.04 + energy * 0.05
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: pos, weight: 0.6)
  }

  private func splatterPosition(focus: SIMD2<Float>) -> (Float, Float) {
    let isOutlier = nextSeed() < 0.35
    if isOutlier {
      return ((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    return (focus.x + (nextSeed() - 0.5) * 0.75,
            focus.y + (nextSeed() - 0.5) * 0.80)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.30 {
      radius = 0.004 + nextSeed() * 0.008
      opacityBase = 0.95
    } else if sizeRoll < 0.65 {
      radius = 0.012 + nextSeed() * 0.013
      opacityBase = 0.93
    } else {
      radius = 0.025 + nextSeed() * 0.015
      opacityBase = 0.92
    }
    return (radius, opacityBase + high * 0.06)
  }

  private func splatterShape(radius: Float, at p: SIMD2<Float>, burstRoll: Float) -> (variant: Float, angle: Float) {
    if radius < 0.012 {
      return (burstRoll < 0.50 ? 2.0 : 0.0, 0)
    } else if burstRoll < 0.15 {
      let local = localStrokeAngle(at: p)
      let angle = (nextSeed() < 0.60)
        ? local + (nextSeed() - 0.5) * 0.8
        : nextSeed() * .pi * 2
      return (1.0, angle)
    } else if burstRoll < 0.25 {
      return (2.0, 0)
    } else {
      return (0.0, 0)
    }
  }

  private func makeSplatterStroke(high: Float, focus: SIMD2<Float>,
                                  burstShapeRoll: Float, burstTypeRoll: Float) -> AbExStroke {
    let (x, y) = splatterPosition(focus: focus)
    let (radius, opacity) = splatterSizeAndOpacity(high: high)
    let (shapeVariant, angle) = splatterShape(radius: radius, at: SIMD2(x, y), burstRoll: burstShapeRoll)
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    let dur = pickDurability(permanentChance: 0.12, stickyChance: 0.28)
    return AbExStroke(
      posAngle: SIMD4(x, y, angle, radius),
      sizeOpacity: SIMD4(burstTypeRoll, opacity, bristleSeed, 2),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: shapeVariant, durability: dur)),
      animation: SIMD4(0, 1, 0, 0))
  }

  func appendSplatters(to strokes: inout [AbExStroke], high: Float) {
    guard high > 0.05, (wallClock - lastSplatterTime) > 0.35, strokes.count < 12 else { return }
    lastSplatterTime = wallClock
    let count = high > 0.30 ? 2 : 1
    for _ in 0..<count where strokes.count < 12 {
      let focus = splatterFocus()
      let burstShapeRoll = nextSeed()
      let burstTypeRoll  = nextSeed()
      strokes.append(makeSplatterStroke(high: high, focus: focus,
                                         burstShapeRoll: burstShapeRoll,
                                         burstTypeRoll: burstTypeRoll))
      depositDensity(at: SIMD2(focus.x, focus.y), weight: 0.25)
    }
  }

  func appendKnifeStroke(to strokes: inout [AbExStroke],
                         energy: Float, focus: SIMD2<Float>) {
    guard energy > 0.05,
          (wallClock - lastKnifeTime) > 0.65,
          strokes.count < 12,
          nextSeed() < 0.85 else { return }
    lastKnifeTime = wallClock
    let isOutlier = nextSeed() < 0.30
    var pos: SIMD2<Float>
    if isOutlier {
      pos = SIMD2((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    } else {
      let suggested = SIMD2(focus.x + (nextSeed() - 0.5) * 0.65,
                            focus.y + (nextSeed() - 0.5) * 0.70)
      pos = applyDensityBias(at: suggested, dispersion: 0.30)
    }
    let x = pos.x, y = pos.y
    let local = localStrokeAngle(at: pos)
    let angle = (nextSeed() < 0.75)
      ? local + (nextSeed() - 0.5) * 0.5
      : nextSeed() * .pi * 2
    let halfLen = 0.22 + nextSeed() * 0.22 + energy * 0.18
    let halfWidth = 0.011 + nextSeed() * 0.010
    let opacity: Float = 0.78 + nextSeed() * 0.20 + energy * 0.05
    let bristleSeed = nextSeed() * 100
    let color = pickKnifeColor()
    let curveRoll = nextSeed()
    let curvature: Float
    if curveRoll < 0.40 {
      curvature = 0
    } else if curveRoll < 0.75 {
      let amp = 0.20 + nextSeed() * 0.35
      let dir: Float = nextSeed() < 0.5 ? 1 : -1
      curvature = amp * dir
    } else {
      let amp = 0.20 + nextSeed() * 0.35
      let dir: Float = nextSeed() < 0.5 ? 1 : -1
      curvature = (1.0 + amp) * dir
    }
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 4),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, curvature)))
    depositFlow(at: pos, angle: angle, weight: 1.0 + energy * 0.4)
    depositDensity(at: pos, weight: 1.1 + energy * 0.3)
  }

  func appendScumble(to strokes: inout [AbExStroke],
                     mid: Float, energy: Float, focus: SIMD2<Float>) {
    guard mid > 0.10,
          (wallClock - lastScumbleTime) > 1.2,
          strokes.count < 12,
          nextSeed() < 0.75 else { return }
    lastScumbleTime = wallClock
    let x = focus.x + (nextSeed() - 0.5) * 0.55
    let y = focus.y + (nextSeed() - 0.5) * 0.55
    let angle = nextSeed() * .pi * 2
    let halfLen   = 0.32 + nextSeed() * 0.22 + energy * 0.08
    let halfWidth = 0.06 + nextSeed() * 0.06 + energy * 0.02
    let opacity: Float = 0.60 + nextSeed() * 0.30
    let bristleSeed = nextSeed() * 100
    let colorRoll = nextSeed()
    let color: SIMD3<Float>
    if colorRoll < 0.75 {
      color = pickColorBiased()
    } else if colorRoll < 0.90 {
      let warmth: Float = nextSeed() < 0.5 ? 1.0 : -1.0
      color = Self.srgbToLinear(SIMD3(
        0.92 + warmth * 0.04,
        0.92 + nextSeed() * 0.04,
        0.92 - warmth * 0.04
      ))
    } else {
      let g = 0.45 + nextSeed() * 0.25
      color = Self.srgbToLinear(SIMD3(g, g, g))
    }
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 5),
      color: SIMD4(color.x, color.y, color.z, 0),
      animation: SIMD4(0, 1, 0, 0)))
    depositDensity(at: SIMD2(x, y), weight: 1.0)
  }

}
