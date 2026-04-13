//
//  VMError.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import Foundation

enum VMError: LocalizedError, Sendable {
  case invalidSession(underlying: (any Error & Sendable)?)
  case invalidURL
  case nilEngineOrPlayer
  case failedToCreateFile
  case unableToInitialize(underlying: (any Error & Sendable)?)
  case failedToPlay(underlying: (any Error & Sendable)?)
  case fileAccessDenied
  
  var errorDescription: String? {
    switch self {
    case .invalidSession: "There was an error setting up the player. Please try again."
    case .invalidURL: "There was an error loading the file. Please try again."
    case .nilEngineOrPlayer: "There was an error setting up the player. Please try again."
    case .failedToCreateFile: "There was an error loading the file. Please try again."
    case .unableToInitialize: "The player is having trouble initializing. Please try again."
    case .failedToPlay: "The player failed to play. Please try again."
    case .fileAccessDenied: "Unable to access the selected file. Please try again."
    }
  }
  
  var underlyingError: (any Error & Sendable)? {
    switch self {
    case .invalidSession(let e), .unableToInitialize(let e), .failedToPlay(let e): e
    default: nil
    }
  }
}
