//
//  BassHapticTrack.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import Foundation

nonisolated struct BassPulse: Sendable {
  struct Point: Sendable {
    var time: TimeInterval
    var intensity: Float
  }

  struct Transient: Sendable {
    var intensity: Float
    var sharpness: Float
  }

  var start: TimeInterval
  var duration: TimeInterval
  var sharpness: Float
  var transient: Transient?
  var envelope: [Point]

  var end: TimeInterval { start + duration }

  func resumed(at time: TimeInterval) -> BassPulse? {
    let offset = time - start
    guard offset > 0, offset < duration,
          let next = envelope.firstIndex(where: { $0.time > offset }), next > 0 else { return nil }

    let before = envelope[next - 1]
    let after = envelope[next]
    let fraction = Float((offset - before.time) / (after.time - before.time))
    let entry = Point(time: 0, intensity: before.intensity + (after.intensity - before.intensity) * fraction)
    let remainder = envelope[next...].map { Point(time: $0.time - offset, intensity: $0.intensity) }

    return BassPulse(
      start: time,
      duration: duration - offset,
      sharpness: sharpness,
      transient: nil,
      envelope: [entry] + remainder
    )
  }
}

nonisolated struct BassHapticTrack: Sendable {
  var pulses: [BassPulse]

  func pulses(startingIn range: Range<TimeInterval>) -> ArraySlice<BassPulse> {
    pulses[firstIndex(startingAtOrAfter: range.lowerBound) ..< firstIndex(startingAtOrAfter: range.upperBound)]
  }

  func pulse(activeAt time: TimeInterval) -> BassPulse? {
    let index = firstIndex(startingAtOrAfter: time)
    guard index > 0, pulses[index - 1].end > time else { return nil }
    return pulses[index - 1]
  }

  private func firstIndex(startingAtOrAfter time: TimeInterval) -> Int {
    var low = 0
    var high = pulses.count
    while low < high {
      let middle = (low + high) / 2
      if pulses[middle].start < time {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low
  }
}
