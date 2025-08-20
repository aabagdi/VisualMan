//
//  GenreListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct GenreListView: View {
  @State private var searchText: String = ""
  
  let genres: [MPMediaItemCollection]
  let albums: [MPMediaItemCollection]
  
  private var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return genres
    } else {
      return genres.filter {
        $0.representativeItem?.genre?.localizedCaseInsensitiveContains(searchText) ?? false
      }
    }
  }
  
  var body: some View {
    Section {
      if !genres.isEmpty {
        List(searchResults, id: \.representativeItem?.persistentID) { genre in
          NavigationLink(destination: GenreDetailView(genre: genre.representativeItem?.genre ?? "Unknown", albums: albums.filter { $0.representativeItem?.genre == genre.representativeItem?.genre })) {
            Text(genre.representativeItem?.genre ?? "Unknown")
          }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Genres")
      } else {
        Text("No genres found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
