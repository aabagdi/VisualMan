//
//  AudioTapProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Accelerate
import Synchronization
import os

final class AudioTapProcessor: Sendable {
  nonisolated private static let ringCapacity = 8192
  nonisolated private static let ringMask = ringCapacity - 1

  private let dspProcessor = DSPProcessor()

  private let ringLock = OSAllocatedUnfairLock()
  nonisolated(unsafe) private var ringBuffer: [8192 of Float] = .init(repeating: 0.0)
  nonisolated(unsafe) private var monoScratch: [8192 of Float] = .init(repeating: 0.0)
  nonisolated(unsafe) private var drainScratch: [Float] = Array(repeating: 0, count: ringCapacity)

  private let writeIndex = Atomic<Int>(0)
  private let readIndex = Atomic<Int>(0)
  private let sampleRateBits = Atomic<UInt32>(0)

  nonisolated func processSamples(
    channels: UnsafePointer<UnsafeMutablePointer<Float>>,
    channelCount: Int,
    frameCount: Int,
    sampleRate: Float
  ) {
    guard frameCount > 0, channelCount > 0 else { return }

    if channelCount == 1 {
      let buf = UnsafeBufferPointer(start: channels[0], count: frameCount)
      ringLock.withLockUnchecked {
        writeToRing(buf, sampleRate: sampleRate)
      }
      return
    }

    let n = min(frameCount, Self.ringCapacity)
    let skip = frameCount - n

    ringLock.withLockUnchecked {
      monoScratch.withUnsafeElementPointer { dst in
        var scale: Float = 1.0 / Float(channelCount)
        vDSP_vsmul(channels[0] + skip, 1, &scale, dst, 1, vDSP_Length(n))
        for c in 1..<channelCount {
          vDSP_vsma(channels[c] + skip, 1, &scale, dst, 1, dst, 1, vDSP_Length(n))
        }
        let buf = UnsafeBufferPointer(start: dst, count: n)
        writeToRing(buf, sampleRate: sampleRate)
      }
    }
  }
  
  nonisolated private func writeToRing(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) {
    let n = samples.count
    guard n > 0, let src = samples.baseAddress else { return }

    sampleRateBits.store(sampleRate.bitPattern, ordering: .relaxed)

    let effective = min(n, Self.ringCapacity)
    let srcStart = src + (n - effective)

    let write = writeIndex.load(ordering: .relaxed)
    let writePos = write & Self.ringMask
    let firstChunk = min(effective, Self.ringCapacity - writePos)

    ringBuffer.withUnsafeElementPointer { ring in
      (ring + writePos).update(from: srcStart, count: firstChunk)
      let remaining = effective - firstChunk
      if remaining > 0 {
        ring.update(from: srcStart + firstChunk, count: remaining)
      }
    }

    writeIndex.store(write &+ effective, ordering: .releasing)
  }

  private func drainAndProcess(dsp: DSPProcessor) async -> DSPProcessor.DSPResult? {
    let w = writeIndex.load(ordering: .acquiring)
    var r = readIndex.load(ordering: .relaxed)
    var count = w &- r
    guard count > 0 else { return nil }

    if count > Self.ringCapacity {
      r = w &- Self.ringCapacity
      count = Self.ringCapacity
    }

    let rate = Float(bitPattern: sampleRateBits.load(ordering: .relaxed))
    guard rate > 0 else {
      readIndex.store(w, ordering: .releasing)
      return nil
    }

    let capturedR = r
    let capturedCount = count
    ringLock.withLock {
      drainScratch.withUnsafeMutableBufferPointer { dst in
        guard let dstBase = dst.baseAddress else { return }
        let readPos = capturedR & Self.ringMask
        let firstChunk = min(capturedCount, Self.ringCapacity - readPos)
        ringBuffer.withUnsafeElementPointer { ring in
          dstBase.update(from: ring + readPos, count: firstChunk)
          let rem = capturedCount - firstChunk
          if rem > 0 {
            (dstBase + firstChunk).update(from: ring, count: rem)
          }
        }
      }
    }

    readIndex.store(w, ordering: .releasing)
    return await dsp.processSamples(drainScratch[0..<count], sampleRate: rate)
  }

  @MainActor
  func tick(handler: (DSPProcessor.DSPResult) -> Void) async {
    guard let result = await drainAndProcess(dsp: dspProcessor) else { return }
    guard !Task.isCancelled else { return }
    handler(result)
  }

  func reset() async {
    ringLock.withLock {
      readIndex.store(writeIndex.load(ordering: .acquiring), ordering: .releasing)
      sampleRateBits.store(0, ordering: .relaxed)
    }
    await dspProcessor.reset()
  }
}
