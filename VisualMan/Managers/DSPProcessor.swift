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
  }
  
  enum Constants {
    static let fftSize = 2048
    static let ringMask = fftSize - 1
    static let spectrumSize = 1024
    static let barCount = 32
    static let minFrequency: Float = 60.0
    static let maxFrequency: Float = 13000.0
    static let boostCeilingFrequency: Float = 500.0
    static let presenceLowFrequency: Float = 2000.0
    static let presenceHighFrequency: Float = 8000.0
    static let attackTau: Float = 0.009
    static let releaseTau: Float = 0.024
    static let gainHistorySize = 30
    static let minGain: Float = 0.3
    static let maxGain: Float = 2.0
    static let targetPeak: Float = 0.75
    static let dbOffset: Float = 60.0
    static let dbRange: Float = 80.0
    static let interpolation: Float = 0.2
    static let avgWeight: Float = 0.7
    static let maxWeight: Float = 0.3
    static let tanhScale: Float = 1.5
    static let lowFrequencyBoostFactor: Float = 0.5
    static let presenceBoostFactor: Float = 0.4
    static let gainSmoothingFactor: Float = 0.95
    static let gainHistoryRebuildInterval = 1024
  }

  private let dftSetup: OpaquePointer?
  private var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  private var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  private var gainHistory: [30 of Float] = .init(repeating: 0.0)
  private var gainHistoryWriteIndex = 0
  private var gainHistoryCount = 0
  private var gainHistorySum: Float = 0
  private var gainHistoryEvictionsSinceRebuild = 0
  private var currentGain: Float = 1.0
  private var hannWindow: [2048 of Float] = .init(repeating: 0.0)
  private var cachedSampleRate: Float = 0.0
  
  var aWeightTable: [1024 of Float] = .init(repeating: 0.0)
  
  private var ringBuffer: [2048 of Float] = .init(repeating: 0.0)
  private var ringWriteIndex: Int = 0
  
  private var windowBuffer: [2048 of Float] = .init(repeating: 0.0)
  
  private var realIn: [1024 of Float] = .init(repeating: 0.0)
  private var imagIn: [1024 of Float] = .init(repeating: 0.0)
  private var realOut: [1024 of Float] = .init(repeating: 0.0)
  private var imagOut: [1024 of Float] = .init(repeating: 0.0)
  private var magnitudes: [1024 of Float] = .init(repeating: 0.0)
  private var weightedMagnitudes: [1024 of Float] = .init(repeating: 0.0)
  private var normalizedSpectrum: [1024 of Float] = .init(repeating: 0.0)

  init() {
    dftSetup = vDSP_DFT_zrop_CreateSetup(nil,
                                         vDSP_Length(Constants.fftSize),
                                         vDSP_DFT_Direction.FORWARD)
    hannWindow.withUnsafeElementPointer { hann in
      vDSP_hann_window(hann, vDSP_Length(Constants.fftSize), Int32(vDSP_HANN_NORM))
    }
  }

  isolated deinit {
    if let dftSetup {
      vDSP_DFT_DestroySetup(dftSetup)
    }
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
    magnitudes = [1024 of Float](repeating: 0.0)
    weightedMagnitudes = [1024 of Float](repeating: 0.0)
    normalizedSpectrum = [1024 of Float](repeating: 0.0)
    gainHistory = [30 of Float](repeating: 0.0)
    gainHistoryWriteIndex = 0
    gainHistoryCount = 0
    gainHistorySum = 0
    gainHistoryEvictionsSinceRebuild = 0
    currentGain = 1.0
  }

  func processSamples(_ samples: [Float], sampleRate: Float) -> DSPResult {
    writeToRing(samples)
    
    guard computeFFTMagnitudes() else {
      return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
    }
    
    normalizeToLogScale(sampleRate: sampleRate)
    
    audioLevels.withUnsafeElementPointer { al in
      normalizedSpectrum.withUnsafeElementPointer { lm in
        var interpolation: Float = Constants.interpolation
        vDSP_vintb(al, 1, lm, 1, &interpolation, al, 1, vDSP_Length(Constants.spectrumSize))
      }
    }
    
    let newBars = createVisualizerBars(from: audioLevels, sampleRate: sampleRate)
    updateAutomaticGainControl(bars: newBars)
    
    let dt = sampleRate > 0 ? Float(samples.count) / sampleRate : 1.0 / 60.0
    smoothVisualizerBars(newBars, dt: dt)
    
    return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
  }
  
  private func writeToRing(_ samples: [Float]) {
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
  
  private func computeFFTMagnitudes() -> Bool {
    guard let dftSetup else { return false }
    
    let splitPoint = ringWriteIndex
    ringBuffer.withUnsafeElementPointer { ring in
      windowBuffer.withUnsafeElementPointer { wb in
        let tailCount = Constants.fftSize - splitPoint
        wb.update(from: ring + splitPoint, count: tailCount)
        if splitPoint > 0 {
          (wb + tailCount).update(from: ring, count: splitPoint)
        }
        hannWindow.withUnsafeElementPointer { hann in
          vDSP_vmul(wb, 1, hann, 1, wb, 1, vDSP_Length(Constants.fftSize))
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
        magnitudes.withUnsafeElementPointer { mag in
          var complex = DSPSplitComplex(realp: ro, imagp: io)
          vDSP_zvabs(&complex, 1, mag, 1, vDSP_Length(Constants.spectrumSize))
        }
      }
    }
    
    var scaleFactor: Float = 2.0 / Float(Constants.fftSize)
    magnitudes.withUnsafeElementPointer { mag in
      vDSP_vsmul(mag, 1, &scaleFactor, mag, 1, vDSP_Length(Constants.spectrumSize))
    }
    
    return true
  }
  
  private func normalizeToLogScale(sampleRate: Float) {
    if sampleRate != cachedSampleRate {
      rebuildAWeightTable(sampleRate: sampleRate)
      cachedSampleRate = sampleRate
    }
    
    magnitudes.withUnsafeElementPointer { mag in
      aWeightTable.withUnsafeElementPointer { aw in
        weightedMagnitudes.withUnsafeElementPointer { wm in
          var floor: Float = 1e-10
          vDSP_vsadd(mag, 1, &floor, wm, 1, 1024)
          vDSP_vmul(wm, 1, aw, 1, wm, 1, 1024)
        }
      }
    }
    
    weightedMagnitudes.withUnsafeElementPointer { wm in
      normalizedSpectrum.withUnsafeElementPointer { lm in
        var ref: Float = 1.0
        vDSP_vdbcon(wm, 1, &ref, lm, 1, 1024, 1)
        
        var offset: Float = Constants.dbOffset
        vDSP_vsadd(lm, 1, &offset, lm, 1, 1024)
        var range: Float = Constants.dbRange
        vDSP_vsdiv(lm, 1, &range, lm, 1, 1024)
        
        var low: Float = 0.0
        var high: Float = 1.0
        vDSP_vclip(lm, 1, &low, &high, lm, 1, 1024)
      }
    }
  }
  
  private func smoothVisualizerBars(_ newBars: [32 of Float], dt: Float) {
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
  
  private func updateAutomaticGainControl(bars: [32 of Float]) {
    var maxBar: Float = 0
    for i in 0..<Constants.barCount where bars[i] > maxBar {
      maxBar = bars[i]
    }
    
    if maxBar < 0.01 {
      currentGain = currentGain * Constants.gainSmoothingFactor
                  + 1.0 * (1.0 - Constants.gainSmoothingFactor)
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
    currentGain = currentGain * Constants.gainSmoothingFactor
                + desiredGain * (1.0 - Constants.gainSmoothingFactor)
  }
}
