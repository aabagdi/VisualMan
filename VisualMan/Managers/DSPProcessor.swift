//
//  DSPProcessor.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Foundation
import Accelerate

actor DSPProcessor {
  struct DSPResult: Sendable {
    let audioLevels: [1024 of Float]
    let visualizerBars: [32 of Float]
  }

  private nonisolated(unsafe) var dftSetup: OpaquePointer?
  private var audioLevels = [1024 of Float](repeating: 0.0)
  private var visualizerBars = [32 of Float](repeating: 0.0)
  private var peakLevels = [32 of Float](repeating: 0.0)
  private var peakHoldTime = [32 of Float](repeating: 0.0)
  private var gainHistory: [Float] = []
  private var currentGain: Float = 1.0
  private var hannWindow = [2048 of Float](repeating: 0.0)
  private var aWeightTable = [1024 of Float](repeating: 0.0)
  private var cachedSampleRate: Float = 0.0
  private var realIn = [2048 of Float](repeating: 0.0)
  private var imagIn = [2048 of Float](repeating: 0.0)
  private var realOut = [2048 of Float](repeating: 0.0)
  private var imagOut = [2048 of Float](repeating: 0.0)
  private var magnitudes = [1024 of Float](repeating: 0.0)
  private var weightedMagnitudes = [1024 of Float](repeating: 0.0)
  private var logMagnitudes = [1024 of Float](repeating: 0.0)

  private let numberOfBars = 32
  private let smoothingFactor: Float = 0.8
  private let attackTime: Float = 0.1
  private let releaseTime: Float = 0.6
  private let peakHoldDuration: Float = 10.0
  private let gainHistorySize = 30

  init() {
    dftSetup = vDSP_DFT_zop_CreateSetup(nil, 2048, vDSP_DFT_Direction.FORWARD)
    hannWindow.withUnsafeElementPointer { hann in
      vDSP_hann_window(hann, 2048, Int32(vDSP_HANN_NORM))
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
    peakLevels = [32 of Float](repeating: 0.0)
    peakHoldTime = [32 of Float](repeating: 0.0)
    realIn = [2048 of Float](repeating: 0.0)
    imagIn = [2048 of Float](repeating: 0.0)
    realOut = [2048 of Float](repeating: 0.0)
    imagOut = [2048 of Float](repeating: 0.0)
    magnitudes = [1024 of Float](repeating: 0.0)
    weightedMagnitudes = [1024 of Float](repeating: 0.0)
    logMagnitudes = [1024 of Float](repeating: 0.0)
    gainHistory = []
    currentGain = 1.0
  }

  func processSamples(_ samples: [Float], sampleRate: Float) -> DSPResult {
    guard computeFFTMagnitudes(samples) else {
      return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
    }
    
    normalizeToLogScale(sampleRate: sampleRate)
    
    audioLevels.withUnsafeElementPointer { al in
      logMagnitudes.withUnsafeElementPointer { lm in
        var interpolation: Float = 0.2
        vDSP_vintb(al, 1, lm, 1, &interpolation, al, 1, 1024)
      }
    }
    
    let newBars = createVisualizerBars(from: audioLevels, sampleRate: sampleRate)
    updateAutomaticGainControl(bars: newBars)
    smoothVisualizerBars(newBars)
    
    return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
  }
  
  private func computeFFTMagnitudes(_ samples: [Float]) -> Bool {
    let sampleCount = min(samples.count, 2048)
    realIn.withUnsafeElementPointer { ri in
      hannWindow.withUnsafeElementPointer { hann in
        samples.withUnsafeBufferPointer { srcBuf in
          ri.update(from: srcBuf.baseAddress!, count: sampleCount)
        }
        vDSP_vmul(ri, 1, hann, 1, ri, 1, vDSP_Length(sampleCount))
      }
    }
    
    guard let dftSetup else { return false }
    
    realIn.withUnsafeElementPointer { ri in
      imagIn.withUnsafeElementPointer { ii in
        realOut.withUnsafeElementPointer { ro in
          imagOut.withUnsafeElementPointer { io in
            vDSP_DFT_Execute(dftSetup, ri, ii, ro, io)
          }
        }
      }
    }
    
    realOut.withUnsafeElementPointer { ro in
      imagOut.withUnsafeElementPointer { io in
        magnitudes.withUnsafeElementPointer { mag in
          var complex = DSPSplitComplex(realp: ro, imagp: io)
          vDSP_zvabs(&complex, 1, mag, 1, 1024)
        }
      }
    }
    
    var scaleFactor: Float = 2.0 / Float(2048)
    magnitudes.withUnsafeElementPointer { mag in
      vDSP_vsmul(mag, 1, &scaleFactor, mag, 1, 1024)
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
        
        var offset: Float = 60.0
        vDSP_vsadd(lm, 1, &offset, lm, 1, 1024)
        var range: Float = 80.0
        vDSP_vsdiv(lm, 1, &range, lm, 1, 1024)
        
        var low: Float = 0.0
        var high: Float = 1.0
        vDSP_vclip(lm, 1, &low, &high, lm, 1, 1024)
      }
    }
  }
  
  private func smoothVisualizerBars(_ newBars: [32 of Float]) {
    for i in 0..<numberOfBars {
      let currentLevel = visualizerBars[i]
      let targetLevel = newBars[i] * currentGain
      
      if targetLevel > currentLevel {
        visualizerBars[i] = currentLevel + (targetLevel - currentLevel) * (1.0 - attackTime)
      } else {
        visualizerBars[i] = currentLevel + (targetLevel - currentLevel) * (1.0 - releaseTime)
      }
      
      visualizerBars[i] = min(1.0, visualizerBars[i])
      
      if visualizerBars[i] > peakLevels[i] {
        peakLevels[i] = visualizerBars[i]
        peakHoldTime[i] = peakHoldDuration
      } else if peakHoldTime[i] > 0 {
        peakHoldTime[i] -= 1
      } else {
        peakLevels[i] *= 0.95
      }
    }
  }
  
  private func updateAutomaticGainControl(bars: [32 of Float]) {
    var maxBar: Float = 0.0
    var bars = bars
    bars.withUnsafeElementPointer { b in
      vDSP_maxv(b, 1, &maxBar, 32)
    }
    
    gainHistory.append(maxBar)
    if gainHistory.count > gainHistorySize {
      gainHistory.removeFirst()
    }
    
    let averagePeak = gainHistory.reduce(0, +) / Float(gainHistory.count)
    
    let targetPeak: Float = 0.75
    var desiredGain: Float = 1.0
    
    if averagePeak > 0.01 {
      desiredGain = targetPeak / averagePeak
    }
    
    desiredGain = max(0.3, min(2.0, desiredGain))
    
    currentGain = currentGain * 0.95 + desiredGain * 0.05
  }
  
  private func rebuildAWeightTable(sampleRate: Float) {
    let binFrequencyWidth = sampleRate / Float(2048)
    
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
    
    let minFreq: Float = 60.0
    let maxFreq: Float = 13000.0
    
    let logMinFreq = log10(minFreq)
    let logMaxFreq = log10(maxFreq)
    let binWidth = sampleRate / Float(2048)
    let logBoostCeiling = log10(500.0 as Float)
    
    fftData.withUnsafeElementPointer { fft in
      for i in 0..<numberOfBars {
        let logFreqLow = logMinFreq + (logMaxFreq - logMinFreq) * Float(i) / Float(numberOfBars)
        let logFreqHigh = logMinFreq + (logMaxFreq - logMinFreq) * Float(i + 1) / Float(numberOfBars)
        
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
        
        let rawMag = avgMag * 0.7 + maxMag * 0.3
        let logCenter = (logFreqLow + logFreqHigh) / 2.0
        bars[i] = applyFrequencyBoosts(rawMag,
                                       logCenter: logCenter,
                                       logMinFreq: logMinFreq,
                                       logBoostCeiling: logBoostCeiling)
        
        bars[i] = tanh(bars[i] * 1.5)
        
        bars[i] = max(0, min(1, bars[i]))
      }
    }
    
    return bars
  }
  
}

extension DSPProcessor {
  private func applyFrequencyBoosts(_ magnitude: Float,
                                    logCenter: Float,
                                    logMinFreq: Float,
                                    logBoostCeiling: Float) -> Float {
    var result = magnitude
    
    if logCenter < logBoostCeiling {
      let boost = 1.0 + 0.5 * (logBoostCeiling - logCenter) / (logBoostCeiling - logMinFreq)
      result *= boost
    }
    
    let logPresenceLow = log10(2000.0 as Float)
    let logPresenceHigh = log10(8000.0 as Float)
    if logCenter >= logPresenceLow && logCenter <= logPresenceHigh {
      let mid = (logPresenceLow + logPresenceHigh) / 2.0
      let halfWidth = (logPresenceHigh - logPresenceLow) / 2.0
      let distance = abs(logCenter - mid) / halfWidth
      let boost = 1.0 + 0.4 * (1.0 - distance * distance)
      result *= boost
    }
    
    return result
  }
}
