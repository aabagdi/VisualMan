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
  @State private var visualizerSelection = VisualizerSelection()
  @State private var isShowingFileImporter = false
  @State private var selectedAudioSource: FileAudioSource?
  @State private var isShowingFilePlayer = false
  @State private var fileLoadingFailed = false
  @State private var fileError: VMError?
  
  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(MusicLibraryAccessManager.self) private var library
  @Dependency(AudioPlaylistManager.self) private var playlistManager
  
  var body: some View {
    NavigationStack {
      AlbumListView(albums: library.albums)
        .navigationDestination(for: NowPlayingDestination.self) { _ in
          MusicPlayerView(playlistManager.audioSources,
                          startingIndex: playlistManager.currentIndex)
        }
        .navigationDestination(isPresented: $isShowingFilePlayer) {
          if let audioSource = selectedAudioSource {
            MusicPlayerView(fileAudioSource: audioSource)
          }
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            NavigationLink("Credits", destination: CreditsView())
          }
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Files", systemImage: "folder.fill") {
              isShowingFileImporter = true
            }
            if audioManager.isPlaying || audioManager.currentTime > 0 {
              NavigationLink(value: NowPlayingDestination()) {
                Label("Now Playing", systemImage: "play.fill")
              }
            }
          }
        }
    }
    .fileImporter(
      isPresented: $isShowingFileImporter,
      allowedContentTypes: [.aiff, .mp3, .wav, .mpeg4Audio, .audio]
    ) { result in
      switch result {
      case .success(let url):
        openFile(at: url)
      case .failure:
        fileError = VMError.failedToCreateFile
        fileLoadingFailed = true
      }
    }
    .alert(
      fileError?.errorDescription ?? "An unknown error occurred while loading the file.",
      isPresented: $fileLoadingFailed
    ) {
      Button("Okay", role: .cancel) {
        fileLoadingFailed = false
        fileError = nil
      }
    }
    .environment(visualizerSelection)
  }
  
  private func openFile(at url: URL) {
    Task { @MainActor in
      let isSecurityScoped = url.startAccessingSecurityScopedResource()
      do {
        selectedAudioSource = try await FileAudioSource.from(
          url: url,
          isSecurityScoped: isSecurityScoped
        )
        isShowingFilePlayer = true
      } catch let error as VMError {
        if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        fileError = error
        fileLoadingFailed = true
      } catch {
        if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        fileError = VMError.failedToCreateFile
        fileLoadingFailed = true
      }
    }
  }
}
