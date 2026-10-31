//
//  AbstractExpressionismRenderer+Audio.swift
//  VisualMan
//
//  Created by on 4/23/26.
//

#if !targetEnvironment(simulator)
import QuartzCore
import simd

extension AbstractExpressionismRenderer {
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

    let atmTarget = min(1.0, ((slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0) * 1.6)
    let atmRate = 1 - exp(-dt / (atmTarget > atmosphereIntensity ? 1.5 : 3.0))
    atmosphereIntensity += (atmTarget - atmosphereIntensity) * atmRate

    atmosphereHue = (atmosphereHue + dt * 0.0033).truncatingRemainder(dividingBy: 1.0)

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }
}

#endif
