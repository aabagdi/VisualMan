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
  @State private var scrollAnimationKey: UUID
  
  @Dependency(\.uuid) var uuid
  @Dependency(\.continuousClock) var clock
  
  init(
    _ text: String,
    resetID: ResetID,
    spacing: CGFloat = 100,
    initialDelay: Duration = .seconds(2),
    speed: Double = 20.0
  ) {
    @Dependency(\.uuid) var uuid
    
    self.text = text
    self.resetID = resetID
    self.spacing = spacing
    self.initialDelay = initialDelay
    self.speed = speed
    self.scrollAnimationKey = uuid()
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
        ForEach(0..<(shouldScroll ? 3 : 1), id: \.self) { _ in
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
      .id("\(String(describing: resetID))-\(scrollAnimationKey)")
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
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      containerSize = newSize
    }
    .onChange(of: textSize) { oldSize, newSize in
      if oldSize == .zero && newSize.width > containerSize.width && !scrollToEnd {
        startScrollAfterDelay()
      }
    }
    .onChange(of: resetID) { _, _ in
      resetMarquee()
    }
    .onChange(of: scrollAnimationKey) { _, _ in
      if textSize.width > containerSize.width {
        startScrollAfterDelay()
      }
    }
  }
  
  private func resetMarquee() {
    scrollToEnd = false
    textSize = .zero
    scrollAnimationKey = uuid()
    
    Task {
      try? await clock.sleep(for: .milliseconds(100))
      scrollAnimationKey = uuid()
    }
  }
  
  private func startScrollAfterDelay() {
    Task {
      try? await clock.sleep(for: initialDelay)
      scrollToEnd = true
    }
  }
}
