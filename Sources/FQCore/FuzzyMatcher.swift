import Foundation

public enum FuzzyMatcher {
  public static func rank(
    query: String,
    applications: [ApplicationCandidate]
  ) -> [ApplicationCandidate] {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else {
      return applications
    }

    let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return applications.enumerated().compactMap { offset, application in
      score(terms: terms, application: application).map {
        RankedApplication(application: application, score: $0, originalOffset: offset)
      }
    }.sorted { lhs, rhs in
      if lhs.score != rhs.score {
        return lhs.score > rhs.score
      }

      let comparison = lhs.application.name.localizedStandardCompare(rhs.application.name)
      if comparison != .orderedSame {
        return comparison == .orderedAscending
      }
      return lhs.originalOffset < rhs.originalOffset
    }.map(\.application)
  }

  private static func score(
    terms: [String],
    application: ApplicationCandidate
  ) -> Int? {
    let fields = [
      normalize(application.name),
      normalize(application.bundleIdentifier ?? ""),
      String(application.processIdentifier),
    ]

    var total = 0
    for term in terms {
      let best = fields.compactMap { score(term: term, in: $0) }.max()
      guard let best else {
        return nil
      }
      total += best
    }
    return total
  }

  private static func score(term: String, in field: String) -> Int? {
    guard !field.isEmpty else {
      return nil
    }
    if field == term {
      return 10_000
    }
    if field.hasPrefix(term) {
      return 8_000 - min(field.count - term.count, 1_000)
    }
    if let range = field.range(of: term) {
      let offset = field.distance(from: field.startIndex, to: range.lowerBound)
      return 6_000 - min(offset * 10, 2_000)
    }
    return subsequenceScore(term: term, field: field)
  }

  private static func subsequenceScore(term: String, field: String) -> Int? {
    let needle = Array(term)
    let haystack = Array(field)
    var needleIndex = 0
    var positions: [Int] = []

    for (index, character) in haystack.enumerated() where needleIndex < needle.count {
      if character == needle[needleIndex] {
        positions.append(index)
        needleIndex += 1
      }
    }

    guard needleIndex == needle.count, let first = positions.first else {
      return nil
    }

    var gaps = 0
    var consecutivePairs = 0
    for pair in zip(positions, positions.dropFirst()) {
      let distance = pair.1 - pair.0
      gaps += max(0, distance - 1)
      if distance == 1 {
        consecutivePairs += 1
      }
    }

    return 2_000 - min(first * 8 + gaps * 12, 1_500) + consecutivePairs * 30
  }

  private static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    ).lowercased()
  }
}

private struct RankedApplication {
  let application: ApplicationCandidate
  let score: Int
  let originalOffset: Int
}
