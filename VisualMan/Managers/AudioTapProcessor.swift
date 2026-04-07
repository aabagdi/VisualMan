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
  private let resultContinuation = Mutex<AsyncStream<DSPProcessor.DSPResult>.Continuation?>(nil)
  private let forwardingTask = Mutex<Task<Void, Never>?>(nil)
  
  nonisolated func processSamples(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) {
    guard isProcessingBuffer.compareExchange(expected: false,
                                             desired: true,
                                             ordering: .acquiringAndReleasing).exchanged else { return }
    let dsp = dspProcessor
    let copied = Array(samples)
    
    Task {
      let result = await dsp.processSamples(copied, sampleRate: sampleRate)
      resultContinuation.withLock { _ = $0?.yield(result) }
      isProcessingBuffer.store(false, ordering: .releasing)
    }
  }
  
  @MainActor
  func startForwarding(handler: @escaping @MainActor (DSPProcessor.DSPResult) -> Void) {
    stopForwarding()
    let (stream, continuation) = AsyncStream<DSPProcessor.DSPResult>.makeStream(bufferingPolicy: .bufferingNewest(1))
    resultContinuation.withLock { $0 = continuation }
    let task = Task { @MainActor in
      for await result in stream {
        guard !Task.isCancelled else { break }
        handler(result)
      }
    }
    forwardingTask.withLock { $0 = task }
  }
  
  func stopForwarding() {
    resultContinuation.withLock {
      $0?.finish()
      $0 = nil
    }
    forwardingTask.withLock {
      $0?.cancel()
      $0 = nil
    }
  }
  
  func reset() async {
    await dspProcessor.reset()
  }
}
