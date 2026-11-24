//
//  HapticsManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/23/26.
//

import Foundation
import CoreHaptics
import AVFoundation

final class HapticsManager {
  private let hapticEngine: CHHapticEngine?
  
  private init() throws {
    hapticEngine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
    
    try hapticEngine?.start()
  }
}
