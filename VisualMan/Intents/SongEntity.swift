//
//  SongEntity.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import MediaPlayer

struct SongEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Song",
    numericFormat: "\(placeholder: .int) songs"
  )
  static let defaultQuery = SongQuery()

  let id: String

  @Property(title: "Title")
  var title: String

  @Property(title: "Artist")
  var artist: String?

  @Property(title: "Album")
  var album: String?

  var displayRepresentation: DisplayRepresentation {
    if let artist {
      DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    } else {
      DisplayRepresentation(title: "\(title)")
    }
  }

  init(item: MPMediaItem) {
    id = String(item.persistentID)
    title = item.title ?? String(localized: "Unknown")
    artist = item.artist
    album = item.albumTitle
  }
}

struct SongQuery: EntityStringQuery {
  func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
    try SongLibrary.requireAccess()
    return await SongLibrary.songs(withIDs: identifiers).map(SongEntity.init)
  }

  func entities(matching string: String) async throws -> [SongEntity] {
    try SongLibrary.requireAccess()
    let string = VisualizerMention.noteSpokenText(string, source: "SongQuery")
    return await SongLibrary.songs(matching: string).map(SongEntity.init)
  }

  func suggestedEntities() async throws -> [SongEntity] {
    guard SongLibrary.hasAccess else { return [] }
    return await SongLibrary.suggestedSongs().map(SongEntity.init)
  }
}

nonisolated enum SongLibraryError: Error, CustomLocalizedStringResourceConvertible {
  case noAccess
  case songNotFound
  case noMatch

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .noAccess: "VisualMan doesn't have access to your music library. You can allow it in Settings."
    case .songNotFound: "That song isn't in your music library anymore."
    case .noMatch: "VisualMan couldn't find that in your music library."
    }
  }
}

nonisolated enum SongLibrary {
  static let suggestionLimit = 20
  static let searchLimit = 50

  static var hasAccess: Bool {
    MPMediaLibrary.authorizationStatus() == .authorized
  }

  static func requireAccess() throws {
    guard hasAccess else { throw SongLibraryError.noAccess }
  }

  @concurrent
  static func songs(withIDs identifiers: [String]) async -> [MPMediaItem] {
    identifiers.compactMap { identifier in
      guard let persistentID = UInt64(identifier) else { return nil }
      let query = MPMediaQuery.songs()
      query.addFilterPredicate(MPMediaPropertyPredicate(
        value: NSNumber(value: persistentID),
        forProperty: MPMediaItemPropertyPersistentID
      ))
      return query.items?.first
    }
  }

  @concurrent
  static func songs(matching text: String, artist: String? = nil) async -> [MPMediaItem] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }

    let songs = MPMediaQuery.songs().items ?? []
    var scored = songs.compactMap { item -> (MPMediaItem, Int)? in
      let score = LibraryFuzzyMatch.songScore(item, title: text, artist: artist)
      return score >= LibraryFuzzyMatch.minimumScore ? (item, score) : nil
    }
    if artist == nil {
      let byArtist = songs.compactMap { item -> (MPMediaItem, Int)? in
        let score = LibraryFuzzyMatch.score(item.artist, against: text)
        return score >= 85 ? (item, score - 60) : nil
      }
      scored.append(contentsOf: byArtist)
    }
    var seen = Set<UInt64>()
    return scored
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.playCount > $1.0.playCount }
      .map(\.0)
      .filter { seen.insert($0.persistentID).inserted }
      .prefix(searchLimit)
      .map { $0 }
  }

  @concurrent
  static func suggestedSongs() async -> [MPMediaItem] {
    let songs = MPMediaQuery.songs().items ?? []
    let recent = songs
      .filter { $0.lastPlayedDate != nil }
      .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
      .prefix(suggestionLimit / 2)
    let mostPlayed = songs
      .filter { $0.playCount > 0 }
      .sorted { $0.playCount > $1.playCount }
    var seen = Set<UInt64>()
    let suggestions = (Array(recent) + mostPlayed).filter { seen.insert($0.persistentID).inserted }
    return Array(suggestions.prefix(suggestionLimit))
  }

  @concurrent
  static func anySongs() async -> [MPMediaItem] {
    Array((MPMediaQuery.songs().items ?? []).prefix(suggestionLimit))
  }

  @concurrent
  static func albumTracks(albumID: UInt64, songID: UInt64) async -> [MPMediaItem] {
    let query = MPMediaQuery.songs()
    query.addFilterPredicate(MPMediaPropertyPredicate(
      value: NSNumber(value: albumID),
      forProperty: MPMediaItemPropertyAlbumPersistentID
    ))
    let tracks = (query.items ?? []).sorted {
      ($0.discNumber, $0.albumTrackNumber) < ($1.discNumber, $1.albumTrackNumber)
    }
    if !tracks.isEmpty { return tracks }
    let song = MPMediaQuery.songs()
    song.addFilterPredicate(MPMediaPropertyPredicate(
      value: NSNumber(value: songID),
      forProperty: MPMediaItemPropertyPersistentID
    ))
    return song.items ?? []
  }

  @concurrent
  static func album(containing song: MPMediaItem) async -> [MPMediaItem] {
    let query = MPMediaQuery.songs()
    query.addFilterPredicate(MPMediaPropertyPredicate(
      value: NSNumber(value: song.albumPersistentID),
      forProperty: MPMediaItemPropertyAlbumPersistentID
    ))
    let tracks = (query.items ?? []).sorted {
      ($0.discNumber, $0.albumTrackNumber) < ($1.discNumber, $1.albumTrackNumber)
    }
    return tracks.isEmpty ? [song] : tracks
  }

  @concurrent
  static func albums(withIDs identifiers: [String]) async -> [MPMediaItemCollection] {
    identifiers.compactMap {
      collection(UInt64($0), property: MPMediaItemPropertyAlbumPersistentID, grouping: .album)
    }
  }

  @concurrent
  static func artists(withIDs identifiers: [String]) async -> [MPMediaItemCollection] {
    identifiers.compactMap {
      collection(UInt64($0), property: MPMediaItemPropertyArtistPersistentID, grouping: .artist)
    }
  }

  @concurrent
  static func albums(matching text: String) async -> [MPMediaItemCollection] {
    rankedCollections(MPMediaQuery.albums().collections ?? [], text: text) { $0.representativeItem?.albumTitle }
  }

  @concurrent
  static func artists(matching text: String) async -> [MPMediaItemCollection] {
    rankedCollections(MPMediaQuery.artists().collections ?? [], text: text) { $0.representativeItem?.artist }
  }

  static func tracks(of album: MPMediaItemCollection) -> [MPMediaItem] {
    album.items.sorted {
      ($0.discNumber, $0.albumTrackNumber) < ($1.discNumber, $1.albumTrackNumber)
    }
  }

  static func tracks(ofArtist artist: MPMediaItemCollection) -> [MPMediaItem] {
    artist.items.sorted {
      (($0.albumTitle ?? ""), $0.discNumber, $0.albumTrackNumber)
        < (($1.albumTitle ?? ""), $1.discNumber, $1.albumTrackNumber)
    }
  }

  private static func collection(
    _ persistentID: UInt64?,
    property: String,
    grouping: MPMediaGrouping
  ) -> MPMediaItemCollection? {
    guard let persistentID else { return nil }
    let query = MPMediaQuery.songs()
    query.groupingType = grouping
    query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: persistentID), forProperty: property))
    return query.collections?.first
  }

  private static func rankedCollections(
    _ collections: [MPMediaItemCollection],
    text: String,
    name: (MPMediaItemCollection) -> String?
  ) -> [MPMediaItemCollection] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    return collections
      .map { ($0, LibraryFuzzyMatch.score(name($0), against: text)) }
      .filter { $0.1 >= LibraryFuzzyMatch.minimumScore + 20 }
      .sorted { $0.1 > $1.1 }
      .prefix(searchLimit)
      .map(\.0)
  }

}
