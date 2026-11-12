//
//  AbstractExpressionismRenderer+Splatters.swift
//  VisualMan
//
//  Created by on 5/18/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  private static let splatHistoryLimit = 24

  private func splatterPosition(focus: SIMD2<Float>) -> (Float, Float) {
    var candidates: [SIMD2<Float>] = (0..<4).map { _ in
      SIMD2((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    if nextSeed() < 0.20 {
      candidates.append(SIMD2(focus.x + (nextSeed() - 0.5) * 0.6,
                              focus.y + (nextSeed() - 0.5) * 0.6))
    }
    var best = candidates[0]
    var bestDist: Float = -1
    for c in candidates {
      let d = recentSplats.map { simd_distance_squared($0, c) }.min() ?? 1
      if d > bestDist { bestDist = d; best = c }
    }
    recentSplats.append(best)
    if recentSplats.count > Self.splatHistoryLimit {
      recentSplats.removeFirst(recentSplats.count - Self.splatHistoryLimit)
    }
    return (best.x, best.y)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.12 {
      radius = 0.0015 + nextSeed() * 0.003
      opacityBase = 0.98
    } else if sizeRoll < 0.25 {
      radius = 0.005 + nextSeed() * 0.008
      opacityBase = 0.95
    } else if sizeRoll < 0.55 {
      radius = 0.014 + nextSeed() * 0.016
      opacityBase = 0.93
    } else if sizeRoll < 0.85 {
      radius = 0.028 + nextSeed() * 0.018
      opacityBase = 0.92
    } else {
      radius = 0.044 + nextSeed() * 0.024
      opacityBase = 0.88
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
    let color = pickColorBiased(at: SIMD2(x, y))
    let dur = pickDurability(permanentChance: 0.12, stickyChance: 0.28)
    return AbExStroke(
      posAngle: SIMD4(x, y, angle, radius),
      sizeOpacity: SIMD4(burstTypeRoll, opacity, bristleSeed, 2),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: shapeVariant, durability: dur)),
      animation: SIMD4(0, 1, 0, 0))
  }

  static let splatterInterval: Float = 0.3
  static let pearlescentChance: Float = 1 / 8192

  func rollPearlescent(_ stroke: inout AbExStroke) {
    splatCounter &+= 1
    if trailHash(splatCounter, 0x51ED270B) < Self.pearlescentChance {
      stroke.color.w += 4
    }
  }

  private static func splatDensityWeight(typeRoll: Float) -> Float {
    switch typeRoll {
    case ..<0.33: return 0.10
    case ..<0.66: return 0.30
    case ..<0.88: return 0.80
    default:      return 1.50
    }
  }

  func appendSplatters(to strokes: inout [AbExStroke], high: Float) {
    guard high > 0.03, (wallClock - lastSplatterTime) > Self.splatterInterval,
          strokes.count < Self.maxStrokesPerFrame else { return }
    lastSplatterTime = wallClock
    let count: Int
    if high > 0.40 {
      count = 4
    } else if high > 0.20 {
      count = 3
    } else {
      count = 2
    }
    for _ in 0..<count where strokes.count < Self.maxStrokesPerFrame {
      let focus = splatterFocus()
      let burstShapeRoll = nextSeed()
      splatCounter &+= 1
      let burstTypeRoll = trailHash(splatCounter, UInt32(bitPattern: Int32(songSeed * 1000)))
      var mainStroke = makeSplatterStroke(high: high, focus: focus,
                                            burstShapeRoll: burstShapeRoll,
                                            burstTypeRoll: burstTypeRoll)
      rollPearlescent(&mainStroke)
      let mainRadius = mainStroke.posAngle.w
      strokes.append(mainStroke)
      
      let landed = SIMD2(mainStroke.posAngle.x, mainStroke.posAngle.y)
      depositDensity(at: landed, weight: Self.splatDensityWeight(typeRoll: burstTypeRoll))

      if mainRadius > 0.012 && nextSeed() < 0.55 && strokes.count < Self.maxStrokesPerFrame {
        let satCount = (mainRadius > 0.030) ? Int(2 + nextSeed() * 2) : 1
        for _ in 0..<satCount where strokes.count < Self.maxStrokesPerFrame {
          let satAngle = nextSeed() * .pi * 2
          let satDist = mainRadius * (2.0 + nextSeed() * 4.0)
          let satX = landed.x + cos(satAngle) * satDist
          let satY = landed.y + sin(satAngle) * satDist
          let satRadius = 0.0010 + nextSeed() * 0.0025
          let bristleSeed = nextSeed() * 100
          splatCounter &+= 1
          let satTypeRoll = trailHash(splatCounter, 0x2545F491)
          let color = mainStroke.color
          strokes.append(AbExStroke(
            posAngle: SIMD4(satX, satY, 0, satRadius),
            sizeOpacity: SIMD4(satTypeRoll, 0.85 + nextSeed() * 0.10,
                                 bristleSeed, 2),
            color: color,
            animation: SIMD4(0, 1, 0, 0)))
        }
      }
    }
  }
}

#endif
