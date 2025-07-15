//
//  MusicLibraryAccessManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import Foundation
import MediaPlayer
import Combine

@MainActor
class MusicLibraryAccessManager: ObservableObject {
  @Published var songs: [MPMediaItem] = []
  @Published var playlists: [MPMediaItemCollection] = []
  @Published var albums: [MPMediaItemCollection] = []
  @Published var artists: [MPMediaItemCollection] = []
  @Published var genres: [MPMediaItemCollection] = []
  @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
  @Published var isLoading = false
    
  func requestMusicLibraryAccess() {
    MPMediaLibrary.requestAuthorization() { [weak self] status in
      Task { @MainActor in
        self?.authorizationStatus = status
        if status == .authorized {
          self?.loadLibrary()
        }
      }
    }
  }
  
  func loadLibrary() {
    isLoading = true
    
    songs = MPMediaQuery.songs().items ?? []
    playlists = MPMediaQuery.playlists().collections ?? []
    albums = MPMediaQuery.albums().collections ?? []
    artists = MPMediaQuery.artists().collections ?? []
    genres = MPMediaQuery.genres().collections ?? []
    
    isLoading = false
  }
}
