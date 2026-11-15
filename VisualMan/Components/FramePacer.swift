//
//  FramePacer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/15/26.
//

import QuartzCore
import os

nonisolated final class FramePacer: Sendable {
  static let rates = [120, 80, 60]
  static let window = 60
  static let stepDownLoad = 0.99
  static let stepUpLoad = 0.95

  private struct State {
    var lastCompletion: CFTimeInterval = 0
    var costs: [CFTimeInterval] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func frameCompleted(submitted: CFTimeInterval) {
    let now = CACurrentMediaTime()
    state.withLock { state in
      state.costs.append(now - max(submitted, state.lastCompletion))
      state.lastCompletion = now
    }
  }

  func takeFrameCost() -> CFTimeInterval? {
    state.withLock { state in
      guard state.costs.count >= Self.window else { return nil }
      state.costs.sort()
      let median = state.costs[state.costs.count / 2]
      state.costs.removeAll(keepingCapacity: true)
      return median
    }
  }

  func reset() {
    state.withLock { $0 = State() }
  }

  static func rate(current: Int, cost: CFTimeInterval, displayPeriod: CFTimeInterval) -> Int {
    if cost > displayPeriod * stepDownLoad {
      let lower = rates.filter { $0 < current }
      return lower.first { cost <= stepDownLoad / Double($0) } ?? lower.last ?? current
    }
    return rates.first { $0 > current && cost < stepUpLoad / Double($0) } ?? current
  }
}
