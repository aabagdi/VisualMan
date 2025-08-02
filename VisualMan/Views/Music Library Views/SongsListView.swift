//
//  SongsListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import SwiftUI
import MediaPlayer

struct SongsListView: View {
  @State var searchText: String = ""
  
  let songs: [MPMediaItem]
  
  private var filteredSongs: [MPMediaItem] {
    if searchText.isEmpty {
      return songs
    } else {
      return songs.filter { $0.title?.localizedCaseInsensitiveContains(searchText) ?? false || $0.artist?.localizedCaseInsensitiveContains(searchText) ?? false }
    }
  }
  
  var body: some View {
    NavigationStack {
      List(filteredSongs.enumerated(), id: \.element.persistentID) { index, song in
        NavigationLink(destination: MusicPlayerView(filteredSongs, startingIndex: index)) {
          VStack(alignment: .leading) {
            Text(song.title ?? "Unknown")
              .font(.headline)
            Text(song.artist ?? "Unknown")
              .font(.caption2)
          }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
      }
      .searchable(text: $searchText)
    }
  }
}
