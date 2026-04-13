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
  
  private enum Constants {
    static let fftSize = 2048
    static let spectrumSize = 1024
    static let barCount = 32
    static let minFrequency: Float = 60.0
    static let maxFrequency: Float = 13000.0
    static let boostCeilingFrequency: Float = 500.0
    static let presenceLowFrequency: Float = 2000.0
    static let presenceHighFrequency: Float = 8000.0
    static let attackTime: Float = 0.15
    static let releaseTime: Float = 0.5
    static let referenceFrameRate: Float = 60.0
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
  }

  private nonisolated(unsafe) var dftSetup: OpaquePointer?
  private var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  private var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  private var gainHistory = [Float]()
  private var currentGain: Float = 1.0
  private var hannWindow: [2048 of Float] = .init(repeating: 0.0)
  private var aWeightTable: [1024 of Float] = .init(repeating: 0.0)
  private var cachedSampleRate: Float = 0.0
  
  private var ringBuffer: [2048 of Float] = .init(repeating: 0.0)
  private var ringWriteIndex: Int = 0
  
  private var windowBuffer: [2048 of Float] = .init(repeating: 0.0)
  
  private var realIn: [1024 of Float] = .init(repeating: 0.0)
  private var imagIn: [1024 of Float] = .init(repeating: 0.0)
  private var realOut: [1024 of Float] = .init(repeating: 0.0)
  private var imagOut: [1024 of Float] = .init(repeating: 0.0)
  private var magnitudes: [1024 of Float] = .init(repeating: 0.0)
  private var weightedMagnitudes: [1024 of Float] = .init(repeating: 0.0)
  private var logMagnitudes: [1024 of Float] = .init(repeating: 0.0)

  init() {
    dftSetup = vDSP_DFT_zrop_CreateSetup(nil,
                                         vDSP_Length(Constants.fftSize),
                                         vDSP_DFT_Direction.FORWARD)
    hannWindow.withUnsafeElementPointer { hann in
      vDSP_hann_window(hann, vDSP_Length(Constants.fftSize), Int32(vDSP_HANN_NORM))
    }
  }

  deinit {
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
    logMagnitudes = [1024 of Float](repeating: 0.0)
    gainHistory = []
    currentGain = 1.0
  }

  func processSamples(_ samples: [Float], sampleRate: Float) -> DSPResult {
    writeToRing(samples)
    
    guard computeFFTMagnitudes() else {
      return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
    }
    
    normalizeToLogScale(sampleRate: sampleRate)
    
    audioLevels.withUnsafeElementPointer { al in
      logMagnitudes.withUnsafeElementPointer { lm in
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
    
    ringWriteIndex = (ringWriteIndex + effective) % Constants.fftSize
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
      logMagnitudes.withUnsafeElementPointer { lm in
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
    let steps = max(dt * Constants.referenceFrameRate, 0.0001)
    let attackRetention = pow(Constants.attackTime, steps)
    let releaseRetention = pow(Constants.releaseTime, steps)
    
    for i in 0..<Constants.barCount {
      let currentLevel = visualizerBars[i]
      let targetLevel = newBars[i] * currentGain
      let retention = targetLevel > currentLevel ? attackRetention : releaseRetention
      
      visualizerBars[i] = targetLevel + (currentLevel - targetLevel) * retention
      visualizerBars[i] = min(1.0, visualizerBars[i])
    }
  }
  
  private func updateAutomaticGainControl(bars: [32 of Float]) {
    var maxBar: Float = 0.0
    var bars = bars
    bars.withUnsafeElementPointer { b in
      vDSP_maxv(b, 1, &maxBar, 32)
    }
    
    if maxBar < 0.01 {
      currentGain = currentGain * Constants.gainSmoothingFactor + 1.0 * (1.0 - Constants.gainSmoothingFactor)
      return
    }
    
    gainHistory.append(maxBar)
    if gainHistory.count > Constants.gainHistorySize {
      gainHistory.removeFirst()
    }
    
    let averagePeak = gainHistory.reduce(0, +) / Float(gainHistory.count)
    var desiredGain: Float = 1.0
    if averagePeak > 0.01 {
      desiredGain = Constants.targetPeak / averagePeak
    }
    desiredGain = max(Constants.minGain, min(Constants.maxGain, desiredGain))
    currentGain = currentGain * Constants.gainSmoothingFactor + desiredGain * (1.0 - Constants.gainSmoothingFactor)
  }
}

extension DSPProcessor {
  private func rebuildAWeightTable(sampleRate: Float) {
    let binFrequencyWidth = sampleRate / Float(Constants.fftSize)

    let c1: Float = 12194.217 * 12194.217
    let c2: Float = 20.598997 * 20.598997
    let c3: Float = 107.65265 * 107.65265
    let c4: Float = 737.86223 * 737.86223

    for i in 0..<1024 {
      let frequency = Float(i) * binFrequencyWidth
      let f2 = frequency * frequency
      let f4 = f2 * f2
      let num = c1 * f4

      let term1 = f2 + c2
      let term2 = f2 + c3
      let term3 = f2 + c4
      let term4 = f2 + c1
      let sqrtTerm = sqrt(term2 * term3)
      let den = term1 * sqrtTerm * term4

      var aWeight: Float = 0.0
      if den > 0 && frequency > 10 {
        aWeight = 2.0 + 20.0 * log10(num / den)
      } else if frequency <= 10 {
        aWeight = -50.0
      }
      aWeightTable[i] = pow(10.0, aWeight / 20.0)
    }
  }

  private func createVisualizerBars(from fftData: [1024 of Float], sampleRate: Float) -> [32 of Float] {
    var bars = [32 of Float](repeating: 0.0)
    var fftData = fftData

    let logMinFreq = log10(Constants.minFrequency)
    let logMaxFreq = log10(Constants.maxFrequency)
    let binWidth = sampleRate / Float(Constants.fftSize)
    let logBoostCeiling = log10(Constants.boostCeilingFrequency)

    fftData.withUnsafeElementPointer { fft in
      for i in 0..<Constants.barCount {
        let logFreqLow = logMinFreq + (logMaxFreq - logMinFreq) * Float(i) / Float(Constants.barCount)
        let logFreqHigh = logMinFreq + (logMaxFreq - logMinFreq) * Float(i + 1) / Float(Constants.barCount)

        let freqLow = pow(10, logFreqLow)
        let freqHigh = pow(10, logFreqHigh)

        let fracBinLow = freqLow / binWidth
        let fracBinHigh = freqHigh / binWidth
        let startBin = max(0, min(Int(fracBinLow), 1023))
        let endBin = max(startBin + 1, min(Int(fracBinHigh), 1024))
        let count = vDSP_Length(endBin - startBin)

        var maxMag: Float = 0
        var avgMag: Float = 0

        if count <= 2 {
          let centerBin = (fracBinLow + fracBinHigh) / 2.0
          let binIndex = max(0, min(Int(centerBin), 1022))
          let frac = centerBin - Float(binIndex)
          let v0 = (fft + binIndex).pointee
          let v1 = (fft + binIndex + 1).pointee
          avgMag = v0 + (v1 - v0) * frac
          maxMag = max(v0, v1)
        } else {
          vDSP_maxv(fft + startBin, 1, &maxMag, count)
          vDSP_meanv(fft + startBin, 1, &avgMag, count)
        }

        let rawMag = avgMag * Constants.avgWeight + maxMag * Constants.maxWeight
        let logCenter = (logFreqLow + logFreqHigh) / 2.0
        bars[i] = applyFrequencyBoosts(rawMag,
                                       logCenter: logCenter,
                                       logMinFreq: logMinFreq,
                                       logBoostCeiling: logBoostCeiling)

        bars[i] = tanh(bars[i] * Constants.tanhScale)
        bars[i] = max(0, min(1, bars[i]))
      }
    }

    return bars
  }

  private func applyFrequencyBoosts(_ magnitude: Float,
                                    logCenter: Float,
                                    logMinFreq: Float,
                                    logBoostCeiling: Float) -> Float {
    var result = magnitude
    
    if logCenter < logBoostCeiling {
      let ratio = (logBoostCeiling - logCenter) / (logBoostCeiling - logMinFreq)
      let boost = 1.0 + Constants.lowFrequencyBoostFactor * ratio
      result *= boost
    }
    
    let logPresenceLow = log10(Constants.presenceLowFrequency)
    let logPresenceHigh = log10(Constants.presenceHighFrequency)
    if logCenter >= logPresenceLow && logCenter <= logPresenceHigh {
      let mid = (logPresenceLow + logPresenceHigh) / 2.0
      let halfWidth = (logPresenceHigh - logPresenceLow) / 2.0
      let distance = abs(logCenter - mid) / halfWidth
      let boost = 1.0 + Constants.presenceBoostFactor * (1.0 - distance * distance)
      result *= boost
    }
    
    return result
  }
}
