//
//  FilesTabView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct FilesTabView: View {
  @State private var showingFilePicker = false
  @State private var showingPlayer = false
  @State private var selectedAudioSource: FileAudioSource?
  
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
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [.audio],
      ) { result in
        switch result {
        case .success(let url):
          selectedAudioSource = FileAudioSource(url: url)
          showingPlayer = true
        case .failure(let error):
          print("Error selecting file: \(error)")
        }
      }
      .navigationDestination(isPresented: $showingPlayer) {
        if let audioSource = selectedAudioSource, let url = audioSource.getPlaybackURL() {
          MusicPlayerView(fileURL: url)
            .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
    }
  }
}
