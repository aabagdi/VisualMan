//
//  NowPlayingIndicatorView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import SwiftUI

struct NowPlayingIndicatorView: View {
  let isAnimating: Bool
  
  @State private var barHeights: [CGFloat] = [0.3, 0.5, 0.4]

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 1.5) {
      ForEach(0..<3, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1)
          .frame(width: 3, height: barHeights[index] * 12)
      }
    }
    .frame(width: 14, height: 12, alignment: .bottom)
    .accessibilityHidden(true)
    .onChange(of: isAnimating && !reduceMotion, initial: true) {
      if isAnimating && !reduceMotion {
        startAnimating()
      } else {
        stopAnimating()
      }
    }
  }
  
  private func startAnimating() {
    withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
      barHeights[0] = 1.0
    }
    withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
      barHeights[1] = 0.85
    }
    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
      barHeights[2] = 0.95
    }
  }
  
  private func stopAnimating() {
    withAnimation(.easeOut(duration: 0.3)) {
      barHeights = [0.4, 0.55, 0.45]
    }
  }
}
