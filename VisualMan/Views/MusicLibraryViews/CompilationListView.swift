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
  
  private let placeholder = UIImage(resource: .artPlaceholder)
  
  private var displayedCompilations: [MPMediaItemCollection] {
    filteredCompilations ?? compilations
  }
  
  var body: some View {
    Section {
      if !compilations.isEmpty {
        List(displayedCompilations, id: \.representativeItem?.persistentID) { compilation in
          NavigationLink(destination: AlbumDetailView(album: compilation)) {
            HStack {
              Image(uiImage: compilation.representativeItem?.albumArt ?? placeholder)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 60, height: 60)
              
              VStack(alignment: .leading, spacing: 2) {
                Text(compilation.representativeItem?.albumTitle ?? "Unknown")
                  .font(.system(size: 16))
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                
                Text("Various Artists")
                  .font(.system(size: 14))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              .padding(.leading, 8)
              
              Spacer()
            }
            .padding(.vertical, 2)
          }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task(id: searchText) {
          if searchText.isEmpty {
            filteredCompilations = nil
            return
          }
          try? await Task.sleep(for: .milliseconds(300))
          filteredCompilations = compilations.filtered(by: searchText) {
            [$0.representativeItem?.albumTitle]
          }
        }
        .navigationTitle("Compilations")
      } else {
        Text("No compilations found!")
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
