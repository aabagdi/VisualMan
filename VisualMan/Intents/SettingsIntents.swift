//
//  SettingsIntents.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import Dependencies

nonisolated enum ToggleSettingOption: String, AppEnum {
  case bassHaptics
  case reduceFlashing
  case keepControlsVisible

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Setting"

  static let caseDisplayRepresentations: [ToggleSettingOption: DisplayRepresentation] = [
    .bassHaptics: DisplayRepresentation(title: "Bass Haptics", synonyms: ["Haptics", "Vibration", "Bass Vibration"]),
    .reduceFlashing: DisplayRepresentation(title: "Reduce Flashing", synonyms: ["Flashing", "Flash Reduction"]),
    .keepControlsVisible: DisplayRepresentation(
      title: "Keep Controls Visible",
      synonyms: ["Controls", "Always Show Controls", "Visible Controls"]
    ),
  ]
}

nonisolated enum IntensityOption: String, AppEnum {
  case calm
  case normal
  case intense

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Intensity"

  static let caseDisplayRepresentations: [IntensityOption: DisplayRepresentation] = [
    .calm: DisplayRepresentation(title: "Calm", synonyms: ["Gentle", "Low", "Relaxed"]),
    .normal: DisplayRepresentation(title: "Normal", synonyms: ["Default", "Medium"]),
    .intense: DisplayRepresentation(title: "Intense", synonyms: ["High", "Strong", "Maximum"]),
  ]

  var intensity: VisualizerIntensity {
    switch self {
    case .calm: .calm
    case .normal: .normal
    case .intense: .intense
    }
  }
}

struct SetToggleSettingIntent: AppIntent {
  static let title: LocalizedStringResource = "Change VisualMan Setting"
  static let description = IntentDescription(
    "Turns a VisualMan setting on or off: Bass Haptics, Reduce Flashing, or Keep Controls Visible.",
    searchKeywords: ["setting", "turn on", "turn off", "haptics", "flashing", "controls"]
  )
  static var supportedModes: IntentModes { .background }

  @Parameter(title: "Setting", description: "The setting to change")
  var setting: ToggleSettingOption

  @Parameter(
    title: "On",
    description: "Whether the setting should be on",
    displayName: Bool.IntentDisplayName(true: "On", false: "Off")
  )
  var enabled: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Turn \(\.$setting) \(\.$enabled)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: SettingsIntentActions.set(setting, enabled: enabled))
  }
}

struct TurnOnSettingIntent: AppIntent {
  static let title: LocalizedStringResource = "Turn On VisualMan Setting"
  static let description = IntentDescription("Turns on Bass Haptics, Reduce Flashing, or Keep Controls Visible.")
  static var supportedModes: IntentModes { .background }

  @Parameter(title: "Setting", description: "The setting to turn on")
  var setting: ToggleSettingOption

  static var parameterSummary: some ParameterSummary {
    Summary("Turn on \(\.$setting)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: SettingsIntentActions.set(setting, enabled: true))
  }
}

struct TurnOffSettingIntent: AppIntent {
  static let title: LocalizedStringResource = "Turn Off VisualMan Setting"
  static let description = IntentDescription("Turns off Bass Haptics, Reduce Flashing, or Keep Controls Visible.")
  static var supportedModes: IntentModes { .background }

  @Parameter(title: "Setting", description: "The setting to turn off")
  var setting: ToggleSettingOption

  static var parameterSummary: some ParameterSummary {
    Summary("Turn off \(\.$setting)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: SettingsIntentActions.set(setting, enabled: false))
  }
}

enum SettingsIntentActions {
  static func set(_ setting: ToggleSettingOption, enabled: Bool) -> IntentDialog {
    @Dependencies.Dependency(HapticsManager.self) var hapticsManager
    @Dependencies.Dependency(AccessibilityManager.self) var accessibilityManager

    let state: LocalizedStringResource = enabled ? "on" : "off"
    switch setting {
    case .bassHaptics:
      guard hapticsManager.isSupported else {
        return "This device doesn't support haptics."
      }
      hapticsManager.isActive = enabled
      return "Bass Haptics is \(state)."
    case .reduceFlashing:
      accessibilityManager.reducesFlashing = enabled
      return "Reduce Flashing is \(state)."
    case .keepControlsVisible:
      accessibilityManager.keepsControlsVisible = enabled
      return "Keep Controls Visible is \(state)."
    }
  }
}

struct SetIntensityIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Visualizer Intensity"
  static let description = IntentDescription(
    "Sets how strongly VisualMan's visualizers react to the music: Calm, Normal, or Intense.",
    searchKeywords: ["intensity", "calm", "intense", "strength", "reaction"]
  )
  static var supportedModes: IntentModes { .background }

  @Parameter(title: "Intensity", description: "How strongly the visualizers react, from Calm to Intense")
  var intensity: IntensityOption

  static var parameterSummary: some ParameterSummary {
    Summary("Set intensity to \(\.$intensity)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(AccessibilityManager.self) var accessibilityManager

    accessibilityManager.intensity = intensity.intensity
    return .result(dialog: "Visualizer intensity is \(intensity.intensity.displayName).")
  }
}

struct SetHapticStrengthIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Haptic Strength"
  static let description = IntentDescription(
    "Sets how strong VisualMan's bass haptics feel, from 0 to 100 percent. 50 percent is the default.",
    searchKeywords: ["haptic", "vibration", "strength", "stronger", "weaker"]
  )
  static var supportedModes: IntentModes { .background }

  @Parameter(
    title: "Strength",
    description: "Haptic strength in percent, from 0 (weakest) to 100 (strongest); 50 is the default",
    inclusiveRange: (0, 100)
  )
  var percent: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Set haptic strength to \(\.$percent) percent")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(HapticsManager.self) var hapticsManager

    guard hapticsManager.isSupported else {
      return .result(dialog: "This device doesn't support haptics.")
    }
    let range = HapticsManager.Constants.strengthRange
    let clamped = Double(min(max(percent, 0), 100)) / 100
    hapticsManager.strength = range.lowerBound + (range.upperBound - range.lowerBound) * clamped
    if !hapticsManager.isActive {
      hapticsManager.isActive = true
    }
    return .result(dialog: "Haptic strength is \(min(max(percent, 0), 100)) percent.")
  }
}

#if canImport(FoundationModelsCore)
@available(iOS 27.3, *)
extension SetToggleSettingIntent: ToolIntent {}

@available(iOS 27.3, *)
extension SetIntensityIntent: ToolIntent {}

@available(iOS 27.3, *)
extension SetHapticStrengthIntent: ToolIntent {}
#endif
