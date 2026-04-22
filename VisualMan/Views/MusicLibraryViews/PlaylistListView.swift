//
//  PlaylistListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct PlaylistListView: View {
  @State private var searchText: String = ""
  @State private var filteredPlaylists: [MPMediaItemCollection]?
  
  let playlists: [MPMediaItemCollection]
  
  private var displayedPlaylists: [MPMediaItemCollection] {
    filteredPlaylists ?? playlists
  }
  
  var body: some View {
    Group {
      if !playlists.isEmpty {
        List(displayedPlaylists, id: \.representativeItem?.persistentID) { playlist in
          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Unknown")
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredPlaylists, source: playlists) {
          [$0.value(forProperty: MPMediaPlaylistPropertyName) as? String]
        }
      } else {
        Text("No playlists found!")
          .font(.caption)
      }
    }
    .navigationTitle("Playlists")
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
