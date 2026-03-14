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
    let audioLevels: [512 of Float]
    let visualizerBars: [32 of Float]
  }
  
  private nonisolated(unsafe) var dftSetup: OpaquePointer?
  private var audioLevels = [512 of Float](repeating: 0.0)
  private var visualizerBars = [32 of Float](repeating: 0.0)
  private var peakLevels = [32 of Float](repeating: 0.0)
  private var peakHoldTime = [32 of Float](repeating: 0.0)
  private var gainHistory: [Float] = []
  private var currentGain: Float = 1.0
  
  private let numberOfBars = 32
  private let smoothingFactor: Float = 0.8
  private let attackTime: Float = 0.1
  private let releaseTime: Float = 0.6
  private let peakHoldDuration: Float = 10.0
  private let gainHistorySize = 30
  
  init() {
    dftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)
  }
  
  deinit {
    if let dftSetup {
      vDSP_DFT_DestroySetup(dftSetup)
    }
  }
  
  func reset() {
    audioLevels = [512 of Float](repeating: 0.0)
    visualizerBars = [32 of Float](repeating: 0.0)
    peakLevels = [32 of Float](repeating: 0.0)
    peakHoldTime = [32 of Float](repeating: 0.0)
    gainHistory = []
    currentGain = 1.0
  }
  
  func processSamples(_ samples: [Float], sampleRate: Float) -> DSPResult {
    var realIn = [1024 of Float](repeating: 0.0)
    var imagIn = [1024 of Float](repeating: 0.0)
    var realOut = [1024 of Float](repeating: 0.0)
    var imagOut = [1024 of Float](repeating: 0.0)
    
    for i in 0..<min(samples.count, 1024) {
      let window = 0.5 - 0.5 * cos(2.0 * .pi * Float(i) / Float(1023))
      realIn[i] = samples[i] * window
    }
    
    guard let dftSetup else { return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars) }
    
    withUnsafeMutablePointer(to: &realIn) { riPtr in
      withUnsafeMutablePointer(to: &imagIn) { iiPtr in
        withUnsafeMutablePointer(to: &realOut) { roPtr in
          withUnsafeMutablePointer(to: &imagOut) { ioPtr in
            let ri = UnsafeMutableRawPointer(riPtr).assumingMemoryBound(to: Float.self)
            let ii = UnsafeMutableRawPointer(iiPtr).assumingMemoryBound(to: Float.self)
            let ro = UnsafeMutableRawPointer(roPtr).assumingMemoryBound(to: Float.self)
            let io = UnsafeMutableRawPointer(ioPtr).assumingMemoryBound(to: Float.self)
            vDSP_DFT_Execute(dftSetup, ri, ii, ro, io)
          }
        }
      }
    }
    
    var magnitudes = [512 of Float](repeating: 0.0)
    
    withUnsafeMutablePointer(to: &realOut) { roPtr in
      withUnsafeMutablePointer(to: &imagOut) { ioPtr in
        withUnsafeMutablePointer(to: &magnitudes) { magPtr in
          let ro = UnsafeMutableRawPointer(roPtr).assumingMemoryBound(to: Float.self)
          let io = UnsafeMutableRawPointer(ioPtr).assumingMemoryBound(to: Float.self)
          let mag = UnsafeMutableRawPointer(magPtr).assumingMemoryBound(to: Float.self)
          var complex = DSPSplitComplex(realp: ro, imagp: io)
          vDSP_zvabs(&complex, 1, mag, 1, 512)
        }
      }
    }
    
    var scaleFactor: Float = 2.0 / Float(1024)
    withUnsafeMutablePointer(to: &magnitudes) { magPtr in
      let mag = UnsafeMutableRawPointer(magPtr).assumingMemoryBound(to: Float.self)
      vDSP_vsmul(mag, 1, &scaleFactor, mag, 1, 512)
    }
    
    var logMagnitudes = [512 of Float](repeating: 0.0)
    
    let binFrequencyWidth = sampleRate / Float(1024)
    
    for i in 0..<512 {
      let frequency = Float(i) * binFrequencyWidth
      
      let f2 = frequency * frequency
      let f4 = f2 * f2
      
      let c1: Float = 12194.217 * 12194.217
      let c2: Float = 20.598997 * 20.598997
      let c3: Float = 107.65265 * 107.65265
      let c4: Float = 737.86223 * 737.86223
      
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
      
      let aWeightLinear = pow(10.0, aWeight / 20.0)
      
      let magnitude = magnitudes[i] + 1e-10
      
      let weightedMagnitude = magnitude * aWeightLinear
      
      let db = 20.0 * log10(weightedMagnitude)
      
      let normalized = (db + 60.0) / 80.0
      
      logMagnitudes[i] = max(0.0, min(1.0, normalized))
    }
    
    for i in 0..<512 {
      audioLevels[i] = audioLevels[i] * 0.8 + logMagnitudes[i] * 0.2
    }
    
    let newBars = createVisualizerBars(from: audioLevels, sampleRate: sampleRate)
    
    updateAutomaticGainControl(bars: newBars)
    
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
    
    return DSPResult(audioLevels: audioLevels, visualizerBars: visualizerBars)
  }
  
  private func updateAutomaticGainControl(bars: [32 of Float]) {
    var maxBar: Float = 0.0
    for i in bars.indices {
      maxBar = max(maxBar, bars[i])
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
  
  private func createVisualizerBars(from fftData: [512 of Float], sampleRate: Float) -> [32 of Float] {
    var bars = [32 of Float](repeating: 0.0)
    
    let minFreq: Float = 60.0
    let maxFreq: Float = 16000.0
    
    let logMinFreq = log10(minFreq)
    let logMaxFreq = log10(maxFreq)
    
    for i in 0..<numberOfBars {
      let logFreqLow = logMinFreq + (logMaxFreq - logMinFreq) * Float(i) / Float(numberOfBars)
      let logFreqHigh = logMinFreq + (logMaxFreq - logMinFreq) * Float(i + 1) / Float(numberOfBars)
      
      let freqLow = pow(10, logFreqLow)
      let freqHigh = pow(10, logFreqHigh)
      
      let binWidth = sampleRate / Float(fftData.count * 2)
      let binLow = Int(freqLow / binWidth)
      let binHigh = Int(freqHigh / binWidth)
      
      let startBin = max(0, min(binLow, fftData.count - 1))
      let endBin = max(startBin + 1, min(binHigh, fftData.count))
      
      var maxMag: Float = 0
      var avgMag: Float = 0
      var count = 0
      
      for j in startBin..<endBin {
        let mag = fftData[j]
        avgMag += mag
        maxMag = max(maxMag, mag)
        count += 1
      }
      
      if count > 0 {
        avgMag /= Float(count)
        bars[i] = avgMag * 0.7 + maxMag * 0.3
        
        let freqCenter = (freqLow + freqHigh) / 2.0
        
        if freqCenter < 200 {
          bars[i] *= 1.5
        } else if freqCenter < 500 {
          bars[i] *= 1.2
        }
        
        bars[i] = tanh(bars[i] * 2.0) / 2.0
        
        bars[i] = max(0, min(1, bars[i]))
      }
    }
    
    return bars
  }
}
