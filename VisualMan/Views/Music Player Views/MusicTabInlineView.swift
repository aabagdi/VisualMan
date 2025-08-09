//
//  MusicTabInlineView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/3/25.
//

import SwiftUI

struct MusicTabInlineView: View {
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  @State private var audioManager = AudioEngineManager.shared
  
  private let placeholder: UIImage = UIImage(named: "Art Placeholder")!
  
  private var albumArt: UIImage {
    switch playlistManager.currentAudioSource == nil {
    case true:
      return placeholder
    case false:
      return playlistManager.currentAudioSource?.albumArt ?? placeholder
    }
  }
  
  private var disabledIfNoSong: Bool {
    playlistManager.currentAudioSource == nil
  }
  
  var body: some View {
    GeometryReader { g in
      HStack(alignment: .center) {
        VStack {
          Spacer()
          Image(uiImage: albumArt)
            .resizable()
            .frame(width: 25, height: 25)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal)
          Spacer()
        }
        
        VStack {
          Text("\(playlistManager.currentAudioSource?.title ?? "Unknown") • \(playlistManager.currentAudioSource?.artist ?? "Unknown")")
            .font(.system(size: 12))
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        
        Spacer()
        
        HStack {
          Button {
            if audioManager.isPlaying {
              audioManager.pause()
            } else if audioManager.currentTime > 0 && audioManager.currentTime < audioManager.duration {
              audioManager.resume()
            } else {
              playCurrentSong()
            }
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 12))
          }
          .buttonStyle(.plain)
          .padding()
          .disabled(disabledIfNoSong)
        }
      }
    }
  }
  
  private func playCurrentSong() {
    guard let source = playlistManager.currentAudioSource else { return }
    try? audioManager.play(source)
  }
}
