//
//  DSPProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Accelerate

actor DSPProcessor {
  struct DSPResult: Sendable {
    let audioLevels: [1024 of Float]
    let visualizerBars: [32 of Float]
    let waveform: [1024 of Float]
  }

  private let dftSetup: OpaquePointer
  private var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  private var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  private var gainHistory: [120 of Float] = .init(repeating: 0.0)
  private var gainHistoryWriteIndex = 0
  private var gainHistoryCount = 0
  private var gainHistorySum: Float = 0
  private var gainHistoryEvictionsSinceRebuild = 0
  private var currentGain: Float = 1.0
  private var hannWindow: [2048 of Float] = .init(repeating: 0.0)
  private var cachedSampleRate: Float = 0.0
  
  var weightingDBTable: [1024 of Float] = .init(repeating: 0.0)
  var cachedBarBinRanges: [32 of BarBinRange] = .init(
    repeating: BarBinRange(startBin: 0, endBin: 1, fracBinLow: 0, fracBinHigh: 0)
  )
  var barBoostTable: [32 of Float] = .init(repeating: 0.0)
  
  private var ringBuffer: [2048 of Float] = .init(repeating: 0.0)
  private var ringWriteIndex: Int = 0
  
  private var windowBuffer: [2048 of Float] = .init(repeating: 0.0)
  
  private var realIn: [1024 of Float] = .init(repeating: 0.0)
  private var imagIn: [1024 of Float] = .init(repeating: 0.0)
  private var realOut: [1024 of Float] = .init(repeating: 0.0)
  private var imagOut: [1024 of Float] = .init(repeating: 0.0)
  private var powerSpectrum: [1024 of Float] = .init(repeating: 0.0)
  private var normalizedSpectrum: [1024 of Float] = .init(repeating: 0.0)
  private var waveformBuffer: [1024 of Float] = .init(repeating: 0.0)

  init() {
    precondition(Constants.fftSize > 0 && Constants.fftSize.nonzeroBitCount == 1,
                 "fftSize must be a power of two (ringMask relies on this)")
    guard let setup = vDSP_DFT_zrop_CreateSetup(nil,
                                                vDSP_Length(Constants.fftSize),
                                                vDSP_DFT_Direction.FORWARD) else {
      fatalError("vDSP_DFT_zrop_CreateSetup failed for fftSize=\(Constants.fftSize)")
    }
    dftSetup = setup
    hannWindow.withUnsafeElementPointer { hann in
      vDSP_hann_window(hann, vDSP_Length(Constants.fftSize), Int32(vDSP_HANN_NORM))
    }
  }

  isolated deinit {
    vDSP_DFT_DestroySetup(dftSetup)
  }

  func reset() {
    audioLevels = [1024 of Float](repeating: 0.0)
    visualizerBars = [32 of Float](repeating: 0.0)
    ringBuffer = [2048 of Float](repeating: 0.0)
    ringWriteIndex = 0
    windowBuffer = [2048 of Float](repeating: 0.0)
    realIn = [1024 of Float](repeating: 0.0)
    imagIn = [1024 of Float](repeating: 0.0)
    realOut = [1024 of Float](repeating: 0.0)
    imagOut = [1024 of Float](repeating: 0.0)
    powerSpectrum = [1024 of Float](repeating: 0.0)
    normalizedSpectrum = [1024 of Float](repeating: 0.0)
    waveformBuffer = [1024 of Float](repeating: 0.0)
    gainHistory = [120 of Float](repeating: 0.0)
    gainHistoryWriteIndex = 0
    gainHistoryCount = 0
    gainHistorySum = 0
    gainHistoryEvictionsSinceRebuild = 0
    currentGain = 1.0
  }

  func processSamples(_ samples: ArraySlice<Float>, sampleRate: Float) -> DSPResult {
    let analyzed = samples.suffix(Constants.fftSize)
    let skipped = samples.count - analyzed.count
    if skipped > 0 {
      writeToRing(samples.prefix(skipped))
    }

    var hopStart = analyzed.startIndex
    var pendingSamples = skipped
    while hopStart < analyzed.endIndex {
      let hopEnd = min(hopStart + Constants.hopSize, analyzed.endIndex)
      let hop = analyzed[hopStart..<hopEnd]
      pendingSamples += hop.count
      let dt = sampleRate > 0 ? Float(pendingSamples) / sampleRate : 1.0 / 60.0
      analyzeHop(hop, sampleRate: sampleRate, dt: dt)
      pendingSamples = 0
      hopStart = hopEnd
    }

    return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars, waveform: waveformBuffer)
  }

  private func analyzeHop(_ samples: ArraySlice<Float>, sampleRate: Float, dt: Float) {
    writeToRing(samples)

    captureWaveform()
    computePowerSpectrum()
    
    normalizeToLogScale(sampleRate: sampleRate)
    
    audioLevels.withUnsafeElementPointer { al in
      normalizedSpectrum.withUnsafeElementPointer { lm in
        var interpolation: Float = 1 - exp(-max(dt, 1e-4) / Constants.levelsTau)
        vDSP_vintb(al, 1, lm, 1, &interpolation, al, 1, vDSP_Length(Constants.spectrumSize))
      }
    }
    
    let newBars = createVisualizerBars(from: audioLevels)

    updateAutomaticGainControl(bars: newBars, dt: dt)
    smoothVisualizerBars(newBars, dt: dt)
  }
  
  private func writeToRing(_ samples: ArraySlice<Float>) {
    let n = samples.count
    guard n > 0 else { return }
    
    let effective = min(n, Constants.fftSize)
    let skipFront = n - effective
    
    ringBuffer.withUnsafeElementPointer { ring in
      samples.withUnsafeBufferPointer { src in
        guard let base = src.baseAddress else { return }
        let srcStart = base + skipFront
        
        let firstChunk = min(effective, Constants.fftSize - ringWriteIndex)
        (ring + ringWriteIndex).update(from: srcStart, count: firstChunk)
        
        let remaining = effective - firstChunk
        if remaining > 0 {
          ring.update(from: srcStart + firstChunk, count: remaining)
        }
      }
    }
    
    ringWriteIndex = (ringWriteIndex + effective) & Constants.ringMask
  }
  
  private func captureWaveform() {
    let halfFFT = Constants.fftSize / 2
    let start = (ringWriteIndex + Constants.fftSize - halfFFT) & Constants.ringMask
    ringBuffer.withUnsafeElementPointer { ring in
      waveformBuffer.withUnsafeElementPointer { wf in
        let tailCount = min(halfFFT, Constants.fftSize - start)
        wf.update(from: ring + start, count: tailCount)
        let remaining = halfFFT - tailCount
        if remaining > 0 {
          (wf + tailCount).update(from: ring, count: remaining)
        }
      }
    }
  }

  private func computePowerSpectrum() {
    let splitPoint = ringWriteIndex
    ringBuffer.withUnsafeElementPointer { ring in
      windowBuffer.withUnsafeElementPointer { wb in
        hannWindow.withUnsafeElementPointer { hann in
          let tailCount = Constants.fftSize - splitPoint
          vDSP_vmul(ring + splitPoint, 1, hann, 1, wb, 1, vDSP_Length(tailCount))
          if splitPoint > 0 {
            vDSP_vmul(ring, 1, hann + tailCount, 1, wb + tailCount, 1, vDSP_Length(splitPoint))
          }
        }
      }
    }
    
    windowBuffer.withUnsafeElementPointer { wb in
      realIn.withUnsafeElementPointer { ri in
        imagIn.withUnsafeElementPointer { ii in
          var split = DSPSplitComplex(realp: ri, imagp: ii)
          wb.withMemoryRebound(to: DSPComplex.self, capacity: Constants.spectrumSize) { complexPtr in
            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(Constants.spectrumSize))
          }
        }
      }
    }
    
    realIn.withUnsafeElementPointer { ri in
      imagIn.withUnsafeElementPointer { ii in
        realOut.withUnsafeElementPointer { ro in
          imagOut.withUnsafeElementPointer { io in
            vDSP_DFT_Execute(dftSetup, ri, ii, ro, io)
          }
        }
      }
    }
    
    realOut[0] = 0
    imagOut[0] = 0
    
    realOut.withUnsafeElementPointer { ro in
      imagOut.withUnsafeElementPointer { io in
        powerSpectrum.withUnsafeElementPointer { power in
          var complex = DSPSplitComplex(realp: ro, imagp: io)
          vDSP_zvmags(&complex, 1, power, 1, vDSP_Length(Constants.spectrumSize))
        }
      }
    }
  }
  
  private func normalizeToLogScale(sampleRate: Float) {
    if sampleRate != cachedSampleRate {
      rebuildWeightingDBTable(sampleRate: sampleRate)
      rebuildBarBinRanges(sampleRate: sampleRate)
      cachedSampleRate = sampleRate
    }
    
    powerSpectrum.withUnsafeElementPointer { power in
      weightingDBTable.withUnsafeElementPointer { weighting in
        normalizedSpectrum.withUnsafeElementPointer { lm in
          var ref: Float = 1.0
          let specLen = vDSP_Length(Constants.spectrumSize)
          vDSP_vdbcon(power, 1, &ref, lm, 1, specLen, 0)

          var invRange: Float = 1.0 / Constants.dbRange
          vDSP_vasm(lm, 1, weighting, 1, &invRange, lm, 1, specLen)

          var low: Float = 0.0
          var high: Float = 1.0
          vDSP_vclip(lm, 1, &low, &high, lm, 1, specLen)
        }
      }
    }
  }
  
  private func smoothVisualizerBars(_ newBars: borrowing [32 of Float], dt: Float) {
    let safeDt = max(dt, 1e-4)
    let attackRetention = exp(-safeDt / Constants.attackTau)
    let releaseRetention = exp(-safeDt / Constants.releaseTau)
    
    for i in 0..<Constants.barCount {
      let current = visualizerBars[i]
      let target = newBars[i] * currentGain
      let retention = target > current ? attackRetention : releaseRetention
      let next = target + (current - target) * retention
      visualizerBars[i] = min(1.0, next)
    }
  }
  
  private func updateAutomaticGainControl(bars: borrowing [32 of Float], dt: Float) {
    var maxBar: Float = 0
    bars.withUnsafeBorrowedElementPointer { b in
      vDSP_maxv(b, 1, &maxBar, vDSP_Length(Constants.barCount))
    }

    let safeDt = max(dt, 1e-4)
    let retention = exp(-safeDt / Constants.gainTau)

    if maxBar < 0.01 {
      currentGain = 1.0 + (currentGain - 1.0) * retention
      return
    }

    if gainHistoryCount < Constants.gainHistorySize {
      gainHistory[gainHistoryCount] = maxBar
      gainHistorySum += maxBar
      gainHistoryCount += 1
    } else {
      let evicted = gainHistory[gainHistoryWriteIndex]
      gainHistory[gainHistoryWriteIndex] = maxBar
      gainHistorySum += maxBar - evicted
      gainHistoryWriteIndex = (gainHistoryWriteIndex + 1) % Constants.gainHistorySize
      gainHistoryEvictionsSinceRebuild += 1
      if gainHistoryEvictionsSinceRebuild >= Constants.gainHistoryRebuildInterval {
        gainHistory.withUnsafeElementPointer { gh in
          vDSP_sve(gh, 1, &gainHistorySum, vDSP_Length(Constants.gainHistorySize))
        }
        gainHistoryEvictionsSinceRebuild = 0
      }
    }

    let averagePeak = gainHistorySum / Float(gainHistoryCount)
    var desiredGain: Float = 1.0
    if averagePeak > 0.01 {
      desiredGain = Constants.targetPeak / averagePeak
    }
    desiredGain = max(Constants.minGain, min(Constants.maxGain, desiredGain))

    currentGain = desiredGain + (currentGain - desiredGain) * retention
  }
}
