//
//  PlaybackIntents.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import Dependencies

nonisolated struct PausePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Pause Music"
  static let description = IntentDescription("Pauses the song playing in VisualMan.")
  static var supportedModes: IntentModes { .background }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(AudioEngineManager.self) var audioManager
    @Dependencies.Dependency(PlaybackController.self) var playback

    guard audioManager.isPlaying else {
      return .result(dialog: "Nothing is playing.")
    }
    playback.pause()
    return .result(dialog: "Paused.")
  }
}

nonisolated struct ResumePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume Music"
  static let description = IntentDescription("Resumes the paused song in VisualMan.")
  static var supportedModes: IntentModes { .background }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(AudioEngineManager.self) var audioManager
    @Dependencies.Dependency(AudioPlaylistManager.self) var playlistManager
    @Dependencies.Dependency(PlaybackController.self) var playback

    guard !audioManager.isPlaying else {
      return .result(dialog: "Already playing.")
    }
    guard playlistManager.currentAudioSource != nil else {
      return .result(dialog: "Pick a song in VisualMan first.")
    }
    playback.play()
    return .result(dialog: "Resumed.")
  }
}

nonisolated struct NextSongIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Next Song"
  static let description = IntentDescription("Skips to the next song in VisualMan.")
  static var supportedModes: IntentModes { .background }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(AudioPlaylistManager.self) var playlistManager
    @Dependencies.Dependency(PlaybackController.self) var playback

    guard playlistManager.currentAudioSource != nil else {
      return .result(dialog: "Nothing is playing.")
    }
    guard playlistManager.hasNext else {
      return .result(dialog: "This is the last song.")
    }
    playback.skipForwards()
    return .result(dialog: "Skipped.")
  }
}

nonisolated struct PreviousSongIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Previous Song"
  static let description = IntentDescription("Goes back a song in VisualMan, or restarts the current one.")
  static var supportedModes: IntentModes { .background }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    @Dependencies.Dependency(AudioPlaylistManager.self) var playlistManager
    @Dependencies.Dependency(PlaybackController.self) var playback

    guard playlistManager.currentAudioSource != nil else {
      return .result(dialog: "Nothing is playing.")
    }
    playback.skipBackwards()
    return .result(dialog: "Went back.")
  }
}
