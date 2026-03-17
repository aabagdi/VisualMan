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
  var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
  
  var songs: [MPMediaItem] {
    MPMediaQuery.songs().items ?? []
  }
  
  var playlists: [MPMediaItemCollection] {
    MPMediaQuery.playlists().collections ?? []
  }
  
  var albums: [MPMediaItemCollection] {
    (MPMediaQuery.albums().collections ?? [])
      .filter { !($0.representativeItem?.isCompilation ?? false) }
      .sorted {
        $0.representativeItem?.albumArtist ?? "Unknown" < $1.representativeItem?.albumArtist ?? "Unknown"
      }
  }
  
  var artists: [MPMediaItemCollection] {
    MPMediaQuery.artists().collections ?? []
  }
  
  var compilations: [MPMediaItemCollection] {
    MPMediaQuery.compilations().collections ?? []
  }
  
  var genres: [MPMediaItemCollection] {
    MPMediaQuery.genres().collections ?? []
  }
    
  func requestMusicLibraryAccess() {
    MPMediaLibrary.requestAuthorization { status in
      Task { @MainActor in
        self.authorizationStatus = status
      }
    }
  }
}
