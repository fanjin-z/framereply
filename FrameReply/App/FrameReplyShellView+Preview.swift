//
//  FrameReplyShellView+Preview.swift
//  FrameReply
//

import SwiftData
import SwiftUI

struct FrameReplyShellView_Previews: PreviewProvider {
    static var previews: some View {
        FrameReplyShellView()
            .modelContainer(try! FrameReplyDataStore.makeContainer(inMemory: true))
            .previewDisplayName("FrameReply Shell")
    }
}
