//
//  AccessibilityManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import Foundation
import MediaAccessibility
import Sharing
import UIKit

nonisolated enum VisualizerIntensity: String, CaseIterable, Sendable {
  case calm
  case normal
  case intense

  var displayName: LocalizedStringResource {
    switch self {
    case .calm: "Calm"
    case .normal: "Normal"
    case .intense: "Intense"
    }
  }

  var gain: Float {
    switch self {
    case .calm: 0.6
    case .normal: 1.0
    case .intense: 1.3
    }
  }

  var riseSeconds: Float {
    switch self {
    case .calm: 0.15
    case .normal, .intense: 0
    }
  }
}

@Observable
@MainActor
final class AccessibilityManager {
  private(set) var systemDimsFlashingLights = MADimFlashingLightsEnabled()
  private(set) var systemReducesMotion = UIAccessibility.isReduceMotionEnabled

  @ObservationIgnored @Shared(.reducesFlashingOverride) private var reducesFlashingOverride
  @ObservationIgnored @Shared(.visualizerIntensityOverride) private var intensityOverride
  @ObservationIgnored @Shared(.keepsControlsVisible) private var storedKeepsControlsVisible

  var reducesFlashing: Bool {
    get { reducesFlashingOverride ?? systemDimsFlashingLights }
    set { $reducesFlashingOverride.withLock { $0 = newValue } }
  }

  var intensity: VisualizerIntensity {
    get { intensityOverride ?? (systemReducesMotion ? .calm : .normal) }
    set { $intensityOverride.withLock { $0 = newValue } }
  }

  var keepsControlsVisible: Bool {
    get { storedKeepsControlsVisible }
    set { $storedKeepsControlsVisible.withLock { $0 = newValue } }
  }

  @ObservationIgnored private var observers: [any NSObjectProtocol] = []

  init() {
    let names = [
      Notification.Name(kMADimFlashingLightsChangedNotification as String),
      UIAccessibility.reduceMotionStatusDidChangeNotification,
      UIApplication.didBecomeActiveNotification,
    ]
    observers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          self?.refreshSystemSettings()
        }
      }
    }
  }

  isolated deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func refreshSystemSettings() {
    let dimsFlashingLights = MADimFlashingLightsEnabled()
    if dimsFlashingLights != systemDimsFlashingLights {
      systemDimsFlashingLights = dimsFlashingLights
    }
    let reducesMotion = UIAccessibility.isReduceMotionEnabled
    if reducesMotion != systemReducesMotion {
      systemReducesMotion = reducesMotion
    }
  }
}
