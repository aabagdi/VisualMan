//
//  PlayWithVisualizerIntent.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import MediaPlayer

struct PlayWithVisualizerIntent: AppIntent {
  static let title: LocalizedStringResource = "Start Visualizer with Music"
  static let description = IntentDescription(
    """
    Opens a specific VisualMan visualizer, such as Plasma or the CRT Oscilloscope, and starts a song, \
    album, or artist from your library on it. Use when the request names a visualizer, like \
    "with the Plasma visualizer". Plain playback without a visualizer starts on Bars.
    """,
    searchKeywords: ["visualizer", "visualization", "with the", "start", "show"]
  )
  static var supportedModes: IntentModes { .foreground }

  @Parameter(
    title: "Music",
    description: "The song, album, or artist to play, such as Come As You Are or Nirvana"
  )
  var music: String

  @Parameter(title: "Visualizer", description: "The visualizer to start on, such as Plasma or the CRT Oscilloscope")
  var visualizer: VisualizerOption

  static var parameterSummary: some ParameterSummary {
    Summary("Play \(\.$music) with \(\.$visualizer)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try SongLibrary.requireAccess()
    let text = VisualizerMention.noteSpokenText(music, source: "PlayWithVisualizer")
    guard let match = await LibrarySearch.searchWithFallback(text).first else {
      throw SongLibraryError.noMatch
    }
    let (tracks, startingIndex) = await LibrarySearch.queue(for: match)
    guard !tracks.isEmpty else { throw SongLibraryError.songNotFound }

    let type = visualizer.visualizer
    LibraryPlayback.play(tracks, startingIndex: startingIndex, visualizer: type)
    let title = tracks[startingIndex].title ?? text
    return .result(dialog: "Playing \(title) with \(type.displayName).")
  }
}

#if canImport(FoundationModelsCore)
@available(iOS 27.3, *)
extension PlayWithVisualizerIntent: ToolIntent {}
#endif
