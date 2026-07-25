//
//  ContentView.swift
//  FrameReply
import SwiftData
import SwiftUI

struct ContentView: View {
    let runtime: AppRuntime

    var body: some View {
        FrameReplyShellView(runtime: runtime)
    }
}

#if DEBUG
    struct ContentView_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            let runtime = try! AppRuntime.showcase()
            ContentView(runtime: runtime)
                .modelContainer(runtime.modelContainer)
        }
    }
#endif
