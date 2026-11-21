//
//  ExternalDisplayView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/20/26.
//

import SwiftUI
import Dependencies

struct ExternalDisplayView: View {
  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(AudioPlaylistManager.self) private var playlistManager
  @Dependency(VisualizerSelection.self) private var visualizerSelection
  @Dependency(VisualizerRendererCache.self) private var rendererCache
  @Dependency(VisualizerSnapshotter.self) private var snapshotter

  var body: some View {
    ZStack {
      Color.black

      if let current = playlistManager.currentAudioSource {
        VisualizerContainerView(
          currentVisualizer: visualizerSelection.current,
          visualizerBars: audioManager.visualizerBars,
          audioLevels: audioManager.audioLevels,
          waveform: audioManager.waveform,
          albumArt: current.albumArt,
          isPlaying: audioManager.isPlaying
        )
      } else {
        Text("VisualMan")
          .font(.largeTitle)
          .fontWeight(.semibold)
          .foregroundStyle(.white.opacity(0.6))
      }
    }
    .ignoresSafeArea()
    .environment(visualizerSelection)
    .environment(rendererCache)
    .environment(snapshotter)
    .task {
      await rendererCache.preWarm()
    }
  }
}
