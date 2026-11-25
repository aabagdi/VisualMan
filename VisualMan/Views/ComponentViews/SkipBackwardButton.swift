//
//  SkipBackwardButton.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import SwiftUI
import Dependencies

struct SkipBackwardButton: View {
  let viewModel: MusicPlayerView.MusicPlayerViewModel
  let color: Color

  @Dependency(AudioEngineManager.self) private var audioManager

  var body: some View {
    SkipBackwardButtonContent(viewModel: viewModel, color: color, restarts: audioManager.currentTime >= 3)
  }
}

private struct SkipBackwardButtonContent: View {
  let viewModel: MusicPlayerView.MusicPlayerViewModel
  let color: Color
  let restarts: Bool

  var body: some View {
    Button {
      viewModel.skipBackwards()
    } label: {
      Image(systemName: "backward")
        .foregroundStyle(color)
    }
    .accessibilityLabel(restarts ? Text("Restart") : Text("Previous"))
  }
}
