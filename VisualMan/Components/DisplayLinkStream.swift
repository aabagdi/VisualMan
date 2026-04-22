//
//  DisplayLinkStream.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import QuartzCore

@MainActor
final class DisplayLinkStream: NSObject {
  private var displayLink: CADisplayLink?
  private var continuation: AsyncStream<Void>.Continuation?

  func makeFrameStream() -> AsyncStream<Void> {
    stop()
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.continuation = continuation
    let link = CADisplayLink(target: self, selector: #selector(onFrame))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .current, forMode: .common)
    self.displayLink = link
    return stream
  }

  var frames: AsyncStream<Void> { makeFrameStream() }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    continuation?.finish()
    continuation = nil
  }

  @objc private func onFrame() {
    continuation?.yield()
  }
}
