//
//  AbstractExpressionismRenderer+GPUTiming.swift
//  VisualMan
//
//  Created on 11/3/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension AbstractExpressionismRenderer {
  enum GPUMark: Int, CaseIterable {
    case frameStart, afterPaint, afterVelocity, afterSmear, afterPigment, afterCompose
  }

  func gpuMark(_ encoder: any MTL4ComputeCommandEncoder, _ mark: GPUMark) {
    gpuTiming?.write(mark, encoder: encoder)
  }

  final class GPUTiming {
    private static let slots = Int(AbstractExpressionismRenderer.maxFramesInFlight)
    private static let marksPerSlot = GPUMark.allCases.count
    private static let reportEvery = 120
    private static let machNsPerTick: Double = {
      var info = mach_timebase_info()
      mach_timebase_info(&info)
      return Double(info.numer) / Double(info.denom)
    }()

    private let device: MTLDevice
    private let heap: any MTL4CounterHeap
    private var slot = 0
    private var written: [[Bool]]
    private var slotSkipped: [Bool]
    private var pendingSkipped = false

    private var passTotals = [Double](repeating: 0, count: GPUMark.allCases.count)
    private var frameTotal: Double = 0
    private var frameMax: Double = 0
    private var frames = 0
    private var skippedFrames = 0
    private var reference: (cpu: MTLTimestamp, gpu: MTLTimestamp)

    static func makeIfRequested(device: MTLDevice) -> GPUTiming? {
      guard UserDefaults.standard.bool(forKey: "AbExGPUTiming") else { return nil }
      let desc = MTL4CounterHeapDescriptor()
      desc.type = .timestamp
      desc.count = slots * marksPerSlot
      guard let heap = try? device.makeCounterHeap(descriptor: desc) else {
        AbstractExpressionismRenderer.logger.error("GPU timing: could not create a counter heap")
        return nil
      }
      AbstractExpressionismRenderer.logger.notice("GPU timing enabled")
      return GPUTiming(device: device, heap: heap)
    }

    private init(device: MTLDevice, heap: any MTL4CounterHeap) {
      self.device = device
      self.heap = heap
      self.written = Array(repeating: Array(repeating: false, count: Self.marksPerSlot),
                           count: Self.slots)
      self.slotSkipped = Array(repeating: false, count: Self.slots)
      self.reference = device.sampleTimestamps()
    }

    func beginFrame(frameNumber: UInt64, skippedPaint: Bool) {
      slot = Int(frameNumber % UInt64(Self.slots))
      resolve(slot: slot)
      written[slot] = Array(repeating: false, count: Self.marksPerSlot)
      slotSkipped[slot] = false
    }

    func markSkippedPaint() { slotSkipped[slot] = true }

    func write(_ mark: GPUMark, encoder: any MTL4ComputeCommandEncoder) {
      encoder.writeTimestamp(granularity: .precise, counterHeap: heap,
                             index: slot * Self.marksPerSlot + mark.rawValue)
      written[slot][mark.rawValue] = true
    }

    private func resolve(slot: Int) {
      let flags = written[slot]
      guard flags[GPUMark.frameStart.rawValue], flags[GPUMark.afterCompose.rawValue] else { return }
      let range = (slot * Self.marksPerSlot)..<((slot + 1) * Self.marksPerSlot)
      guard let data = try? heap.resolveCounterRange(range),
            data.count >= Self.marksPerSlot * MemoryLayout<UInt64>.size else { return }
      let ticks: [UInt64] = data.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: UInt64.self).prefix(Self.marksPerSlot))
      }
      if ticks.contains(MTLCounterErrorValue) { return }

      let now = device.sampleTimestamps()
      let gpuSpan = Double(now.gpu &- reference.gpu)
      guard gpuSpan > 0 else { return }
      let cpuNs = Double(now.cpu &- reference.cpu) * Self.machNsPerTick
      let nsPerTick = cpuNs / gpuSpan

      var previous = ticks[GPUMark.frameStart.rawValue]
      var total: Double = 0
      for mark in GPUMark.allCases where mark != .frameStart && flags[mark.rawValue] {
        let t = ticks[mark.rawValue]
        let ms = Double(t &- previous) * nsPerTick / 1e6
        passTotals[mark.rawValue] += ms
        total += ms
        previous = t
      }
      frameTotal += total
      frameMax = max(frameMax, total)
      frames += 1
      if slotSkipped[slot] { skippedFrames += 1 }
      if frames >= Self.reportEvery { report() }
    }

    private func report() {
      let n = Double(frames)
      func f(_ v: Double) -> String { String(format: "%.2f", v) }
      let labels: [(GPUMark, String)] = [(.afterPaint, "paint"), (.afterVelocity, "velocity"),
                                         (.afterSmear, "smear"), (.afterPigment, "pigment"),
                                         (.afterCompose, "compose")]
      let parts = labels.map { "\($0.1) \(f(passTotals[$0.0.rawValue] / n))" }.joined(separator: "  ")
      let line = "AbEx GPU ms/frame over \(frames) frames (\(skippedFrames) paint-skipped): "
        + "\(parts)  | total \(f(frameTotal / n))  max \(f(frameMax))"
      AbstractExpressionismRenderer.logger.notice("\(line, privacy: .public)")
      passTotals = Array(repeating: 0, count: GPUMark.allCases.count)
      frameTotal = 0; frameMax = 0; frames = 0; skippedFrames = 0
    }
  }
}

#endif
