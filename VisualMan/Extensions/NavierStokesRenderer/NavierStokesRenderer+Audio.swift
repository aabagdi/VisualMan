//
//  NavierStokesRenderer+Audio.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

private struct GasPalette {
  let dyes: [SIMD3<Float>]

  func dye(_ h: Float) -> SIMD3<Float> {
    let x = (h - floor(h)) * Float(dyes.count)
    let i = Int(x) % dyes.count
    let j = (i + 1) % dyes.count
    let f = x - floor(x)
    let t = f * f * (3.0 - 2.0 * f)
    return simd_mix(dyes[i], dyes[j], SIMD3<Float>(repeating: t))
  }

  func color(h: Float, amount: Float) -> SIMD3<Float> {
    dye(h) * amount
  }
}

private let bassPalette = GasPalette(dyes: [
  SIMD3<Float>(0.00, 1.00, 1.00),
  SIMD3<Float>(0.00, 1.00, 0.75),
  SIMD3<Float>(0.30, 1.00, 0.80),
])

private let midPalette = GasPalette(dyes: [
  SIMD3<Float>(0.00, 0.75, 1.00),
  SIMD3<Float>(0.00, 0.55, 1.00),
  SIMD3<Float>(0.00, 0.35, 1.00),
])

private let highPalette = GasPalette(dyes: [
  SIMD3<Float>(1.00, 0.80, 0.00),
  SIMD3<Float>(1.00, 0.20, 0.45),
  SIMD3<Float>(1.00, 0.00, 0.90),
])

private func rotate(_ v: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
  let c = cos(angle)
  let s = sin(angle)
  return SIMD2<Float>(c * v.x - s * v.y, s * v.x + c * v.y)
}

private struct Nozzle {
  var anchor: SIMD2<Float>
  var direction: SIMD2<Float>
  var slide: SIMD2<Float>
  var phase: Float
}

private let bassNozzles: [Nozzle] = [
  Nozzle(anchor: SIMD2(0.20, 0.04), direction: simd_normalize(SIMD2(0.30, 0.51)),
         slide: SIMD2(1, 0), phase: 0.0),
  Nozzle(anchor: SIMD2(0.80, 0.04), direction: simd_normalize(SIMD2(-0.30, 0.51)),
         slide: SIMD2(1, 0), phase: 2.1),
]

private let midNozzles: [Nozzle] = [
  Nozzle(anchor: SIMD2(0.03, 0.58), direction: simd_normalize(SIMD2(0.47, -0.08)),
         slide: SIMD2(0, 1), phase: 0.7),
  Nozzle(anchor: SIMD2(0.97, 0.42), direction: simd_normalize(SIMD2(-0.47, 0.08)),
         slide: SIMD2(0, 1), phase: 3.3),
]

private let highNozzles: [Nozzle] = [
  Nozzle(anchor: SIMD2(0.30, 0.96), direction: simd_normalize(SIMD2(0.20, -0.46)),
         slide: SIMD2(1, 0), phase: 1.3),
  Nozzle(anchor: SIMD2(0.50, 0.96), direction: SIMD2(0.0, -1.0),
         slide: SIMD2(1, 0), phase: 4.2),
  Nozzle(anchor: SIMD2(0.70, 0.96), direction: simd_normalize(SIMD2(-0.20, -0.46)),
         slide: SIMD2(1, 0), phase: 5.6),
]

extension NavierStokesRenderer {
  var technicolorThemeDye: SIMD3<Float> {
    bassPalette.dye(fmod(time * 0.05, 1.0))
  }
}

extension NavierStokesRenderer {
  func injectAudioSplats(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float,
                         mid: Float,
                         high: Float) {
    let high = min(high * Self.highBandGain, 1.0)
    updateDynamics(bass: bass, mid: mid, high: high)

    if bass > 0.01 {
      collectBassJets(bass: bass)
      flushSplats(encoder: encoder)
    }
    if mid > 0.01 {
      collectMidJets(mid: mid)
      flushSplats(encoder: encoder)
    }
    if high > 0.02 {
      collectHighJets(high: high)
      flushSplats(encoder: encoder)
    }
  }

  private func flushSplats(encoder: any MTL4ComputeCommandEncoder) {
    if !forceSplats.isEmpty {
      dispatchBatchedSplats(encoder: encoder, texture: velocityA, splats: forceSplats,
                            isVelocity: true)
      dispatchBatchedSplats(encoder: encoder, texture: u0, splats: forceSplats,
                            isVelocity: true)
    }
    if !dyeSplats.isEmpty {
      dispatchBatchedSplats(encoder: encoder, texture: dyeA, splats: dyeSplats,
                            isVelocity: false)
    }
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    forceSplats.removeAll(keepingCapacity: true)
    dyeSplats.removeAll(keepingCapacity: true)
  }

  private func dispatchBatchedSplats(encoder: any MTL4ComputeCommandEncoder,
                                     texture: MTLTexture,
                                     splats: [SplatParams],
                                     isVelocity: Bool) {
    var minX: Float = Float(gridWidth)
    var minY: Float = Float(gridHeight)
    var maxX: Float = 0
    var maxY: Float = 0
    let rMult: Float = sqrt(6.0)
    for sp in splats {
      let r = sp.radius * rMult
      minX = min(minX, sp.position.x - r)
      minY = min(minY, sp.position.y - r)
      maxX = max(maxX, sp.position.x + r)
      maxY = max(maxY, sp.position.y + r)
    }
    let ox = max(0, Int(floor(minX)))
    let oy = max(0, Int(floor(minY)))
    let ex = min(gridWidth, Int(ceil(maxX)))
    let ey = min(gridHeight, Int(ceil(maxY)))
    let regionW = ex - ox
    let regionH = ey - oy
    if regionW <= 0 || regionH <= 0 { return }

    encoder.setComputePipelineState(pipelines.splatBatch)
    argumentTable.setTexture(texture.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniformArray(splats), index: 0)
    let count = UInt32(splats.count)
    argumentTable.setAddress(writeUniform(count), index: 1)
    let origin = SIMD2<UInt32>(UInt32(ox), UInt32(oy))
    argumentTable.setAddress(writeUniform(origin), index: 2)
    argumentTable.setAddress(writeUniform(UInt32(isVelocity ? 1 : 0)), index: 3)
    dispatchGrid(encoder: encoder, width: regionW, height: regionH)
  }

  private func updateDynamics(bass: Float, mid: Float, high: Float) {
    if !dynamicsWarm {
      bassFast = bass; midFast = mid; highFast = high
      bassEnvelope = bass; midEnvelope = mid; highEnvelope = high
      bassBurst = 0; midBurst = 0; highBurst = 0
      dynamicsWarm = true
    }
    trackBand(level: bass, fast: &bassFast, envelope: &bassEnvelope, burst: &bassBurst)
    trackBand(level: mid, fast: &midFast, envelope: &midEnvelope, burst: &midBurst)
    trackBand(level: high, fast: &highFast, envelope: &highEnvelope, burst: &highBurst)

    let swell = max(dynamics(level: bass, envelope: bassEnvelope),
                    dynamics(level: mid, envelope: midEnvelope),
                    dynamics(level: high, envelope: highEnvelope))
    let swellTerm = simd_clamp((swell - 1.0) / (Self.dynamicsMax - 1.0), 0, 1)
    let burstTerm = min(max(bassBurst, midBurst, highBurst) / 2.5, 1.0)
    lastExcitement = simd_clamp(swellTerm * 0.7 + burstTerm * 0.6, 0, 1)
  }

  private func trackBand(level: Float, fast: inout Float, envelope: inout Float, burst: inout Float) {
    let hit = max(0, level - fast) / max(envelope, Self.dynamicsFloor)
    burst = max(burst * exp(-dt / Self.burstDecaySeconds), min(hit, 2.5))
    fast += (level - fast) * (1 - exp(-dt / Self.transientFollowerSeconds))
    envelope += (level - envelope) * (1 - exp(-dt / Self.dynamicsEnvelopeSeconds))
  }

  private func dynamics(level: Float, envelope: Float) -> Float {
    simd_clamp(level / max(envelope, Self.dynamicsFloor), Self.dynamicsMin, Self.dynamicsMax)
  }

  private struct DynamicsScales {
    let speed: Float
    let volume: Float
    let drive: Float
    let dye: Float
  }

  private func dynamicsScales(_ dyn: Float) -> DynamicsScales {
    DynamicsScales(speed: pow(dyn, Self.dynamicsSpeedExponent),
                   volume: pow(dyn, Self.dynamicsVolumeExponent),
                   drive: pow(dyn, 0.5),
                   dye: pow(dyn, 0.8))
  }

  private func emitJet(_ nozzle: Nozzle,
                       speed: Float,
                       radius: Float,
                       strength: Float,
                       wobble: Float,
                       slideAmount: Float,
                       color: SIMD3<Float>,
                       density: Float) {
    let flap = 1.0 + Self.excitementWobbleGain * lastExcitement
    let angle = (sin(wobblePhase * 0.9 + nozzle.phase)
                 + 0.4 * lastExcitement * sin(wobblePhase * 3.1 + nozzle.phase * 2.3)) * wobble * flap
    let dir = rotate(nozzle.direction, by: angle)
    let slide = nozzle.slide * sin(time * 0.37 + nozzle.phase * 1.7) * slideAmount
    let pos = (nozzle.anchor + slide) * SIMD2<Float>(Float(gridWidth), Float(gridHeight))

    forceSplats.append(SplatParams(position: pos,
                                   value: SIMD3<Float>(dir.x * speed, dir.y * speed, strength),
                                   radius: radius))
    dyeSplats.append(SplatParams(position: pos + dir * radius * 0.8,
                                 value: color * Self.dyeInjectionScale,
                                 radius: radius * 1.4,
                                 weight: density * Self.dyeInjectionScale))
  }

  private func collectBassJets(bass: Float) {
    let gs = gridScale
    let hit = bassBurst * Self.burstGain + highBurst * Self.percussiveSpillGain
    let dyn = dynamicsScales(dynamics(level: bass, envelope: bassEnvelope))

    let speed = (Self.bassJetSpeed + bass * Self.bassJetSpeedRange) * dyn.speed * (1.0 + hit)
    let radius = gs * Self.bassJetRadius * (0.5 + bass * 1.0) * dyn.volume * (1.0 + hit * 0.6)
    let strength = min((0.3 + bass * 0.3 + hit * 0.8) * dyn.drive, 1.0)
    let hue = fmod(time * 0.05, 1.0)
    let brightness = (0.35 + bass * 0.9) * dyn.dye * (1.0 + hit * 0.5)
    let density = Self.bassGasWeight * brightness

    for (i, nozzle) in bassNozzles.enumerated() {
      let nozzleColor = bassPalette.color(h: hue + Float(i) * 0.08, amount: brightness)
      emitJet(nozzle, speed: speed, radius: radius, strength: strength,
              wobble: 0.30, slideAmount: 0.05, color: nozzleColor, density: density)
    }
  }

  private func collectMidJets(mid: Float) {
    let gs = gridScale
    let hit = midBurst * Self.burstGain + highBurst * Self.percussiveSpillGain
    let dyn = dynamicsScales(dynamics(level: mid, envelope: midEnvelope))

    let speed = (Self.midJetSpeed + mid * Self.midJetSpeedRange) * dyn.speed * (1.0 + hit)
    let radius = gs * Self.midJetRadius * (0.5 + mid * 0.9) * dyn.volume * (1.0 + hit * 0.6)
    let strength = min((0.25 + mid * 0.3 + hit * 0.8) * dyn.drive, 1.0)

    for (i, nozzle) in midNozzles.enumerated() {
      let hue = fmod(time * 0.07 + Float(i) * 0.45, 1.0)
      let brightness = (0.3 + mid * 0.9) * dyn.dye * (1.0 + hit * 0.5)
      let color = midPalette.color(h: hue, amount: brightness)
      emitJet(nozzle, speed: speed, radius: radius, strength: strength,
              wobble: 0.45, slideAmount: 0.08, color: color,
              density: Self.midGasWeight * brightness)
    }
  }

  private func collectHighJets(high: Float) {
    let gs = gridScale
    let hit = highBurst * Self.burstGain
    let dyn = dynamicsScales(dynamics(level: high, envelope: highEnvelope))

    let speed = (Self.highJetSpeed + high * Self.highJetSpeedRange) * dyn.speed * (1.0 + hit)
    let radius = gs * Self.highJetRadius * (0.5 + high * 1.0) * dyn.volume * (1.0 + hit * 0.8)
    let strength = min((0.2 + high * 0.3 + hit * 0.8) * dyn.drive, 1.0)

    for (i, nozzle) in highNozzles.enumerated() {
      let hue = fmod(time * 0.09 + Float(i) * 0.3, 1.0)
      let brightness = (0.35 + high * 1.0) * dyn.dye * (1.0 + hit * 0.6)
      let color = highPalette.color(h: hue, amount: brightness)
      emitJet(nozzle, speed: speed, radius: radius, strength: strength,
              wobble: 0.6, slideAmount: 0.04, color: color,
              density: Self.highGasWeight * brightness)
    }
  }
}

#endif
