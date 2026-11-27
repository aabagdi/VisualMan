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
        List(displayedPlaylists, id: \.persistentID) { playlist in
          NavigationLink {
            PlaylistDetailView(playlist: playlist)
          } label: {
            Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? String(localized: "Unknown"))
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredPlaylists, source: playlists) {
          [$0.value(forProperty: MPMediaPlaylistPropertyName) as? String]
        }
      } else {
        ContentUnavailableView("No Playlists", systemImage: "list.number",
                               description: Text("Your music library has no playlists."))
      }
    }
    .navigationTitle("Playlists")
    .modifier(SettingsToolbarButton())
  }
}
