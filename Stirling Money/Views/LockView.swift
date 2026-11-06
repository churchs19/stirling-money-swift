import SwiftUI

/// Covers the app while it's locked.
struct LockView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Stirling Money Is Locked")
                .font(.title2.bold())
            Button("Unlock with \(AppLock.methodName)") {
                Task { await appLock.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appLock.isAuthenticating)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            await appLock.promptIfNeeded()
        }
    }
}

#Preview {
    LockView()
        .environment(AppLock())
}
