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
  
  var songs: [MPMediaItem] {
    _ = libraryChangeCount
    return MPMediaQuery.songs().items ?? []
  }
  
  var playlists: [MPMediaItemCollection] {
    _ = libraryChangeCount
    return MPMediaQuery.playlists().collections ?? []
  }
  
  var albums: [MPMediaItemCollection] {
    _ = libraryChangeCount
    return (MPMediaQuery.albums().collections ?? [])
      .filter { !($0.representativeItem?.isCompilation ?? false) }
      .sorted {
        $0.representativeItem?.albumArtist ?? "Unknown" < $1.representativeItem?.albumArtist ?? "Unknown"
      }
  }
  
  var artists: [MPMediaItemCollection] {
    _ = libraryChangeCount
    return MPMediaQuery.artists().collections ?? []
  }
  
  var compilations: [MPMediaItemCollection] {
    _ = libraryChangeCount
    return MPMediaQuery.compilations().collections ?? []
  }
  
  var genres: [MPMediaItemCollection] {
    _ = libraryChangeCount
    return MPMediaQuery.genres().collections ?? []
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
