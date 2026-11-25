//
//  DetentSlider.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import SwiftUI
import UIKit

struct DetentSlider: UIViewRepresentable {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let detent: Double
  let snapDistance: Double
  let accessibilityLabel: LocalizedStringResource

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> UISlider {
    let slider = UISlider()
    slider.minimumValue = 0
    slider.maximumValue = 1
    slider.trackConfiguration = UISlider.TrackConfiguration(
      allowsTickValuesOnly: false,
      ticks: [UISlider.TrackConfiguration.Tick(position: Float(fraction(of: detent)))]
    )
    slider.accessibilityLabel = String(localized: accessibilityLabel)
    slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
    return slider
  }

  func updateUIView(_ slider: UISlider, context: Context) {
    context.coordinator.parent = self
    let position = Float(fraction(of: value))
    if !slider.isTracking, slider.value != position {
      slider.value = position
    }
    slider.accessibilityValue = value.formatted(.percent.precision(.fractionLength(0)))
  }

  func fraction(of value: Double) -> Double {
    (value - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  func value(atFraction fraction: Double) -> Double {
    range.lowerBound + fraction * (range.upperBound - range.lowerBound)
  }

  final class Coordinator: NSObject {
    var parent: DetentSlider
    private let feedback = UISelectionFeedbackGenerator()
    private var isSnapped = false

    init(_ parent: DetentSlider) {
      self.parent = parent
    }

    @objc func valueChanged(_ slider: UISlider) {
      var newValue = parent.value(atFraction: Double(slider.value))
      let snaps = abs(newValue - parent.detent) <= parent.snapDistance
      if snaps {
        newValue = parent.detent
        slider.value = Float(parent.fraction(of: parent.detent))
        if !isSnapped {
          feedback.selectionChanged()
        }
      }
      isSnapped = snaps
      parent.value = newValue
    }
  }
}

#Preview {
  @Previewable @State var value = 1.4

  DetentSlider(
    value: $value,
    range: 0.2...1.8,
    detent: 1,
    snapDistance: 0.05,
    accessibilityLabel: "Haptic Strength"
  )
  .padding()
}
