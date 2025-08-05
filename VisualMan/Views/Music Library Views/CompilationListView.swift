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
  
  let compilations: [MPMediaItemCollection]
  
  private let placeholder = UIImage(named: "Art Placeholder")!
  
  var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return compilations
    } else {
      return compilations.filter {
        $0.representativeItem?.title?.localizedCaseInsensitiveContains(searchText) ?? false
      }
    }
  }
  
  var body: some View {
    Section {
      if !compilations.isEmpty {
        NavigationStack {
          List(searchResults, id: \.representativeItem?.persistentID) { compilation in
            NavigationLink(destination: AlbumDetailView(album: compilation)) {
              HStack {
                Image(uiImage: compilation.representativeItem?.albumArt ?? placeholder)
                  .resizable()
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .frame(width: 60, height: 60)
                
                VStack(alignment: .leading, spacing: 2) {
                  Text(compilation.representativeItem?.albumTitle ?? "Unknown")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                  
                  Text("Various Artists")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                .padding(.leading, 8)
                
                Spacer()
              }
              .padding(.vertical, 2)
            }
          }
          .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
          .navigationTitle("Compilations")
        }
      } else {
        Text("No compilations found!")
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
