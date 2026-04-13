//
//  AudioTapProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Synchronization

final class AudioTapProcessor: Sendable {
  nonisolated private static let pendingSampleCap = 8192
  
  private let dspProcessor = DSPProcessor()
  private let isProcessingBuffer = Atomic<Bool>(false)
  private typealias ForwardingState = (
    continuation: AsyncStream<DSPProcessor.DSPResult>.Continuation?,
    task: Task<Void, Never>?
  )
  private let forwardingState = Mutex<ForwardingState>((nil, nil))
  private let pendingSamples = Mutex<(samples: [Float], sampleRate: Float)>(([], 0))
  
  nonisolated func processSamples(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) {
    pendingSamples.withLock { pending in
      pending.samples.append(contentsOf: samples)
      pending.sampleRate = sampleRate
      let overflow = pending.samples.count - Self.pendingSampleCap
      if overflow > 0 {
        pending.samples.removeFirst(overflow)
      }
    }
    
    guard isProcessingBuffer.compareExchange(expected: false,
                                             desired: true,
                                             ordering: .acquiringAndReleasing).exchanged else { return }
    let dsp = dspProcessor
    
    Task {
      defer { isProcessingBuffer.store(false, ordering: .releasing) }
      
      let drained: ([Float], Float) = pendingSamples.withLock { pending in
        let s = pending.samples
        let r = pending.sampleRate
        pending.samples.removeAll(keepingCapacity: true)
        return (s, r)
      }
      let (batch, rate) = drained
      guard !batch.isEmpty, rate > 0 else { return }
      
      let result = await dsp.processSamples(batch, sampleRate: rate)
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
    pendingSamples.withLock {
      $0.samples.removeAll(keepingCapacity: true)
      $0.sampleRate = 0
    }
    await dspProcessor.reset()
  }
}
