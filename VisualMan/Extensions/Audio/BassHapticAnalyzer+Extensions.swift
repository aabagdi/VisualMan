//
//  BassHapticAnalyzer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import Foundation
import Accelerate

nonisolated extension BassHapticAnalyzer {
  static func detectOnsets(level: [Float], envelope: [Float], click: [Float], rate: Double) -> [Onset] {
    let noveltyWindow = sampleCount(Constants.noveltyWindow, rate: rate)
    let peakHold = sampleCount(Constants.peakHold, rate: rate)
    let spacing = sampleCount(Constants.minimumOnsetSpacing, rate: rate)
    let lag = sampleCount(Constants.onsetLag, rate: rate)

    var onsets: [Onset] = []
    var troughIndex = 0
    var index = 1

    while index < level.count {
      if level[index] <= level[troughIndex] {
        troughIndex = index
        index += 1
        continue
      }
      guard level[index] - level[troughIndex] >= Constants.onsetRise else {
        index += 1
        continue
      }

      let peakIndex = findPeak(from: index, in: level, hold: peakHold)
      let previous = vDSP.maximum(level[max(0, troughIndex - noveltyWindow) ... troughIndex])
      let half = (envelope[troughIndex] + envelope[peakIndex]) / 2
      let crossing = (troughIndex ... peakIndex).first { envelope[$0] >= half } ?? index
      var onset = Onset(
        index: min(crossing, index + lag),
        isNovel: level[peakIndex] - previous >= Constants.onsetNovelty,
        hasClick: false
      )
      if let clickIndex = clickOnset(near: onset.index, click: click, rate: rate) {
        onset.index = clickIndex
        onset.hasClick = true
      }

      if let last = onsets.last, onset.index - last.index < spacing {
        if onset.isNovel && !last.isNovel {
          onset.index = last.index
          onsets[onsets.count - 1] = onset
        }
      } else {
        onsets.append(onset)
      }

      troughIndex = peakIndex
      index = peakIndex + 1
    }

    return onsets
  }

  private static func findPeak(from start: Int, in level: [Float], hold: Int) -> Int {
    var peakIndex = start
    var index = start + 1
    while index < level.count,
          index - peakIndex <= hold,
          level[peakIndex] - level[index] < Constants.peakDrop {
      if level[index] > level[peakIndex] {
        peakIndex = index
      }
      index += 1
    }
    return peakIndex
  }

  private static func clickOnset(near index: Int, click: [Float], rate: Double) -> Int? {
    let search = sampleCount(Constants.clickSearch, rate: rate)
    let background = sampleCount(Constants.clickBackground, rate: rate)
    let gap = sampleCount(Constants.clickGap, rate: rate)
    let first = max(background + gap, index - search)
    let last = min(click.count - 1, index + search)
    guard first <= last else { return nil }

    return (first ... last).first { candidate in
      let mean = vDSP.mean(click[candidate - gap - background ..< candidate - gap])
      return click[candidate] >= Constants.clickRatio * max(mean, Constants.clickFloor)
    }
  }
}

nonisolated extension BassHapticAnalyzer {
  static func buildPulses(onsets: [Onset], signals: Signals) -> [BassPulse] {
    let level = signals.level
    let minimum = sampleCount(Constants.minimumPulseDuration, rate: signals.rate)
    let maximum = sampleCount(Constants.maximumPulseDuration, rate: signals.rate)
    let floorLevel = Constants.floorDecibels + 0.1

    var pulses: [BassPulse] = []
    var open: OpenPulse?
    var next = 0

    for index in level.indices {
      if next < onsets.count, onsets[next].index <= index {
        let onset = onsets[next]
        next += 1
        if let current = open {
          if onset.isNovel {
            pulses.append(contentsOf: pulse(from: current, to: index, releaseLimit: nil, signals: signals))
            open = OpenPulse(start: index, peak: level[index], onset: onset)
          }
        } else {
          open = OpenPulse(start: index, peak: level[index], onset: onset)
        }
      }

      guard var current = open else { continue }
      current.peak = max(current.peak, level[index])
      open = current

      let age = index - current.start
      if age >= minimum, level[index] <= floorLevel || level[index] < current.peak - Constants.pulseEndDrop {
        let limit = next < onsets.count ? onsets[next].index : level.count
        pulses.append(contentsOf: pulse(from: current, to: index, releaseLimit: limit, signals: signals))
        open = nil
      } else if age >= maximum {
        pulses.append(contentsOf: pulse(from: current, to: index, releaseLimit: nil, signals: signals))
        open = OpenPulse(start: index, peak: current.peak, onset: nil)
      }
    }

    if let open {
      pulses.append(contentsOf: pulse(from: open, to: level.count - 1, releaseLimit: level.count, signals: signals))
    }

    return pulses
  }

  private static func pulse(from open: OpenPulse, to end: Int, releaseLimit: Int?, signals: Signals) -> [BassPulse] {
    let rate = signals.rate
    guard end > open.start,
          vDSP.maximum(signals.intensity[open.start ... end]) >= Constants.minimumPulseIntensity else { return [] }

    var points = simplified(Array(signals.intensity[open.start ... end]), tolerance: Constants.envelopeTolerance)
      .map { BassPulse.Point(time: Double($0.offset) / rate, intensity: $0.value) }
    var length = end - open.start
    if let releaseLimit {
      length = min(end + sampleCount(Constants.releaseDuration, rate: rate), releaseLimit) - open.start
      points.append(BassPulse.Point(time: Double(length) / rate, intensity: 0))
    }

    let window = open.start ..< min(end, open.start + sampleCount(Constants.sharpnessWindow, rate: rate))
    let bassEnergy = vDSP.sum(signals.bassPower[window])
    let subFraction = bassEnergy > 0 ? min(1, vDSP.sum(signals.subPower[window]) / bassEnergy) : 1
    let sharpness = Constants.pulseSharpness.lowerBound
      + (Constants.pulseSharpness.upperBound - Constants.pulseSharpness.lowerBound) * (1 - subFraction)

    return [
      BassPulse(
        start: Double(open.start) / rate,
        duration: Double(length) / rate,
        sharpness: sharpness,
        transient: open.onset.flatMap { transient(for: $0, at: open.start, signals: signals) },
        envelope: points
      )
    ]
  }

  private static func transient(for onset: Onset, at start: Int, signals: Signals) -> BassPulse.Transient? {
    guard onset.isNovel else { return nil }
    let level = signals.level
    let ahead = start ... min(level.count - 1, start + sampleCount(Constants.attackWindow, rate: signals.rate))
    let behind = max(0, start - sampleCount(Constants.attackLookBehind, rate: signals.rate)) ... start
    let rise = vDSP.maximum(level[ahead]) - vDSP.minimum(level[behind])
    let range = Constants.attackRise
    let strength = min(1, max(0, (rise - range.lowerBound) / (range.upperBound - range.lowerBound)))
    let value = strength * vDSP.maximum(signals.intensity[ahead])
    guard value >= Constants.minimumTransientIntensity else { return nil }

    return BassPulse.Transient(
      intensity: value,
      sharpness: onset.hasClick ? Constants.clickSharpness : Constants.softSharpness
    )
  }

  private static func simplified(_ values: [Float], tolerance: Float) -> [(offset: Int, value: Float)] {
    var keep = [Bool](repeating: false, count: values.count)
    keep[0] = true
    keep[values.count - 1] = true
    var spans = [(0, values.count - 1)]

    while let (first, last) = spans.popLast() {
      guard last - first > 1 else { continue }
      let slope = (values[last] - values[first]) / Float(last - first)
      var worst = first
      var worstError = tolerance
      for index in first + 1 ..< last {
        let error = abs(values[index] - values[first] - slope * Float(index - first))
        if error > worstError {
          worstError = error
          worst = index
        }
      }
      guard worst != first else { continue }
      keep[worst] = true
      spans.append((first, worst))
      spans.append((worst, last))
    }

    return values.indices.filter { keep[$0] }.map { (offset: $0, value: values[$0]) }
  }
}

nonisolated extension BassHapticAnalyzer {
  static func filtered(_ signal: [Float], with taps: [Float]) -> [Float] {
    let half = taps.count / 2
    var padded = [Float](repeating: 0, count: signal.count + taps.count)
    padded.replaceSubrange(half ..< half + signal.count, with: signal)
    return Array(vDSP.convolve(padded, withKernel: taps).prefix(signal.count))
  }

  static func lowPassTaps(count: Int, cutoff: Double, sampleRate: Double) -> [Float] {
    let middle = Double(count - 1) / 2
    let frequency = cutoff / sampleRate
    let taps = (0 ..< count).map { index -> Double in
      let offset = Double(index) - middle
      let sinc = offset == 0 ? 2 * frequency : sin(2 * .pi * frequency * offset) / (.pi * offset)
      return sinc * hamming(index, count: count)
    }
    let sum = taps.reduce(0, +)
    return taps.map { Float($0 / sum) }
  }

  static func hilbertTaps(count: Int) -> [Float] {
    (0 ..< count).map { index in
      let offset = index - count / 2
      guard offset % 2 != 0 else { return 0 }
      return Float(hamming(index, count: count) * 2 / (.pi * Double(offset)))
    }
  }

  static func hannTaps(count: Int) -> [Float] {
    let taps = (0 ..< count).map { 0.5 - 0.5 * cos(2 * .pi * Double($0 + 1) / Double(count + 1)) }
    let sum = taps.reduce(0, +)
    return taps.map { Float($0 / sum) }
  }

  static func highPassCoefficients(cutoff: Double, sampleRate: Double) -> [Double] {
    let omega = 2 * .pi * cutoff / sampleRate
    let alpha = sin(omega) / 2.0.squareRoot()
    let cosine = cos(omega)
    let scale = 1 / (1 + alpha)
    return [
      (1 + cosine) / 2 * scale,
      -(1 + cosine) * scale,
      (1 + cosine) / 2 * scale,
      -2 * cosine * scale,
      (1 - alpha) * scale
    ]
  }

  static func oddCount(_ value: Double) -> Int {
    Int(value.rounded()) | 1
  }

  static func sampleCount(_ duration: TimeInterval, rate: Double) -> Int {
    max(1, Int((duration * rate).rounded()))
  }

  private static func hamming(_ index: Int, count: Int) -> Double {
    0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(count - 1))
  }
}
