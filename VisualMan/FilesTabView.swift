//
//  FilesTabView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct FilesTabView: View {
  @State private var showingFilePicker = false
  @State private var selectedFileURL: URL?
  @State private var showingPlayer = false
  @State private var selectedAudioSource: FileAudioSource?
  
  var body: some View {
    NavigationStack {
      VStack {
        Button("Select Audio File") {
          showingFilePicker = true
        }
        .font(.headline)
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
      }
      .navigationTitle("Files")
      .sheet(isPresented: $showingFilePicker) {
        FilePickerView(
          selectedFileURL: $selectedFileURL,
          onFilePicked: { url in
            selectedAudioSource = FileAudioSource(url: url)
            showingFilePicker = false
            showingPlayer = true
          }
        )
      }
      .navigationDestination(isPresented: $showingPlayer) {
        if let audioSource = selectedAudioSource {
          MusicPlayerView(audioSource)
        }
      }
    }
  }
}
