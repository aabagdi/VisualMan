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
  
  private var progress: T {
    let range = inRange.upperBound - inRange.lowerBound
    guard range > 0 else { return 0 }
    let correctedValue = value - inRange.lowerBound
    return max(0, min(1, correctedValue / range))
  }
  
  private var displayProgress: T {
    return max(0, min(1, progress + localTempProgress))
  }
  
  private var currentPosition: T {
    return inRange.lowerBound + (displayProgress * (inRange.upperBound - inRange.lowerBound))
  }
  
  var body: some View {
    GeometryReader { bounds in
      ZStack {
        VStack {
          ZStack(alignment: .center) {
            Capsule()
              .fill(emptyColor)
            Capsule()
              .fill(isActive ? activeFillColor : fillColor)
              .mask({
                HStack {
                  Rectangle()
                    .frame(width: max(bounds.size.width * CGFloat(displayProgress), 0), alignment: .leading)
                  Spacer(minLength: 0)
                }
              })
          }
          .frame(height: height)  // Explicit height
          
          HStack {
            Text(currentPosition.asTimeString(style: .positional))
            Spacer(minLength: 0)
            Text("-" + (inRange.upperBound - currentPosition).asTimeString(style: .positional))
          }
          .font(.system(.headline, design: .rounded))
          .monospacedDigit()
          .foregroundColor(isActive ? fillColor : emptyColor)
        }
        .frame(width: isActive ? bounds.size.width * 1.04 : bounds.size.width, alignment: .center)
        .animation(animation, value: isActive)
      }
      .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
      .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .updating($isActive) { value, state, transaction in
          state = true
        }
        .onChanged { gesture in
          localTempProgress = T(gesture.translation.width / bounds.size.width)
          // Update the binding with the new position
          let newPosition = inRange.lowerBound + (displayProgress * (inRange.upperBound - inRange.lowerBound))
          value = max(inRange.lowerBound, min(inRange.upperBound, newPosition))
        }
        .onEnded { _ in
          // Commit the drag by updating the actual value
          let newPosition = inRange.lowerBound + (displayProgress * (inRange.upperBound - inRange.lowerBound))
          value = max(inRange.lowerBound, min(inRange.upperBound, newPosition))
          localTempProgress = 0
        })
      .onChange(of: isActive) { _, newValue in
        onEditingChanged(newValue)
      }
    }
    .frame(height: isActive ? height * 1.25 : height, alignment: .center)
  }
  
  private var animation: Animation {
    if isActive {
      return .spring()
    } else {
      return .spring(response: 0.5, dampingFraction: 0.5, blendDuration: 0.6)
    }
  }
}
