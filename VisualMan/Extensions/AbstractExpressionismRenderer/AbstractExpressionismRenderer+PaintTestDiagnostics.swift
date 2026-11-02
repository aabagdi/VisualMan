//
//  AbstractExpressionismRenderer+PaintTestDiagnostics.swift
//  VisualMan
//
//  Created on 11/2/26.
//

#if !targetEnvironment(simulator)
import Foundation

extension AbstractExpressionismRenderer {
  static let paintTestDebugMode: Int = {
    guard let raw = UserDefaults.standard.string(forKey: "AbExPaintTestDebug")?
            .trimmingCharacters(in: .whitespaces).lowercased() else { return 0 }
    switch raw {
    case "black", "1": return 1
    case "alpha", "2": return 2
    default: return 0
    }
  }()
}

#endif
