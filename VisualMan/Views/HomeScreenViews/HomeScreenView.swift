//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI
import Dependencies
internal import UniformTypeIdentifiers

private struct NowPlayingDestination: Hashable {}

struct HomeScreenView: View {
  @State private var isShowingFileImporter = false
  @State private var selectedAudioSource: FileAudioSource?
  @State private var fileError: VMError?
  
  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(MusicLibraryAccessManager.self) private var library
  @Dependency(AudioPlaylistManager.self) private var playlistManager
  @Dependency(VisualizerSelection.self) private var visualizerSelection
  
  var body: some View {
    NavigationStack {
      AlbumListView(albums: library.albums)
        .navigationDestination(for: NowPlayingDestination.self) { _ in
          MusicPlayerView(playlistManager.audioSources,
                          startingIndex: playlistManager.currentIndex)
        }
        .navigationDestination(item: $selectedAudioSource) { audioSource in
          MusicPlayerView(fileAudioSource: audioSource)
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            NavigationLink("Credits") {
              CreditsView()
            }
          }
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Files", systemImage: "folder.fill") {
              isShowingFileImporter = true
            }
            if audioManager.isPlaying || audioManager.hasPlaybackPosition {
              NavigationLink(value: NowPlayingDestination()) {
                Label("Now Playing", systemImage: "play.fill")
              }
            }
          }
        }
        .modifier(SettingsToolbarButton())
    }
    .fileImporter(
      isPresented: $isShowingFileImporter,
      allowedContentTypes: [.aiff, .mp3, .wav, .mpeg4Audio, .audio]
    ) { fileImporterCompleted($0) }
    .alert(
      fileError?.errorDescription ?? String(localized: "An unknown error occurred while loading the file."),
      isPresented: $fileError.isPresented
    ) {
      Button("Okay", role: .cancel) { }
    }
    .environment(visualizerSelection)
  }
  
  private func fileImporterCompleted(_ result: Result<URL, any Error>) {
    switch result {
    case .success(let url):
      openFile(at: url)
    case .failure:
      fileError = VMError.failedToCreateFile
    }
  }

  private func openFile(at url: URL) {
    Task {
      let isSecurityScoped = url.startAccessingSecurityScopedResource()
      do {
        selectedAudioSource = try await FileAudioSource.from(
          url: url,
          isSecurityScoped: isSecurityScoped
        )
      } catch let error as VMError {
        if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        fileError = error
      } catch {
        if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        fileError = VMError.failedToCreateFile
      }
    }
  }
}

private extension Optional {
  var isPresented: Bool {
    get { self != nil }
    set {
      guard !newValue else { return }
      self = nil
    }
  }
}
