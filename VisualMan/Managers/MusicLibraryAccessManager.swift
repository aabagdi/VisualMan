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
@Observable
final class MusicLibraryAccessManager {
  var songs: [MPMediaItem] = []
  var playlists: [MPMediaItemCollection] = []
  var albums: [MPMediaItemCollection] = []
  var artists: [MPMediaItemCollection] = []
  var compilations: [MPMediaItemCollection] = []
  var genres: [MPMediaItemCollection] = []
  var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
  var isLoading = false
    
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
    compilations = MPMediaQuery.compilations().collections ?? []
    artists = MPMediaQuery.artists().collections ?? []
    genres = MPMediaQuery.genres().collections ?? []
    
    albums.sort {
      $0.representativeItem?.albumArtist ?? "Unknown" < $1.representativeItem?.albumArtist ?? "Unknown"
    }
    
    isLoading = false
  }
}
