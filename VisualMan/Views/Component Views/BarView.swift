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
  
  private var barHeight: CGFloat {
    let height = CGFloat(level) * maxHeight
    return max(minHeight, height)
  }
  
  private var barColor: Color {
    let position = Float(index) / Float(totalBars)
    
    if position < 0.33 {
      let t = position / 0.33
      return Color(
        red: Double(t),
        green: 1.0,
        blue: 0.0
      )
    } else if position < 0.66 {
      let t = (position - 0.33) / 0.33
      return Color(
        red: 1.0,
        green: Double(1.0 - t * 0.5),
        blue: 0.0
      )
    } else {
      let t = (position - 0.66) / 0.34
      return Color(
        red: 1.0,
        green: Double(0.5 - t * 0.5),
        blue: 0.0
      )
    }
  }
  
  var body: some View {
    GeometryReader { g in
      VStack {
        Spacer(minLength: 0)
        RoundedRectangle(cornerRadius: g.size.width * 0.2077922078)
          .fill(barColor)
          .frame(height: barHeight)
          .animation(.easeOut(duration: 0.1), value: barHeight)
        Spacer()
      }
    }
  }
}
