//
//  ProgressSliderView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

import SwiftUI

struct ProgressSliderView<T: BinaryFloatingPoint>: View {
  let value: () -> T
  let setValue: (T) -> Void
  let inRange: ClosedRange<T>
  let activeFillColor: Color
  let fillColor: Color
  let emptyColor: Color
  let height: CGFloat
  let onEditingChanged: (Bool) -> Void

  @State private var isDragging: Bool = false
  @State private var tempValue: T = 0
  @State private var playedSeconds: T = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .caption) private var sliderHeight: CGFloat = 30

  init(
    value: @escaping () -> T,
    setValue: @escaping (T) -> Void,
    inRange: ClosedRange<T>,
    activeFillColor: Color,
    fillColor: Color,
    emptyColor: Color,
    height: CGFloat,
    onEditingChanged: @escaping (Bool) -> Void
  ) {
    self.value = value
    self.setValue = setValue
    self.inRange = inRange
    self.activeFillColor = activeFillColor
    self.fillColor = fillColor
    self.emptyColor = emptyColor
    self.height = height
    self.onEditingChanged = onEditingChanged
  }

  private var elapsedSeconds: T {
    isDragging ? tempValue.rounded(.down) : playedSeconds
  }

  private var remainingTime: T {
    max(inRange.upperBound.rounded() - elapsedSeconds, 0)
  }
  
  var body: some View {
    GeometryReader { bounds in
      ZStack {
        VStack(spacing: 4) {
          ZStack(alignment: .leading) {
            Capsule()
              .fill(emptyColor)
              .frame(height: height)
            
            ProgressFillView(
              value: value,
              draggedValue: isDragging ? tempValue : nil,
              inRange: inRange,
              color: isDragging ? activeFillColor : fillColor,
              width: bounds.size.width,
              height: height,
              playedSeconds: $playedSeconds
            )
          }
          .frame(height: height)
          
          HStack {
            Text(elapsedSeconds.asTimeString())
              .font(.caption)
              .monospacedDigit()
              .foregroundStyle(isDragging ? activeFillColor : fillColor)
            
            Spacer(minLength: 0)
            
            Text("-" + remainingTime.asTimeString())
              .font(.caption)
              .monospacedDigit()
              .foregroundStyle(isDragging ? activeFillColor : fillColor)
          }
        }
        .frame(width: isDragging && !reduceMotion ? bounds.size.width * 1.04 : bounds.size.width)
        .scaleEffect(isDragging && !reduceMotion ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: isDragging ? 10 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
      }
      .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { dragChanged($0, width: bounds.size.width) }
          .onEnded { _ in dragEnded() }
      )
    }
    .frame(height: sliderHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Playback position")
    .accessibilityValue(
      "\(elapsedSeconds.asTimeString()) of \((inRange.upperBound).asTimeString())"
    )
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilityShowsLargeContentViewer {
      Text("\(elapsedSeconds.asTimeString()) of \((inRange.upperBound).asTimeString())")
    }
    .accessibilityAdjustableAction { adjustableActionPerformed($0) }
  }

  private func dragChanged(_ gesture: DragGesture.Value, width: CGFloat) {
    if !isDragging {
      isDragging = true
      onEditingChanged(true)
    }

    let progress = T(gesture.location.x / width)
    let clampedProgress = max(min(progress, 1), 0)

    tempValue = clampedProgress * (inRange.upperBound - inRange.lowerBound) + inRange.lowerBound
  }

  private func dragEnded() {
    setValue(tempValue)
    playedSeconds = tempValue.rounded(.down)
    isDragging = false
    onEditingChanged(false)
  }

  private func adjustableActionPerformed(_ direction: AccessibilityAdjustmentDirection) {
    let range = inRange.upperBound - inRange.lowerBound
    let step = range * 0.05
    let current = value()
    switch direction {
    case .increment:
      setValue(min(current + step, inRange.upperBound))
    case .decrement:
      setValue(max(current - step, inRange.lowerBound))
    @unknown default:
      break
    }
    onEditingChanged(false)
  }
}

private struct ProgressFillView<T: BinaryFloatingPoint>: View {
  let value: () -> T
  let draggedValue: T?
  let inRange: ClosedRange<T>
  let color: Color
  let width: CGFloat
  let height: CGFloat
  @Binding var playedSeconds: T

  var body: some View {
    let current = max(min(value(), inRange.upperBound), inRange.lowerBound)
    let range = inRange.upperBound - inRange.lowerBound
    let progress = range == 0 ? 0 : ((draggedValue ?? current) - inRange.lowerBound) / range

    Capsule()
      .fill(color)
      .frame(width: max(width * CGFloat(progress), 0), height: height)
      .onChange(of: current.rounded(.down), initial: true) { _, seconds in
        playedSeconds = seconds
      }
  }
}
