//
//  SongsListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import SwiftUI
import Dependencies
import MediaPlayer

struct SongsListView: View {
  @State private var searchText: String = ""
  @State private var filteredSongs: [MPMediaItem]?
  
  @Dependency(AudioEngineManager.self) private var audioManager
  
  let songs: [MPMediaItem]
  
  private var displayedSongs: [MPMediaItem] {
    filteredSongs ?? songs
  }
  
  var body: some View {
    Group {
      if !songs.isEmpty {
        List(displayedSongs.enumerated(), id: \.element.persistentID) { index, song in
          let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
          NavigationLink(destination: MusicPlayerView(displayedSongs, startingIndex: index)) {
            SongRowView(song: song, isCurrentSong: isCurrentSong, isPlaying: audioManager.isPlaying)
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredSongs, source: songs) {
          [$0.title, $0.artist]
        }
      } else {
        Text("No songs found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(SettingsToolbarButton())
    .navigationTitle("Songs")
  }
}
