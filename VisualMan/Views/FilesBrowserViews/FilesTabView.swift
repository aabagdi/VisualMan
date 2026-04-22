//
//  FilesTabView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct FilesTabView: View {
  @State private var showingPlayer = false
  @State private var selectedAudioSource: FileAudioSource?
  @State private var fileLoadingFailed: Bool = false
  @State private var fileError: VMError?
  @State private var isShowingVisualizer = false

  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(AudioPlaylistManager.self) private var playlistManager

  var body: some View {
    DocumentBrowserRepresentable(
      onDocumentPicked: { url in
      Task { @MainActor in
        do {
          let isSecurityScoped = url.startAccessingSecurityScopedResource()

          selectedAudioSource = try await FileAudioSource.from(
            url: url,
            isSecurityScoped: isSecurityScoped
          )
          showingPlayer = true

        } catch let error as VMError {
          fileError = error
          fileLoadingFailed = true
        } catch {
          fileError = VMError.failedToCreateFile
          fileLoadingFailed = true
        }
      }
    },
      showVisualizerButton: audioManager.isPlaying || audioManager.currentTime > 0,
      onVisualizerTapped: { isShowingVisualizer = true }
    )
    .alert(
      fileError?.errorDescription ?? "An unknown error occurred while loading the file.",
      isPresented: $fileLoadingFailed
    ) {
      Button("Okay", role: .cancel) {
        fileLoadingFailed = false
        fileError = nil
      }
    }
    .navigationDestination(isPresented: $showingPlayer) {
      if let audioSource = selectedAudioSource {
        MusicPlayerView(fileAudioSource: audioSource)
          .toolbarVisibility(.hidden, for: .tabBar)
      }
    }
    .navigationDestination(isPresented: $isShowingVisualizer) {
      MusicPlayerView(playlistManager.audioSources, startingIndex: playlistManager.currentIndex)
    }
  }
}
