//
//  DSPProcessor+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/13/26.
//

import Accelerate

extension DSPProcessor {
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

  func createVisualizerBars(from fftData: [1024 of Float], sampleRate: Float) -> [32 of Float] {
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
