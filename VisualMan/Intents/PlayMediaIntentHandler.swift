//
//  PlayMediaIntentHandler.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import Intents
import MediaPlayer

nonisolated final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
  func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
    if let items = intent.mediaItems, !items.isEmpty {
      return INPlayMediaMediaItemResolutionResult.successes(with: items)
    }
    guard SongLibrary.hasAccess else {
      return [INPlayMediaMediaItemResolutionResult.unsupported(forReason: .loginRequired)]
    }
    guard let item = await SiriMediaSearch.bestItem(for: intent.mediaSearch) else {
      return [INPlayMediaMediaItemResolutionResult.unsupported()]
    }
    return INPlayMediaMediaItemResolutionResult.successes(with: [item])
  }

  func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
    guard let identifier = intent.mediaItems?.first?.identifier else {
      return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
    }
    let played = await SiriMediaPlayback.play(
      identifier: identifier,
      shuffled: intent.playShuffled ?? false,
      queueLocation: intent.playbackQueueLocation
    )
    return INPlayMediaIntentResponse(code: played ? .success : .failure, userActivity: nil)
  }
}

nonisolated enum SiriMediaSearch {
  static let defaultIdentifier = "default"

  static func bestItem(for search: INMediaSearch?) async -> INMediaItem? {
    guard let search, search.reference != .currentlyPlaying else { return defaultItem }

    let artist = search.artistName
    let matches: [LibraryMatch]
    if let spoken = search.mediaName, !spoken.isEmpty {
      let name = VisualizerMention.noteSpokenText(
        LibrarySearch.strippingAppName(from: spoken),
        source: "INMediaSearch"
      )
      switch search.mediaType {
      case .album: matches = await LibrarySearch.albums(named: name, artist: artist)
      case .artist: matches = await LibrarySearch.artists(named: name)
      default: matches = await LibrarySearch.searchWithFallback(name, artist: artist)
      }
    } else if let album = search.albumName, !album.isEmpty {
      matches = await LibrarySearch.albums(named: album, artist: artist)
    } else if let artist, !artist.isEmpty {
      matches = await LibrarySearch.artists(named: artist)
    } else {
      return defaultItem
    }
    return matches.first.map(mediaItem)
  }

  private static var defaultItem: INMediaItem {
    INMediaItem(identifier: defaultIdentifier, title: String(localized: "Music"), type: .music, artwork: nil)
  }

  private static func mediaItem(for match: LibraryMatch) -> INMediaItem {
    switch match {
    case .song(let item):
      INMediaItem(identifier: match.identifier, title: item.title, type: .song, artwork: nil, artist: item.artist)
    case .album(let album):
      INMediaItem(
        identifier: match.identifier,
        title: album.representativeItem?.albumTitle,
        type: .album,
        artwork: nil,
        artist: album.representativeItem?.albumArtist ?? album.representativeItem?.artist
      )
    case .artist(let artist):
      INMediaItem(
        identifier: match.identifier,
        title: artist.representativeItem?.artist,
        type: .artist,
        artwork: nil,
        artist: artist.representativeItem?.artist
      )
    }
  }
}

enum SiriMediaPlayback {
  static func play(identifier: String, shuffled: Bool, queueLocation: INPlaybackQueueLocation) async -> Bool {
    let visualizer = VisualizerMention.takePending()?.visualizer ?? .bars
    if identifier == SiriMediaSearch.defaultIdentifier {
      if !shuffled, LibraryPlayback.resume() { return true }
      let songs = await LibrarySearch.recommended().compactMap { match -> MPMediaItem? in
        if case .song(let item) = match { item } else { nil }
      }
      guard !songs.isEmpty else { return false }
      LibraryPlayback.play(shuffled ? songs.shuffled() : songs, startingIndex: 0, visualizer: visualizer)
      return true
    }

    guard let match = await LibrarySearch.match(forIdentifier: identifier) else { return false }
    var (tracks, startingIndex) = await LibrarySearch.queue(for: match)
    guard !tracks.isEmpty else { return false }

    if shuffled {
      let keepingFirst = if case .song = match { true } else { false }
      (tracks, startingIndex) = LibrarySearch.shuffled(tracks, startingIndex: startingIndex, keepingFirst: keepingFirst)
    }

    switch queueLocation {
    case .next: LibraryPlayback.enqueue(tracks, next: true)
    case .later: LibraryPlayback.enqueue(tracks, next: false)
    default: LibraryPlayback.play(tracks, startingIndex: startingIndex, visualizer: visualizer)
    }
    return true
  }
}
