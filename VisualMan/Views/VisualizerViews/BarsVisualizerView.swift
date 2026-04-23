//
//  BarVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct BarsVisualizerView: View {
  let visualizerBars: [32 of Float]

  var barCount: Int { visualizerBars.count }
  let barSpacing: CGFloat = 2
  let minBarHeight: CGFloat = 4

  var body: some View {
    GeometryReader { g in
      let totalSpacing = barSpacing * CGFloat(barCount - 1)
      let barWidth = (g.size.width - 32 - totalSpacing) / CGFloat(barCount)
      let cornerRadius = barWidth * 0.2077922078
      HStack(spacing: barSpacing) {
        ForEach(0..<barCount, id: \.self) { index in
          BarView(
            level: visualizerBars[index],
            index: index,
            totalBars: barCount,
            maxHeight: g.size.height,
            minHeight: minBarHeight,
            cornerRadius: cornerRadius
          )
        }
      }
      .padding(.horizontal)
    }
    .background(Color.black)
    .accessibilityHidden(true)
  }
}
