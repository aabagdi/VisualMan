//
//  BarVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct BarsVisualizerView: View {
  let visualizerBars: [32 of Float]

  @State private var smoothedBars: [32 of Float] = .init(repeating: 0.0)

  var barCount: Int { visualizerBars.count }
  let barSpacing: CGFloat = 2
  let minBarHeight: CGFloat = 4

  private let attackTime: Float = 0.04
  private let releaseTime: Float = 0.12

  var body: some View {
    TimelineView(.animation) { timeline in
      GeometryReader { g in
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = (g.size.width - 32 - totalSpacing) / CGFloat(barCount)
        let cornerRadius = barWidth * 0.2077922078
        HStack(spacing: barSpacing) {
          ForEach(0..<barCount, id: \.self) { index in
            BarView(
              level: smoothedBars[index],
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
      .onChange(of: timeline.date) { oldValue, newValue in
        let dt = min(Float(newValue.timeIntervalSince(oldValue)), 0.1)
        updateSmoothedBars(dt: dt)
      }
    }
    .background(Color.black)
    .accessibilityHidden(true)
  }

  private func updateSmoothedBars(dt: Float) {
    let attackFactor = 1 - exp(-dt / attackTime)
    let releaseFactor = 1 - exp(-dt / releaseTime)
    var bars = smoothedBars
    for i in 0..<barCount {
      let target = visualizerBars[i]
      let factor = target > bars[i] ? attackFactor : releaseFactor
      bars[i] += (target - bars[i]) * factor
    }
    smoothedBars = bars
  }
}
