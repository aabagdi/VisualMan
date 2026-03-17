//
//  MusicLibraryAccessManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import Foundation
import MediaPlayer

@MainActor
@Observable
final class MusicLibraryAccessManager {
  var authorizationStatus: MPMediaLibraryAuthorizationStatus
  private(set) var libraryChangeCount: Int = 0
  
  @ObservationIgnored private var cachedSongs: [MPMediaItem]?
  @ObservationIgnored private var cachedPlaylists: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedAlbums: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedArtists: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedCompilations: [MPMediaItemCollection]?
  @ObservationIgnored private var cachedGenres: [MPMediaItemCollection]?
  @ObservationIgnored private var lastCacheChangeCount: Int = -1
  
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
    cachedSongs = MPMediaQuery.songs().items ?? []
    cachedPlaylists = MPMediaQuery.playlists().collections ?? []
    cachedAlbums = (MPMediaQuery.albums().collections ?? [])
      .filter { !($0.representativeItem?.isCompilation ?? false) }
      .sorted {
        $0.representativeItem?.albumArtist ?? "Unknown" < $1.representativeItem?.albumArtist ?? "Unknown"
      }
    cachedArtists = MPMediaQuery.artists().collections ?? []
    cachedCompilations = MPMediaQuery.compilations().collections ?? []
    cachedGenres = MPMediaQuery.genres().collections ?? []
    lastCacheChangeCount = libraryChangeCount
  }
  
  init() {
    authorizationStatus = MPMediaLibrary.authorizationStatus()
    
    NotificationCenter.default.addObserver(
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
    
  func requestMusicLibraryAccess() {
    MPMediaLibrary.requestAuthorization { status in
      Task { @MainActor in
        self.authorizationStatus = status
      }
    }
  }
}
