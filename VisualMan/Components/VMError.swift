//
//  VMError.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import Foundation

enum VMError: LocalizedError, Sendable {
  case invalidSession
  case invalidURL
  case nilEngineOrPlayer
  case failedToCreateFile
  case invalidBuffer
  case unableToInitialize
  case failedToPlay
  case fileAccessDenied
  case fileSelectionFailed
  case noAudioSource
  
  var errorDescription: String? {
    switch self {
    case .invalidSession: "There was an error setting up the player. Please try again."
    case .invalidURL: "There was an error loading the file. Please try again."
    case .nilEngineOrPlayer: "There was an error setting up the player. Please try again."
    case .failedToCreateFile: "There was an error loading the file. Please try again."
    case .invalidBuffer: "There was an error setting up the player. Please try again."
    case .unableToInitialize: "The player is having trouble initializing. Please try again."
    case .failedToPlay: "The player failed to play. Please try again."
    case .fileAccessDenied: "Unable to access the selected file. Please try again."
    case .fileSelectionFailed: "Failed to select the file. Please try again."
    case .noAudioSource: "No audio source is available to play."
    }
  }
}
