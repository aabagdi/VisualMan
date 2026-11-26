//
//  ExternalDisplayPlaceholderView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import SwiftUI

struct ExternalDisplayPlaceholderView: View {
  let albumArt: UIImage?

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  var body: some View {
    Color.black
      .overlay {
        if let albumArt {
          Image(uiImage: albumArt)
            .resizable()
            .scaledToFill()
            .blur(radius: 40)
            .opacity(colorSchemeContrast == .increased ? 0.3 : 0.5)
            .accessibilityHidden(true)
            .accessibilityIgnoresInvertColors()
        }
      }
      .overlay {
        Label("Audio output source", systemImage: "airplay.audio")
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundStyle(.white.opacity(colorSchemeContrast == .increased ? 1 : 0.8))
      }
      .clipped()
  }
}
