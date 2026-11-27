//
//  PlaySongIntent.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import Dependencies
import MediaPlayer

struct PlaySongIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play Song"
  static let description = IntentDescription("Plays a song in VisualMan, with a visualizer if you pick one.")
  static var supportedModes: IntentModes { .foreground }

  @Parameter(title: "Song", requestValueDialog: "Which song?")
  var song: SongEntity

  @Parameter(title: "Visualizer")
  var visualizer: VisualizerOption?

  static var parameterSummary: some ParameterSummary {
    Summary("Play \(\.$song) with \(\.$visualizer)")
  }

  init() {}

  init(song: SongEntity, visualizer: VisualizerOption?) {
    self.song = song
    self.visualizer = visualizer
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let chosen = visualizer ?? VisualizerMention.takePending()
    try await Self.play(song, visualizer: chosen?.visualizer ?? .bars)
    if let chosen {
      return .result(dialog: "Playing \(song.title) with \(chosen.visualizer.displayName).")
    }
    return .result(dialog: "Playing \(song.title).")
  }

  @MainActor
  static func play(_ song: SongEntity, visualizer: VMVisualizer) async throws {
    @Dependencies.Dependency(PlaybackController.self) var playback

    try SongLibrary.requireAccess()
    guard let item = await SongLibrary.songs(withIDs: [song.id]).first else {
      throw SongLibraryError.songNotFound
    }
    let album = await SongLibrary.album(containing: item)
    let startingIndex = album.firstIndex { $0.persistentID == item.persistentID } ?? 0

    VisualizerIntentActions.select(visualizer)
    playback.start(audioSources: album, startingIndex: startingIndex)
    VisualizerIntentActions.showNowPlaying()
  }
}
