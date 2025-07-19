//
//  AudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import Foundation
import MediaPlayer

protocol AudioSource {
  var title: String? { get }
  var artist: String? { get }
  var duration: TimeInterval? { get }
  var albumArt: UIImage? { get }
  
  func getPlaybackURL() -> URL?
}
