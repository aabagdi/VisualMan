//
//  AlbumListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import MediaPlayer

struct AlbumListView: View {
  let albums: [MPMediaItemCollection]
  let placeholder = UIImage(named: "Art Placeholder")!
  
  var body: some View {
    NavigationStack {
      List(albums, id: \.persistentID) { album in
        NavigationLink(destination: AlbumDetailView(album: album)) {
          HStack {
            Image(uiImage: (album.representativeItem?.albumArt) ?? placeholder)
              .resizable()
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .frame(width: 100, height: 100)
              .padding()
            Spacer()
            VStack {
              Text(album.representativeItem?.albumTitle ?? "Unknown")
                .minimumScaleFactor(0.05)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
              Text(album.representativeItem?.albumArtist ?? "Unknown")
                .font(.caption)
                .minimumScaleFactor(0.05)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
          }
          .padding()
        }
      }
    }
  }
}
