//
//  BassHapticAnalyzer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import AVFoundation
import Accelerate

nonisolated enum BassHapticAnalyzer {
  enum Constants {
    static let analysisRate: Double = 1000
    static let readFrames: AVAudioFrameCount = 32768
    static let decimationCutoff: Double = 500
    static let decimationTransition: Double = 600
    static let clickCutoff: Double = 2000
    static let bassLowCut: Double = 22
    static let bassHighCut: Double = 150
    static let subHighCut: Double = 60
    static let bandFilterDuration: TimeInterval = 0.3
    static let hilbertDuration: TimeInterval = 0.4
    static let smoothingDuration: TimeInterval = 0.02

    static let silenceAmplitude: Float = 1e-4
    static let activeFraction: Float = 0.03
    static let referencePercentile: Float = 0.95
    static let floorDecibels: Float = -24
    static let headroomDecibels: Float = 3

    static let onsetRise: Float = 3
    static let onsetNovelty: Float = 2
    static let noveltyWindow: TimeInterval = 0.05
    static let peakDrop: Float = 1
    static let peakHold: TimeInterval = 0.08
    static let minimumOnsetSpacing: TimeInterval = 0.06
    static let onsetLag: TimeInterval = 0.008

    static let clickSearch: TimeInterval = 0.015
    static let clickBackground: TimeInterval = 0.025
    static let clickGap: TimeInterval = 0.002
    static let clickRatio: Float = 4
    static let clickFloor: Float = 1e-7

    static let pulseEndDrop: Float = 18
    static let releaseDuration: TimeInterval = 0.02
    static let minimumPulseDuration: TimeInterval = 0.03
    static let maximumPulseDuration: TimeInterval = 20
    static let minimumPulseIntensity: Float = 0.1
    static let envelopeTolerance: Float = 0.04

    static let attackWindow: TimeInterval = 0.04
    static let attackLookBehind: TimeInterval = 0.02
    static let attackRise: ClosedRange<Float> = 2 ... 10
    static let minimumTransientIntensity: Float = 0.1
    static let clickSharpness: Float = 0.8
    static let softSharpness: Float = 0.5
    static let pulseSharpness: ClosedRange<Float> = 0.1 ... 0.4
    static let sharpnessWindow: TimeInterval = 0.15
  }

  struct Decimated {
    var low: [Float]
    var click: [Float]
    var rate: Double
  }

  struct Onset {
    var index: Int
    var isNovel: Bool
    var hasClick: Bool
  }

  struct OpenPulse {
    var start: Int
    var peak: Float
    var onset: Onset?
  }

  struct Signals {
    var level: [Float]
    var intensity: [Float]
    var bassPower: [Float]
    var subPower: [Float]
    var rate: Double
  }

  @concurrent
  static func analyze(url: URL) async throws -> BassHapticTrack {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let decimated = try decimate(url: url)
    try Task.checkCancellation()
    return track(from: decimated)
  }

  private static func decimate(url: URL) throws -> Decimated {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let sampleRate = format.sampleRate
    let channelCount = Int(format.channelCount)
    let factor = max(1, Int((sampleRate / Constants.analysisRate).rounded()))
    let rate = sampleRate / Double(factor)

    guard channelCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Constants.readFrames),
          var highPass = vDSP.Biquad(
            coefficients: highPassCoefficients(cutoff: Constants.clickCutoff, sampleRate: sampleRate),
            channelCount: 1,
            sectionCount: 1,
            ofType: Float.self
          ) else {
      return Decimated(low: [], click: [], rate: rate)
    }

    let lowTaps = lowPassTaps(
      count: oddCount(3.3 * sampleRate / Constants.decimationTransition),
      cutoff: Constants.decimationCutoff,
      sampleRate: sampleRate
    )
    let boxTaps = [Float](repeating: 1 / Float(factor), count: factor)
    var lowPending = [Float](repeating: 0, count: lowTaps.count / 2)
    var clickPending = [Float](repeating: 0, count: factor / 2)
    var low: [Float] = []
    var click: [Float] = []
    low.reserveCapacity(Int(file.length) / factor + 2)
    click.reserveCapacity(Int(file.length) / factor + 2)

    while file.framePosition < file.length {
      try Task.checkCancellation()
      try file.read(into: buffer)
      let frames = Int(buffer.frameLength)
      guard frames > 0, let channels = buffer.floatChannelData else { break }

      let mono = monoSamples(from: channels, channelCount: channelCount, frames: frames)
      clickPending.append(contentsOf: vDSP.square(highPass.apply(input: mono)))
      lowPending.append(contentsOf: mono)
      drain(&lowPending, through: lowTaps, factor: factor, into: &low)
      drain(&clickPending, through: boxTaps, factor: factor, into: &click)
    }

    lowPending.append(contentsOf: repeatElement(0, count: lowTaps.count / 2))
    clickPending.append(contentsOf: repeatElement(0, count: factor - 1))
    drain(&lowPending, through: lowTaps, factor: factor, into: &low)
    drain(&clickPending, through: boxTaps, factor: factor, into: &click)

    let count = min(low.count, click.count)
    low.removeLast(low.count - count)
    click.removeLast(click.count - count)
    return Decimated(low: low, click: click, rate: rate)
  }

  private static func monoSamples(
    from channels: UnsafePointer<UnsafeMutablePointer<Float>>,
    channelCount: Int,
    frames: Int
  ) -> [Float] {
    var mono = [Float](UnsafeBufferPointer(start: channels[0], count: frames))
    guard channelCount > 1 else { return mono }
    for channel in 1 ..< channelCount {
      mono = vDSP.add(mono, UnsafeBufferPointer(start: channels[channel], count: frames))
    }
    return vDSP.multiply(1 / Float(channelCount), mono)
  }

  private static func drain(_ pending: inout [Float], through taps: [Float], factor: Int, into output: inout [Float]) {
    guard pending.count >= taps.count else { return }
    let count = (pending.count - taps.count) / factor + 1
    let consumed = (count - 1) * factor + taps.count
    output.append(contentsOf: vDSP.downsample(pending[..<consumed], decimationFactor: factor, filter: taps))
    pending.removeFirst(count * factor)
  }

  private static func track(from decimated: Decimated) -> BassHapticTrack {
    let rate = decimated.rate
    let bandCount = oddCount(Constants.bandFilterDuration * rate)
    guard decimated.low.count > bandCount else { return BassHapticTrack(pulses: []) }

    let lowCutTaps = lowPassTaps(count: bandCount, cutoff: Constants.bassLowCut, sampleRate: rate)
    let bassTaps = vDSP.subtract(
      lowPassTaps(count: bandCount, cutoff: Constants.bassHighCut, sampleRate: rate),
      lowCutTaps
    )
    let subTaps = vDSP.subtract(
      lowPassTaps(count: bandCount, cutoff: Constants.subHighCut, sampleRate: rate),
      lowCutTaps
    )

    let bass = filtered(decimated.low, with: bassTaps)
    let quadrature = filtered(bass, with: hilbertTaps(count: oddCount(Constants.hilbertDuration * rate)))
    let bassPower = vDSP.square(bass)
    let subPower = vDSP.square(filtered(decimated.low, with: subTaps))
    let envelope = vForce.sqrt(
      filtered(
        vDSP.add(bassPower, vDSP.square(quadrature)),
        with: hannTaps(count: oddCount(Constants.smoothingDuration * rate))
      )
    )

    let peak = vDSP.maximum(envelope)
    guard peak > Constants.silenceAmplitude else { return BassHapticTrack(pulses: []) }

    let active = envelope.filter { $0 > peak * Constants.activeFraction }.sorted()
    let reference = active[Int(Float(active.count - 1) * Constants.referencePercentile)]
    let floor = reference * pow(10, Constants.floorDecibels / 20)
    let level = vDSP.amplitudeToDecibels(
      vDSP.clip(envelope, to: floor ... .greatestFiniteMagnitude),
      zeroReference: reference
    )
    let intensity = vDSP.clip(
      vDSP.multiply(
        1 / (Constants.headroomDecibels - Constants.floorDecibels),
        vDSP.add(-Constants.floorDecibels, level)
      ),
      to: 0 ... 1
    )

    let onsets = detectOnsets(level: level, envelope: envelope, click: decimated.click, rate: rate)
    let signals = Signals(level: level, intensity: intensity, bassPower: bassPower, subPower: subPower, rate: rate)
    return BassHapticTrack(pulses: buildPulses(onsets: onsets, signals: signals))
  }
}
