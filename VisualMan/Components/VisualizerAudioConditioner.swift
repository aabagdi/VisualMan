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
    static let flashLimitSeconds: Float = 0.5
    static let defaultFrameInterval: Float = 1.0 / 60.0
    static let maxFrameInterval: Float = 0.1
    static let transientAverageSeconds: Float = 0.25
    static let fadeFactorPerSecond: Float = 0.000_466
  }

  private struct Stage {
    var gain: Float
    var transientBoost: Float
    var averageAlpha: Float
    var maxRise: Float
    var maxFall: Float
  }

  private var levels: [1024 of Float] = .init(repeating: 0)
  private var bars: [32 of Float] = .init(repeating: 0)
  private var levelAverages: [1024 of Float] = .init(repeating: 0)
  private var barAverages: [32 of Float] = .init(repeating: 0)
  private var waveformPeak: Float = 0
  private var lastTime: CFTimeInterval?

  mutating func reset() {
    levels = .init(repeating: 0)
    bars = .init(repeating: 0)
    levelAverages = .init(repeating: 0)
    barAverages = .init(repeating: 0)
    waveformPeak = 0
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
    let dt = advance(to: now)
    let stage = makeStage(dt: dt, intensity: intensity, limitsFlashing: limitsFlashing)

    inputLevels.withUnsafeElementPointer { input in
      levels.withUnsafeElementPointer { state in
        levelAverages.withUnsafeElementPointer { average in
          Self.apply(stage, to: input, state: state, average: average, count: 1024)
        }
      }
    }
    inputBars.withUnsafeElementPointer { input in
      bars.withUnsafeElementPointer { state in
        barAverages.withUnsafeElementPointer { average in
          Self.apply(stage, to: input, state: state, average: average, count: 32)
        }
      }
    }
    let waveformGain = intensity.waveformGain
    waveform.withUnsafeElementPointer { samples in
      if waveformGain != 1 {
        Self.scale(samples, count: 1024, by: waveformGain, lower: -1, upper: 1)
      }
      limitWaveformRise(samples, maxRise: stage.maxRise)
    }
  }

  mutating func fade(
    levels inputLevels: inout [1024 of Float],
    bars inputBars: inout [32 of Float],
    waveform: inout [1024 of Float],
    intensity: VisualizerIntensity,
    limitsFlashing: Bool,
    now: CFTimeInterval = CACurrentMediaTime()
  ) {
    let dt = advance(to: now)
    let stage = makeStage(dt: dt, intensity: intensity, limitsFlashing: limitsFlashing)
    var factor = pow(Constants.fadeFactorPerSecond, dt)

    inputLevels.withUnsafeElementPointer { input in
      levels.withUnsafeElementPointer { state in
        Self.fade(input, state: state, by: factor, maxFall: stage.maxFall, count: 1024)
      }
    }
    inputBars.withUnsafeElementPointer { input in
      bars.withUnsafeElementPointer { state in
        Self.fade(input, state: state, by: factor, maxFall: stage.maxFall, count: 32)
      }
    }
    waveform.withUnsafeElementPointer { samples in
      var peak: Float = 0
      vDSP_maxmgv(samples, 1, &peak, 1024)
      if peak > 0, stage.maxFall.isFinite {
        factor = max(factor, (peak - stage.maxFall) / peak)
      }
      vDSP_vsmul(samples, 1, &factor, samples, 1, 1024)
      waveformPeak = peak * factor
    }
  }

  private mutating func advance(to now: CFTimeInterval) -> Float {
    let dt = lastTime.map { min(max(Float(now - $0), 0), Constants.maxFrameInterval) }
      ?? Constants.defaultFrameInterval
    lastTime = now
    return dt
  }

  private func makeStage(dt: Float, intensity: VisualizerIntensity, limitsFlashing: Bool) -> Stage {
    let flashSeconds = limitsFlashing ? Constants.flashLimitSeconds : 0
    let riseSeconds = max(intensity.riseSeconds, flashSeconds)
    let fallSeconds = max(intensity.fallSeconds, flashSeconds)
    return Stage(
      gain: intensity.gain,
      transientBoost: intensity.transientBoost,
      averageAlpha: 1 - exp(-dt / Constants.transientAverageSeconds),
      maxRise: riseSeconds > 0 ? dt / riseSeconds : .infinity,
      maxFall: fallSeconds > 0 ? dt / fallSeconds : .infinity
    )
  }

  private mutating func limitWaveformRise(_ samples: UnsafeMutablePointer<Float>, maxRise: Float) {
    var peak: Float = 0
    vDSP_maxmgv(samples, 1, &peak, 1024)
    let limited = min(peak, waveformPeak + maxRise)
    if peak > limited {
      var factor = limited / peak
      vDSP_vsmul(samples, 1, &factor, samples, 1, 1024)
    }
    waveformPeak = limited
  }

  private static func fade(
    _ input: UnsafeMutablePointer<Float>,
    state: UnsafeMutablePointer<Float>,
    by factor: Float,
    maxFall: Float,
    count: Int
  ) {
    let n = vDSP_Length(count)
    var factor = factor
    vDSP_vsmul(input, 1, &factor, input, 1, n)
    if maxFall.isFinite {
      var lower = -maxFall
      var upper: Float = 0
      vDSP_vsub(state, 1, input, 1, input, 1, n)
      vDSP_vclip(input, 1, &lower, &upper, input, 1, n)
      vDSP_vadd(state, 1, input, 1, input, 1, n)
    }
    state.update(from: input, count: count)
  }

  private static func apply(
    _ stage: Stage,
    to input: UnsafeMutablePointer<Float>,
    state: UnsafeMutablePointer<Float>,
    average: UnsafeMutablePointer<Float>,
    count: Int
  ) {
    let n = vDSP_Length(count)
    for i in 0..<count {
      let deviation = input[i] - average[i]
      average[i] += deviation * stage.averageAlpha
      if stage.transientBoost > 0 {
        input[i] = min(max(input[i] + deviation * stage.transientBoost, 0), 1)
      }
    }
    if stage.gain != 1 {
      scale(input, count: count, by: stage.gain, lower: 0, upper: 1)
    }
    let maxRise = stage.maxRise
    let maxFall = stage.maxFall
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
