import Combine
import SwiftData
import SwiftUI

@main
struct FrameReplyApp: App {
    @StateObject private var startup = AppStartupController()

    var body: some Scene {
        WindowGroup {
            startupView
        }
    }

    @ViewBuilder
    private var startupView: some View {
        switch startup.state {
        case .loading:
            ProgressView("Opening FrameReply…")
        case .ready(let container):
            ContentView()
                .modelContainer(container)
        case .failed(let message):
            DataStoreRecoveryView(
                message: message,
                onRetry: startup.retry,
                onReset: startup.resetLocalData
            )
        }
    }
}

@MainActor
final class AppStartupController: ObservableObject {
    enum State {
        case loading
        case ready(ModelContainer)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    init() {
        retry()
    }

    func retry() {
        state = .loading
        do {
            let container = try FrameReplyDataStore.prepareShared()
            try ChatRepository(container: container).seedIfNeeded()
            try PersonaRepository(container: container).seedPersonasIfNeeded()
            try FrameReplyDataStore.protectPersistentStoreFiles()
            state = .ready(container)
        } catch {
            state = .failed(
                "FrameReply could not open its protected local database. You can retry or permanently reset local chats, personas, and drafts."
            )
        }
    }

    func resetLocalData() {
        do {
            try FrameReplyDataStore.resetPersistentStore()
            retry()
        } catch {
            state = .failed(
                "FrameReply could not reset its local database. Restart the device and try again.")
        }
    }
}

private struct DataStoreRecoveryView: View {
    let message: String
    let onRetry: () -> Void
    let onReset: () -> Void

    @State private var isResetConfirmationPresented = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .medium))
            Text("Local Data Unavailable")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
            Button("Reset Local Data", role: .destructive) {
                isResetConfirmationPresented = true
            }
        }
        .padding(32)
        .confirmationDialog(
            "Permanently reset all local FrameReply data?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset Local Data", role: .destructive, action: onReset)
        } message: {
            Text("This cannot be undone.")
        }
    }
}
