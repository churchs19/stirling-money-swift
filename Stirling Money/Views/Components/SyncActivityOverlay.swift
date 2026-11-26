import SwiftUI

/// Covers the app while a long sync runs, so the user knows it's working: the first sync on a device, or fetching a
/// book someone shared. Appears only after a moment, so quick syncs don't flash it, and can be sent to the
/// background.
struct SyncActivityOverlay: View {
    let activity: SyncStatus.Activity?
    /// Hides the overlay; the sync carries on.
    var dismiss: () -> Void = {}

    @State private var isShown = false

    var body: some View {
        ZStack {
            if let activity, isShown {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                card(for: activity)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShown && activity != nil)
        .task(id: activity) {
            isShown = false
            guard activity != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            isShown = !Task.isCancelled
        }
    }

    private func card(for activity: SyncStatus.Activity) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(title(for: activity))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail(for: activity))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Continue in Background", action: dismiss)
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("syncActivity")
    }

    private func title(for activity: SyncStatus.Activity) -> String {
        switch activity {
        case .firstSync:
            String(localized: "Getting your books from iCloud…")
        case let .joining(name?):
            String(localized: "Adding \(name)…")
        case .joining(nil):
            String(localized: "Adding the shared book…")
        }
    }

    private func detail(for activity: SyncStatus.Activity) -> String {
        switch activity {
        case .firstSync:
            String(localized: "This can take a minute the first time. Anything you add now is kept and synced too.")
        case .joining:
            String(localized: "Its accounts and transactions are on their way. It opens when they've arrived.")
        }
    }
}

/// Shows `status.activity`, and hides it when sent to the background (the sync carries on).
struct SyncActivityHost: View {
    let status: SyncStatus

    var body: some View {
        SyncActivityOverlay(activity: status.activity) {
            status.activity = nil
        }
    }
}

#Preview("First Sync") {
    Color.gray.opacity(0.2)
        .overlay { SyncActivityOverlay(activity: .firstSync) }
}

#Preview("Joining") {
    Color.gray.opacity(0.2)
        .overlay { SyncActivityOverlay(activity: .joining(bookName: "Home")) }
}
