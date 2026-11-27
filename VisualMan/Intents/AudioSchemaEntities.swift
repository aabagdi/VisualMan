//
//  AudioSchemaEntities.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents
import MediaPlayer

@available(iOS 27.0, *)
@AppEntity(schema: .audio.artist)
struct AudioArtistEntity {
  static let defaultQuery = AudioArtistQuery()

  let id: String
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  init?(artist collection: MPMediaItemCollection) {
    guard let item = collection.representativeItem else { return nil }
    self.init(id: String(item.artistPersistentID), name: item.artist ?? String(localized: "Unknown"))
  }

  init(artistOf item: MPMediaItem) {
    self.init(id: String(item.artistPersistentID), name: item.artist ?? String(localized: "Unknown"))
  }
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.album)
struct AudioAlbumEntity {
  static let defaultQuery = AudioAlbumQuery()

  let id: String
  var title: String
  var artistName: String
  var artists: [AudioArtistEntity]
  var universalProductCode: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: "\(artistName)")
  }

  init?(album collection: MPMediaItemCollection) {
    guard let item = collection.representativeItem else { return nil }
    self.init(albumOf: item)
  }

  init(albumOf item: MPMediaItem) {
    id = String(item.albumPersistentID)
    title = item.albumTitle ?? String(localized: "Unknown")
    artistName = item.albumArtist ?? item.artist ?? String(localized: "Unknown")
    artists = [AudioArtistEntity(artistOf: item)]
    universalProductCode = nil
  }
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.song)
struct AudioSongEntity {
  static let defaultQuery = AudioSongQuery()

  let id: String
  var title: String
  var artistName: String
  var artists: [AudioArtistEntity]
  var composerName: String?
  var composers: [AudioArtistEntity]
  var albumTitle: String?
  var album: AudioAlbumEntity?
  var internationalStandardRecordingCode: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: "\(artistName)")
  }

  init(item: MPMediaItem) {
    id = String(item.persistentID)
    title = item.title ?? String(localized: "Unknown")
    artistName = item.artist ?? String(localized: "Unknown")
    artists = [AudioArtistEntity(artistOf: item)]
    composerName = item.composer
    composers = []
    albumTitle = item.albumTitle
    album = item.albumTitle == nil ? nil : AudioAlbumEntity(albumOf: item)
    internationalStandardRecordingCode = nil
  }
}

@available(iOS 27.0, *)
@UnionValue
enum AudioItem {
  case song(AudioSongEntity)
  case album(AudioAlbumEntity)
  case artist(AudioArtistEntity)
}

@available(iOS 27.0, *)
@AppEnum(schema: .audio.playbackAttributes)
enum AudioPlaybackAttribute: String {
  case shuffle
  case `repeat`

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .shuffle: "Shuffle",
    .repeat: "Repeat",
  ]
}

@available(iOS 27.0, *)
@AppEnum(schema: .audio.queueInsertionLocation)
enum AudioQueueLocation: String {
  case next
  case tail

  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .next: "Play Next",
    .tail: "Play Last",
  ]
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct AudioWarmupResult: TransientAppEntity {
  var displayRepresentation: DisplayRepresentation { "Queue ready" }

  init() {}
}

@available(iOS 27.0, *)
struct AudioSongQuery: EntityStringQuery {
  func entities(for identifiers: [AudioSongEntity.ID]) async throws -> [AudioSongEntity] {
    try SongLibrary.requireAccess()
    return await SongLibrary.songs(withIDs: identifiers).map(AudioSongEntity.init)
  }

  func entities(matching string: String) async throws -> [AudioSongEntity] {
    try SongLibrary.requireAccess()
    let string = VisualizerMention.noteSpokenText(string, source: "AudioSongQuery")
    return await SongLibrary.songs(matching: string).map(AudioSongEntity.init)
  }

  func suggestedEntities() async throws -> [AudioSongEntity] {
    guard SongLibrary.hasAccess else { return [] }
    return await SongLibrary.suggestedSongs().map(AudioSongEntity.init)
  }
}

@available(iOS 27.0, *)
struct AudioAlbumQuery: EntityStringQuery {
  func entities(for identifiers: [AudioAlbumEntity.ID]) async throws -> [AudioAlbumEntity] {
    try SongLibrary.requireAccess()
    return await SongLibrary.albums(withIDs: identifiers).compactMap(AudioAlbumEntity.init(album:))
  }

  func entities(matching string: String) async throws -> [AudioAlbumEntity] {
    try SongLibrary.requireAccess()
    let string = VisualizerMention.noteSpokenText(string, source: "AudioAlbumQuery")
    return await SongLibrary.albums(matching: string).compactMap(AudioAlbumEntity.init(album:))
  }
}

@available(iOS 27.0, *)
struct AudioArtistQuery: EntityStringQuery {
  func entities(for identifiers: [AudioArtistEntity.ID]) async throws -> [AudioArtistEntity] {
    try SongLibrary.requireAccess()
    return await SongLibrary.artists(withIDs: identifiers).compactMap(AudioArtistEntity.init(artist:))
  }

  func entities(matching string: String) async throws -> [AudioArtistEntity] {
    try SongLibrary.requireAccess()
    let string = VisualizerMention.noteSpokenText(string, source: "AudioArtistQuery")
    return await SongLibrary.artists(matching: string).compactMap(AudioArtistEntity.init(artist:))
  }
}
