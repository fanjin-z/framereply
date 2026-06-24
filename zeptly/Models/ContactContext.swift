//
//  ContactContext.swift
//  zeptly
//

import SwiftUI

struct ContactContext: Equatable {
    var relationshipSubtitle: String
    var relationshipNotes: String
    var keyFacts: [String]
    var currentInteractionGoal: String
    var preferredPersona: String

    static let empty = ContactContext(
        relationshipSubtitle: "",
        relationshipNotes: "",
        keyFacts: [],
        currentInteractionGoal: "",
        preferredPersona: "Professional"
    )
}
