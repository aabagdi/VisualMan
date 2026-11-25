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
    Group {
      if !compilations.isEmpty {
        List(displayedCompilations, id: \.persistentID) { compilation in
          NavigationLink {
            AlbumDetailView(album: compilation)
          } label: {
            AlbumRowView(album: compilation)
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredCompilations, source: compilations) {
          [$0.representativeItem?.albumTitle]
        }
      } else {
        ContentUnavailableView("No Compilations", systemImage: "person.2.crop.square.stack.fill",
                               description: Text("Your music library has no compilations."))
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(SettingsToolbarButton())
    .navigationTitle("Compilations")
  }
}
