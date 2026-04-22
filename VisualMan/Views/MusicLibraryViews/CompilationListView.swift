//
//  CompilationListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct CompilationListView: View {
  @State private var searchText: String = ""
  @State private var filteredCompilations: [MPMediaItemCollection]?
  
  let compilations: [MPMediaItemCollection]
  
  private var displayedCompilations: [MPMediaItemCollection] {
    filteredCompilations ?? compilations
  }
  
  var body: some View {
    Section {
      if !compilations.isEmpty {
        List(displayedCompilations, id: \.representativeItem?.persistentID) { compilation in
          NavigationLink(destination: AlbumDetailView(album: compilation)) {
            AlbumRowView(album: compilation)
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredCompilations, source: compilations) {
          [$0.representativeItem?.albumTitle]
        }
        .navigationTitle("Compilations")
      } else {
        Text("No compilations found!")
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
