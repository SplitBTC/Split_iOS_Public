//
//  ToastManager.swift
//  Split Rewards
//  created 12/06/25
//
//  Global toast state for the app.
//  - Supports payment success / payment failure / generic info / error
//  - Only one toast visible at a time
//  - Each toast auto-dismisses after a short duration
//

import Foundation
import Combine

/// High-level type of toast.
/// You can extend this later for non-wallet toasts if needed.
enum ToastKind: Equatable {
    case paymentPending
    case paymentSuccess
    case paymentFailure
    case info
    case error
}

/// Direction of a payment, when the toast represents a payment event.
enum PaymentDirection: Equatable {
    case sent      // Money leaving the user’s wallet
    case received  // Money entering the user’s wallet
}

/// Model for a single toast.
struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let kind: ToastKind
    let title: String
    let subtitle: String?
    let direction: PaymentDirection?   // nil for non-payment toasts

    init(
        kind: ToastKind,
        title: String,
        subtitle: String? = nil,
        direction: PaymentDirection? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.direction = direction
    }

    var blocksInteraction: Bool {
        kind != .paymentPending
    }

    var isTapToDismissEnabled: Bool {
        kind != .paymentPending
    }
}

/// Central manager that controls which toast, if any, is visible.
@MainActor
final class ToastManager: ObservableObject {
    private let transactionBadgeLeadDuration: TimeInterval = 0.24

    /// The currently visible toast, if any.
    @Published private(set) var activeToast: AppToast?
    @Published private(set) var isTransactionBadgeHeld = false

    /// Task responsible for auto-dismissing the current toast.
    private var dismissTask: Task<Void, Never>?
    private var transactionBadgeLeadTask: Task<Void, Never>?

    deinit {
        dismissTask?.cancel()
        transactionBadgeLeadTask?.cancel()
    }

    // MARK: - Core show/hide

    /// Show a toast with full control over its fields.
    /// - Parameters:
    ///   - kind: High-level toast kind (status).
    ///   - title: Primary title text.
    ///   - subtitle: Optional subtitle text.
    ///   - direction: Optional payment direction (sent/received).
    ///   - duration: Auto-dismiss delay in seconds.
    func show(
        kind: ToastKind,
        title: String,
        subtitle: String? = nil,
        direction: PaymentDirection? = nil,
        duration: TimeInterval? = 3.0
    ) {
        // Cancel any existing auto-dismiss task when a new toast is shown.
        dismissTask?.cancel()
        dismissTask = nil

        let toast = AppToast(
            kind: kind,
            title: title,
            subtitle: subtitle,
            direction: direction
        )
        activeToast = toast

        if kind == .paymentSuccess || kind == .paymentFailure {
            holdTransactionBadgeBriefly()
        }

        // Schedule auto-dismiss after the given duration.
        guard let duration else { return }

        dismissTask = Task { [weak self] in
            // Sleep off the main actor.
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                return
            }

            // If the task wasn't cancelled, clear the toast on the main actor.
            await MainActor.run {
                guard let self else { return }
                // Only clear if the toast we're dismissing is still active.
                if self.activeToast?.id == toast.id {
                    self.activeToast = nil
                    self.dismissTask = nil
                }
            }
        }
    }

    /// Manually hide any active toast immediately.
    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        activeToast = nil
    }

    private func holdTransactionBadgeBriefly() {
        transactionBadgeLeadTask?.cancel()
        isTransactionBadgeHeld = true
        let delayNanos = UInt64(transactionBadgeLeadDuration * 1_000_000_000)

        transactionBadgeLeadTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanos)
            } catch {
                return
            }

            await MainActor.run {
                guard let self else { return }
                self.isTransactionBadgeHeld = false
                self.transactionBadgeLeadTask = nil
            }
        }
    }

    // MARK: - Convenience helpers (payment)

    /// Show a successful payment toast.
    ///
    /// - Parameters:
    ///   - direction: Payment direction. Defaults to `.sent` for backwards compatibility.
    ///   - subtitle: Optional subtitle (e.g. "+50,000 sats").
    ///   - duration: Auto-dismiss delay.
    func showPaymentSuccess(
        direction: PaymentDirection = .sent,
        subtitle: String? = nil,
        duration: TimeInterval = 3.0
    ) {
        let title: String
        switch direction {
        case .sent:
            title = "Payment sent"
        case .received:
            title = "Payment received"
        }

        show(
            kind: .paymentSuccess,
            title: title,
            subtitle: subtitle,
            direction: direction,
            duration: duration
        )
    }

    func showPaymentPending(direction: PaymentDirection = .sent) {
        show(
            kind: .paymentPending,
            title: "",
            direction: direction,
            duration: nil
        )
    }

    /// Show a failed payment toast.
    ///
    /// - Parameters:
    ///   - direction: Payment direction. Defaults to `.sent` for backwards compatibility.
    ///   - subtitle: Optional subtitle (e.g. error hint).
    ///   - duration: Auto-dismiss delay.
    func showPaymentFailure(
        direction: PaymentDirection = .sent,
        subtitle: String? = nil,
        duration: TimeInterval = 4.0
    ) {
        let title: String
        switch direction {
        case .sent:
            title = "Send failed"
        case .received:
            title = "Receive failed"
        }

        show(
            kind: .paymentFailure,
            title: title,
            subtitle: subtitle ?? "Something went wrong. Please try again.",
            direction: direction,
            duration: duration
        )
    }

    // MARK: - Convenience helpers (generic)

    func showInfo(
        title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 5.0
    ) {
        show(kind: .info, title: title, subtitle: subtitle, direction: nil, duration: duration)
    }

    func showError(
        title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 5.0
    ) {
        show(kind: .error, title: title, subtitle: subtitle, direction: nil, duration: duration)
    }
}
