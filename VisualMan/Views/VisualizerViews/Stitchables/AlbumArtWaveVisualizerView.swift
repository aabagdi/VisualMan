//
//  AlbumArtWaveVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/31/25.
//

import SwiftUI
import Dependencies

struct AlbumArtWaveVisualizerView: View {
  @State private var audio = SmoothedAudio()

  @Dependency(AudioEngineManager.self) private var audioManager

  let albumArt: UIImage?
  private static let placeholder = UIImage(resource: .artPlaceholder)

  var body: some View {
    GeometryReader { g in
      TimelineView(.animation) { timeline in
        Image(uiImage: albumArt ?? Self.placeholder)
          .resizable()
          .scaledToFill()
          .scaleEffect(1.2)
          .frame(width: g.size.width, height: g.size.height)
          .albumArtWaveShader(time: audio.time,
                              smoothedBass: audio.bass,
                              smoothedMid: audio.mid,
                              smoothedHigh: audio.high)
          .onChange(of: timeline.date) { oldValue, newValue in
            let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
            audio.update(from: audioManager.audioLevels, dt: dt)
          }
          .ignoresSafeArea()
      }
    }
    .accessibilityHidden(true)
  }
}
