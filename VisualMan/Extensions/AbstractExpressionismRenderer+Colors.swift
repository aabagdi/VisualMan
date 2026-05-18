//
//  AbstractExpressionismRenderer+Colors.swift
//  VisualMan
//
//  Created by on 5/18/26.
//

import Metal
import simd

extension AbstractExpressionismRenderer {
  nonisolated static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
    func f(_ x: Float) -> Float {
      x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return SIMD3(f(c.x), f(c.y), f(c.z))
  }

  static let warmColors: [SIMD3<Float>] = [
    SIMD3(0.85, 0.15, 0.05), SIMD3(0.90, 0.55, 0.05),
    SIMD3(0.80, 0.60, 0.10), SIMD3(0.55, 0.25, 0.08),
    SIMD3(0.35, 0.15, 0.08), SIMD3(0.75, 0.05, 0.20),
  ].map(srgbToLinear)

  static let coolColors: [SIMD3<Float>] = [
    SIMD3(0.05, 0.10, 0.70), SIMD3(0.05, 0.35, 0.65),
    SIMD3(0.10, 0.40, 0.25), SIMD3(0.25, 0.10, 0.50),
    SIMD3(0.02, 0.20, 0.45), SIMD3(0.15, 0.55, 0.35),
  ].map(srgbToLinear)

  struct Pigment {
    let linearRgb: SIMD3<Float>
    let hue: Float
    let value: Float
    let saturation: Float
    let name: String
  }

  static let mixboxPigments: [Pigment] = [
    Pigment(linearRgb: SIMD3(0.991, 0.839, 0.0), hue: 0.141, value: 0.99, saturation: 1.00, name: "Cadmium Yellow"),
    Pigment(linearRgb: SIMD3(0.973, 0.651, 0.0), hue: 0.112, value: 0.97, saturation: 1.00, name: "Hansa Yellow"),
    Pigment(linearRgb: SIMD3(1.0, 0.141, 0.0), hue: 0.024, value: 1.00, saturation: 1.00, name: "Cadmium Orange"),
    Pigment(linearRgb: SIMD3(1.0, 0.02, 0.001), hue: 0.000, value: 1.00, saturation: 1.00, name: "Cadmium Red"),
    Pigment(linearRgb: SIMD3(0.216, 0.001, 0.027), hue: 0.951, value: 0.22, saturation: 1.00,
            name: "Quinacridone Magenta"),
    Pigment(linearRgb: SIMD3(0.076, 0.0, 0.054), hue: 0.864, value: 0.08, saturation: 1.00, name: "Cobalt Violet"),
    Pigment(linearRgb: SIMD3(0.01, 0.0, 0.1), hue: 0.717, value: 0.10, saturation: 1.00, name: "Ultramarine Blue"),
    Pigment(linearRgb: SIMD3(0.0, 0.015, 0.235), hue: 0.677, value: 0.24, saturation: 1.00, name: "Cobalt Blue"),
    Pigment(linearRgb: SIMD3(0.004, 0.011, 0.058), hue: 0.658, value: 0.06, saturation: 0.93, name: "Phthalo Blue"),
    Pigment(linearRgb: SIMD3(0.0, 0.045, 0.032), hue: 0.452, value: 0.05, saturation: 1.00, name: "Phthalo Green"),
    Pigment(linearRgb: SIMD3(0.002, 0.153, 0.008), hue: 0.339, value: 0.15, saturation: 0.99, name: "Permanent Green"),
    Pigment(linearRgb: SIMD3(0.147, 0.296, 0.001), hue: 0.250, value: 0.30, saturation: 1.00, name: "Sap Green"),
    Pigment(linearRgb: SIMD3(0.198, 0.065, 0.0), hue: 0.055, value: 0.20, saturation: 1.00, name: "Burnt Sienna"),
  ]

  static func nearestPigment(toHue targetHue: Float,
                             valueBias: Float = 0.0) -> Pigment {
    var bestIdx = 0
    var bestScore: Float = .infinity
    for (idx, p) in mixboxPigments.enumerated() {
      let dh = abs(p.hue - targetHue)
      let hueDist = min(dh, 1.0 - dh)
      let score = hueDist - valueBias * p.value * 0.10
      if score < bestScore {
        bestScore = score
        bestIdx = idx
      }
    }
    return mixboxPigments[bestIdx]
  }

  func pickColor(warm: Bool) -> SIMD3<Float> {
    let palette = warm ? Self.warmColors : Self.coolColors
    let r = nextSeed()
    let idx = Int(r * Float(palette.count)) % palette.count
    var color = palette[idx]
    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.1
    color = pointwiseMin(pointwiseMax(color + variation, .zero), SIMD3(repeating: 1))
    return color
  }

  func pickColorBiased() -> SIMD3<Float> {
    var baseHue = (time * 0.0042 + songSeed * 0.7)
      .truncatingRemainder(dividingBy: 1.0)
    if baseHue < 0 { baseHue += 1 }

    let energy = (slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0
    let dissonance = min(max(energy * 1.5, 0.05), 0.95)

    let r = nextSeed()
    let offset: Float
    if r < 0.60 {
      offset = (nextSeed() - 0.5) * 0.24 * (0.5 + dissonance * 0.5)
    } else if r < 0.88 {
      let direction: Float = (nextSeed() < 0.5) ? 1.0 : -1.0
      offset = direction * (0.42 + (nextSeed() - 0.5) * 0.16) * dissonance
    } else {
      offset = 0.5 + (nextSeed() - 0.5) * 0.10
    }

    var hue = (baseHue + offset).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1 }

    let pigment = Self.nearestPigment(toHue: hue, valueBias: 0.0)

    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.05
    let varied = pigment.linearRgb + variation
    return SIMD3(max(0, varied.x), max(0, varied.y), max(0, varied.z))
  }

  func pickKnifeColor() -> SIMD3<Float> {
    var baseHue = (time * 0.0042 + songSeed * 0.7)
      .truncatingRemainder(dividingBy: 1.0)
    if baseHue < 0 { baseHue += 1 }

    let energy = (slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0
    let dissonance = min(max(energy * 1.5, 0.05), 0.95)

    let r = nextSeed()
    let offset: Float
    if r < 0.65 {
      offset = 0.5 + (nextSeed() - 0.5) * 0.16
    } else if r < 0.90 {
      let direction: Float = (nextSeed() < 0.5) ? 1.0 : -1.0
      offset = direction * (0.33 + (nextSeed() - 0.5) * 0.08)
    } else {
      offset = (nextSeed() - 0.5) * 0.18 * (0.5 + dissonance * 0.5)
    }

    var hue = (baseHue + offset).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1 }

    let pigment = Self.nearestPigment(toHue: hue, valueBias: 0.4)

    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.04
    let varied = pigment.linearRgb + variation
    return SIMD3(max(0, varied.x), max(0, varied.y), max(0, varied.z))
  }

  func pickStainColor() -> SIMD3<Float> {
    var baseHue = (time * 0.0042 + songSeed * 0.7)
      .truncatingRemainder(dividingBy: 1.0)
    if baseHue < 0 { baseHue += 1 }

    let r = nextSeed()
    let offset: Float
    if r < 0.55 {
      offset = (nextSeed() - 0.5) * 0.30
    } else if r < 0.85 {
      let direction: Float = (nextSeed() < 0.5) ? 1.0 : -1.0
      offset = direction * (0.18 + nextSeed() * 0.18)
    } else {
      offset = 0.45 + (nextSeed() - 0.5) * 0.24
    }

    var hue = (baseHue + offset).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1 }

    let pigment = Self.nearestPigment(toHue: hue, valueBias: 0.0)

    let whiteTarget = SIMD3<Float>(1.0, 1.0, 0.97)
    let dilution: Float = 0.65 + nextSeed() * 0.20
    let diluted = pigment.linearRgb * (1.0 - dilution) + whiteTarget * dilution

    return SIMD3(max(0, diluted.x), max(0, diluted.y), max(0, diluted.z))
  }

  nonisolated static func hsvToRgb(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
    let h = hsv.x * 6.0
    let s = hsv.y
    let v = hsv.z
    let c = v * s
    let x = c * (1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0))
    let m = v - c
    let rgb: SIMD3<Float>
    switch Int(h) {
    case 0:  rgb = SIMD3(c, x, 0)
    case 1:  rgb = SIMD3(x, c, 0)
    case 2:  rgb = SIMD3(0, c, x)
    case 3:  rgb = SIMD3(0, x, c)
    case 4:  rgb = SIMD3(x, 0, c)
    default: rgb = SIMD3(c, 0, x)
    }
    return rgb + SIMD3<Float>(repeating: m)
  }
}
