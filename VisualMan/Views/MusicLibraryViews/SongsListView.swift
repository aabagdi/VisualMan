//
//  SongsListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import SwiftUI
import MediaPlayer

private struct SongSelection: Hashable {
  let index: Int
}

struct SongsListView: View {
  @State private var searchText: String = ""
  @State private var filteredSongs: [MPMediaItem]?
  
  @Environment(AudioEngineManager.self) private var audioManager
  
  let songs: [MPMediaItem]
  
  private var displayedSongs: [MPMediaItem] {
    filteredSongs ?? songs
  }
  
  var body: some View {
    Group {
      if !songs.isEmpty {
        List(displayedSongs.enumerated(), id: \.element.persistentID) { index, song in
          let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
          NavigationLink(value: SongSelection(index: index)) {
            SongRowView(song: song, isCurrentSong: isCurrentSong, isPlaying: audioManager.isPlaying)
          }
        }
        .navigationDestination(for: SongSelection.self) { selection in
          MusicPlayerView(displayedSongs, startingIndex: selection.index)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task(id: searchText) {
          if searchText.isEmpty {
            filteredSongs = nil
            return
          }
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          filteredSongs = songs.filtered(by: searchText) {
            [$0.title, $0.artist]
          }
        }
      } else {
        Text("No songs found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .navigationTitle("Songs")
  }
}
