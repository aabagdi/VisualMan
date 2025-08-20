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
  @State private var showingFilePicker = false
  @State private var showingPlayer = false
  @State private var selectedAudioSource: FileAudioSource?
  @State private var fileLoadingFailed: Bool = false
  @State private var fileError: Error?
  @State private var title: String?
  @State private var artist: String?
  @State private var albumArt: UIImage?
  
  var body: some View {
    NavigationStack {
      VStack {
        Button("Select an audio file to play") {
          showingFilePicker.toggle()
        }
        .buttonStyle(.borderedProminent)
        .padding()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(UIColor.systemGroupedBackground))
      .alert("Failed to load file: \(fileError?.localizedDescription ?? "Unknown file loading error")", isPresented: $fileLoadingFailed) {
        Button("Okay", role: .cancel) {
          fileLoadingFailed = false
          fileError = nil
        }
      }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [.audio]
      ) { result in
        switch result {
        case .success(let url):
          Task { @MainActor in
            do {
              guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "FilesTabView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access file"])
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
              fileError = error
              fileLoadingFailed = true
              print("Error loading file: \(error)")
            }
          }
          
        case .failure(let error):
          fileError = error
          fileLoadingFailed = true
          print("File selection failed: \(error)")
        }
      }
      .navigationDestination(isPresented: $showingPlayer) {
        if let audioSource = selectedAudioSource {
          MusicPlayerView(fileAudioSource: audioSource)
            .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
    }
  }
  
  func extractMetadata(from asset: AVAsset) async throws {
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
