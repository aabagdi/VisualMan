//
//  LiquidLightRenderer+Drops.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/6/26.
//

#if !targetEnvironment(simulator)
import Metal

extension LiquidLightRenderer {
  static let dripScatter: Float = 0.03
  static let dropLifetime: Float = 5.0
  static let sameColourSwellGain: Float = 2.4

  func detectAndEmitDrop(bass: Float, inResumeGrace: Bool) {
    let bassBaseline: Float = 0.08
    let bassUpTau: Float = 0.06
    let bassDownTau: Float = 0.20
    let bassA = 1 - exp(-dt / (bass > smoothedBass ? bassUpTau : bassDownTau))
    smoothedBass += (bass - smoothedBass) * bassA

    if wallClock >= nextPipetteMoveWallTime {
      pipettePos = insideBeam(SIMD2<Float>((hashUnit(6.1) - 0.5) * 1.5,
                                           (hashUnit(8.3) - 0.5) * 1.5) * visibleHalfExtent)
      pipetteLayer = Int(hashUnit(4.3) * 4) % 4
      lastPipetteMoveWallTime = wallClock
      nextPipetteMoveWallTime = wallClock + 10 + 12 * hashUnit(2.2)
    }
    let settled = wallClock - lastPipetteMoveWallTime > 0.3

    let transient = bass > smoothedBass * 1.8 && bass > bassBaseline
    let cooldownOK = (wallClock - lastDropWallTime) > 2.5
    if transient && cooldownOK && settled && !inResumeGrace {
      lastDropWallTime = wallClock
      emitDrop(size: 0.045 + 0.025 * hashUnit(3.3), scatter: Self.dripScatter)
    } else if wallClock >= nextDripWallTime && settled && !inResumeGrace {
      let size = 0.022 + 0.024 * hashUnit(5.1)
      emitDrop(size: hashUnit(9.9) < 0.18 ? -size : size, scatter: Self.dripScatter)
      let burst = hashUnit(11.3) < 0.15
      nextDripWallTime = wallClock + (burst ? 0.5 + 0.4 * hashUnit(7.7) : 4.0 + 5.0 * hashUnit(7.7))
    }
  }

  private func insideBeam(_ pos: SIMD2<Float>) -> SIMD2<Float> {
    let halfExtent = visibleHalfExtent
    var p = pos.clamped(lowerBound: -halfExtent * 0.85, upperBound: halfExtent * 0.85)
    let maxRadius = Self.apertureRadius * 0.78
    let r = (p.x * p.x + p.y * p.y).squareRoot()
    if r > maxRadius { p *= maxRadius / r }
    return p
  }

  private func hashUnit(_ salt: Float) -> Float {
    let v = sin(Float(frameNumber) * 0.6180339 * salt * 12.9898) * 43758.5453
    return v - v.rounded(.down)
  }

  private var visibleHalfExtent: SIMD2<Float> {
    let longSide = Float(max(simWidth, simHeight, 1))
    return SIMD2<Float>(Float(simWidth), Float(simHeight)) / longSide * 0.5
  }

  private func emitDrop(size: Float, scatter: Float) {
    let jitter = SIMD2<Float>(hashUnit(1.7) - 0.5, hashUnit(2.9) - 0.5) * 2 * scatter
    let pos = insideBeam(pipettePos + jitter)
    let (layer, ontoSameColour) = size < 0 ? (pipetteLayer, false) : chooseBottle(at: pos)
    drops[nextDropSlot] = SIMD4<Float>(pos.x, pos.y, wallClock, Float(layer))
    dropSizes[nextDropSlot] = size
    dropSwellGains[nextDropSlot] = ontoSameColour ? Self.sameColourSwellGain : 1
    nextDropSlot = (nextDropSlot + 1) % 4
  }

  private func chooseBottle(at pos: SIMD2<Float>) -> (layer: Int, ontoSameColour: Bool) {
    let under = phaseUnder(pos)
    let present = (0..<4).filter { under[$0] > 0.2 }
    let absent = (0..<4).filter { under[$0] <= 0.2 }
    func random(_ options: [Int]) -> Int {
      options[Int(hashUnit(14.9) * Float(options.count)) % options.count]
    }

    if !present.isEmpty, hashUnit(13.1) < 0.1 || absent.isEmpty {
      return (present.contains(pipetteLayer) ? pipetteLayer : random(present), true)
    }
    if absent.contains(pipetteLayer) { return (pipetteLayer, false) }
    return (random(absent), false)
  }

  private func phaseUnder(_ pos: SIMD2<Float>) -> SIMD4<Float> {
    let probes = probeBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: Self.probeCount)
    let d = pos - pipettePos
    var index = 0
    if abs(d.x) > Self.dripScatter * 0.5 || abs(d.y) > Self.dripScatter * 0.5 {
      index = abs(d.x) >= abs(d.y) ? (d.x > 0 ? 1 : 2) : (d.y > 0 ? 3 : 4)
    }
    return probes[index]
  }

  func dropAge(_ i: Int) -> Float? {
    let birth = drops[i].z
    let age = wallClock - birth
    guard birth >= 0, age >= 0, age <= Self.dropLifetime else { return nil }
    return age
  }

  func dropStateUniforms() -> LiquidLightDropState {
    let longSide = Float(max(simWidth, simHeight))
    func state(_ i: Int) -> SIMD4<Float> {
      guard let age = dropAge(i) else { return .zero }
      let sign: Float = dropSizes[i] < 0 ? -1 : 1
      return SIMD4<Float>(abs(dropSizes[i]) * longSide, sign, age, dropSwellGains[i])
    }
    return LiquidLightDropState(s0: state(0), s1: state(1), s2: state(2), s3: state(3))
  }

  func rippleUniforms() -> LiquidLightDrops {
    func ripple(_ i: Int) -> SIMD4<Float> {
      guard let age = dropAge(i) else { return SIMD4<Float>(0, 0, -1, 0) }
      return SIMD4<Float>(drops[i].x, drops[i].y, age, abs(dropSizes[i]))
    }
    return LiquidLightDrops(d0: ripple(0), d1: ripple(1), d2: ripple(2), d3: ripple(3))
  }

  func probePipette(encoder: any MTL4ComputeCommandEncoder, phase: MTLTexture) {
    encoder.setComputePipelineState(probePipeline)
    argumentTable.setTexture(phase.gpuResourceID, index: 0)
    let params = LiquidProbeParams(simSize: SIMD2<Float>(Float(simWidth), Float(simHeight)),
                                   center: pipettePos,
                                   offset: SIMD2<Float>(repeating: Self.dripScatter))
    argumentTable.setAddress(writeUniform(params), index: 0)
    argumentTable.setAddress(probeBuffer.gpuAddress, index: 1)
    encoder.dispatchThreads(threadsPerGrid: MTLSize(width: Self.probeCount, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: Self.probeCount, height: 1, depth: 1))
  }
}

#endif
