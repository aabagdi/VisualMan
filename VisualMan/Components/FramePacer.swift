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
  static let startRate = 80
  static let window = 60
  static let stepDownLoad = 0.99
  static let stepUpLoad = 0.95
  static let blockedDrawableWait: CFTimeInterval = 0.002

  private struct State {
    var lastCompletion: CFTimeInterval = 0
    var costs: [CFTimeInterval] = []
    var skipsNextFrame = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func acquireDrawable<Drawable>(skipsAfterWait: Bool, _ acquire: () -> Drawable?) -> Drawable? {
    let start = CACurrentMediaTime()
    let drawable = acquire()
    let waited = CACurrentMediaTime() - start
    state.withLock { $0.skipsNextFrame = skipsAfterWait && waited > Self.blockedDrawableWait }
    return drawable
  }

  func takeFrameSkip() -> Bool {
    state.withLock { state in
      defer { state.skipsNextFrame = false }
      return state.skipsNextFrame
    }
  }

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
