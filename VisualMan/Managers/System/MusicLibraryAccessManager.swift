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
  nonisolated struct LibrarySnapshot {
    var songs: [MPMediaItem]
    var playlists: [MPMediaItemCollection]
    var albums: [MPMediaItemCollection]
    var artists: [MPMediaItemCollection]
    var compilations: [MPMediaItemCollection]
    var genres: [MPMediaItemCollection]
  }

  var authorizationStatus: MPMediaLibraryAuthorizationStatus
  private(set) var isLoading: Bool = false
  private(set) var songs: [MPMediaItem] = []
  private(set) var playlists: [MPMediaItemCollection] = []
  private(set) var albums: [MPMediaItemCollection] = []
  private(set) var artists: [MPMediaItemCollection] = []
  private(set) var compilations: [MPMediaItemCollection] = []
  private(set) var genres: [MPMediaItemCollection] = []

  @ObservationIgnored private var libraryObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  init() {
    authorizationStatus = MPMediaLibrary.authorizationStatus()

    libraryObserver = NotificationCenter.default.addObserver(
      forName: .MPMediaLibraryDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshLibrary()
      }
    }
    MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
    refreshLibrary()
  }

  isolated deinit {
    loadTask?.cancel()
    MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
    if let libraryObserver {
      NotificationCenter.default.removeObserver(libraryObserver)
    }
  }

  func requestMusicLibraryAccess() async {
    authorizationStatus = await MPMediaLibrary.requestAuthorization()
    refreshLibrary()
  }

  private func refreshLibrary() {
    loadTask?.cancel()
    isLoading = true
    loadTask = Task { [weak self] in
      let snapshot = await Self.loadLibrary()
      guard !Task.isCancelled, let self else { return }
      songs = snapshot.songs
      playlists = snapshot.playlists
      albums = snapshot.albums
      artists = snapshot.artists
      compilations = snapshot.compilations
      genres = snapshot.genres
      isLoading = false
    }
  }

  @concurrent
  nonisolated private static func loadLibrary() async -> sending LibrarySnapshot {
    LibrarySnapshot(
      songs: MPMediaQuery.songs().items ?? [],
      playlists: MPMediaQuery.playlists().collections ?? [],
      albums: (MPMediaQuery.albums().collections ?? [])
        .filter { !($0.representativeItem?.isCompilation ?? false) }
        .sorted {
          ($0.representativeItem?.albumArtist ?? "Unknown") < ($1.representativeItem?.albumArtist ?? "Unknown")
        },
      artists: MPMediaQuery.artists().collections ?? [],
      compilations: MPMediaQuery.compilations().collections ?? [],
      genres: MPMediaQuery.genres().collections ?? []
    )
  }
}
