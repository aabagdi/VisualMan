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
  static let shared = AudioEngineManager()
  
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  
  @Published var audioLevels: [Float] = Array(repeating: 0, count: 512)
  @Published var isPlaying = false
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 0
  @Published var isInitialized = false
  @Published var initializationError: Error?
  
  private var audioFile: AVAudioFile?
  private var displayLink: CADisplayLink?
  private var securityScopedURL: URL?
  
  init() {
    do {
      try setupAudioEngine()
      isInitialized = true
    } catch {
      initializationError = error
      isInitialized = false
      print("Failed to setup audio engine: \(error)")
    }
  }
   
  isolated deinit {
    stopDisplayLink()
    stopSecurityScopedAccess()
  }
  
  private func setupAudioEngine() throws {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      throw Errors.invalidSession
    }
    
    engine = AVAudioEngine()
    
    player = AVAudioPlayerNode()
    
    guard let engine,
          let player else { return }
    
    _ = engine.mainMixerNode
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.stop()
    
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }
  
  
  func play(_ source: AudioSource) throws {
    guard let url = source.getPlaybackURL() else {
      throw Errors.invalidURL
    }
    
    try play(from: url)
  }
  
  private func play(from url: URL) throws {
    stopSecurityScopedAccess()
    
    let accessing = url.startAccessingSecurityScopedResource()
    
    if accessing {
      securityScopedURL = url
    }
    try playAudioFromURL(url)
  }
  
  private func playAudioFromURL(_ url: URL) throws {
    guard let engine,
          let player else {
      throw Errors.nilEngineOrPlayer
    }
    
    do {
      audioFile = try AVAudioFile(forReading: url)
      
      guard let audioFile else {
        throw Errors.failedToCreateFile
      }
      
      duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
      
      engine.prepare()
      
      if !engine.isRunning {
        try engine.start()
      }
      
      player.scheduleFile(audioFile, at: nil)
      
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = true
        self?.startDisplayLink()
      }
    } catch {
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = false
        self?.stopDisplayLink()
      }
      throw Errors.failedToPlay
    }
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
      guard let channelData = buffer.floatChannelData?[0] else { return }
      
      let frameLength = Int(buffer.frameLength)
      let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
      
      Task { @MainActor in
        self?.processAudioBuffer(samples)
      }
    }
    
    player.play()
  }
  
  private func stopSecurityScopedAccess() {
    if let url = securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedURL = nil
    }
  }
  
  func pause() {
    player?.pause()
    isPlaying = false
    stopDisplayLink()
  }
  
  func resume() {
    player?.play()
    isPlaying = true
    startDisplayLink()
  }
  
  func stop() {
    player?.stop()
    engine?.mainMixerNode.removeTap(onBus: 0)
    engine?.stop()
    isPlaying = false
    currentTime = 0
    stopDisplayLink()
    stopSecurityScopedAccess()
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
    guard let nodeTime = player?.lastRenderTime,
          let playerTime = player?.playerTime(forNodeTime: nodeTime),
          let audioFile else { return }
    
    currentTime = Double(playerTime.sampleTime) / audioFile.fileFormat.sampleRate
  }
  
  private func processAudioBuffer(_ samples: [Float]) {
    var realIn = [Float](repeating: 0, count: 1024)
    var imagIn = [Float](repeating: 0, count: 1024)
    var realOut = [Float](repeating: 0, count: 1024)
    var imagOut = [Float](repeating: 0, count: 1024)
    
    for i in 0..<min(samples.count, 1024) {
      let window = 0.54 - 0.46 * cos(2.0 * .pi * Float(i) / 1023.0)
      realIn[i] = samples[i] * window
    }
    
    guard let dftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD) else { return }
    
    vDSP_DFT_Execute(dftSetup, &realIn, &imagIn, &realOut, &imagOut)
    
    var magnitudes = [Float](repeating: 0.0, count: 512)
    
    realOut.withUnsafeBufferPointer { realPtr in
      imagOut.withUnsafeBufferPointer { imagPtr in
        guard let realBase = realPtr.baseAddress,
              let imagBase = imagPtr.baseAddress else { return }
        
        var complex = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: realBase),
                                      imagp: UnsafeMutablePointer(mutating: imagBase))
        vDSP_zvabs(&complex, 1, &magnitudes, 1, 512)
      }
    }
    
    var scaleFactor: Float = 1.0 / Float(1024)
    vDSP_vsmul(magnitudes, 1, &scaleFactor, &magnitudes, 1, 512)
    
    var logMagnitudes = [Float](repeating: 0.0, count: 512)
    
    let sampleRate: Float = 44100.0
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
      
      let normalized = (db + 80.0) / 70.0
      
      logMagnitudes[i] = max(0.0, min(1.0, normalized))
    }
    
    for i in 0..<512 {
      audioLevels[i] = audioLevels[i] * 0.8 + logMagnitudes[i] * 0.2
    }
    
    vDSP_DFT_DestroySetup(dftSetup)
  }}
