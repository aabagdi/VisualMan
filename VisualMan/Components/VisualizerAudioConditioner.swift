//
//  VisualizerAudioConditioner.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import Accelerate
import QuartzCore

struct VisualizerAudioConditioner {
  enum Constants {
    static let flashLimitSeconds: Float = 0.35
    static let defaultFrameInterval: Float = 1.0 / 60.0
    static let maxFrameInterval: Float = 0.1
  }

  private var levels: [1024 of Float] = .init(repeating: 0)
  private var bars: [32 of Float] = .init(repeating: 0)
  private var lastTime: CFTimeInterval?

  mutating func reset() {
    levels = .init(repeating: 0)
    bars = .init(repeating: 0)
    lastTime = nil
  }

  mutating func condition(
    levels inputLevels: inout [1024 of Float],
    bars inputBars: inout [32 of Float],
    waveform: inout [1024 of Float],
    intensity: VisualizerIntensity,
    limitsFlashing: Bool,
    now: CFTimeInterval = CACurrentMediaTime()
  ) {
    let dt = lastTime.map { min(max(Float(now - $0), 0), Constants.maxFrameInterval) }
      ?? Constants.defaultFrameInterval
    lastTime = now

    let riseSeconds = max(intensity.riseSeconds, limitsFlashing ? Constants.flashLimitSeconds : 0)
    let maxRise = riseSeconds > 0 ? dt / riseSeconds : .infinity
    let maxFall = limitsFlashing ? dt / Constants.flashLimitSeconds : .infinity
    let gain = intensity.gain

    inputLevels.withUnsafeElementPointer { input in
      levels.withUnsafeElementPointer { state in
        Self.apply(to: input, state: state, count: 1024, gain: gain, maxRise: maxRise, maxFall: maxFall)
      }
    }
    inputBars.withUnsafeElementPointer { input in
      bars.withUnsafeElementPointer { state in
        Self.apply(to: input, state: state, count: 32, gain: gain, maxRise: maxRise, maxFall: maxFall)
      }
    }
    if gain != 1 {
      waveform.withUnsafeElementPointer { samples in
        Self.scale(samples, count: 1024, by: gain, lower: -1, upper: 1)
      }
    }
  }

  private static func apply(
    to input: UnsafeMutablePointer<Float>,
    state: UnsafeMutablePointer<Float>,
    count: Int,
    gain: Float,
    maxRise: Float,
    maxFall: Float
  ) {
    let n = vDSP_Length(count)
    if gain != 1 {
      scale(input, count: count, by: gain, lower: 0, upper: 1)
    }
    if maxRise.isFinite || maxFall.isFinite {
      var lower = -maxFall
      var upper = maxRise
      vDSP_vsub(state, 1, input, 1, input, 1, n)
      vDSP_vclip(input, 1, &lower, &upper, input, 1, n)
      vDSP_vadd(state, 1, input, 1, input, 1, n)
    }
    state.update(from: input, count: count)
  }

  private static func scale(
    _ values: UnsafeMutablePointer<Float>,
    count: Int,
    by gain: Float,
    lower: Float,
    upper: Float
  ) {
    let n = vDSP_Length(count)
    var gain = gain
    vDSP_vsmul(values, 1, &gain, values, 1, n)
    guard gain > 1 else { return }
    var lower = lower
    var upper = upper
    vDSP_vclip(values, 1, &lower, &upper, values, 1, n)
  }
}
