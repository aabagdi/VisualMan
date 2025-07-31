//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer
import Combine

struct MusicPlayerView: View {
  @State private var currentVisualizer = Visualizers.bars
  @State private var isTapped: Bool = false
  @State private var failedPlaying: Bool = false
  @State private var playingError: Error?
  @State private var currentIndex: Int
  @State private var scrollToEnd = false
  @State private var textSize: CGSize = .zero
  @State private var containerSize: CGSize = .zero
  @State private var scrollAnimationKey = UUID()
  
  @ObservedObject private var audioManager = AudioEngineManager.shared
  
  private var sliderColor: Color = .white
  
  private var shouldScroll: Bool {
    textSize.width > containerSize.width
  }
  
  private var scrollDuration: Double {
    Double(textSize.width) / 20.0
  }
  
  private var normalFillColor: Color {
    sliderColor.opacity(0.5)
  }
  private var emptyColor: Color {
    sliderColor.opacity(0.3)
  }
  
  enum Visualizers: String, CaseIterable {
    case bars = "Bars"
    case julia = "Julia Set"
    case fireworks = "Fireworks"
    case interference = "Interference Pattern"
    case voronoi = "Voronoi Diagram"
  }
  
  let audioSources: [any AudioSource]
  
  var currentAudioSource: (any AudioSource)? {
    guard currentIndex >= 0 && currentIndex < audioSources.count else { return nil }
    return audioSources[currentIndex]
  }
  
  var hasNext: Bool {
    currentIndex < audioSources.count - 1
  }
  
  var hasPrevious: Bool {
    currentIndex > 0
  }
  
  init(_ audioSources: [AudioSource], startingIndex: Int) {
    self.audioSources = audioSources
    self._currentIndex = State(initialValue: startingIndex)
  }
  
  init(fileURL: URL, title: String? = nil) {
    self.audioSources = [FileAudioSource(url: fileURL, title: title)]
    self._currentIndex = State(initialValue: 0)
  }
  
  var body: some View {
    ZStack {
      currentShader(currentVisualizer: currentVisualizer, visualizerBars: audioManager.visualizerBars, audioLevels: audioManager.audioLevels)
        .ignoresSafeArea()
      VStack {
        Spacer()
        if let current = currentAudioSource {
          GeometryReader { g in
            ScrollViewReader { _ in
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: shouldScroll ? 100 : 0) {
                  ForEach(0..<(shouldScroll ? 3 : 1), id: \.self) { _ in
                    Text("\(current.title ?? "Unknown") • \(current.artist ?? "Unknown")")
                      .font(.title2)
                      .fontWeight(.semibold)
                      .foregroundColor(.white)
                      .lineLimit(1)
                      .fixedSize()
                      .background(
                        GeometryReader { textGeometry in
                          Color.clear
                            .onAppear {
                              let newSize = textGeometry.size
                              if newSize != textSize {
                                textSize = newSize
                              }
                            }
                        }
                      )
                  }
                }
                .id("\(currentIndex)-\(scrollAnimationKey)")
                .padding(.horizontal)
                .offset(x: shouldScroll ? (scrollToEnd ? -textSize.width - 100 : 0) : 0)
                .animation(scrollToEnd ? .linear(duration: scrollDuration).repeatForever(autoreverses: false) : .none, value: scrollToEnd)
              }
              .disabled(true)
              .onAppear {
                containerSize = g.size
              }
              .onChange(of: textSize) { oldSize, newSize in
                if oldSize == .zero && newSize.width > containerSize.width && !scrollToEnd {
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scrollToEnd = true
                  }
                }
              }
              .onChange(of: currentIndex) { _, _ in
                scrollToEnd = false
                textSize = .zero
                scrollAnimationKey = UUID()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  scrollAnimationKey = UUID()
                }
              }
              .onChange(of: scrollAnimationKey) { _, _ in
                if textSize.width > containerSize.width {
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scrollToEnd = true
                  }
                }
              }
            }
          }
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
            skipBackwards()
          } label: {
            Image(systemName: "backward")
              .foregroundStyle(normalFillColor)
          }
          Spacer()
          Button {
            if audioManager.isPlaying {
              audioManager.pause()
            } else {
              audioManager.resume()
            }
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause" : "play")
              .foregroundStyle(normalFillColor)
          }
          Spacer()
          Button {
            skipForwards()
          } label: {
            Image(systemName: "forward")
              .foregroundStyle(normalFillColor)
          }
        }
        .padding()
        .onAppear {
          do {
            try audioManager.play(audioSources[currentIndex])
          } catch {
            failedPlaying.toggle()
          }
        }
        .onDisappear {
          audioManager.stop()
        }
      }
      .zIndex(1)
      .opacity(isTapped ? 0 : 1)
    }
    .onTapGesture {
      withAnimation(.easeInOut) {
        isTapped.toggle()
      }
    }
    .toolbar {
      Picker("Current Visualizer", selection: $currentVisualizer) {
        ForEach(Visualizers.allCases, id: \.self) { type in
          Text(type.rawValue)
            .tag(type)
        }
      }
      .fixedSize()
    }
  }
  
  private func playCurrentSong() {
    guard let source = currentAudioSource else { return }
    
    audioManager.stop()
    
    do {
      try audioManager.play(source)
    } catch {
      failedPlaying = true
      playingError = error
    }
  }
  
  private func skipBackwards() {
    if audioManager.currentTime >= 3 {
      audioManager.seek(to: 0)
      return
    } else if currentIndex > 0 {
      currentIndex -= 1
      playCurrentSong()
    } else if currentIndex == 0 {
      audioManager.seek(to: 0)
    }
  }
  
  private func skipForwards() {
    guard hasNext else { return }
    currentIndex += 1
    playCurrentSong()
  }
  
  @ViewBuilder
  private func currentShader(currentVisualizer: Visualizers, visualizerBars: [Float], audioLevels: [Float]) -> some View {
    switch currentVisualizer {
    case .bars:
      BarVisualizerView(visualizerBars: visualizerBars)
    case .julia:
      JuliaVisualizerView(audioLevels: audioLevels)
    case .fireworks:
      FireworksVisualizerView(audioLevels: audioLevels)
    case .interference:
      InterferenceVisualizerView(audioLevels: audioLevels)
    case .voronoi:
      VoronoiVisualizerView(audioLevels: audioLevels)
    }
  }
}
