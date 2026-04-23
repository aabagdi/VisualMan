//
//  LiquidLightRenderer+Rendering.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

import Metal
import QuartzCore

extension LiquidLightRenderer {
  private func handleResumeState(gap: Double) {
    let gapResume = gap > 0.2
    let isResume = (lastFrameTime == 0) || gapResume

    if isResume {
      dt = 0
      if gapResume {
        resumeSuppressionRemaining = Self.resumeFadeDuration
        envelope = .zero
        slowEnvelope = .zero
        smoothedBass = 0
        smoothedSpeed = 0.25
        if gap > 2.0 {
          resumeFadeIn = 0
        }
      }
    } else {
      dt = Float(max(1.0 / 240.0, min(1.0 / 30.0, gap)))
    }
  }

  private func detectAndEmitDrop(bass: Float, inResumeGrace: Bool) {
    let bassBaseline: Float = 0.08
    let bassUpTau: Float = 0.06
    let bassDownTau: Float = 0.20
    let bassA = 1 - exp(-dt / (bass > smoothedBass ? bassUpTau : bassDownTau))
    smoothedBass += (bass - smoothedBass) * bassA

    let transient = bass > smoothedBass * 1.6 && bass > bassBaseline
    let cooldownOK = (wallClock - lastDropWallTime) > 0.35
    if transient && cooldownOK && !inResumeGrace {
      lastDropWallTime = wallClock
      dropHueCounter = (dropHueCounter + 0.37).truncatingRemainder(dividingBy: 1.0)
      let seed = Float(frameNumber) * 0.6180339
      let x = sin(seed * 12.9) * 0.4
      let y = cos(seed * 7.3) * 0.35
      drops[nextDropSlot] = SIMD4<Float>(x, y, time, dropHueCounter)
      nextDropSlot = (nextDropSlot + 1) % 4
    }
  }

  func processAudio(bass: Float, mid: Float, high: Float) -> SIMD3<Float> {
    let now = CACurrentMediaTime()
    let gap = lastFrameTime == 0 ? 0 : (now - lastFrameTime)
    handleResumeState(gap: gap)
    lastFrameTime = now
    wallClock += dt

    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)
    let inResumeGrace = resumeSuppressionRemaining > 0

    let input = SIMD3<Float>(bass, mid, high)

    let fastAttackA = 1 - exp(-dt / 0.012)
    let fastDecayA  = 1 - exp(-dt / 0.12)
    var fastRate = SIMD3<Float>(repeating: fastDecayA)
    fastRate.replace(with: SIMD3<Float>(repeating: fastAttackA), where: input .> envelope)
    envelope += (input - envelope) * fastRate

    let slowA = 1 - exp(-dt / 0.35)
    slowEnvelope += (input - slowEnvelope) * slowA

    let audioEnergy = slowEnvelope.sum() / 3.0
    let targetSpeed = 0.25 + audioEnergy * 0.6
    let speedA = 1 - exp(-dt / (targetSpeed > smoothedSpeed ? 0.18 : 0.25))
    smoothedSpeed += (targetSpeed - smoothedSpeed) * speedA
    time += dt * smoothedSpeed

    detectAndEmitDrop(bass: bass, inResumeGrace: inResumeGrace)

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }

  func renderLiquidLight(encoder: any MTL4ComputeCommandEncoder,
                         output: MTLTexture,
                         audio: SIMD3<Float>) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(output.gpuResourceID, index: 0)

    let colorShift = time * 0.015 + audio.y * 0.08

    func computeDrop(_ d: SIMD4<Float>) -> (precomp: SIMD4<Float>, color: SIMD4<Float>) {
      let age = time - d.z
      let alive: Float = (d.z >= 0 && age >= 0 && age <= 4.0) ? 1.0 : 0.0
      let ringRadius = age * 0.35
      let tNorm = max(0, min(1, age * 0.25))
      let smoothFade = max(0, 1.0 - tNorm * tNorm * (3.0 - 2.0 * tNorm))
      let easeIn = max(0, min(1, age / 0.1))
      let fade = smoothFade * easeIn * easeIn * (3.0 - 2.0 * easeIn)
      let tint = Self.liquidColor(id: d.w, t: colorShift)
      return (SIMD4<Float>(ringRadius, fade, alive, 0),
              SIMD4<Float>(tint.x, tint.y, tint.z, 0))
    }
    let r0 = computeDrop(drops[0])
    let r1 = computeDrop(drops[1])
    let r2 = computeDrop(drops[2])
    let r3 = computeDrop(drops[3])

    let params = LiquidLightParams(
      time: time, bass: audio.x, mid: audio.y, high: audio.z,
      drops: LiquidLightDrops(d0: drops[0], d1: drops[1], d2: drops[2], d3: drops[3]),
      dropPrecomp: LiquidLightDropPrecomp(p0: r0.precomp, p1: r1.precomp,
                                          p2: r2.precomp, p3: r3.precomp),
      dropColors: LiquidLightDropColors(c0: r0.color, c1: r1.color,
                                        c2: r2.color, c3: r3.color)
    )
    argumentTable.setAddress(writeUniform(params), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  static func liquidColor(id: Float, t: Float) -> SIMD3<Float> {
    var h = (id * 5.0 + t).truncatingRemainder(dividingBy: 1.0)
    if h < 0 { h += 1 }
    func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ u: Float) -> SIMD3<Float> { a + (b - a) * u }
    if h < 0.18 {
      return mix(SIMD3(0.6, 0.0, 0.02), SIMD3(0.85, 0.02, 0.1), h / 0.18)
    } else if h < 0.35 {
      return mix(SIMD3(0.85, 0.02, 0.1), SIMD3(0.6, 0.0, 0.55), (h - 0.18) / 0.17)
    } else if h < 0.52 {
      return mix(SIMD3(0.6, 0.0, 0.55), SIMD3(0.02, 0.06, 0.7), (h - 0.35) / 0.17)
    } else if h < 0.68 {
      return mix(SIMD3(0.02, 0.06, 0.7), SIMD3(0.0, 0.5, 0.6), (h - 0.52) / 0.16)
    } else if h < 0.84 {
      return mix(SIMD3(0.0, 0.5, 0.6), SIMD3(0.7, 0.35, 0.0), (h - 0.68) / 0.16)
    } else {
      return mix(SIMD3(0.7, 0.35, 0.0), SIMD3(0.6, 0.0, 0.02), (h - 0.84) / 0.16)
    }
  }

  func renderBlur(encoder: any MTL4ComputeCommandEncoder,
                  input: MTLTexture,
                  output: MTLTexture,
                  audio: SIMD3<Float>) {
    encoder.setComputePipelineState(blurPipeline)

    argumentTable.setTexture(input.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)

    let blurParams = BlurParams(
      innerRadius: 0.45 + audio.y * 0.05,
      outerRadius: 1.15,
      maxBlurRadius: 8.0 + audio.y * 2.0,
      texWidth: Float(input.width),
      texHeight: Float(input.height),
      bass: audio.x,
      mid: audio.y
    )
    argumentTable.setAddress(writeUniform(blurParams), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }
}
