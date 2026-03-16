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
        $0.representativeItem?.genre?.localizedStandardContains(searchText) ?? false
      }
    }
  }
  
  var body: some View {
    Section {
      if !genres.isEmpty {
        List(searchResults, id: \.representativeItem?.persistentID) { genre in
          let genreName = genre.representativeItem?.genre ?? "Unknown"
          let genreAlbums = albums.filter {
            $0.representativeItem?.genre == genre.representativeItem?.genre
          }
          NavigationLink(destination: GenreDetailView(genre: genreName, albums: genreAlbums)) {
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
