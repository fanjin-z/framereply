//
//  ProviderRequestLimits.swift
//  FrameReply
//

import Foundation

nonisolated enum ProviderRequestLimits {
    static let openAIConnectionCheckMaxToken = 16
    static let connectionCheckMaxToken = 64
    static let chatImportMaxToken = 8_000

    static func suggestedRepliesMaxToken(for task: SuggestedReplyTask) -> Int {
        switch task {
        case .standard, .personaStyleLearning:
            8_000
        case .drafting:
            3_200
        }
    }
}
