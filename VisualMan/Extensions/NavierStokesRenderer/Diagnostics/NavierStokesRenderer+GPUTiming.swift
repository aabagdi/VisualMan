//
//  NavierStokesRenderer+GPUTiming.swift
//  VisualMan
//
//  Created on 11/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension NavierStokesRenderer {
  enum GPUMark: Int, CaseIterable {
    case frameStart, afterPredictorTrace, afterPredictorProjection, afterFlowStep, afterProjection,
         afterVortices, afterDyeMap, afterDyeDiffuse, afterBloom, afterHalation, afterCloud, afterRender
  }

  func gpuMark(_ encoder: any MTL4ComputeCommandEncoder, _ mark: GPUMark) {
    gpuTiming?.write(mark, encoder: encoder)
  }

  final class GPUTiming {
    private static let slots = Int(NavierStokesRenderer.maxFramesInFlight)
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

    private var passSamples = [[Double]](repeating: [], count: GPUMark.allCases.count)
    private var frameSamples: [Double] = []
    private var framesBegun = 0
    private var windowStart: UInt64?
    private var reference: (cpu: MTLTimestamp, gpu: MTLTimestamp)

    static func makeIfRequested(device: MTLDevice) -> GPUTiming? {
      guard UserDefaults.standard.bool(forKey: "NavierStokesGPUTiming") else { return nil }
      let desc = MTL4CounterHeapDescriptor()
      desc.type = .timestamp
      desc.count = slots * marksPerSlot
      guard let heap = try? device.makeCounterHeap(descriptor: desc) else {
        NavierStokesRenderer.logger.error("GPU timing: could not create a counter heap")
        return nil
      }
      NavierStokesRenderer.logger.notice("GPU timing enabled")
      return GPUTiming(device: device, heap: heap)
    }

    private init(device: MTLDevice, heap: any MTL4CounterHeap) {
      self.device = device
      self.heap = heap
      self.written = Array(repeating: Array(repeating: false, count: Self.marksPerSlot),
                           count: Self.slots)
      self.reference = device.sampleTimestamps()
    }

    func beginFrame(frameNumber: UInt64) {
      slot = Int(frameNumber % UInt64(Self.slots))
      if windowStart == nil { windowStart = mach_absolute_time() }
      framesBegun += 1
      resolve(slot: slot)
      written[slot] = Array(repeating: false, count: Self.marksPerSlot)
    }

    func write(_ mark: GPUMark, encoder: any MTL4ComputeCommandEncoder) {
      encoder.writeTimestamp(granularity: .precise, counterHeap: heap,
                             index: slot * Self.marksPerSlot + mark.rawValue)
      written[slot][mark.rawValue] = true
    }

    private func resolve(slot: Int) {
      guard !written[slot].contains(false) else { return }
      let range = (slot * Self.marksPerSlot)..<((slot + 1) * Self.marksPerSlot)
      guard let data = try? heap.resolveCounterRange(range),
            data.count >= Self.marksPerSlot * MemoryLayout<UInt64>.size else { return }
      let ticks: [UInt64] = data.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: UInt64.self).prefix(Self.marksPerSlot))
      }
      if ticks.contains(MTLCounterErrorValue) { return }
      guard zip(ticks, ticks.dropFirst()).allSatisfy({ $0 <= $1 }) else { return }

      let now = device.sampleTimestamps()
      let gpuSpan = Double(now.gpu &- reference.gpu)
      guard gpuSpan > 0 else { return }
      let cpuNs = Double(now.cpu &- reference.cpu) * Self.machNsPerTick
      let nsPerTick = cpuNs / gpuSpan

      var previous = ticks[GPUMark.frameStart.rawValue]
      var total: Double = 0
      for mark in GPUMark.allCases where mark != .frameStart {
        let t = ticks[mark.rawValue]
        let ms = Double(t &- previous) * nsPerTick / 1e6
        passSamples[mark.rawValue].append(ms)
        total += ms
        previous = t
      }
      frameSamples.append(total)
      if frameSamples.count >= Self.reportEvery { report() }
    }

    private func report() {
      func f(_ v: Double) -> String { String(format: "%.2f", v) }
      func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
      let labels: [(GPUMark, String)] = [(.afterPredictorTrace, "predictor trace"),
                                         (.afterPredictorProjection, "predictor projection"),
                                         (.afterFlowStep, "flow step"),
                                         (.afterProjection, "projection"),
                                         (.afterVortices, "dye velocity + vortices"),
                                         (.afterDyeMap, "dye map"),
                                         (.afterDyeDiffuse, "dye diffuse"),
                                         (.afterBloom, "bloom"),
                                         (.afterHalation, "halation"),
                                         (.afterCloud, "cloud lighting"),
                                         (.afterRender, "render")]
      let parts = labels.map { "\($0.1) \(f(median(passSamples[$0.0.rawValue])))" }
        .joined(separator: "  ")
      let mean = frameSamples.reduce(0, +) / Double(frameSamples.count)
      var line = "NS GPU ms/frame over \(frameSamples.count) frames: \(parts)  | "
        + "total \(f(median(frameSamples)))  mean \(f(mean))  max \(f(frameSamples.max() ?? 0))"
      let now = mach_absolute_time()
      if let windowStart, now > windowStart {
        let seconds = Double(now - windowStart) * Self.machNsPerTick / 1e9
        line += "  | \(String(format: "%.1f", Double(framesBegun) / seconds)) fps"
      }
      NavierStokesRenderer.logger.notice("\(line, privacy: .public)")
      passSamples = Array(repeating: [], count: GPUMark.allCases.count)
      frameSamples = []
      framesBegun = 0
      windowStart = now
    }
  }
}

#endif
