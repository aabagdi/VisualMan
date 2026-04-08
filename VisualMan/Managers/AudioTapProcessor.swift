//
//  AudioTapProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Synchronization

final class AudioTapProcessor: Sendable {
  private let dspProcessor = DSPProcessor()
  private let isProcessingBuffer = Atomic<Bool>(false)
  private typealias ForwardingState = (
    continuation: AsyncStream<DSPProcessor.DSPResult>.Continuation?,
    task: Task<Void, Never>?
  )
  private let forwardingState = Mutex<ForwardingState>((nil, nil))
  private let latestSamples = Mutex<([Float], Float)?>(nil)
  
  nonisolated func processSamples(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) {
    let copied = Array(samples)
    latestSamples.withLock { $0 = (copied, sampleRate) }
    
    guard isProcessingBuffer.compareExchange(expected: false,
                                             desired: true,
                                             ordering: .acquiringAndReleasing).exchanged else { return }
    let dsp = dspProcessor
    
    Task {
      defer { isProcessingBuffer.store(false, ordering: .releasing) }
      
      guard let (samples, rate) = latestSamples.withLock({
        let v = $0
        $0 = nil
        return v
      }) else { return }
      
      let result = await dsp.processSamples(samples, sampleRate: rate)
      forwardingState.withLock { _ = $0.continuation?.yield(result) }
    }
  }
  
  @MainActor
  func startForwarding(handler: @escaping @MainActor (DSPProcessor.DSPResult) -> Void) {
    stopForwarding()
    let (stream, continuation) = AsyncStream<DSPProcessor.DSPResult>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let task = Task { @MainActor in
      for await result in stream {
        guard !Task.isCancelled else { break }
        handler(result)
      }
    }
    forwardingState.withLock {
      $0.continuation = continuation
      $0.task = task
    }
  }
  
  func stopForwarding() {
    forwardingState.withLock {
      $0.continuation?.finish()
      $0.continuation = nil
      $0.task?.cancel()
      $0.task = nil
    }
  }
  
  func reset() async {
    await dspProcessor.reset()
  }
}
