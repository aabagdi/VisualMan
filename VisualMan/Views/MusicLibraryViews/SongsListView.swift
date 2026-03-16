//
//  SongsListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import SwiftUI
import MediaPlayer

struct SongsListView: View {
  @State private var searchText: String = ""
  
  @Environment(AudioEngineManager.self) private var audioManager
  
  let songs: [MPMediaItem]
  
  private var searchResults: [MPMediaItem] {
    if searchText.isEmpty {
      return songs
    } else {
      return songs.filter {
        $0.title?.localizedStandardContains(searchText) ?? false
        || $0.artist?.localizedStandardContains(searchText) ?? false
      }
    }
  }
  
  var body: some View {
    Section {
      if !songs.isEmpty {
        List(Array(searchResults.enumerated()), id: \.element.persistentID) { index, song in
          let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
          NavigationLink(destination: MusicPlayerView(searchResults, startingIndex: index)) {
            HStack(spacing: 10) {
              if isCurrentSong {
                NowPlayingIndicatorView(isAnimating: audioManager.isPlaying)
                  .foregroundStyle(.tint)
              }
              VStack(alignment: .leading) {
                Text(song.title ?? "Unknown")
                  .font(.headline)
                  .foregroundStyle(isCurrentSong ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text("\(song.artist ?? "Unknown") • \(song.albumTitle ?? "Unknown")")
                  .font(.caption2)
              }
            }
          }
          .toolbarVisibility(.hidden, for: .tabBar)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      } else {
        Text("No songs found!")
          .font(.caption)
      }
    }
    .navigationTitle("Songs")
  }
}
