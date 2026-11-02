//
//  AbstractExpressionismRenderer+Colors.swift
//  VisualMan
//
//  Created by on 5/18/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  nonisolated static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
    func f(_ x: Float) -> Float {
      x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return SIMD3(f(c.x), f(c.y), f(c.z))
  }

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
    Pigment(linearRgb: SIMD3(1.0, 1.0, 1.0), hue: -1, value: 1.00, saturation: 0.00, name: "Titanium White"),
  ]

  static var titaniumWhite: Pigment { mixboxPigments[13] }

  static let brushWhiteChance: Float = 0.10
  static let knifeWhiteChance: Float = 0.22

  static func makePigmentWeights(seed: Float) -> [Float] {
    func hash(_ i: Int) -> Float {
      var x = sin(seed * 12.9898 + Float(i) * 78.233) * 43758.5453
      x -= x.rounded(.down)
      return x
    }
    var weights = mixboxPigments.map { p -> Float in
      p.hue >= 0 ? 0.25 : 0
    }
    for i in weights.indices where weights[i] > 0 {
      weights[i] += 0.75 * hash(i)
    }
    let stars = weights.indices
      .filter { weights[$0] > 0 }
      .sorted { hash($0 + 100) > hash($1 + 100) }
      .prefix(3)
    for i in stars { weights[i] *= 2.2 }
    return weights
  }

  func currentPigmentWeights() -> [Float] {
    if pigmentWeightsSeed != songSeed || pigmentWeights.isEmpty {
      pigmentWeights = Self.makePigmentWeights(seed: songSeed)
      pigmentWeightsSeed = songSeed
    }
    return pigmentWeights
  }

  func weightedPigment(nearHue targetHue: Float, valueBias: Float = 0.0) -> Pigment {
    let weights = currentPigmentWeights()
    var odds = [Float](repeating: 0, count: weights.count)
    var total: Float = 0
    for (idx, p) in Self.mixboxPigments.enumerated() where weights[idx] > 0 {
      let dh = abs(p.hue - targetHue)
      let hueDist = min(dh, 1.0 - dh)
      let kernel = exp(-(hueDist * hueDist) / (0.11 * 0.11)) + 0.10
      odds[idx] = weights[idx] * kernel * (1 + valueBias * p.value)
      total += odds[idx]
    }
    var roll = nextSeed() * total
    for idx in odds.indices where odds[idx] > 0 {
      roll -= odds[idx]
      if roll <= 0 { return Self.mixboxPigments[idx] }
    }
    return Self.mixboxPigments[0]
  }

  func pickColorBiased(at pos: SIMD2<Float>) -> SIMD3<Float> {
    if nextSeed() < Self.brushWhiteChance, whiteAllowed(at: pos) {
      return Self.titaniumWhite.linearRgb
    }
    var baseHue = (time * 0.0042 + songSeed * 0.7)
      .truncatingRemainder(dividingBy: 1.0)
    if baseHue < 0 { baseHue += 1 }

    let energy = (slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0
    let dissonance = min(max(energy * 1.5, 0.05), 0.95)

    let r = nextSeed()
    let offset: Float
    if r < 0.55 {
      offset = (nextSeed() - 0.5) * 0.70 * (0.5 + dissonance * 0.5)
    } else if r < 0.85 {
      let direction: Float = (nextSeed() < 0.5) ? 1.0 : -1.0
      offset = direction * (0.42 + (nextSeed() - 0.5) * 0.16) * dissonance
    } else {
      offset = 0.5 + (nextSeed() - 0.5) * 0.10
    }

    var hue = (baseHue + offset).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1 }

    return weightedPigment(nearHue: hue).linearRgb
  }

  func pickKnifeColor(at pos: SIMD2<Float>) -> SIMD3<Float> {
    if nextSeed() < Self.knifeWhiteChance, whiteAllowed(at: pos) {
      return Self.titaniumWhite.linearRgb
    }
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

    return weightedPigment(nearHue: hue, valueBias: 0.4).linearRgb
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

    return weightedPigment(nearHue: hue).linearRgb
  }

}

#endif
