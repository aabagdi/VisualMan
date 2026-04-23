//
//  AbstractExpressionismRenderer+Rendering.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import Metal
import QuartzCore

extension AbstractExpressionismRenderer {
  private static let warmColors: [SIMD3<Float>] = [
    SIMD3(0.85, 0.15, 0.05), SIMD3(0.90, 0.55, 0.05),
    SIMD3(0.80, 0.60, 0.10), SIMD3(0.55, 0.25, 0.08),
    SIMD3(0.35, 0.15, 0.08), SIMD3(0.75, 0.05, 0.20),
  ]
  private static let coolColors: [SIMD3<Float>] = [
    SIMD3(0.05, 0.10, 0.70), SIMD3(0.05, 0.35, 0.65),
    SIMD3(0.10, 0.40, 0.25), SIMD3(0.25, 0.10, 0.50),
    SIMD3(0.02, 0.20, 0.45), SIMD3(0.15, 0.55, 0.35),
  ]

  private func nextSeed() -> Float {
    strokeSeed &+= 1
    let x = strokeSeed &* 2654435769
    return Float(x) / Float(UInt32.max)
  }

  private func pickColor(warm: Bool) -> SIMD3<Float> {
    let palette = warm ? Self.warmColors : Self.coolColors
    let r = nextSeed()
    let idx = Int(r * Float(palette.count)) % palette.count
    var color = palette[idx]
    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.1
    color = pointwiseMin(pointwiseMax(color + variation, .zero), SIMD3(repeating: 1))
    return color
  }

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
        if gap > 2.0 { resumeFadeIn = 0 }
      }
    } else {
      dt = Float(max(1.0 / 240.0, min(1.0 / 30.0, gap)))
    }
  }

  func processAudio(bass: Float, mid: Float, high: Float) -> SIMD3<Float> {
    let now = CACurrentMediaTime()
    let gap = lastFrameTime == 0 ? 0 : (now - lastFrameTime)
    handleResumeState(gap: gap)
    lastFrameTime = now
    wallClock += dt
    time += dt
    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)

    let input = SIMD3<Float>(bass, mid, high)
    let fastA = 1 - exp(-dt / 0.015)
    let fastD = 1 - exp(-dt / 0.15)
    var fastRate = SIMD3<Float>(repeating: fastD)
    fastRate.replace(with: SIMD3<Float>(repeating: fastA), where: input .> envelope)
    envelope += (input - envelope) * fastRate

    let slowA = 1 - exp(-dt / 0.4)
    slowEnvelope += (input - slowEnvelope) * slowA

    let bassA = 1 - exp(-dt / (bass > smoothedBass ? 0.06 : 0.25))
    smoothedBass += (bass - smoothedBass) * bassA

    hueOffset += dt * 0.02

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }

  func generateStrokes(audio: SIMD3<Float>) -> [AbExStroke] {
    var strokes = [AbExStroke]()
    if resumeSuppressionRemaining > 0 { return strokes }

    let bass = audio.x, mid = audio.y, high = audio.z
    let energy = (bass + mid + high) / 3.0

    let bassTransient = bass > smoothedBass * 1.4 && bass > 0.06
    if bassTransient && (wallClock - lastGesturalTime) > 0.2 && strokes.count < 8 {
      lastGesturalTime = wallClock
      let count = bass > 0.3 ? 2 : 1
      for _ in 0..<count where strokes.count < 8 {
        let x = (nextSeed() - 0.5) * 1.0
        let y = (nextSeed() - 0.5) * 0.7
        let angle = nextSeed() * .pi * 2
        let halfLen = 0.14 + bass * 0.28 + nextSeed() * 0.10
        let halfWidth = 0.014 + bass * 0.022 + nextSeed() * 0.010
        let opacity = 0.85 + bass * 0.15
        let bristleSeed = nextSeed() * 100
        let color = pickColor(warm: nextSeed() > 0.3)
        strokes.append(AbExStroke(
          posAngle: SIMD4(x, y, angle, halfLen),
          sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
          color: SIMD4(color.x, color.y, color.z, 0)))
      }
    }

    if mid > 0.04 && (wallClock - lastWashTime) > 0.3 && strokes.count < 8 {
      lastWashTime = wallClock
      let x = (nextSeed() - 0.5) * 0.8
      let y = (nextSeed() - 0.5) * 0.5
      let angle = nextSeed() * .pi
      let halfLen = 0.18 + mid * 0.25
      let halfWidth = 0.12 + mid * 0.18
      let opacity = 0.10 + mid * 0.14
      let bristleSeed = nextSeed() * 100
      let color = pickColor(warm: nextSeed() > 0.5)
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, halfLen),
        sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
        color: SIMD4(color.x, color.y, color.z, 0)))
    }

    // Treble → splatter
    if high > 0.04 && (wallClock - lastSplatterTime) > 0.12 && strokes.count < 8 {
      lastSplatterTime = wallClock
      let count = high > 0.25 ? 2 : 1
      for _ in 0..<count where strokes.count < 8 {
        let x = (nextSeed() - 0.5) * 1.1
        let y = (nextSeed() - 0.5) * 0.8
        let radius = 0.010 + high * 0.024 + nextSeed() * 0.012
        let opacity = 0.85 + high * 0.15
        let bristleSeed = nextSeed() * 100
        let color = pickColor(warm: nextSeed() > 0.4)
        strokes.append(AbExStroke(
          posAngle: SIMD4(x, y, 0, radius),
          sizeOpacity: SIMD4(radius, opacity, bristleSeed, 2),
          color: SIMD4(color.x, color.y, color.z, 0)))
      }
    }

    if energy > 0.01 && strokes.count < 8 && nextSeed() < 0.04 {
      let x = (nextSeed() - 0.5) * 0.7
      let y = (nextSeed() - 0.5) * 0.4
      let angle = time * 0.1 + nextSeed() * .pi
      let halfLen = 0.20 + nextSeed() * 0.15
      let halfWidth = 0.14 + nextSeed() * 0.10
      let opacity: Float = 0.04 + energy * 0.05
      let bristleSeed = nextSeed() * 100
      let color = pickColor(warm: nextSeed() > 0.5)
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, halfLen),
        sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
        color: SIMD4(color.x, color.y, color.z, 0)))
    }

    return strokes
  }

  func renderPaint(encoder: any MTL4ComputeCommandEncoder,
                   colorIn: MTLTexture, colorOut: MTLTexture,
                   heightIn: MTLTexture, heightOut: MTLTexture,
                   params: AbExParams, strokes: [AbExStroke]) {
    encoder.setComputePipelineState(paintPipeline)
    argumentTable.setTexture(colorIn.gpuResourceID,  index: 0)
    argumentTable.setTexture(colorOut.gpuResourceID, index: 1)
    argumentTable.setTexture(heightIn.gpuResourceID, index: 2)
    argumentTable.setTexture(heightOut.gpuResourceID, index: 3)
    argumentTable.setAddress(writeUniform(params), index: 0)

    if strokes.isEmpty {
      let empty = AbExStroke(posAngle: .zero, sizeOpacity: .zero, color: .zero)
      argumentTable.setAddress(writeUniform(empty), index: 1)
    } else {
      argumentTable.setAddress(writeUniformArray(strokes), index: 1)
    }

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: colorOut.width, height: colorOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func renderDiffuse(encoder: any MTL4ComputeCommandEncoder,
                     colorIn: MTLTexture, colorOut: MTLTexture,
                     heightIn: MTLTexture, heightOut: MTLTexture,
                     params: AbExParams) {
    encoder.setComputePipelineState(diffusePipeline)
    argumentTable.setTexture(colorIn.gpuResourceID,   index: 0)
    argumentTable.setTexture(colorOut.gpuResourceID,  index: 1)
    argumentTable.setTexture(heightIn.gpuResourceID,  index: 2)
    argumentTable.setTexture(heightOut.gpuResourceID, index: 3)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: colorOut.width, height: colorOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func renderLight(encoder: any MTL4ComputeCommandEncoder,
                   colorIn: MTLTexture, heightIn: MTLTexture,
                   colorOut: MTLTexture,
                   params: AbExParams) {
    encoder.setComputePipelineState(lightPipeline)
    argumentTable.setTexture(colorIn.gpuResourceID,  index: 0)
    argumentTable.setTexture(heightIn.gpuResourceID, index: 1)
    argumentTable.setTexture(colorOut.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: colorOut.width, height: colorOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }
}
