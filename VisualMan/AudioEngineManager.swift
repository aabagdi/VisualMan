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
  
  private var audioFile: AVAudioFile?
  private var displayLink: CADisplayLink?
  private var securityScopedURL: URL?
  
  init() {
    setupAudioEngine()
  }
  
  isolated deinit {
    stopDisplayLink()
    stopSecurityScopedAccess()
  }
  
  private func setupAudioEngine() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Audio session error: \(error)")
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
  
  
  func play(_ source: AudioSource) {
    guard let url = source.getPlaybackURL() else {
      print("No playback URL available for audio source")
      return
    }
    
    play(from: url)
  }
  
  private func play(from url: URL) {
    stopSecurityScopedAccess()
    
    let accessing = url.startAccessingSecurityScopedResource()
    
    if accessing {
      securityScopedURL = url
    }
    playAudioFromURL(url)
  }
  
  private func playAudioFromURL(_ url: URL) {
    guard let engine,
          let player else {
      print("engine or player node is nil")
      return
    }
    
    do {
      audioFile = try AVAudioFile(forReading: url)
      
      guard let audioFile else {
        print("Failed to create audio file")
        return
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
      print("Error playing audio: \(error)")
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = false
        self?.stopDisplayLink()
      }
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
    
    guard let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD) else { return }
    
    vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)
    
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
    for i in 0..<512 {
      let magnitude = magnitudes[i] + 1e-10
      
      let db = 20.0 * log10(magnitude)
      
      let frequencyWeight: Float
      if i < 10 {
        frequencyWeight = 0.8
      } else if i < 50 {
        frequencyWeight = 1.2
      } else if i < 150 {
        frequencyWeight = 1.5
      } else {
        frequencyWeight = 2.0
      }
      
      let normalized = ((db + 60.0) / 60.0) * frequencyWeight
      
      logMagnitudes[i] = max(0.0, min(1.0, normalized))
    }
    
    for i in 0..<512 {
      audioLevels[i] = audioLevels[i] * 0.8 + logMagnitudes[i] * 0.2
    }
    
    vDSP_DFT_DestroySetup(fftSetup)
  }
}
