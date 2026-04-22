//
//  DSPProcessor+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/13/26.
//

import Accelerate

extension DSPProcessor {
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
    static let gainTau: Float = 0.3
    static let logMinFreq: Float = log10(minFrequency)
    static let logMaxFreq: Float = log10(maxFrequency)
    static let logBoostCeiling: Float = log10(boostCeilingFrequency)
    static let logPresenceLow: Float = log10(presenceLowFrequency)
    static let logPresenceHigh: Float = log10(presenceHighFrequency)
    static let logPresenceMid: Float = (logPresenceLow + logPresenceHigh) / 2.0
    static let logPresenceHalfWidth: Float = (logPresenceHigh - logPresenceLow) / 2.0
  }
  
  func rebuildAWeightTable(sampleRate: Float) {
    let binFrequencyWidth = sampleRate / Float(Constants.fftSize)
    
    let c1: Float = 12194.217 * 12194.217
    let c2: Float = 20.598997 * 20.598997
    let c3: Float = 107.65265 * 107.65265
    let c4: Float = 737.86223 * 737.86223
    
    for i in 0..<Constants.spectrumSize {
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
  
  struct BarBinRange {
    let startBin: Int
    let endBin: Int
    let fracBinLow: Float
    let fracBinHigh: Float
    let logCenter: Float
  }

  func rebuildBarBinRanges(sampleRate: Float) {
    let binWidth = sampleRate / Float(Constants.fftSize)
    let logRange = Constants.logMaxFreq - Constants.logMinFreq
    let invBarCount = 1.0 / Float(Constants.barCount)

    for i in 0..<Constants.barCount {
      let logFreqLow = Constants.logMinFreq + logRange * Float(i) * invBarCount
      let logFreqHigh = Constants.logMinFreq + logRange * Float(i + 1) * invBarCount
      let freqLow = pow(10, logFreqLow)
      let freqHigh = pow(10, logFreqHigh)
      let fracBinLow = freqLow / binWidth
      let fracBinHigh = freqHigh / binWidth
      let startBin = max(0, min(Int(fracBinLow), 1023))
      let endBin = max(startBin + 1, min(Int(fracBinHigh), 1024))
      cachedBarBinRanges[i] = BarBinRange(
        startBin: startBin, endBin: endBin,
        fracBinLow: fracBinLow, fracBinHigh: fracBinHigh,
        logCenter: (logFreqLow + logFreqHigh) / 2.0
      )
    }
  }

  func createVisualizerBars(from fftData: [1024 of Float], sampleRate: Float) -> [32 of Float] {
    var bars = [32 of Float](repeating: 0.0)

    var fftData = fftData

    fftData.withUnsafeElementPointer { fft in
      for i in 0..<Constants.barCount {
        let range = cachedBarBinRanges[i]
        let count = vDSP_Length(range.endBin - range.startBin)

        var maxMag: Float = 0
        var avgMag: Float = 0

        if count <= 2 {
          let centerBin = (range.fracBinLow + range.fracBinHigh) / 2.0
          let binIndex = max(0, min(Int(centerBin), 1022))
          let frac = centerBin - Float(binIndex)
          let v0 = (fft + binIndex).pointee
          let v1 = (fft + binIndex + 1).pointee
          avgMag = v0 + (v1 - v0) * frac
          maxMag = max(v0, v1)
        } else {
          vDSP_maxv(fft + range.startBin, 1, &maxMag, count)
          vDSP_meanv(fft + range.startBin, 1, &avgMag, count)
        }

        let rawMag = avgMag * Constants.avgWeight + maxMag * Constants.maxWeight
        bars[i] = applyFrequencyBoosts(rawMag, logCenter: range.logCenter)

        bars[i] = tanh(bars[i] * Constants.tanhScale)
        bars[i] = max(0, min(1, bars[i]))
      }
    }

    return bars
  }
  
  private func applyFrequencyBoosts(_ magnitude: Float, logCenter: Float) -> Float {
    var result = magnitude

    if logCenter < Constants.logBoostCeiling {
      let ratio = (Constants.logBoostCeiling - logCenter)
                / (Constants.logBoostCeiling - Constants.logMinFreq)
      let boost = 1.0 + Constants.lowFrequencyBoostFactor * ratio
      result *= boost
    }

    if logCenter >= Constants.logPresenceLow && logCenter <= Constants.logPresenceHigh {
      let distance = abs(logCenter - Constants.logPresenceMid) / Constants.logPresenceHalfWidth
      let boost = 1.0 + Constants.presenceBoostFactor * (1.0 - distance * distance)
      result *= boost
    }

    return result
  }
}
