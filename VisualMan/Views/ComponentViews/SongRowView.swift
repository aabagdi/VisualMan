//
//  SongRowView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI
import MediaPlayer

struct SongRowView: View {
  let song: MPMediaItem
  let isCurrentSong: Bool
  let isPlaying: Bool

  var body: some View {
    HStack(spacing: 10) {
      if isCurrentSong {
        NowPlayingIndicatorView(isAnimating: isPlaying)
          .foregroundStyle(.tint)
      }
      VStack(alignment: .leading) {
        Text(song.title ?? String(localized: "Unknown"))
          .font(.headline)
          .foregroundStyle(isCurrentSong ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        Text("\(song.artist ?? String(localized: "Unknown")) • \(song.albumTitle ?? String(localized: "Unknown"))")
          .font(.caption2)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isCurrentSong ? .isSelected : [])
  }
}
