import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    private let relockThreshold: TimeInterval = 30
    private var backgroundedAt: Date?
    private var hasUnlockedSinceLaunch = false

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            let needsUnlock = shouldRequireUnlockOnActive
            backgroundedAt = nil

            guard needsUnlock else {
                return
            }

            isLocked = true
            requestUnlock()

        case .background:
            backgroundedAt = Date()

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    func requestUnlock() {
        guard !isAuthenticating else {
            return
        }

        let context = LAContext()
        var evaluationError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            // If the device has no biometric/passcode auth configured, avoid bricking the app.
            isLocked = false
            isAuthenticating = false
            errorMessage = nil
            hasUnlockedSinceLaunch = true
            return
        }

        isLocked = true
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                let didAuthenticate = try await evaluatePolicy(with: context)

                if didAuthenticate {
                    isLocked = false
                    errorMessage = nil
                    hasUnlockedSinceLaunch = true
                } else {
                    isLocked = true
                    errorMessage = "Unlock Split to continue."
                }
            } catch {
                isLocked = true
                errorMessage = userFacingErrorMessage(for: error)
            }

            isAuthenticating = false
        }
    }

    private var shouldRequireUnlockOnActive: Bool {
        if !hasUnlockedSinceLaunch {
            return true
        }

        guard let backgroundedAt else {
            return false
        }

        return Date().timeIntervalSince(backgroundedAt) >= relockThreshold
    }

    private func evaluatePolicy(with context: LAContext) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Split"
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        guard let authError = error as? LAError else {
            return "Unlock Split to continue."
        }

        switch authError.code {
        case .userCancel, .systemCancel, .appCancel:
            return "Unlock Split to continue."
        case .biometryLockout:
            return "Face ID is locked. Use your device passcode to unlock Split."
        case .authenticationFailed:
            return "Authentication failed. Try again."
        case .passcodeNotSet:
            return "Set a device passcode to protect Split with Face ID or Touch ID."
        default:
            return authError.localizedDescription
        }
    }
}

struct AppLockOverlay: View {
    let isAuthenticating: Bool
    let errorMessage: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color.splitAppBlack
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.splitBrandBlue.opacity(0.22),
                    Color.splitBrandPink.opacity(0.16),
                    Color.splitAppBlack.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("token_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.splitBrandPink.opacity(0.82), lineWidth: 2)
                    )
                    .shadow(color: Color.splitBrandPink.opacity(0.22), radius: 18, x: 0, y: 10)

                VStack(spacing: 10) {
                    Text("Unlock Split")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text("Use Face ID, Touch ID, or your device passcode to continue.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(Color(red: 1, green: 0.74, blue: 0.84))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onUnlock) {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }

                        Text(isAuthenticating ? "Checking Identity" : "Unlock Split")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.splitBrandPink)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.splitCardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }
}
