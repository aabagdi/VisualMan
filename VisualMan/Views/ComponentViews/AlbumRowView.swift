//
//  AlbumRowView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI
import MediaPlayer

struct AlbumRowView: View {
  let album: MPMediaItemCollection

  private let placeholder = UIImage(resource: .artPlaceholder)

  var body: some View {
    HStack {
      Image(uiImage: album.representativeItem?.thumbnailImage ?? placeholder)
        .resizable()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 60, height: 60)

      VStack(alignment: .leading, spacing: 2) {
        Text(album.representativeItem?.albumTitle ?? "Unknown")
          .font(.system(size: 16))
          .foregroundStyle(.primary)
          .lineLimit(1)

        if album.representativeItem?.isCompilation == true {
          Text("Various Artists")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Text(album.representativeItem?.albumArtist ?? "Unknown")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.leading, 8)

      Spacer()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
