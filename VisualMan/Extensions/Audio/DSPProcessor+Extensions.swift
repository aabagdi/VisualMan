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
    static let hopSize = 512
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
    static let gainHistorySize = 120
    static let minGain: Float = 0.3
    static let maxGain: Float = 2.0
    static let targetPeak: Float = 0.75
    static let dbOffset: Float = 60.0
    static let dbRange: Float = 80.0
    static let levelsTau: Float = 0.208
    static let avgWeight: Float = 0.7
    static let maxWeight: Float = 0.3
    static let tanhScale: Float = 1.5
    static let lowFrequencyBoostFactor: Float = 0.5
    static let presenceBoostFactor: Float = 0.4
    static let gainHistoryRebuildInterval = 1024
    static let gainTau: Float = 0.3
    static let logMinFreq: Float = log10(minFrequency)
    static let logMaxFreq: Float = log10(maxFrequency)
    static let logBoostCeiling: Float = log10(boostCeilingFrequency)
    static let logPresenceLow: Float = log10(presenceLowFrequency)
    static let logPresenceHigh: Float = log10(presenceHighFrequency)
    static let logPresenceMid: Float = (logPresenceLow + logPresenceHigh) / 2.0
    static let logPresenceHalfWidth: Float = (logPresenceHigh - logPresenceLow) / 2.0
    static let magnitudeScaleDB: Float = 20.0 * log10(2.0 / Float(fftSize))
  }
  
  func rebuildWeightingDBTable(sampleRate: Float) {
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
      let den = term1 * sqrt(term2 * term3) * term4
      
      var aWeight: Float = 0.0
      if den > 0 && frequency > 10 {
        aWeight = 2.0 + 20.0 * log10(num / den)
      } else if frequency <= 10 {
        aWeight = -50.0
      }
      weightingDBTable[i] = aWeight + Constants.magnitudeScaleDB + Constants.dbOffset
    }
  }
  
  struct BarBinRange {
    let startBin: Int
    let endBin: Int
    let fracBinLow: Float
    let fracBinHigh: Float
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
        fracBinLow: fracBinLow, fracBinHigh: fracBinHigh
      )
      barBoostTable[i] = frequencyBoost(logCenter: (logFreqLow + logFreqHigh) / 2.0) * Constants.tanhScale
    }
  }

  func createVisualizerBars(from fftData: borrowing [1024 of Float]) -> [32 of Float] {
    var bars = [32 of Float](repeating: 0.0)

    fftData.withUnsafeBorrowedElementPointer { fft in
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

        bars[i] = avgMag * Constants.avgWeight + maxMag * Constants.maxWeight
      }
    }

    bars.withUnsafeElementPointer { b in
      barBoostTable.withUnsafeElementPointer { boost in
        var count = Int32(Constants.barCount)
        vDSP_vmul(b, 1, boost, 1, b, 1, vDSP_Length(Constants.barCount))
        vvtanhf(b, b, &count)
      }
    }
    return bars
  }
  
  private func frequencyBoost(logCenter: Float) -> Float {
    var result: Float = 1.0

    if logCenter < Constants.logBoostCeiling {
      let ratio = (Constants.logBoostCeiling - logCenter)
                / (Constants.logBoostCeiling - Constants.logMinFreq)
      result *= 1.0 + Constants.lowFrequencyBoostFactor * ratio
    }

    if logCenter >= Constants.logPresenceLow && logCenter <= Constants.logPresenceHigh {
      let distance = abs(logCenter - Constants.logPresenceMid) / Constants.logPresenceHalfWidth
      result *= 1.0 + Constants.presenceBoostFactor * (1.0 - distance * distance)
    }

    return result
  }
}
