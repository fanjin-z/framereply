//
//  ContentView.swift
//  FrameReply
import SwiftData
import SwiftUI

struct ContentView: View {
    let runtime: AppRuntime
    @ObservedObject private var onboardingStore: OnboardingStore
    @State private var onboardingCompletionDestination: AppTab?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        onboardingStore = runtime.onboardingStore
    }

    var body: some View {
        switch onboardingStore.presentation {
        case .none:
            FrameReplyShellView(
                runtime: runtime,
                initialTab: onboardingCompletionDestination
            )
        case .initial, .update:
            OnboardingFlowView(
                providerStore: runtime.providerStore,
                presentation: onboardingStore.presentation,
                onComplete: completeOnboarding
            )
        }
    }

    private func completeOnboarding(destination: AppTab) {
        onboardingCompletionDestination = destination
        onboardingStore.completeCurrentOnboarding()
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
