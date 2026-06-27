//
//  RezplyShellView+Preview.swift
//  zeptly
//

import SwiftUI
import SwiftData

struct RezplyShellView_Previews: PreviewProvider {
    static var previews: some View {
        RezplyShellView()
            .modelContainer(try! ZeptlyDataStore.makeContainer(inMemory: true))
            .previewDisplayName("Rezply Shell")
    }
}
