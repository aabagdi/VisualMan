//
//  GenreDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct GenreDetailView: View {
  let genre: String
  let albums: [MPMediaItemCollection]
  
  private let placeholder = UIImage(named: "Art Placeholder")!
  
  var body: some View {
    List(albums, id: \.representativeItem?.persistentID) { album in
      NavigationLink(destination: AlbumDetailView(album: album)) {
        HStack {
          Image(uiImage: album.representativeItem?.albumArt ?? placeholder)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 60, height: 60)
          
          VStack(alignment: .leading, spacing: 2) {
            Text(album.representativeItem?.albumTitle ?? "Unknown")
              .font(.system(size: 16))
              .foregroundColor(.primary)
              .lineLimit(1)
            
            if album.representativeItem?.isCompilation == true {
              Text("Various Artists")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineLimit(1)
            } else {
              Text(album.representativeItem?.albumArtist ?? "Unknown")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
          .padding(.leading, 8)
          
          Spacer()
        }
        .padding(.vertical, 2)
      }
      .toolbarVisibility(.hidden, for: .tabBar)
    }
    .navigationTitle(genre)
  }
}
