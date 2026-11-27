//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import Dependencies
import os

struct MusicPlayerView: View {
  @State private var isTapped: Bool = false
  @State private var showScreenshotToast = false

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @Environment(VisualizerSelection.self) private var visualizerSelection
  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(AudioPlaylistManager.self) private var playlistManager
  @Dependency(PlaybackController.self) private var playback
  @Environment(VisualizerRendererCache.self) private var rendererCache
  @Dependency(\.continuousClock) private var clock
  @Dependency(VisualizerSnapshotter.self) private var snapshotter
  @Dependency(ExternalDisplayManager.self) private var externalDisplay
  @Dependency(VisualizerUsageManager.self) private var usageManager
  
  private let audioSources: [any AudioSource]
  private let startingIndex: Int

  private var currentAudioSource: (any AudioSource)? {
    playlistManager.currentAudioSource
  }
  
  init(_ audioSources: [any AudioSource], startingIndex: Int) {
    self.audioSources = audioSources
    self.startingIndex = startingIndex
  }
  
  init(fileAudioSource: FileAudioSource) {
    audioSources = [fileAudioSource]
    startingIndex = 0
  }
  
  var body: some View {
    ZStack {
      Group {
        if externalDisplay.isConnected {
          ExternalDisplayPlaceholderView(albumArt: currentAudioSource?.albumArt)
        } else {
          AudioReactiveVisualizerLayer(
            currentVisualizer: visualizerSelection.current,
            albumArt: currentAudioSource?.albumArt
          )
        }
      }
      .ignoresSafeArea()
      .onTapGesture { visualizerTapped() }

      PlayerControlsLayer(
        playback: playback,
        isTapped: $isTapped
      )

      Text("Screenshot Saved")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(toastBackground, in: Capsule())
        .opacity(showScreenshotToast ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showScreenshotToast)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .allowsHitTesting(false)
        .accessibilityHidden(!showScreenshotToast)
    }
    .accessibilityAction(.magicTap) {
      playback.togglePlayback()
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(ExternalDisplayAccessory())
    .modifier(SettingsToolbarButton())
    .modifier(VisualizerUsageTracking(visualizer: visualizerSelection.current))
    .environment(snapshotter)
    .onAppear {
      playback.playerAppeared()
      playback.start(audioSources: audioSources, startingIndex: startingIndex)
    }
    .task {
      let preWarmState = pointsOfInterest.beginInterval("Pre-Warm Renderers")
      await rendererCache.preWarm()
      pointsOfInterest.endInterval("Pre-Warm Renderers", preWarmState)
      seedPaletteForCurrentSong()
    }
    .onChange(of: playlistManager.currentIndex) { _, _ in
      seedPaletteForCurrentSong()
    }
    .onDisappear {
      playback.playerDisappeared()
    }
    .task(id: showScreenshotToast) { await screenshotToastChanged() }
    .alert(playback.playingError?.errorDescription
           ?? String(localized: "An unknown error occurred during playback."),
           isPresented: Bindable(playback).failedPlaying) {
      Button("Okay", role: .cancel) { playingErrorOkayTapped() }
    }
    .alert(audioManager.initializationError?.errorDescription
           ?? String(localized: "An unknown error occurred during initialization."),
           isPresented: Bindable(audioManager).failedToInitialize) {
      Button("Okay", role: .cancel) { initializationErrorOkayTapped() }
    }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        #if !targetEnvironment(simulator)
        if visualizerSelection.current == .abstractExpressionism {
          Button {
            rendererCache.renderer(AbstractExpressionismRenderer.self)?.reset()
          } label: {
            Image(systemName: "eraser")
          }
          .accessibilityLabel("Clear Canvas")
        }

        if visualizerSelection.current == .navierStokes {
          Menu {
            Picker("Solver", selection: Bindable(visualizerSelection).navierStokesSolver) {
              ForEach(NavierStokesSolver.allCases, id: \.self) { mode in
                Text(mode.displayName)
              }
            }
          } label: {
            Image(systemName: "graph.2d")
          }
          .accessibilityLabel("Navier-Stokes Solver Mode")
        }
        #endif

        Button {
          Task { await screenshotButtonTapped() }
        } label: {
          Image(systemName: "camera")
        }
        .accessibilityLabel("Capture Screenshot")
      }

      ToolbarSpacer(.fixed, placement: .topBarTrailing)

      ToolbarItem(placement: .topBarTrailing) {
        visualizerSelectorMenu
      }
    }
  }

  private var visualizerSelectorMenu: some View {
    Menu {
      ForEach(VMVisualizer.allCases, id: \.self) { type in
        Button {
          visualizerSelected(type)
        } label: {
          if type == visualizerSelection.current {
            Label(type.displayName, systemImage: "checkmark")
          } else {
            Text(type.displayName)
          }
        }
      }
    } label: {
      Text(visualizerSelection.current.toolbarName)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityLabel(Text(visualizerSelection.current.displayName))
        .accessibilityInputLabels([
          Text(visualizerSelection.current.toolbarName),
          Text(visualizerSelection.current.displayName),
        ])
    }
  }

  private var toastBackground: AnyShapeStyle {
    if colorSchemeContrast == .increased || reduceTransparency {
      AnyShapeStyle(.black.opacity(0.85))
    } else {
      AnyShapeStyle(.ultraThinMaterial)
    }
  }

  private func visualizerTapped() {
    withAnimation(.easeInOut) {
      isTapped.toggle()
    }
  }

  private func visualizerSelected(_ type: VMVisualizer) {
    pointsOfInterest.emitEvent("Visualizer Selected", "\(String(describing: type), privacy: .public)")
    if type != visualizerSelection.current {
      usageManager.recordSelection(type)
      OpenVisualizerIntent.donate(type)
    }
    visualizerSelection.current = type
  }

  private func playingErrorOkayTapped() {
    playback.failedPlaying = false
    playback.playingError = nil
  }

  private func initializationErrorOkayTapped() {
    audioManager.failedToInitialize = false
    audioManager.initializationError = nil
  }

  private func screenshotButtonTapped() async {
    guard await snapshotter.capture() else { return }

    var announcement = AttributedString(localized: "Screenshot Saved")
    announcement.accessibilitySpeechAnnouncementPriority = .high
    AccessibilityNotification.Announcement(announcement).post()

    showScreenshotToast = true
  }

  private func screenshotToastChanged() async {
    guard showScreenshotToast else { return }
    try? await clock.sleep(for: .seconds(2))
    showScreenshotToast = false
  }

  #if !targetEnvironment(simulator)
  private func seedPaletteForCurrentSong() {
    guard let renderer = rendererCache.renderer(AbstractExpressionismRenderer.self),
          let source = playlistManager.currentAudioSource else { return }
    let key = [source.title, source.artist, source.getPlaybackURL()?.lastPathComponent]
      .compactMap { $0 }
      .joined(separator: "|")
    renderer.beginSong(key: key)
  }
  #else
  private func seedPaletteForCurrentSong() {}
  #endif
}

private struct AudioReactiveVisualizerLayer: View {
  let currentVisualizer: VMVisualizer
  let albumArt: UIImage?

  @Dependency(AudioEngineManager.self) private var audioManager

  var body: some View {
    VisualizerContainerView(
      currentVisualizer: currentVisualizer,
      albumArt: albumArt,
      isPlaying: audioManager.isPlaying
    )
  }
}

private struct PlayerControlsLayer: View {
  let playback: PlaybackController
  @Binding var isTapped: Bool

  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(AudioPlaylistManager.self) private var playlistManager

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
  @Dependency(AccessibilityManager.self) private var accessibilityManager
  @ScaledMetric(relativeTo: .title2) private var titleHeight: CGFloat = 40

  private let sliderColor: Color = .white

  private var increasedContrast: Bool { colorSchemeContrast == .increased }
  private var normalFillColor: Color { increasedContrast ? sliderColor : sliderColor.opacity(0.5) }
  private var emptyColor: Color { sliderColor.opacity(increasedContrast ? 0.5 : 0.35) }
  private var controlsHidden: Bool {
    isTapped && !voiceOverEnabled && !switchControlEnabled && !accessibilityManager.keepsControlsVisible
  }

  var body: some View {
    VStack {
      Spacer()
      if let current = playlistManager.currentAudioSource {
        MarqueeTextView(
          "\(current.title ?? String(localized: "Unknown")) • \(current.artist ?? String(localized: "Unknown"))",
          resetID: playlistManager.currentIndex
        )
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .frame(height: titleHeight)
      }

      ProgressSliderView(value: { audioManager.currentTime },
                         setValue: { audioManager.currentTime = $0 },
                         inRange: TimeInterval.zero...max(audioManager.duration, 0.1),
                         activeFillColor: sliderColor,
                         fillColor: normalFillColor,
                         emptyColor: emptyColor,
                         height: 8,
                         onEditingChanged: progressSliderEditingChanged)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .frame(height: 60)
      .padding(.horizontal)

      HStack {
        SkipBackwardButton(playback: playback, color: normalFillColor)
          .padding()

        Spacer()

        Button {
          playback.togglePlayback()
        } label: {
          Image(systemName: audioManager.isPlaying ? "pause" : "play")
            .foregroundStyle(normalFillColor)
        }
        .accessibilityLabel(audioManager.isPlaying ? Text("Pause") : Text("Play"))
        .padding()

        Spacer()

        Button {
          playback.skipForwards()
        } label: {
          Image(systemName: "forward")
            .foregroundStyle(normalFillColor)
        }
        .accessibilityLabel("Next")
        .padding()
      }
      .contentShape(Rectangle())
      .padding(.horizontal)

      AudioRoutePickerView(tintColor: UIColor(normalFillColor))
        .frame(width: 44, height: 44)
        .accessibilityLabel("Audio Output")
        .padding(.bottom)
    }
    .background(
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0.4),
          .init(color: .black.opacity(increasedContrast ? 0.9 : 0.7), location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .contentShape(Rectangle())
    .onTapGesture { controlsTapped() }
    .zIndex(1)
    .opacity(controlsHidden ? 0 : 1)
    .allowsHitTesting(!controlsHidden)
    .accessibilityHidden(controlsHidden)
  }

  private func controlsTapped() {
    withAnimation(.easeInOut) {
      isTapped.toggle()
    }
  }

  private func progressSliderEditingChanged(_ isDragging: Bool) {
    guard !isDragging else { return }
    audioManager.seek(to: audioManager.currentTime)
  }
}

extension NavierStokesSolver {
  var displayName: LocalizedStringResource {
    switch self {
    case .pressureMultigrid: "V-grid solver (more realistic)"
    case .jacobi: "Jacobi solver (more efficient)"
    }
  }
}
