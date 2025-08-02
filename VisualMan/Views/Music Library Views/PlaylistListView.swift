//
//  PlaylistListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct PlaylistListView: View {
  @State var searchText: String = ""
  
  let playlists: [MPMediaItemCollection]
  
  private var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return playlists
    } else {
      return playlists.filter {
        (($0.value(forProperty: MPMediaPlaylistPropertyName) as? String) ?? "").localizedCaseInsensitiveContains(searchText)
      }
    }
  }
  
  var body: some View {
    Section {
      if !playlists.isEmpty {
        List(searchResults, id: \.representativeItem?.persistentID) { playlist in
          NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Unknown")
          }
        }
        .searchable(text: $searchText)
      } else {
        Text("No playlists found!")
          .font(.caption)
      }
    }
    .navigationTitle("Playlists")
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
