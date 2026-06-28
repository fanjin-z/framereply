import Foundation

struct TranscriptMessage: Equatable, Sendable {
    let sender: String
    let normalizedText: String
    let normalizedTime: String
}

struct TranscriptMatch: Equatable, Sendable {
    let existingIndex: Int
    let importedIndex: Int
    let score: Double
    let isExact: Bool
}

struct TranscriptAlignment: Equatable, Sendable {
    let matches: [TranscriptMatch]
    let score: Double
}

enum TranscriptEvidenceLevel: String, Equatable, Sendable {
    case none
    case weak
    case strong
}

enum ChatTranscriptAligner {
    static func align(
        existing: [TranscriptMessage],
        imported: [TranscriptMessage],
        documentFrequency: [String: Int] = [:]
    ) -> TranscriptAlignment {
        guard !existing.isEmpty, !imported.isEmpty else {
            return TranscriptAlignment(matches: [], score: 0)
        }

        var edges: [AlignmentEdge] = []
        for existingIndex in existing.indices {
            for importedIndex in imported.indices {
                guard let edge = edge(
                    existing: existing[existingIndex],
                    imported: imported[importedIndex],
                    existingIndex: existingIndex,
                    importedIndex: importedIndex,
                    documentFrequency: documentFrequency
                ) else {
                    continue
                }
                edges.append(edge)
            }
        }

        guard !edges.isEmpty else {
            return TranscriptAlignment(matches: [], score: 0)
        }
        edges.sort {
            if $0.existingIndex == $1.existingIndex {
                return $0.importedIndex < $1.importedIndex
            }
            return $0.existingIndex < $1.existingIndex
        }

        var bestScores = edges.map(\.score)
        var matchCounts = Array(repeating: 1, count: edges.count)
        var previous = Array<Int?>(repeating: nil, count: edges.count)

        for index in edges.indices {
            for prior in 0..<index where edges[prior].existingIndex < edges[index].existingIndex
                && edges[prior].importedIndex < edges[index].importedIndex
            {
                let candidateScore = bestScores[prior] + edges[index].score
                let candidateCount = matchCounts[prior] + 1
                if candidateScore > bestScores[index]
                    || (candidateScore == bestScores[index] && candidateCount > matchCounts[index])
                {
                    bestScores[index] = candidateScore
                    matchCounts[index] = candidateCount
                    previous[index] = prior
                }
            }
        }

        let bestIndex = bestScores.indices.max {
            if bestScores[$0] == bestScores[$1] {
                return matchCounts[$0] < matchCounts[$1]
            }
            return bestScores[$0] < bestScores[$1]
        }!
        var chain: [TranscriptMatch] = []
        var cursor: Int? = bestIndex
        while let index = cursor {
            let edge = edges[index]
            chain.append(
                TranscriptMatch(
                    existingIndex: edge.existingIndex,
                    importedIndex: edge.importedIndex,
                    score: edge.score,
                    isExact: edge.isExact
                )
            )
            cursor = previous[index]
        }

        return TranscriptAlignment(matches: chain.reversed(), score: bestScores[bestIndex])
    }

    static func identityEvidence(
        imported: [TranscriptMessage],
        candidate: [TranscriptMessage],
        allCandidates: [[TranscriptMessage]]
    ) -> TranscriptEvidenceLevel {
        let frequencies = documentFrequencies(allCandidates)
        let alignment = align(existing: candidate, imported: imported, documentFrequency: frequencies)
        guard !alignment.matches.isEmpty else { return .none }

        let uniqueMatches = alignment.matches.filter { match in
            let message = candidate[match.existingIndex]
            return frequencies[fingerprint(message)] == 1 && match.isExact
        }
        let hasTimestampedIncoming = uniqueMatches.contains { match in
            let message = candidate[match.existingIndex]
            return isIncoming(message.sender) && !message.normalizedTime.isEmpty
        }
        if hasTimestampedIncoming {
            return .strong
        }
        if uniqueMatches.count >= 2,
            uniqueMatches.contains(where: { isIncoming(candidate[$0.existingIndex].sender) })
        {
            return .strong
        }
        return .weak
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        let left = Array(lhs)
        let right = Array(rhs)
        let longestCount = max(left.count, right.count)
        guard longestCount > 0 else { return 1 }

        var previous = Array(0...right.count)
        for (leftOffset, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftOffset + 1
            for (rightOffset, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightOffset + 1] = min(
                    current[rightOffset] + 1,
                    previous[rightOffset + 1] + 1,
                    previous[rightOffset] + substitutionCost
                )
            }
            previous = current
        }
        return 1 - (Double(previous[right.count]) / Double(longestCount))
    }

    static func fingerprint(_ message: TranscriptMessage) -> String {
        [message.sender, message.normalizedText].joined(separator: "\u{1F}")
    }

    private static func documentFrequencies(_ candidates: [[TranscriptMessage]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for candidate in candidates {
            for key in Set(candidate.map { fingerprint($0) }) {
                result[key, default: 0] += 1
            }
        }
        return result
    }

    private static func edge(
        existing: TranscriptMessage,
        imported: TranscriptMessage,
        existingIndex: Int,
        importedIndex: Int,
        documentFrequency: [String: Int]
    ) -> AlignmentEdge? {
        guard existing.sender == imported.sender else { return nil }
        let bothHaveTime = !existing.normalizedTime.isEmpty && !imported.normalizedTime.isEmpty
        guard !bothHaveTime || existing.normalizedTime == imported.normalizedTime else { return nil }

        let exact = existing.normalizedText == imported.normalizedText
        if !exact {
            guard bothHaveTime,
                existing.normalizedText.count >= 24,
                imported.normalizedText.count >= 24,
                similarity(existing.normalizedText, imported.normalizedText) >= 0.97
            else {
                return nil
            }
        }

        var score = exact ? 3.0 : 1.5
        score += isIncoming(existing.sender) ? 3 : 0.5
        if bothHaveTime { score += 2 }
        score += min(3, Double(existing.normalizedText.count) / 24)
        if documentFrequency[fingerprint(existing)] == 1 { score += 3 }

        return AlignmentEdge(
            existingIndex: existingIndex,
            importedIndex: importedIndex,
            score: score,
            isExact: exact
        )
    }

    private static func isIncoming(_ sender: String) -> Bool {
        sender == "contact" || sender.hasPrefix("other:")
    }
}

private struct AlignmentEdge {
    let existingIndex: Int
    let importedIndex: Int
    let score: Double
    let isExact: Bool
}
