//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI

struct MusicPlayerView: View {
  @State private var viewModel = MusicPlayerViewModel()
  @State private var isTapped: Bool = false
  @State private var snapshotter = VisualizerSnapshotter()
  @State private var showScreenshotToast = false
  @State private var toastDismissTask: Task<Void, Never>?

  @Environment(VisualizerSelection.self) private var visualizerSelection

  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(AudioPlaylistManager.self) private var playlistManager
  @Environment(VisualizerRendererCache.self) private var rendererCache
  
  private let _audioSources: [any AudioSource]
  private let _startingIndex: Int
  private let sliderColor: Color = .white
  
  private var normalFillColor: Color {
    sliderColor.opacity(0.5)
  }
  
  private var emptyColor: Color {
    sliderColor.opacity(0.3)
  }
  
  private var currentAudioSource: (any AudioSource)? {
    playlistManager.currentAudioSource
  }
  
  init(_ audioSources: [any AudioSource], startingIndex: Int) {
    _audioSources = audioSources
    _startingIndex = startingIndex
  }
  
  init(fileAudioSource: FileAudioSource) {
    let sources = [fileAudioSource]
    _audioSources = sources
    _startingIndex = 0
  }
  
  var body: some View {
    ZStack {
      AudioReactiveVisualizerLayer(
        currentVisualizer: visualizerSelection.current,
        albumArt: currentAudioSource?.albumArt
      )
      .ignoresSafeArea()
      .onTapGesture {
        withAnimation(.easeInOut) {
          isTapped.toggle()
        }
      }

      PlayerControlsLayer(
        viewModel: viewModel,
        isTapped: $isTapped
      )

      Text("Screenshot Saved")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(showScreenshotToast ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showScreenshotToast)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .allowsHitTesting(false)
    }
    .toolbar(.hidden, for: .tabBar)
    .environment(snapshotter)
    .onAppear {
      viewModel.start(audioSources: _audioSources, startingIndex: _startingIndex)
    }
    .task {
      await rendererCache.preWarm()
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .alert(viewModel.playingError?.errorDescription ?? "An unknown error occurred during playback.",
           isPresented: $viewModel.failedPlaying) {
      Button("Okay", role: .cancel) {
        viewModel.failedPlaying = false
        viewModel.playingError = nil
      }
    }
    .alert(audioManager.initializationError?.errorDescription ?? "An unknown error occurred during initialization.",
           isPresented: Bindable(audioManager).failedToInitialize) {
      Button("Okay", role: .cancel) {
        audioManager.failedToInitialize = false
        audioManager.initializationError = nil
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          captureScreenshot()
        } label: {
          Image(systemName: "camera")
        }
        .accessibilityLabel("Capture Screenshot")
      }

      ToolbarSpacer(.fixed, placement: .topBarTrailing)

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          ForEach(VMVisualizer.allCases, id: \.self) { type in
            Button {
              visualizerSelection.current = type
            } label: {
              if type == visualizerSelection.current {
                Label(type.rawValue, systemImage: "checkmark")
              } else {
                Text(type.rawValue)
              }
            }
          }
        } label: {
          Text(visualizerSelection.current.rawValue)
        }
      }
    }
  }

  private func captureScreenshot() {
    Task { @MainActor in
      guard await snapshotter.capture() else { return }

      toastDismissTask?.cancel()
      showScreenshotToast = true
      toastDismissTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        showScreenshotToast = false
      }
    }
  }
}

private struct AudioReactiveVisualizerLayer: View {
  let currentVisualizer: VMVisualizer
  let albumArt: UIImage?

  @Environment(AudioEngineManager.self) private var audioManager

  var body: some View {
    VisualizerContainerView(
      currentVisualizer: currentVisualizer,
      visualizerBars: audioManager.visualizerBars,
      audioLevels: audioManager.audioLevels,
      waveform: audioManager.waveform,
      albumArt: albumArt
    )
  }
}

private struct PlayerControlsLayer: View {
  let viewModel: MusicPlayerView.MusicPlayerViewModel
  @Binding var isTapped: Bool

  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(AudioPlaylistManager.self) private var playlistManager

  private let sliderColor: Color = .white

  private var normalFillColor: Color { sliderColor.opacity(0.5) }
  private var emptyColor: Color { sliderColor.opacity(0.3) }

  var body: some View {
    @Bindable var audioManager = audioManager

    VStack {
      Spacer()
      if let current = playlistManager.currentAudioSource {
        MarqueeTextView(
          "\(current.title ?? "Unknown") • \(current.artist ?? "Unknown")",
          resetID: playlistManager.currentIndex
        )
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .frame(height: 40)
      }

      ProgressSliderView(value: $audioManager.currentTime,
                         inRange: TimeInterval.zero...max(audioManager.duration, 0.1),
                         activeFillColor: sliderColor,
                         fillColor: normalFillColor,
                         emptyColor: emptyColor,
                         height: 8
      ) { isDragging in
        if !isDragging {
          audioManager.seek(to: audioManager.currentTime)
        }
      }
      .frame(height: 60)
      .padding()

      HStack {
        Button {
          viewModel.skipBackwards()
        } label: {
          Image(systemName: "backward")
            .foregroundStyle(normalFillColor)
        }
        .accessibilityLabel(audioManager.currentTime >= 3 ? "Restart" : "Previous")
        .padding()

        Spacer()

        Button {
          viewModel.togglePlayback()
        } label: {
          Image(systemName: audioManager.isPlaying ? "pause" : "play")
            .foregroundStyle(normalFillColor)
        }
        .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
        .padding()

        Spacer()

        Button {
          viewModel.skipForwards()
        } label: {
          Image(systemName: "forward")
            .foregroundStyle(normalFillColor)
        }
        .accessibilityLabel("Next")
        .padding()
      }
      .contentShape(Rectangle())
      .padding()
    }
    .background(
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0.4),
          .init(color: .black.opacity(0.7), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeInOut) {
        isTapped.toggle()
      }
    }
    .zIndex(1)
    .opacity(isTapped ? 0 : 1)
    .allowsHitTesting(!isTapped)
    .accessibilityHidden(isTapped)
  }
}
