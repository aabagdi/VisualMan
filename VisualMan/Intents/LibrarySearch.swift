//
//  LibrarySearch.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import Foundation
import Dependencies
import MediaPlayer

nonisolated enum LibraryMatch {
  case song(MPMediaItem)
  case album(MPMediaItemCollection)
  case artist(MPMediaItemCollection)

  var identifier: String {
    switch self {
    case .song(let item): "song:\(item.persistentID)"
    case .album(let album): "album:\(album.representativeItem?.albumPersistentID ?? 0)"
    case .artist(let artist): "artist:\(artist.representativeItem?.artistPersistentID ?? 0)"
    }
  }
}

nonisolated enum LibrarySearch {
  static func search(_ text: String, artist: String? = nil) async -> [LibraryMatch] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }

    let (title, spokenArtist) = splitArtist(from: text)
    let artistFilter = artist ?? spokenArtist
    var songs = await SongLibrary.songs(matching: title, artist: artistFilter)
    if songs.isEmpty, artistFilter != nil {
      songs = await SongLibrary.songs(matching: text)
    }
    let albums = artistFilter == nil ? await SongLibrary.albums(matching: text) : []
    let artists = artistFilter == nil ? await SongLibrary.artists(matching: text) : []

    let songMatches = songs.map(LibraryMatch.song)
    let albumMatches = albums.map(LibraryMatch.album)
    let artistMatches = artists.map(LibraryMatch.artist)

    if artists.contains(where: { LibraryFuzzyMatch.score($0.representativeItem?.artist, against: text) == 100 }) {
      return artistMatches + albumMatches + songMatches
    }
    if albums.contains(where: { LibraryFuzzyMatch.score($0.representativeItem?.albumTitle, against: text) == 100 })
      && !songs.contains(where: { LibraryFuzzyMatch.score($0.title, against: text) == 100 }) {
      return albumMatches + songMatches + artistMatches
    }
    return songMatches + albumMatches + artistMatches
  }

  static func searchWithFallback(_ text: String, artist: String? = nil) async -> [LibraryMatch] {
    let matches = await search(text, artist: artist)
    if !matches.isEmpty { return matches }
    return await search(strippingSiriWords(from: text), artist: artist)
  }

  static func albums(named name: String, artist: String? = nil) async -> [LibraryMatch] {
    var albums = await SongLibrary.albums(matching: name)
    if let artist {
      albums = albums.filter {
        let item = $0.representativeItem
        return max(
          LibraryFuzzyMatch.score(item?.albumArtist, against: artist),
          LibraryFuzzyMatch.score(item?.artist, against: artist)
        ) >= 65
      }
    }
    return albums.map(LibraryMatch.album)
  }

  static func artists(named name: String) async -> [LibraryMatch] {
    await SongLibrary.artists(matching: name).map(LibraryMatch.artist)
  }

  static func recommended() async -> [LibraryMatch] {
    var songs = await SongLibrary.suggestedSongs()
    if songs.isEmpty {
      songs = await SongLibrary.anySongs()
    }
    return songs.map(LibraryMatch.song)
  }

  static func match(forIdentifier identifier: String) async -> LibraryMatch? {
    let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    switch parts[0] {
    case "song": return await SongLibrary.songs(withIDs: [parts[1]]).first.map(LibraryMatch.song)
    case "album": return await SongLibrary.albums(withIDs: [parts[1]]).first.map(LibraryMatch.album)
    case "artist": return await SongLibrary.artists(withIDs: [parts[1]]).first.map(LibraryMatch.artist)
    default: return nil
    }
  }

  static func queue(for match: LibraryMatch) async -> (tracks: [MPMediaItem], startingIndex: Int) {
    switch match {
    case .song(let track):
      let songID = track.persistentID
      let album = await SongLibrary.albumTracks(albumID: track.albumPersistentID, songID: songID)
      let index = album.firstIndex { $0.persistentID == songID } ?? 0
      return (album, index)
    case .album(let album):
      return (SongLibrary.tracks(of: album), 0)
    case .artist(let artist):
      return (SongLibrary.tracks(ofArtist: artist), 0)
    }
  }

  static func shuffled(
    _ tracks: [MPMediaItem],
    startingIndex: Int,
    keepingFirst: Bool
  ) -> (tracks: [MPMediaItem], startingIndex: Int) {
    var tracks = tracks
    if keepingFirst, tracks.indices.contains(startingIndex) {
      let first = tracks.remove(at: startingIndex)
      tracks.shuffle()
      tracks.insert(first, at: 0)
    } else {
      tracks.shuffle()
    }
    return (tracks, 0)
  }

  static func strippingSiriWords(from text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let leading = ["play ", "the song ", "the album ", "the artist ", "the band ", "songs by ", "music by "]
    let trailing = [" on visualman", " in visualman", " on visual man", " in visual man", " visualizer"]
    for prefix in leading where result.lowercased().hasPrefix(prefix) {
      result = String(result.dropFirst(prefix.count))
    }
    for suffix in trailing where result.lowercased().hasSuffix(suffix) {
      result = String(result.dropLast(suffix.count))
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func strippingAppName(from text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let names = ["visualman", "visual man", "visual-man"]
    let joiners = [" in ", " on ", " a ", " with ", " using ", " "]
    for name in names {
      for joiner in joiners {
        let suffix = joiner + name
        if result.lowercased().hasSuffix(suffix) {
          result = String(result.dropLast(suffix.count))
          return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let infix = joiner + name + " "
        if let range = result.range(of: infix, options: .caseInsensitive) {
          result.replaceSubrange(range, with: " ")
          return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
    }
    return result
  }

  private static func splitArtist(from text: String) -> (title: String, artist: String?) {
    guard let range = text.range(of: " by ", options: [.caseInsensitive, .backwards]) else { return (text, nil) }
    let title = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    let artist = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty, !artist.isEmpty else { return (text, nil) }
    return (title, artist)
  }
}

enum LibraryPlayback {
  static func play(_ tracks: [MPMediaItem], startingIndex: Int, visualizer: VMVisualizer = .bars) {
    @Dependency(PlaybackController.self) var playback

    VisualizerIntentActions.select(visualizer)
    playback.start(audioSources: tracks, startingIndex: startingIndex)
    VisualizerIntentActions.showNowPlaying()
  }

  static func enqueue(_ tracks: [MPMediaItem], next: Bool) {
    @Dependency(AudioPlaylistManager.self) var playlistManager

    guard playlistManager.currentAudioSource != nil else {
      play(tracks, startingIndex: 0)
      return
    }
    if next {
      playlistManager.audioSources.insert(contentsOf: tracks, at: playlistManager.currentIndex + 1)
    } else {
      playlistManager.audioSources.append(contentsOf: tracks)
    }
  }

  static func resume() -> Bool {
    @Dependency(AudioPlaylistManager.self) var playlistManager
    @Dependency(PlaybackController.self) var playback

    guard playlistManager.currentAudioSource != nil else { return false }
    playback.play()
    VisualizerIntentActions.showNowPlaying()
    return true
  }
}
