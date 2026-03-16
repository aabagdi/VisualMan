//
//  NavierStokesRenderer+AudioSplats.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import simd

extension NavierStokesRenderer {
  func injectAudioSplats(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float,
                         mid: Float,
                         high: Float) {
    let center = Float(gridSize) / 2.0
    let s = Float(gridSize) / 1536.0
    let audioEnergy = (bass + mid + high) / 3.0

    let bassOnset = max(bass - prevBass, 0)
    let midOnset = max(mid - prevMid, 0)
    prevBass = bass
    prevMid = mid

    injectVortex(encoder: encoder, center: center, s: s, audioEnergy: audioEnergy)
    injectBass(encoder: encoder, center: center, s: s,
               bass: bass, bassOnset: bassOnset)
    injectMid(encoder: encoder, center: center, s: s,
              mid: mid, midOnset: midOnset)
    injectHigh(encoder: encoder, center: center, s: s, high: high)
  }

  private func injectVortex(encoder: any MTL4ComputeCommandEncoder,
                            center: Float,
                            s: Float,
                            audioEnergy: Float) {
    let vortexAngle = time * 0.3
    let vortexR: Float = 80.0 * s
    let strength: Float = 20.0 * s * (0.3 + audioEnergy * 0.7)
    for i in 0..<2 {
      if i > 0 { encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch) }
      let a = vortexAngle + Float(i) * .pi
      let pos = SIMD2<Float>(center + cos(a) * vortexR, center + sin(a) * vortexR)
      splatForce(encoder: encoder, pos: pos,
                 force: SIMD3<Float>(-sin(a) * strength, cos(a) * strength, 0), radius: 100.0 * s)
    }
    let hue = fmod(time * 0.1, 1.0)
    let color = SIMD3<Float>(
      0.3 + 0.2 * sin(hue * .pi * 2.0),
      0.15 + 0.2 * sin(hue * .pi * 2.0 + 2.094),
      0.25 + 0.2 * sin(hue * .pi * 2.0 + 4.189)
    )
    splatDye(encoder: encoder, pos: SIMD2<Float>(center, center),
             color: color * (0.3 + audioEnergy * 0.7), radius: 90.0 * s)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  private func injectBass(encoder: any MTL4ComputeCommandEncoder,
                          center: Float,
                          s: Float,
                          bass: Float,
                          bassOnset: Float) {
    let b2 = bass * bass
    let bassBeat = bassOnset > 0.05

    guard bass > 0.03 else { return }

    // Radial shockwave
    let angle = time * 0.5
    let pulseR: Float = 100.0 * s + b2 * 120.0 * s
    let pulsePos = SIMD2<Float>(center + cos(angle) * pulseR * 0.3,
                                 center + sin(angle) * pulseR * 0.3)
    let forceScale: Float = bassBeat ? 350.0 : 200.0
    splatForce(encoder: encoder, pos: pulsePos,
               force: SIMD3<Float>(cos(angle) * b2 * forceScale * s,
                                    sin(angle) * b2 * forceScale * s, 0),
               radius: (80.0 + b2 * 80.0) * s)
    let bassHue = fmod(time * 0.15, 1.0)
    let bright: Float = bassBeat ? 3.0 : 1.5
    splatDye(encoder: encoder, pos: pulsePos,
             color: SIMD3<Float>(b2 * bright * (1.5 + 0.5 * sin(bassHue * .pi * 2.0)),
                                  b2 * bright * (0.4 + 0.4 * sin(bassHue * .pi * 2.0 + 1.0)),
                                  b2 * bright * (0.15 + 0.3 * sin(bassHue * .pi * 2.0 + 2.5))),
             radius: (60.0 + b2 * 60.0) * s)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    if bassBeat {
      let burstAngle = time * 1.7
      for i in 0..<3 {
        if i > 0 { encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch) }
        let a = burstAngle + Float(i) * 2.094
        let pos = SIMD2<Float>(center + cos(a) * 60.0 * s, center + sin(a) * 60.0 * s)
        let f = bassOnset * 300.0 * s
        splatForce(encoder: encoder, pos: pos,
                   force: SIMD3<Float>(cos(a) * f, sin(a) * f, 0), radius: 120.0 * s)
      }
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }

  private func injectMid(encoder: any MTL4ComputeCommandEncoder,
                         center: Float,
                         s: Float,
                         mid: Float,
                         midOnset: Float) {
    let m2 = mid * mid
    let midBeat = midOnset > 0.03

    guard mid > 0.03 else { return }

    let numPairs = midBeat ? 4 : 2
    for i in 0..<numPairs {
      let angle = time * 0.8 + Float(i) * (.pi * 2.0 / Float(numPairs))
      let orbitR = (200.0 + m2 * 200.0) * s
      let pos = SIMD2<Float>(center + cos(angle) * orbitR, center + sin(angle) * orbitR)
      let tx = -sin(angle) * m2 * 250.0 * s
      let ty = cos(angle) * m2 * 250.0 * s
      splatForce(encoder: encoder, pos: pos,
                 force: SIMD3<Float>(tx, ty, 0), radius: (50.0 + m2 * 40.0) * s)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      let cAngle = angle + 0.5
      let cPos = SIMD2<Float>(center + cos(cAngle) * orbitR * 0.5,
                               center + sin(cAngle) * orbitR * 0.5)
      splatForce(encoder: encoder, pos: cPos,
                 force: SIMD3<Float>(-tx * 0.4, -ty * 0.4, 0), radius: 40.0 * s)

      let midHue = fmod(time * 0.12 + Float(i) * 0.25, 1.0)
      let bright: Float = midBeat ? 2.5 : 1.2
      splatDye(encoder: encoder, pos: pos,
               color: SIMD3<Float>(m2 * bright * (0.3 + 0.5 * sin(midHue * .pi * 2.0)),
                                    m2 * bright * (0.8 + 0.5 * sin(midHue * .pi * 2.0 + 2.0)),
                                    m2 * bright * (1.2 + 0.4 * sin(midHue * .pi * 2.0 + 4.0))),
               radius: (40.0 + m2 * 30.0) * s)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }

  private func injectHigh(encoder: any MTL4ComputeCommandEncoder,
                          center: Float,
                          s: Float,
                          high: Float) {
    let h2 = high * high
    guard high > 0.08 else { return }

    let sparkCount = min(Int(high * 8), 5)
    for i in 0..<sparkCount {
      let a = time * 2.5 + Float(i) * 1.57 + sin(time * 1.8 + Float(i)) * 1.5
      let r = (120.0 + sin(time * 1.3 + Float(i) * 2.7) * 200.0) * s
      let pos = SIMD2<Float>(center + cos(a) * r, center + sin(a) * r)

      let f = h2 * 150.0 * s
      splatForce(encoder: encoder, pos: pos,
                 force: SIMD3<Float>(cos(a + 1.5) * f, sin(a + 1.5) * f, 0),
                 radius: (20.0 + h2 * 25.0) * s)

      let hue = fmod(time * 0.25 + Float(i) * 0.2, 1.0)
      splatDye(encoder: encoder, pos: pos,
               color: SIMD3<Float>(h2 * (1.2 + 1.0 * sin(hue * .pi * 2.0)),
                                    h2 * (0.8 + 1.2 * sin(hue * .pi * 2.0 + 2.094)),
                                    h2 * (1.5 + 1.0 * sin(hue * .pi * 2.0 + 4.189))),
               radius: (15.0 + h2 * 20.0) * s)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
}
