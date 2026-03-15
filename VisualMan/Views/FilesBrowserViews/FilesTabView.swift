//
//  FilesTabView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI
import AVKit
internal import UniformTypeIdentifiers

struct FilesTabView: View {
  @State private var showingPlayer = false
  @State private var selectedAudioSource: FileAudioSource?
  @State private var fileLoadingFailed: Bool = false
  @State private var fileError: VMError?
  @State private var title: String?
  @State private var artist: String?
  @State private var albumArt: UIImage?
  @State private var isShowingVisualizer = false
  
  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  var body: some View {
    DocumentBrowserRepresentable(
      onDocumentPicked: { url in
      Task { @MainActor in
        do {
          guard url.startAccessingSecurityScopedResource() else {
            throw VMError.fileAccessDenied
          }
          
          defer {
            url.stopAccessingSecurityScopedResource()
          }
          
          let asset = AVURLAsset(url: url)
          
          try await extractMetadata(from: asset)
          
          selectedAudioSource = FileAudioSource(
            url: url,
            title: title,
            artist: artist,
            albumArt: albumArt
          )
          
          showingPlayer = true
          
        } catch {
          fileError = VMError.failedToCreateFile
          fileLoadingFailed = true
          print("Error loading file: \(error)")
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
  
  private func extractMetadata(from asset: AVAsset) async throws {
    let metadata = try await asset.load(.commonMetadata)
    
    title = try? await AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierTitle
    ).first?.load(.stringValue)
    
    artist = try? await AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierArtist
    ).first?.load(.stringValue)
    
    if let artworkItem = AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierArtwork
    ).first {
      if let imageData = try? await artworkItem.load(.dataValue) {
        albumArt = UIImage(data: imageData)
      }
    }
    
    if title == nil || artist == nil || albumArt == nil {
      if let iTunesMetadata = try? await asset.loadMetadata(for: .iTunesMetadata) {
        
        if title == nil {
          title = try? await AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataSongName
          ).first?.load(.stringValue)
        }
        
        if artist == nil {
          artist = try? await AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataArtist
          ).first?.load(.stringValue)
        }
        
        if albumArt == nil {
          if let artworkItem = AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataCoverArt
          ).first {
            if let imageData = try? await artworkItem.load(.dataValue) {
              albumArt = UIImage(data: imageData)
            }
          }
        }
      }
    }
  }
}
