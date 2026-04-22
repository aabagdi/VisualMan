//
//  AlbumArtWaveVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/31/25.
//

import SwiftUI

struct AlbumArtWaveVisualizerView: View {
  @State private var audio = SmoothedAudio()

  let audioLevels: [1024 of Float]
  let albumArt: UIImage?
  let placeholder = UIImage(resource: .artPlaceholder)

  var body: some View {
    GeometryReader { g in
      TimelineView(.animation) { timeline in
        Image(uiImage: albumArt ?? placeholder)
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
            audio.update(from: audioLevels, dt: dt)
          }
          .ignoresSafeArea()
      }
    }
  }
}
