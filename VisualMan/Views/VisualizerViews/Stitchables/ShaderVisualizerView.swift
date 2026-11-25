//
//  ShaderVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/20/26.
//

import SwiftUI
import Dependencies

struct ShaderVisualizerView<Content: View>: View {
  @State private var audio = SmoothedAudio()

  @Dependency(AudioEngineManager.self) private var audioManager

  @ViewBuilder let content: (SmoothedAudio) -> Content

  var body: some View {
    TimelineView(.animation) { timeline in
      content(audio)
        .onChange(of: timeline.date) { oldValue, newValue in
          let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
          audio.update(from: audioManager.audioLevels, dt: dt)
        }
        .ignoresSafeArea()
    }
    .accessibilityHidden(true)
  }
}
