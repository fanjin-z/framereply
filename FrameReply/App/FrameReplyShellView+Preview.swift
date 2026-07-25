#if DEBUG
    //
    //  FrameReplyShellView+Preview.swift
    //  FrameReply
    //

    import SwiftData
    import SwiftUI

    struct FrameReplyShellView_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            let runtime = try! AppRuntime.showcase()
            FrameReplyShellView(runtime: runtime)
                .modelContainer(runtime.modelContainer)
                .previewDisplayName("FrameReply Shell")
        }
    }
#endif
