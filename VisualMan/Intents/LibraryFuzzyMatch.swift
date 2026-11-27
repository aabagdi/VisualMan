//
//  LibraryFuzzyMatch.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import Foundation
import MediaPlayer

nonisolated enum LibraryFuzzyMatch {
  static let minimumScore = 40

  static func normalized(_ text: String) -> String {
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    let replaced = folded.replacingOccurrences(of: "&", with: " and ")
    let scalars = replaced.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    return String(scalars).split(separator: " ").joined(separator: " ")
  }

  static func compact(_ text: String) -> String {
    normalized(text).replacingOccurrences(of: " ", with: "")
  }

  static func score(_ candidate: String?, against query: String) -> Int {
    guard let candidate else { return 0 }
    let target = compact(candidate)
    let wanted = compact(query)
    guard !target.isEmpty, !wanted.isEmpty else { return 0 }

    if target == wanted { return 100 }
    if wanted.count >= 4, target.hasPrefix(wanted) { return 85 }
    if target.count >= 4, wanted.hasPrefix(target) { return 75 }
    if wanted.count >= 4, target.contains(wanted) { return 70 }

    let tolerance = max(1, min(wanted.count, target.count) / 6)
    if abs(target.count - wanted.count) <= tolerance,
       editDistance(target, wanted, limit: tolerance) <= tolerance {
      return 65
    }

    let targetWords = Set(normalized(candidate).split(separator: " "))
    let wantedWords = Set(normalized(query).split(separator: " "))
    guard !wantedWords.isEmpty else { return 0 }
    let overlap = Double(targetWords.intersection(wantedWords).count) / Double(wantedWords.count)
    return overlap >= 0.6 ? Int(50 * overlap) : 0
  }

  static func songScore(_ item: MPMediaItem, title: String, artist: String?) -> Int {
    if let artist {
      let artistScore = max(score(item.artist, against: artist), score(item.albumArtist, against: artist))
      guard artistScore >= 65 else { return 0 }
      return score(item.title, against: title)
    }
    let titleScore = score(item.title, against: title)
    let combined = max(
      score("\(item.artist ?? "") \(item.title ?? "")", against: title),
      score("\(item.title ?? "") \(item.artist ?? "")", against: title)
    )
    return max(titleScore, combined >= 85 ? combined - 5 : 0)
  }

  private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
    let a = Array(lhs)
    let b = Array(rhs)
    var previous = Array(0...b.count)
    for i in 1...a.count {
      var current = [i] + Array(repeating: 0, count: b.count)
      var rowMinimum = current[0]
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        rowMinimum = min(rowMinimum, current[j])
      }
      if rowMinimum > limit { return limit + 1 }
      previous = current
    }
    return previous[b.count]
  }
}
