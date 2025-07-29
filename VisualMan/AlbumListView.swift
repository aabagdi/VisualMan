//
//  AlbumListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import MediaPlayer

struct AlbumListView: View {
  @State private var searchText: String = ""
  
  let albums: [MPMediaItemCollection]
  let placeholder = UIImage(named: "Art Placeholder")!
  
  private var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return albums
    } else {
      return albums.filter { $0.representativeItem?.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false }
    }
  }
  
  var body: some View {
    NavigationStack {
      List(searchResults, id: \.persistentID) { album in
        NavigationLink(destination: AlbumDetailView(album: album)) {
          HStack {
            Image(uiImage: album.representativeItem?.albumArt ?? placeholder)
              .resizable()
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .frame(width: 100, height: 100)
              .padding()
            Spacer()
            VStack {
              Text(album.representativeItem?.albumTitle ?? "Unknown")
              if album.representativeItem?.isCompilation == true {
                Text("Various Artists")
                  .font(.caption)
              } else {
                Text(album.representativeItem?.albumArtist ?? "Unknown")
                  .font(.caption)
              }
            }
            .minimumScaleFactor(0.05)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
          }
          .padding()
        }
      }
    }
    .searchable(text: $searchText)
  }
}
