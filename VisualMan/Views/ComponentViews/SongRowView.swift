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
        Text(song.title ?? "Unknown")
          .font(.headline)
          .foregroundStyle(isCurrentSong ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        Text("\(song.artist ?? "Unknown") • \(song.albumTitle ?? "Unknown")")
          .font(.caption2)
      }
    }
  }
}
