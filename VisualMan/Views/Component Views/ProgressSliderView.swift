//
//  ProgressSliderView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

import SwiftUI

struct ProgressSliderView<T: BinaryFloatingPoint>: View {
  @Binding var value: T
  let inRange: ClosedRange<T>
  let activeFillColor: Color
  let fillColor: Color
  let emptyColor: Color
  let height: CGFloat
  let onEditingChanged: (Bool) -> Void
  
  @State private var isDragging: Bool = false
  @State private var tempValue: T = 0
  
  init(
    value: Binding<T>,
    inRange: ClosedRange<T>,
    activeFillColor: Color,
    fillColor: Color,
    emptyColor: Color,
    height: CGFloat,
    onEditingChanged: @escaping (Bool) -> Void
  ) {
    self._value = value
    self.inRange = inRange
    self.activeFillColor = activeFillColor
    self.fillColor = fillColor
    self.emptyColor = emptyColor
    self.height = height
    self.onEditingChanged = onEditingChanged
  }
  
  private var currentProgress: T {
    if isDragging {
      return getPrgPercentage(tempValue)
    } else {
      return getPrgPercentage(value)
    }
  }
  
  private var displayTime: T {
    return currentProgress * (inRange.upperBound - inRange.lowerBound) + inRange.lowerBound
  }
  
  private var remainingTime: T {
    return inRange.upperBound - displayTime
  }
  
  var body: some View {
    GeometryReader { bounds in
      ZStack {
        VStack(spacing: 4) {
          ZStack(alignment: .leading) {
            Capsule()
              .fill(emptyColor)
              .frame(height: height)
            
            Capsule()
              .fill(isDragging ? activeFillColor : fillColor)
              .frame(width: max(bounds.size.width * CGFloat(currentProgress), 0), height: height)
          }
          .frame(height: height)
          
          HStack {
            Text(displayTime.asTimeString(style: .positional))
              .font(.caption)
              .monospacedDigit()
              .foregroundColor(isDragging ? fillColor : emptyColor)
            
            Spacer(minLength: 0)
            
            Text("-" + remainingTime.asTimeString(style: .positional))
              .font(.caption)
              .monospacedDigit()
              .foregroundColor(isDragging ? fillColor : emptyColor)
          }
        }
        .frame(width: isDragging ? bounds.size.width * 1.04 : bounds.size.width)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: isDragging ? 10 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
      }
      .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { gesture in
            if !isDragging {
              isDragging = true
              onEditingChanged(true)
            }
            
            let progress = T(gesture.location.x / bounds.size.width)
            let clampedProgress = max(min(progress, 1), 0)
            
            tempValue = clampedProgress * (inRange.upperBound - inRange.lowerBound) + inRange.lowerBound
          }
          .onEnded { _ in
            value = tempValue
            isDragging = false
            onEditingChanged(false)
          }
      )
    }
    .frame(height: 30)
  }
  
  private func getPrgPercentage(_ value: T) -> T {
    let range = inRange.upperBound - inRange.lowerBound
    if range == 0 { return 0 }
    let correctedStartValue = value - inRange.lowerBound
    let percentage = correctedStartValue / range
    return max(min(percentage, 1), 0)
  }
}
