//
//  OpenVisualizerIntent.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import Dependencies

struct OpenVisualizerIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Visualizer"
  static let description = IntentDescription(
    "Switches the VisualMan music visualizer to the one you name. If nothing is playing, asks for a song to play.",
    searchKeywords: ["visualizer", "visualization", "switch", "change", "show"]
  )
  static var supportedModes: IntentModes { .foreground }

  @Parameter(title: "Visualizer", description: "The visualizer to show, such as Plasma or Navier-Stokes")
  var visualizer: VisualizerOption

  @Parameter(title: "Song", description: "A song to start playing with the visualizer when nothing is playing")
  var song: SongEntity?

  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$visualizer)")
  }

  init() {}

  init(visualizer: VisualizerOption) {
    self.visualizer = visualizer
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let type = visualizer.visualizer
    if song == nil && VisualizerIntentActions.select(type) {
      return .result(dialog: "Switched to \(type.displayName).")
    }
    let chosen: SongEntity
    if let song {
      chosen = song
    } else {
      chosen = try await $song.requestValue("What do you want to play?")
    }
    try await PlaySongIntent.play(chosen, visualizer: type)
    return .result(dialog: "Playing \(chosen.title) with \(type.displayName).")
  }
}

struct SwitchVisualizerIntent: AppIntent {
  static let title: LocalizedStringResource = "Switch Visualizer"
  static let description = IntentDescription(
    "Changes the visualizer VisualMan shows while music plays, such as Plasma or the CRT Oscilloscope.",
    searchKeywords: ["visualizer", "visualization", "switch", "change", "show", "with"]
  )
  static var supportedModes: IntentModes { .foreground }

  @Parameter(title: "Visualizer", description: "The visualizer to show, such as Plasma or Navier-Stokes")
  var visualizer: VisualizerOption

  static var parameterSummary: some ParameterSummary {
    Summary("Switch to \(\.$visualizer)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let type = visualizer.visualizer
    VisualizerMention.notePending(visualizer)
    if VisualizerIntentActions.select(type) {
      return .result(dialog: "Switched to \(type.displayName).")
    }
    return .result(dialog: "\(type.displayName) will show when you play a song.")
  }
}

nonisolated struct OpenFavoriteVisualizerIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Favorite Visualizer"
  static let description = IntentDescription(
    "Switches the VisualMan music visualizer to the one you've watched the most.",
    searchKeywords: ["favorite", "favourite", "most used", "visualizer"]
  )
  static var supportedModes: IntentModes { .foreground }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(VisualizerUsageManager.self) var usageManager

    guard let favorite = usageManager.rankings.first(where: \.isUsed)?.visualizer else {
      return .result(dialog: "You haven't used any visualizers yet.")
    }
    let hasSong = VisualizerIntentActions.select(favorite)
    if hasSong {
      return .result(dialog: "Switched to \(favorite.displayName).")
    }
    return .result(dialog: "\(favorite.displayName) will show when you play a song.")
  }
}

enum VisualizerIntentActions {
  @discardableResult
  static func select(_ type: VMVisualizer) -> Bool {
    @Dependencies.Dependency(VisualizerSelection.self) var selection
    @Dependencies.Dependency(VisualizerUsageManager.self) var usageManager
    @Dependencies.Dependency(AudioEngineManager.self) var audioManager

    if type != selection.current {
      usageManager.recordSelection(type)
    }
    selection.current = type

    let hasSong = audioManager.isPlaying || audioManager.hasPlaybackPosition
    if hasSong {
      showNowPlaying()
    }
    return hasSong
  }

  static func showNowPlaying() {
    @Dependencies.Dependency(VisualizerSelection.self) var selection
    @Dependencies.Dependency(PlaybackController.self) var playback

    if !playback.isPlayerOnScreen {
      selection.nowPlayingRequested = true
    }
  }
}

extension OpenVisualizerIntent {
  static func donate(_ visualizer: VMVisualizer) {
    IntentDonationManager.shared.donate(intent: OpenVisualizerIntent(visualizer: VisualizerOption(visualizer)))
  }
}

#if canImport(FoundationModelsCore)
@available(iOS 27.3, *)
extension SwitchVisualizerIntent: ToolIntent {}

@available(iOS 27.3, *)
extension OpenFavoriteVisualizerIntent: ToolIntent {}
#endif
