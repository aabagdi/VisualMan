//
//  AudioEngineManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import MediaPlayer


class AudioEngineManager: ObservableObject {
  private var engine: AVAudioEngine = AVAudioEngine()
  private var playerNode: AVAudioPlayerNode = AVAudioPlayerNode()
  private var analyzer: AVAudioMixerNode = AVAudioMixerNode()

  @Published var audioLevels: [Float] = Array(repeating: 0, count: 64)
  @Published var isPlaying = false
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 0
  
  private var audioFile: AVAudioFile?
  private var displayLink: CADisplayLink?
  
  init() {
    setupAudioEngine()
  }
  
  private func setupAudioEngine() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Audio session error: \(error)")
    }
    
    engine.attach(playerNode)
    engine.attach(analyzer)
    
    engine.connect(playerNode, to: analyzer, format: nil)
    engine.connect(analyzer, to: engine.mainMixerNode, format: nil)
    
    analyzer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
      self?.processAudioBuffer(buffer)
    }
  }
  
  func play(_ mediaItem: MPMediaItem) {
    guard let assetURL = mediaItem.assetURL else {
      print("No asset URL for media item")
      return
    }
    
    stop()
    
    do {
      audioFile = try AVAudioFile(forReading: assetURL)
      guard let audioFile else {
        print("Failed to create audio file")
        return
      }
      
      duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
      
      if !engine.isRunning {
        try engine.start()
      }
      

      playerNode.scheduleFile(audioFile, at: nil)
      
      playerNode.play()

      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = true
        self?.startDisplayLink()
      }
    } catch {
      print("Error playing audio: \(error)")
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = false
        self?.stopDisplayLink()
      }
    }
  }
  
  func pause() {
    playerNode.pause()
    isPlaying = false
    stopDisplayLink()
  }
  
  func resume() {
    playerNode.play()
    isPlaying = true
    startDisplayLink()
  }
  
  func stop() {
    playerNode.stop()
    isPlaying = false
    currentTime = 0
    stopDisplayLink()
  }
  
  func startDisplayLink() {
    displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
    displayLink?.add(to: .current, forMode: .common)
  }
  
  func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }
  
  @objc func updateTime() {
    guard let nodeTime = playerNode.lastRenderTime,
          let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
          let audioFile else { return }
    
    currentTime = Double(playerTime.sampleTime) / audioFile.fileFormat.sampleRate
  }
  
  private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    
    let frameLength = Int(buffer.frameLength)
    
    let samples = channelData[0]
    
    let log2n = vDSP_Length(log2(Float(frameLength)))
    let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))
    
    var realp = [Float](repeating: 0, count: frameLength/2)
    var imagp = [Float](repeating: 0, count: frameLength/2)
    
    let windowSize = frameLength
    var window = [Float](repeating: 0, count: windowSize)
    var windowedSamples = [Float](repeating: 0, count: frameLength)
    
    vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(windowSize))
    
    windowedSamples.withUnsafeBufferPointer { samplesPtr in
      samplesPtr.baseAddress?.withMemoryRebound(to: DSPComplex.self, capacity: frameLength/2) { complexPtr in
        realp.withUnsafeMutableBufferPointer { realPtr in
          imagp.withUnsafeMutableBufferPointer { imagPtr in
            guard let realBase = realPtr.baseAddress,
                  let imagBase = imagPtr.baseAddress,
                  let fftSetup else { return }
            var output = DSPSplitComplex(realp: realBase, imagp: imagBase)
            vDSP_ctoz(complexPtr, 2, &output, 1, vDSP_Length(frameLength/2))
            vDSP_fft_zrip(fftSetup, &output, 1, log2n, Int32(FFT_FORWARD))
            
            var magnitudes = [Float](repeating: 0, count: frameLength/2)
            vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(frameLength/2))
            
            var dbs = [Float](repeating: 0, count: frameLength/2)
            var zero: Float = 1e-9
            vDSP_vdbcon(magnitudes, 1, &zero, &dbs, 1, vDSP_Length(frameLength/2), 1)
            
            let bandCount = audioLevels.count
            var bands = [Float](repeating: 0, count: bandCount)
            
            let nyquist = Float(buffer.format.sampleRate) / 2.0
            let minFreq: Float = 20.0
            let maxFreq = nyquist
            let logMinFreq = log10(minFreq)
            let logMaxFreq = log10(maxFreq)
            
            for i in 0..<bandCount {
              let logFreqStart = logMinFreq + (Float(i) / Float(bandCount)) * (logMaxFreq - logMinFreq)
              let logFreqEnd = logMinFreq + (Float(i + 1) / Float(bandCount)) * (logMaxFreq - logMinFreq)
              
              let freqStart = pow(10, logFreqStart)
              let freqEnd = pow(10, logFreqEnd)
              
              let binStart = Int((freqStart / nyquist) * Float(frameLength/2))
              let binEnd = Int((freqEnd / nyquist) * Float(frameLength/2))
              
              if binStart < frameLength/2 && binEnd <= frameLength/2 && binStart < binEnd {
                let range = binStart..<binEnd
                let sum = dbs[range].reduce(0, +)
                bands[i] = sum / Float(binEnd - binStart)
              }
            }
            
            var normalizedBands = [Float](repeating: 0, count: bandCount)
            let minDB: Float = -60.0
            let maxDB: Float = 0.0
            
            for i in 0..<bandCount {
              let clampedValue = max(minDB, min(maxDB, bands[i]))
              normalizedBands[i] = (clampedValue - minDB) / (maxDB - minDB)
            }
            
            DispatchQueue.main.async { [weak self] in
              guard let self else { return }
              
              let smoothingFactor: Float = 0.3
              for i in 0..<self.audioLevels.count {
                self.audioLevels[i] = (smoothingFactor * normalizedBands[i]) + ((1.0 - smoothingFactor) * self.audioLevels[i])
              }
            }
          }
        }
      }
    }
    print(audioLevels)
    vDSP_destroy_fftsetup(fftSetup)
  }
}
