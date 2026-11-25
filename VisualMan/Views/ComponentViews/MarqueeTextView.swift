//
//  MarqueeTextView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import SwiftUI
import Dependencies

struct MarqueeTextView<ResetID: Equatable>: View {
  let text: String
  let resetID: ResetID
  let spacing: CGFloat
  let initialDelay: Duration
  let speed: Double
  
  @State private var scrollToEnd = false
  @State private var textSize: CGSize = .zero
  @State private var containerSize: CGSize = .zero
  @State private var scrollGeneration = 0
  @State private var resetCount = 0

  @Dependency(\.continuousClock) private var clock

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    _ text: String,
    resetID: ResetID,
    spacing: CGFloat = 100,
    initialDelay: Duration = .seconds(2),
    speed: Double = 20.0
  ) {
    self.text = text
    self.resetID = resetID
    self.spacing = spacing
    self.initialDelay = initialDelay
    self.speed = speed
  }
  
  private var shouldScroll: Bool {
    textSize.width > containerSize.width
  }
  
  private var scrollDuration: Double {
    Double(textSize.width) / speed
  }
  
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: shouldScroll ? spacing : 0) {
        ForEach(0..<(shouldScroll && !reduceMotion ? 3 : 1), id: \.self) { _ in
          Text(text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
              proxy.size
            } action: { newSize in
              if newSize != textSize {
                textSize = newSize
              }
            }
        }
      }
      .id("\(String(describing: resetID))-\(scrollGeneration)")
      .padding(.horizontal)
      .offset(x: shouldScroll ? (scrollToEnd ? -textSize.width - spacing : 0) : 0)
      .animation(
        scrollToEnd
          ? .linear(duration: scrollDuration).repeatForever(autoreverses: false)
          : .none,
        value: scrollToEnd
      )
    }
    .scrollIndicators(.hidden)
    .disabled(true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      containerSize = newSize
    }
    .onChange(of: resetID) { _, _ in
      resetIDChanged()
    }
    .task(id: resetCount) {
      await resetCountChanged()
    }
    .task(id: ScrollTrigger(generation: scrollGeneration,
                             textWidth: textSize.width,
                             canScroll: shouldScroll && !reduceMotion)) {
      await scrollTriggerChanged()
    }
  }

  private func resetIDChanged() {
    scrollToEnd = false
    textSize = .zero
    scrollGeneration += 1
    resetCount += 1
  }

  private func resetCountChanged() async {
    guard resetCount > 0 else { return }
    do {
      try await clock.sleep(for: .milliseconds(100))
    } catch {
      return
    }
    scrollGeneration += 1
  }

  private func scrollTriggerChanged() async {
    scrollToEnd = false
    guard shouldScroll, !reduceMotion else { return }
    do {
      try await clock.sleep(for: initialDelay)
    } catch {
      return
    }
    scrollToEnd = true
  }
}

private struct ScrollTrigger: Equatable {
  let generation: Int
  let textWidth: CGFloat
  let canScroll: Bool
}
