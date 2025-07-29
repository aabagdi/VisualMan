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
  
  @State private var localRealProgress: T = 0
  @State private var localTempProgress: T = 0
  @GestureState private var isActive: Bool = false
  
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
    if isActive {
      return max(min(localRealProgress + localTempProgress, 1), 0)
    } else {
      return getPrgPercentage(value)
    }
  }
  
  private var displayTime: T {
    if isActive {
      return currentProgress * inRange.upperBound
    }
    return value
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
              .fill(isActive ? activeFillColor : fillColor)
              .frame(width: max(bounds.size.width * CGFloat(currentProgress), 0), height: height)
          }
          .frame(height: height)
          
          HStack {
            Text(displayTime.asTimeString(style: .positional))
              .font(.caption)
              .monospacedDigit()
              .foregroundColor(isActive ? fillColor : emptyColor)
            
            Spacer(minLength: 0)
            
            Text("-" + remainingTime.asTimeString(style: .positional))
              .font(.caption)
              .monospacedDigit()
              .foregroundColor(isActive ? fillColor : emptyColor)
          }
        }
        .frame(width: isActive ? bounds.size.width * 1.04 : bounds.size.width)
        .scaleEffect(isActive ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isActive ? 0.2 : 0), radius: isActive ? 10 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
      }
      .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .updating($isActive) { _, state, _ in
            state = true
          }
          .onChanged { gesture in
            let dragProgress = T(gesture.location.x / bounds.size.width)
            let clampedProgress = max(min(dragProgress, 1), 0)
            
            if !isActive {
              localRealProgress = getPrgPercentage(value)
            }
            
            localTempProgress = clampedProgress - localRealProgress
            
            let newValue = clampedProgress * (inRange.upperBound - inRange.lowerBound) + inRange.lowerBound
            value = max(min(newValue, inRange.upperBound), inRange.lowerBound)
          }
          .onEnded { _ in
            localRealProgress = max(min(localRealProgress + localTempProgress, 1), 0)
            localTempProgress = 0
          }
      )
      .onChange(of: isActive) { _, newValue in
        onEditingChanged(newValue)
      }
      .onChange(of: value) { _, _ in
        if !isActive {
          localRealProgress = getPrgPercentage(value)
        }
      }
      .onAppear {
        localRealProgress = getPrgPercentage(value)
      }
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
