//
//  VisualizerUsageManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import Foundation
import Sharing

struct VisualizerUsageRanking: Identifiable {
  let visualizer: VMVisualizer
  let timeOnScreen: Duration
  let timesSelected: Int

  var id: VMVisualizer { visualizer }
  var isUsed: Bool { timeOnScreen > .zero || timesSelected > 0 }
}

@Observable
@MainActor
final class VisualizerUsageManager {
  @ObservationIgnored @Shared(.visualizerUsage) private var usage

  init() {
    migrateLegacyKeys()
  }

  var rankings: [VisualizerUsageRanking] {
    VMVisualizer.allCases.enumerated()
      .map { index, visualizer in
        (index, ranking(for: visualizer))
      }
      .sorted { lhs, rhs in
        if lhs.1.timeOnScreen != rhs.1.timeOnScreen { return lhs.1.timeOnScreen > rhs.1.timeOnScreen }
        if lhs.1.timesSelected != rhs.1.timesSelected { return lhs.1.timesSelected > rhs.1.timesSelected }
        return lhs.0 < rhs.0
      }
      .map(\.1)
  }

  func ranking(for visualizer: VMVisualizer) -> VisualizerUsageRanking {
    VisualizerUsageRanking(
      visualizer: visualizer,
      timeOnScreen: .seconds(usage.secondsOnScreen[visualizer.usageKey] ?? 0),
      timesSelected: usage.timesSelected[visualizer.usageKey] ?? 0
    )
  }

  func recordTimeOnScreen(_ visualizer: VMVisualizer, duration: Duration) {
    guard duration > .zero else { return }
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    $usage.withLock { $0.secondsOnScreen[visualizer.usageKey, default: 0] += seconds }
  }

  func recordSelection(_ visualizer: VMVisualizer) {
    $usage.withLock { $0.timesSelected[visualizer.usageKey, default: 0] += 1 }
  }

  func reset() {
    $usage.withLock { $0 = VisualizerUsage() }
  }

  private func migrateLegacyKeys() {
    let legacyKeys = VMVisualizer.allCases.filter { $0.rawValue != $0.usageKey }
    guard legacyKeys.contains(where: {
      usage.secondsOnScreen[$0.rawValue] != nil || usage.timesSelected[$0.rawValue] != nil
    }) else { return }
    $usage.withLock { usage in
      for visualizer in legacyKeys {
        if let seconds = usage.secondsOnScreen.removeValue(forKey: visualizer.rawValue) {
          usage.secondsOnScreen[visualizer.usageKey, default: 0] += seconds
        }
        if let count = usage.timesSelected.removeValue(forKey: visualizer.rawValue) {
          usage.timesSelected[visualizer.usageKey, default: 0] += count
        }
      }
    }
  }
}

extension VMVisualizer {
  var usageKey: String {
    switch self {
    case .bars: "bars"
    case .threeD: "threeD"
    case .album: "album"
    case .julia: "julia"
    case .fireworks: "fireworks"
    case .interference: "interference"
    case .voronoi: "voronoi"
    case .aurora: "aurora"
    case .oscilloscope: "oscilloscope"
    case .plasma: "plasma"
    case .metaball: "metaball"
    case .navierStokes: "navierStokes"
    case .liquidLight: "liquidLight"
    case .gameOfLife: "gameOfLife"
    case .abstractExpressionism: "abstractExpressionism"
    }
  }
}
