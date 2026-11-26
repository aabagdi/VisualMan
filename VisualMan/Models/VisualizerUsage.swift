//
//  VisualizerUsage.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import Foundation

nonisolated struct VisualizerUsage: Codable, Equatable, Sendable {
  var secondsOnScreen: [String: Double] = [:]
  var timesSelected: [String: Int] = [:]
}
