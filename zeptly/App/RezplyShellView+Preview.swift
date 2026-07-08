//
//  RezplyShellView+Preview.swift
//  zeptly
//

import SwiftData
import SwiftUI

struct RezplyShellView_Previews: PreviewProvider {
    static var previews: some View {
        RezplyShellView()
            .modelContainer(try! ZeptlyDataStore.makeContainer(inMemory: true))
            .previewDisplayName("Rezply Shell")
    }
}
