//
//  ArtistListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct ArtistListView: View {
  @State private var searchText: String = ""
  
  let artists: [MPMediaItemCollection]
  let albums: [MPMediaItemCollection]
  
  private var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return artists
    } else {
      return artists.filter {
        $0.representativeItem?.artist?.localizedStandardContains(searchText) ?? false
      }
    }
  }
  
  var body: some View {
    Section {
      if !artists.isEmpty {
        List(searchResults, id: \.representativeItem?.persistentID) { artist in
          NavigationLink(destination: ArtistDetailView(albums: albums.filter { album in
            album.representativeItem?.artist == artist.representativeItem?.artist
          })) {
            Text(artist.representativeItem?.artist ?? "Unknown")
          }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      } else {
        Text("No artists found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .navigationTitle("Artists")
  }
}
