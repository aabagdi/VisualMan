//
//  PlayAudioIntent.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import MediaIntents
import MediaPlayer

@available(iOS 27.0, *)
@AppIntent(schema: .audio.playAudio)
struct PlayAudioIntent {
  static var supportedModes: IntentModes { .foreground }

  var audioEntity: AudioItem

  @Parameter(default: [])
  var playbackAttributes: Set<AudioPlaybackAttribute>

  var warmupAudioQueueResult: AudioWarmupResult?

  var queueLocation: AudioQueueLocation?

  @MainActor
  func perform() async throws -> some IntentResult {
    try SongLibrary.requireAccess()
    guard let match = await LibrarySearch.match(forIdentifier: audioEntity.libraryIdentifier) else {
      throw SongLibraryError.songNotFound
    }
    var (tracks, startingIndex) = await LibrarySearch.queue(for: match)
    guard !tracks.isEmpty else { throw SongLibraryError.songNotFound }
    let visualizer = VisualizerMention.takePending()?.visualizer ?? .bars

    if playbackAttributes.contains(.shuffle) {
      if case .song = match {
        (tracks, startingIndex) = LibrarySearch.shuffled(tracks, startingIndex: startingIndex, keepingFirst: true)
      } else {
        (tracks, startingIndex) = LibrarySearch.shuffled(tracks, startingIndex: startingIndex, keepingFirst: false)
      }
    }

    switch queueLocation {
    case .next:
      LibraryPlayback.enqueue(tracks, next: true)
    case .tail:
      LibraryPlayback.enqueue(tracks, next: false)
    case nil:
      LibraryPlayback.play(tracks, startingIndex: startingIndex, visualizer: visualizer)
    }
    return .result()
  }
}

@available(iOS 27.0, *)
struct AudioSearchQuery: IntentValueQuery {
  func values(for input: AudioSearch) async throws -> [AudioItem] {
    guard SongLibrary.hasAccess else { return [] }
    switch input.criteria {
    case .searchQuery(let text):
      let text = VisualizerMention.noteSpokenText(text, source: "AudioSearch")
      return await LibrarySearch.searchWithFallback(text).compactMap(AudioItem.init)
    case .unspecified:
      return await LibrarySearch.recommended().compactMap(AudioItem.init)
    case .url:
      return []
    @unknown default:
      return []
    }
  }
}

@available(iOS 27.0, *)
extension AudioItem {
  nonisolated init?(_ match: LibraryMatch) {
    switch match {
    case .song(let item):
      self = .song(AudioSongEntity(item: item))
    case .album(let album):
      guard let entity = AudioAlbumEntity(album: album) else { return nil }
      self = .album(entity)
    case .artist(let artist):
      guard let entity = AudioArtistEntity(artist: artist) else { return nil }
      self = .artist(entity)
    }
  }

  nonisolated var libraryIdentifier: String {
    switch self {
    case .song(let song): "song:\(song.id)"
    case .album(let album): "album:\(album.id)"
    case .artist(let artist): "artist:\(artist.id)"
    }
  }
}
