//
//  AudioTapProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Foundation
import Synchronization

final class AudioTapProcessor: Sendable {
  private let dspProcessor = DSPProcessor()
  private let isProcessingBuffer = Atomic<Bool>(false)
  private let forwardingTask = Mutex<Task<Void, Never>?>(nil)
  
  nonisolated func processSamples(_ samples: [Float], sampleRate: Float) {
    guard isProcessingBuffer.compareExchange(expected: false,
                                              desired: true,
                                              ordering: .acquiringAndReleasing).exchanged else { return }
    let dsp = dspProcessor
    
    Task { [self] in
      let result = await dsp.processSamples(samples, sampleRate: sampleRate)
      await MainActor.run {
        NotificationCenter.default.post(name: .dspResultReady, object: result)
        self.isProcessingBuffer.store(false, ordering: .releasing)
      }
    }
  }
  
  @MainActor
  func startForwarding(handler: @escaping @MainActor (DSPProcessor.DSPResult) -> Void) {
    stopForwarding()
    let task = Task { @MainActor in
      let notifications = NotificationCenter.default.notifications(named: .dspResultReady)
      for await notification in notifications {
        guard !Task.isCancelled else { break }
        if let result = notification.object as? DSPProcessor.DSPResult {
          handler(result)
        }
      }
    }
    forwardingTask.withLock { $0 = task }
  }
  
  func stopForwarding() {
    forwardingTask.withLock {
      $0?.cancel()
      $0 = nil
    }
  }
  
  func reset() async {
    await dspProcessor.reset()
  }
}

extension Notification.Name {
  fileprivate static let dspResultReady = Notification.Name("AudioTapProcessor.dspResultReady")
}
