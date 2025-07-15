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
    guard let assetURL = mediaItem.assetURL else { return }
    
    do {
      audioFile = try AVAudioFile(forReading: assetURL)
      guard let audioFile else { return }
      
      duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
      
      if !engine.isRunning {
        try engine.start()
      }
      
      playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
        DispatchQueue.main.async {
          self?.isPlaying = true
          self?.stopDisplayLink()
        }
      }
      
      playerNode.play()
      isPlaying = true
      startDisplayLink()
    } catch {
      print("Error playing audio: \(error)")
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
    
  }
}
