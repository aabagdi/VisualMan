//
//  MusicLibraryAccessManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import MediaPlayer

@MainActor
@Observable
final class MusicLibraryAccessManager {
  var authorizationStatus: MPMediaLibraryAuthorizationStatus
  private(set) var libraryChangeCount: Int = 0
  var isLoading: Bool = false

  @ObservationIgnored private var cachedSongs: [MPMediaItem]?
  @ObservationIgnored private var cachedPlaylists: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedAlbums: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedArtists: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedCompilations: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedGenres: [MPMediaItemCollection]?
  @ObservationIgnored private var lastCacheChangeCount: Int = -1
  @ObservationIgnored private var loadingTask: Task<Void, Never>?
  @ObservationIgnored private var libraryObserver: (any NSObjectProtocol)?
  
  var songs: [MPMediaItem] {
    _ = libraryChangeCount
    validateCache()
    return cachedSongs ?? []
  }
  
  var playlists: [MPMediaItemCollection] {
    _ = libraryChangeCount
    validateCache()
    return cachedPlaylists ?? []
  }
  
  var albums: [MPMediaItemCollection] {
    _ = libraryChangeCount
    validateCache()
    return cachedAlbums ?? []
  }
  
  var artists: [MPMediaItemCollection] {
    _ = libraryChangeCount
    validateCache()
    return cachedArtists ?? []
  }
  
  var compilations: [MPMediaItemCollection] {
    _ = libraryChangeCount
    validateCache()
    return cachedCompilations ?? []
  }
  
  var genres: [MPMediaItemCollection] {
    _ = libraryChangeCount
    validateCache()
    return cachedGenres ?? []
  }
  
  private func validateCache() {
    guard lastCacheChangeCount != libraryChangeCount else { return }
    lastCacheChangeCount = libraryChangeCount
    let changeCount = libraryChangeCount
    isLoading = true
    loadingTask?.cancel()
    loadingTask = Task {
      let songs = MPMediaQuery.songs().items ?? []
      let playlists = MPMediaQuery.playlists().collections ?? []
      let albums = (MPMediaQuery.albums().collections ?? [])
        .filter { !($0.representativeItem?.isCompilation ?? false) }
        .sorted {
          ($0.representativeItem?.albumArtist ?? "Unknown") < ($1.representativeItem?.albumArtist ?? "Unknown")
        }
      let artists = MPMediaQuery.artists().collections ?? []
      let compilations = MPMediaQuery.compilations().collections ?? []
      let genres = MPMediaQuery.genres().collections ?? []

      guard !Task.isCancelled, lastCacheChangeCount == changeCount else { return }
      cachedSongs = songs
      cachedPlaylists = playlists
      cachedAlbums = albums
      cachedArtists = artists
      cachedCompilations = compilations
      cachedGenres = genres
      isLoading = false
      libraryChangeCount += 1
      lastCacheChangeCount = libraryChangeCount
    }
  }
  
  init() {
    authorizationStatus = MPMediaLibrary.authorizationStatus()

    libraryObserver = NotificationCenter.default.addObserver(
      forName: .MPMediaLibraryDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.libraryChangeCount += 1
      }
    }
    MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
  }

  isolated deinit {
    if let libraryObserver {
      NotificationCenter.default.removeObserver(libraryObserver)
    }
  }
    
  func requestMusicLibraryAccess() {
    MPMediaLibrary.requestAuthorization { [weak self] status in
      Task { @MainActor in
        self?.authorizationStatus = status
      }
    }
  }
}
