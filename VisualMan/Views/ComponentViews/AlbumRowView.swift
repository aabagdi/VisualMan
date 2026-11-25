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

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var artSize: CGFloat = 60

  private var lineLimit: Int {
    dynamicTypeSize.isAccessibilitySize ? 3 : 1
  }

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading))
      : AnyLayout(HStackLayout())

    layout {
      Image(uiImage: album.representativeItem?.thumbnailImage ?? placeholder)
        .resizable()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: artSize, height: artSize)
        .accessibilityHidden(true)
        .accessibilityIgnoresInvertColors()

      VStack(alignment: .leading, spacing: 2) {
        Text(album.representativeItem?.albumTitle ?? "Unknown")
          .font(.body)
          .foregroundStyle(.primary)
          .lineLimit(lineLimit)

        if album.representativeItem?.isCompilation == true {
          Text("Various Artists")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
        } else {
          Text(album.representativeItem?.albumArtist ?? "Unknown")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
        }
      }
      .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 8)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
