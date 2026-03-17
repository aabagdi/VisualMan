//
//  BarVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct BarsVisualizerView: View {
  let visualizerBars: [32 of Float]
  
  let barCount = 32
  let barSpacing: CGFloat = 2
  let minBarHeight: CGFloat = 4
  
  var body: some View {
    GeometryReader { g in
      HStack(spacing: barSpacing) {
        ForEach(0..<barCount, id: \.self) { index in
          BarView(
            level: visualizerBars[index],
            index: index,
            totalBars: barCount,
            maxHeight: g.size.height,
            minHeight: minBarHeight
          )
        }
      }
      .padding(.horizontal)
    }
    .background(Color.black)
  }
}
