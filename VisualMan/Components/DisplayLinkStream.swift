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
  private var _frames: AsyncStream<Void>?

  private func makeFrameStream() -> AsyncStream<Void> {
    stop()
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.continuation = continuation
    let link = CADisplayLink(target: self, selector: #selector(onFrame))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .current, forMode: .common)
    self.displayLink = link
    return stream
  }

  var frames: AsyncStream<Void> {
    if let existing = _frames { return existing }
    let stream = makeFrameStream()
    _frames = stream
    return stream
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    continuation?.finish()
    continuation = nil
    _frames = nil
  }

  @objc private func onFrame() {
    continuation?.yield()
  }
}
