//
//  BarView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct BarView: View {
  let level: Float
  let index: Int
  let totalBars: Int
  let maxHeight: CGFloat
  let minHeight: CGFloat
  let cornerRadius: CGFloat

  private var barHeight: CGFloat {
    let height = CGFloat(level) * maxHeight * 0.85
    return min(maxHeight, max(minHeight, height))
  }

  private var barColor: Color {
    Self.barColor(index: index, totalBars: totalBars)
  }

  static func barColor(index: Int, totalBars: Int) -> Color {
    let position = Float(index) / Float(totalBars)
    if position < 0.33 {
      let t = position / 0.33
      return Color(red: Double(t), green: 1.0, blue: 0.0)
    } else if position < 0.66 {
      let t = (position - 0.33) / 0.33
      return Color(red: 1.0, green: Double(1.0 - t * 0.5), blue: 0.0)
    } else {
      let t = (position - 0.66) / 0.34
      return Color(red: 1.0, green: Double(0.5 - t * 0.5), blue: 0.0)
    }
  }

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(barColor)
      .frame(height: barHeight)
      .animation(.interpolatingSpring(duration: 0.15, bounce: 0), value: barHeight)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
