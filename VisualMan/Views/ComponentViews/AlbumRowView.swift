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

  private static let placeholder = UIImage(resource: .artPlaceholder)

  @State private var thumbnail: UIImage?

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
      Image(uiImage: thumbnail ?? album.representativeItem?.cachedThumbnailImage ?? Self.placeholder)
        .resizable()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: artSize, height: artSize)
        .accessibilityHidden(true)
        .accessibilityIgnoresInvertColors()

      VStack(alignment: .leading, spacing: 2) {
        Text(album.representativeItem?.albumTitle ?? String(localized: "Unknown"))
          .font(.body)
          .foregroundStyle(.primary)
          .lineLimit(lineLimit)

        if album.representativeItem?.isCompilation == true {
          Text("Various Artists")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
        } else {
          Text(album.representativeItem?.albumArtist ?? String(localized: "Unknown"))
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
    .task(id: album.persistentID) { await albumChanged() }
  }

  private func albumChanged() async {
    thumbnail = nil
    await Task.yield()
    guard !Task.isCancelled else { return }
    thumbnail = album.representativeItem?.thumbnailImage
  }
}
