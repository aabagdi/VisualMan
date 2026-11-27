//
//  VisualizerMention.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import Foundation
import os

nonisolated enum VisualizerMention {
  private static let pending = OSAllocatedUnfairLock<(option: VisualizerOption, date: Date)?>(initialState: nil)
  private static let lifetime: TimeInterval = 15
  private static let logger = Logger(subsystem: "com.aabagdi.VisualMan", category: "Siri")

  static func extract(from text: String) -> (text: String, visualizer: VisualizerOption?) {
    let lowered = text.lowercased()
    for (name, option) in names {
      for pattern in patterns(for: name) {
        guard let range = lowered.range(of: pattern.text) else { continue }
        if pattern.mustEnd && range.upperBound != lowered.endIndex { continue }
        var cleaned = text
        let start = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
        let length = lowered.distance(from: range.lowerBound, to: range.upperBound)
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(lower, offsetBy: length)
        cleaned.removeSubrange(lower..<upper)
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), option)
      }
    }
    return (text, nil)
  }

  static func noteSpokenText(_ text: String, source: StaticString) -> String {
    let (cleaned, option) = extract(from: text)
    #if DEBUG
    logger.notice("""
      \(source, privacy: .public) received "\(text, privacy: .public)" → "\(cleaned, privacy: .public)" \
      visualizer: \(option?.rawValue ?? "none", privacy: .public)
      """)
    #endif
    if let option {
      pending.withLock { $0 = (option, Date()) }
    }
    return cleaned
  }

  static func notePending(_ option: VisualizerOption) {
    pending.withLock { $0 = (option, Date()) }
  }

  static func takePending() -> VisualizerOption? {
    pending.withLock { state in
      defer { state = nil }
      guard let state, Date().timeIntervalSince(state.date) < lifetime else { return nil }
      return state.option
    }
  }

  private static var names: [(String, VisualizerOption)] {
    var result: [(String, VisualizerOption)] = []
    for (option, representation) in VisualizerOption.caseDisplayRepresentations {
      result.append((String(localized: representation.title).lowercased(), option))
      for synonym in representation.synonyms {
        result.append((String(localized: synonym).lowercased(), option))
      }
    }
    result.append(("sixties liquid light", .liquidLight))
    result.append(("60s liquid light", .liquidLight))
    result.append(("oscilloscope", .oscilloscope))
    return result.sorted { $0.0.count > $1.0.count }
  }

  private static func patterns(for name: String) -> [(text: String, mustEnd: Bool)] {
    let lead = ["with the ", "with a ", "with ", "using the ", "using ", "on the ", "in the "]
    let trail = [" visualizer", " visualiser", " visualization", " visualisation"]
    var result: [(String, Bool)] = []
    for prefix in lead {
      for suffix in trail {
        result.append((prefix + name + suffix, false))
      }
      result.append((prefix + name, true))
    }
    for suffix in trail {
      result.append((name + suffix, false))
    }
    return result
  }
}
