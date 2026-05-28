//
//  SendPaymentFlowView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import SwiftUI
import Foundation
import UIKit
import Vision
import ImageIO
import CoreImage
import PhotosUI

struct SendPaymentFlowView: View {
    enum StartMode {
        case scan
        case entry(prefilledRecipientInput: String)
    }

    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @Environment(\.dismiss) private var dismiss

    let startMode: StartMode
    let prefilledLnurlComment: String?
    let onExitFlow: (() -> Void)?

    @State private var stage: Stage
    @State private var recipientInput: String
    @State private var normalizedRequest: String
    @State private var amountText: String = ""
    @State private var presetAmountSats: UInt64? = nil
    @State private var isAmountLocked = false
    @State private var isSendMaxAmount = false
    @State private var amountUnit: AmountUnit = .usd
    @State private var isPreparing = false
    @State private var statusMessage: String?
    @State private var paymentPreview: WalletManager.PaymentPreview?
    @State private var scannedContactPayload: SplitContactPayload?
    @State private var showContactPicker = false
    @State private var contacts: [WalletManager.WalletContact] = []
    @State private var isLoadingContacts = false
    @State private var contactsErrorMessage: String?
    @State private var shouldReturnToEntryAfterScan = false
    @State private var selectedQRCodeImageItem: PhotosPickerItem?
    @State private var keyboardHeight: CGFloat = 0

    @FocusState private var focusedField: Field?

    private enum Stage: Equatable {
        case scan
        case entry
        case review
    }

    private enum Field {
        case recipient
        case amount
    }

    private enum AmountUnit: String, CaseIterable {
        case usd = "USD"
        case sats = "Sats"
    }

    private struct QuickAmountOption: Identifiable {
        let id: String
        let label: String
        let rawValue: String
    }

    init(
        startMode: StartMode,
        prefilledLnurlComment: String? = nil,
        onExitFlow: (() -> Void)? = nil
    ) {
        self.startMode = startMode
        self.prefilledLnurlComment = prefilledLnurlComment
        self.onExitFlow = onExitFlow

        switch startMode {
        case .scan:
            _stage = State(initialValue: .scan)
            _recipientInput = State(initialValue: "")
            _normalizedRequest = State(initialValue: "")
        case .entry(let prefilledRecipientInput):
            _stage = State(initialValue: .entry)
            _recipientInput = State(initialValue: prefilledRecipientInput)
            _normalizedRequest = State(initialValue: prefilledRecipientInput)
        }
    }

    var body: some View {
        Group {
            switch stage {
            case .scan:
                scanStage
            case .entry:
                entryStage
            case .review:
                reviewStage
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $scannedContactPayload) { payload in
            NavigationStack {
                CreateContactView(
                    paymentIdentifier: payload.lightningAddress,
                    prefilledName: payload.suggestedName,
                    onSaved: {
                        scannedContactPayload = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            exitFlow()
                        }
                    }
                )
            }
            .environmentObject(walletManager)
        }
        .sheet(isPresented: $showContactPicker) {
            SendContactPickerSheet(
                contacts: contacts,
                isLoading: isLoadingContacts,
                errorMessage: contactsErrorMessage,
                onSelect: selectContact,
                onRetry: {
                    Task { await loadContactsForPicker(forceReload: true) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: amountUnit) { _, _ in
            guard stage == .entry else { return }

            if isSendMaxAmount {
                syncSendMaxAmountDisplay()
            } else if !isAmountLocked {
                amountText = ""
            } else {
                syncLockedAmountDisplay()
            }
        }
        .onChange(of: amountText) { _, newValue in
            guard stage == .entry, !isAmountLocked else { return }
            let sanitized = sanitizeAmountText(newValue, for: amountUnit)
            if sanitized != newValue {
                amountText = sanitized
            }
        }
        .task {
            guard stage == .entry,
                  !recipientInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            updateNormalizedRequest(from: recipientInput)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    private var scanStage: some View {
        ZStack(alignment: .top) {
            QRCodeScannerView(preferredZoomFactor: 1.6, onCodeScanned: handleScannedCode)
                .ignoresSafeArea()

            HStack {
                Button(action: handleScanClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close scanner")

                Spacer()

                PhotosPicker(
                    selection: $selectedQRCodeImageItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose QR code image")
                .disabled(isPreparing)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            if isPreparing {
                preparationOverlay
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: selectedQRCodeImageItem) { _, item in
            guard let item else { return }
            Task { await handleSelectedQRCodeImageItem(item) }
        }
    }

    private var entryStage: some View {
        ZStack {
            Color.splitAppBlack
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Send Bitcoin")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        HStack(spacing: 10) {
                            entryHeaderButton(
                                systemName: "qrcode.viewfinder",
                                accessibilityLabel: "Scan QR",
                                action: openScannerFromEntry
                            )

                            entryHeaderButton(
                                systemName: "xmark",
                                accessibilityLabel: "Close send flow",
                                action: exitFlow
                            )
                        }
                    }

                    recipientSection
                    amountSection

                    if let status = statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(status.lowercased().contains("failed") ? .red : .gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 132)
            }
            .scrollDismissesKeyboard(.interactively)

            if isPreparing {
                preparationOverlay
            }
        }
        .overlay(alignment: .bottom) {
            entryBottomBar
        }
        .overlay(alignment: .bottomTrailing) {
            keyboardDoneButton
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var reviewStage: some View {
        if let paymentPreview {
            SendPaymentReviewView(
                preview: paymentPreview,
                onExitFlow: { completeAndExitFlow() }
            )
            .environmentObject(walletManager)
            .environmentObject(authManager)
            .environmentObject(lndWalletManager)
            .environmentObject(coreLightningWalletManager)
            .environmentObject(eclairWalletManager)
            .environmentObject(sparkSubwalletManager)
        } else {
            ZStack {
                Color.black.opacity(0.97)
                    .ignoresSafeArea()

                Text("No payment details available.")
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }

    private var preparationOverlay: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading payment details…")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
    }

    private func entryHeaderButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.82))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipient address")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))

            ZStack(alignment: .topLeading) {
                if recipientInput.isEmpty {
                    Text("Lightning address, invoice, Bitcoin address, or QR code image")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.24))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $recipientInput)
                    .focused($focusedField, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(height: 130)
                    .onChange(of: recipientInput) { _, newValue in
                        updateNormalizedRequest(from: newValue)
                    }

                VStack {
                    Spacer()

                    HStack {
                        Button(action: openContactPicker) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Contacts")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white.opacity(0.84))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.62))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose contact")

                        Spacer(minLength: 8)

                        Button(action: pasteFromClipboard) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Paste")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white.opacity(0.84))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.62))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Paste address or invoice")
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Amount")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.62))

                Spacer()

                if isAmountLocked {
                    Text("Locked")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if amountUnit == .usd {
                    Text("$")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }

                ZStack(alignment: .leading) {
                    if amountText.isEmpty {
                        Text(amountPlaceholder)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.20))
                    }

                    TextField("", text: $amountText)
                        .focused($focusedField, equals: .amount)
                        .keyboardType(amountUnit == .usd ? .decimalPad : .numberPad)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .onTapGesture {
                            isSendMaxAmount = false
                        }
                }

                if amountUnit == .sats {
                    Text("sats")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture {
                guard !isAmountLocked else { return }
                isSendMaxAmount = false
                focusedField = .amount
            }
            .disabled(isAmountLocked)

            amountUnitToggle
                .padding(.top, 2)

            if !isAmountLocked {
                quickAmountChips
            }

            Text(isAmountLocked ? lockedAmountHelperText : amountHelperText)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.62))
        }
    }

    private var amountUnitToggle: some View {
        HStack(spacing: 10) {
            unitButton(.usd)
            unitButton(.sats)
        }
        .disabled(isAmountLocked)
        .opacity(isAmountLocked ? 0.7 : 1.0)
    }

    private func unitButton(_ unit: AmountUnit) -> some View {
        let isSelected = (amountUnit == unit)

        return Button(action: {
            guard !isSelected else { return }
            amountUnit = unit
        }) {
            Text(unit.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.84))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var quickAmountChips: some View {
        HStack(spacing: 10) {
            ForEach(quickAmounts) { option in
                Button {
                    isSendMaxAmount = false
                    amountText = option.rawValue
                    focusedField = nil
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: applySendMaxAmount) {
                Text("Max")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSendMaxAmount ? .white : Color.splitBrandBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSendMaxAmount ? Color.splitBrandBlue : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSendMaxAmount ? Color.clear : Color.splitBrandBlue.opacity(0.55), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPreparing)
            .opacity(isPreparing ? 0.6 : 1.0)
        }
    }

    private var entryBottomBar: some View {
        VStack(spacing: 12) {
            Button(action: continueTapped) {
                HStack(spacing: 8) {
                    Spacer()
                    if isPreparing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                        Text("Continue")
                            .font(.headline.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canContinueEntry ? Color.splitBrandBlue : Color.white.opacity(0.12))
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canContinueEntry)

            Button(action: exitFlow) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .disabled(isPreparing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            Color.splitAppBlack
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private var keyboardDoneButton: some View {
        if focusedField != nil && keyboardHeight > 0 {
            Button(action: dismissKeyboard) {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, keyboardHeight + 10)
        }
    }

    private var amountPlaceholder: String {
        switch amountUnit {
        case .usd: return "0.00"
        case .sats: return "1000"
        }
    }

    private var canContinueEntry: Bool {
        !isPreparing && !normalizedRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var quickAmounts: [QuickAmountOption] {
        switch amountUnit {
        case .usd:
            return [
                QuickAmountOption(id: "usd-5", label: "$5", rawValue: "5"),
                QuickAmountOption(id: "usd-10", label: "$10", rawValue: "10"),
                QuickAmountOption(id: "usd-25", label: "$25", rawValue: "25")
            ]
        case .sats:
            return [
                QuickAmountOption(id: "sats-1000", label: "1k sats", rawValue: "1000"),
                QuickAmountOption(id: "sats-10000", label: "10k sats", rawValue: "10000"),
                QuickAmountOption(id: "sats-50000", label: "50k sats", rawValue: "50000")
            ]
        }
    }

    private var amountHelperText: String {
        if isSendMaxAmount {
            return "Max uses your available balance. Fees are deducted from that amount."
        }

        if isAmountlessInvoiceEntry {
            return "This blank Lightning invoice needs an amount before you can pay it."
        }

        return "Some recipients (LNURL / Lightning addresses) require you to enter an amount."
    }

    private var isAmountlessInvoiceEntry: Bool {
        isAmountlessBolt11PaymentRequest(normalizedRequest)
    }

    private var lockedAmountHelperText: String {
        return "This request includes a fixed amount."
    }

    private func sanitizeAmountText(_ value: String, for unit: AmountUnit) -> String {
        switch unit {
        case .sats:
            let digits = value.filter { $0.isWholeNumber }
            return String(digits.drop(while: { $0 == "0" }))
        case .usd:
            var result = ""
            var hasDecimalSeparator = false
            var decimalCount = 0

            for character in value {
                if character.isWholeNumber {
                    if hasDecimalSeparator {
                        guard decimalCount < 2 else { continue }
                        decimalCount += 1
                    }
                    result.append(character)
                } else if character == ".", !hasDecimalSeparator {
                    hasDecimalSeparator = true
                    result.append(character)
                }
            }

            if result == "." {
                return "0."
            }

            return result
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        return frame.height
    }

    private func exitFlow() {
        if let onExitFlow {
            onExitFlow()
        } else {
            dismiss()
        }
    }

    private func completeAndExitFlow() {
        paymentPreview = nil
        exitFlow()
    }

    private func handleScanClose() {
        if shouldReturnToEntryAfterScan {
            statusMessage = nil
            shouldReturnToEntryAfterScan = false
            stage = .entry
        } else {
            exitFlow()
        }
    }

    private func openScannerFromEntry() {
        dismissKeyboard()
        statusMessage = nil
        shouldReturnToEntryAfterScan = true
        stage = .scan
    }

    private func showEntryStage(
        with paymentRequest: String,
        resetAmount: Bool = false,
        focusedField nextFocusedField: Field? = nil
    ) {
        recipientInput = paymentRequest
        if resetAmount {
            amountText = ""
            presetAmountSats = nil
            isAmountLocked = false
            isSendMaxAmount = false
        }
        updateNormalizedRequest(from: paymentRequest)
        statusMessage = nil
        shouldReturnToEntryAfterScan = false
        stage = .entry

        if let nextFocusedField {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.focusedField = nextFocusedField
            }
        }
    }

    private func showReviewStage(with preview: WalletManager.PaymentPreview) {
        statusMessage = nil
        isPreparing = true

        Task {
            let checkedPreview = await previewWithRewardsCheck(preview)

            await MainActor.run {
                self.paymentPreview = checkedPreview
                self.isPreparing = false
                self.stage = .review
            }
        }
    }

    @MainActor
    private func previewWithRewardsCheck(_ preview: WalletManager.PaymentPreview) async -> WalletManager.PaymentPreview {
        let rewardsMetadata = await rewardsDestinationMetadata(for: preview)
        guard let destinationPubkey = rewardsMetadata.destinationPubkey else {
            return copyPreview(preview, rewardEligible: false)
        }

        do {
            let response = try await localRewardsCheck(destinationPubkey: destinationPubkey)

            return copyPreview(
                preview,
                rewardEligible: response.rewardEligible,
                destinationPubkey: destinationPubkey,
                paymentHash: rewardsMetadata.paymentHash,
                merchantPubkeyHash: response.merchantPubkeyHash
            )
        } catch {
            print("Rewards check failed: \(error.localizedDescription)")
            return copyPreview(preview, rewardEligible: false)
        }
    }

    private func rewardsDestinationMetadata(
        for preview: WalletManager.PaymentPreview
    ) async -> (destinationPubkey: String?, paymentHash: String?) {
        if let destinationPubkey = preview.destinationPubkey?.nilIfBlank {
            return (destinationPubkey, preview.paymentHash?.nilIfBlank)
        }

        let localMetadata = NWCBolt11MetadataDecoder.decode(preview.paymentRequest)
        func mergedMetadata(
            destinationPubkey: String?,
            paymentHash: String?
        ) -> (destinationPubkey: String?, paymentHash: String?) {
            (
                destinationPubkey?.nilIfBlank ?? localMetadata?.destinationPubkey?.nilIfBlank,
                paymentHash?.nilIfBlank ?? localMetadata?.paymentHash?.nilIfBlank
            )
        }

        switch preview.backend {
        case .spark:
            if let metadata = await walletManager.decodeBolt11InvoiceMetadata(preview.paymentRequest) {
                return mergedMetadata(
                    destinationPubkey: metadata.destinationPubkey,
                    paymentHash: metadata.paymentHash
                )
            }
        case .sparkSubwallet:
            if let metadata = await sparkSubwalletManager.decodeBolt11InvoiceMetadata(preview.paymentRequest) {
                return mergedMetadata(
                    destinationPubkey: metadata.destinationPubkey,
                    paymentHash: metadata.paymentHash
                )
            }
        case .lnd:
            if let decoded = try? await lndWalletManager.decodeInvoice(preview.paymentRequest) {
                return mergedMetadata(
                    destinationPubkey: decoded.destination,
                    paymentHash: decoded.paymentHash
                )
            }
        case .nwc:
            if let localMetadata {
                return (
                    localMetadata.destinationPubkey?.nilIfBlank,
                    localMetadata.paymentHash?.nilIfBlank
                )
            }
        case .coreLightning:
            if let decoded = try? await coreLightningWalletManager.decodeInvoice(preview.paymentRequest) {
                return mergedMetadata(
                    destinationPubkey: decoded.payee,
                    paymentHash: decoded.paymentHash
                )
            }
        case .eclair:
            if let decoded = try? await eclairWalletManager.decodeInvoice(preview.paymentRequest) {
                return mergedMetadata(
                    destinationPubkey: decoded.nodeId,
                    paymentHash: decoded.paymentHash
                )
            }
        }

        if let localMetadata {
            return (
                localMetadata.destinationPubkey?.nilIfBlank,
                localMetadata.paymentHash?.nilIfBlank
            )
        }

        return (nil, preview.paymentHash?.nilIfBlank)
    }

    private func copyPreview(
        _ preview: WalletManager.PaymentPreview,
        rewardEligible: Bool,
        destinationPubkey: String? = nil,
        paymentHash: String? = nil,
        merchantPubkeyHash: String? = nil
    ) -> WalletManager.PaymentPreview {
        WalletManager.PaymentPreview(
            id: preview.id,
            backend: preview.backend,
            paymentRequest: preview.paymentRequest,
            amountSats: preview.amountSats,
            amountFiatUSD: preview.amountFiatUSD,
            routingFeeSats: preview.routingFeeSats,
            feesIncluded: preview.feesIncluded,
            recipientName: preview.recipientName,
            lndAmountOverrideSats: preview.lndAmountOverrideSats,
            destinationPubkey: destinationPubkey?.nilIfBlank ?? preview.destinationPubkey,
            paymentHash: paymentHash?.nilIfBlank ?? preview.paymentHash,
            merchantPubkeyHash: merchantPubkeyHash?.nilIfBlank ?? preview.merchantPubkeyHash,
            rewardEligible: rewardEligible
        )
    }

    private func handleScannedCode(_ code: String) {
        handleIncomingPaymentCode(
            code,
            invalidMessage: "Couldn’t read a supported payment or contact QR."
        )
    }

    private func handleIncomingPaymentCode(_ code: String, invalidMessage: String) {
        if let payload = SplitContactPayload.parse(from: code) {
            handleScannedContactPayload(payload)
            return
        }

        guard let normalized = normalizePaymentRequest(from: code) else {
            statusMessage = invalidMessage
            return
        }

        if shouldOpenEntryFirstSendFlow(for: normalized) {
            showEntryStage(with: normalized, resetAmount: true, focusedField: .amount)
            return
        }

        preparePaymentForReview(paymentRequest: normalized, amountSatsOverride: nil, allowEntryFallback: true)
    }

    private func pasteFromClipboard() {
        dismissKeyboard()
        statusMessage = nil

        guard let clipboardRaw = UIPasteboard.general.string,
              !clipboardRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Clipboard is empty or doesn’t contain text."
            return
        }

        handleIncomingPaymentCode(
            clipboardRaw,
            invalidMessage: "Clipboard text doesn’t contain a supported payment or contact code."
        )
    }

    private func openContactPicker() {
        dismissKeyboard()
        statusMessage = nil
        showContactPicker = true

        Task {
            await loadContactsForPicker()
        }
    }

    @MainActor
    private func loadContactsForPicker(forceReload: Bool = false) async {
        if isLoadingContacts { return }
        if !forceReload && !contacts.isEmpty { return }

        isLoadingContacts = true
        contactsErrorMessage = nil

        do {
            let loaded = try await walletManager.listContacts()
            contacts = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            contactsErrorMessage = error.localizedDescription
        }

        isLoadingContacts = false
    }

    private func selectContact(_ contact: WalletManager.WalletContact) {
        let paymentIdentifier = contact.paymentIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paymentIdentifier.isEmpty else { return }

        recipientInput = paymentIdentifier
        updateNormalizedRequest(from: paymentIdentifier)
        statusMessage = nil
        showContactPicker = false
    }

    @MainActor
    private func handleSelectedQRCodeImageItem(_ item: PhotosPickerItem) async {
        statusMessage = nil

        defer {
            selectedQRCodeImageItem = nil
        }

        let image: UIImage
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let loadedImage = UIImage(data: data) else {
                statusMessage = "Couldn’t read the selected image."
                return
            }
            image = loadedImage
        } catch {
            statusMessage = "Couldn’t read the selected image."
            return
        }

        var qrPayloads: [String] = []
        var seenPayloads = Set<String>()
        for payload in qrCodeStrings(from: image) where seenPayloads.insert(payload).inserted {
            qrPayloads.append(payload)
        }

        if qrPayloads.count > 1 {
            statusMessage = "Multiple QR codes found. Choose an image with one QR code."
            return
        }

        guard let qrPayload = qrPayloads.first else {
            statusMessage = "No QR code found in this image."
            return
        }

        handleIncomingPaymentCode(
            qrPayload,
            invalidMessage: "Selected QR code image doesn’t contain a supported payment or contact code."
        )
    }

    private func qrCodeStrings(from image: UIImage) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        for candidate in qrDecodeImageCandidates(from: image) {
            let payloads = visionQRCodeStrings(from: candidate) + coreImageQRCodeStrings(from: candidate)
            for payload in payloads where seen.insert(payload).inserted {
                results.append(payload)
            }
        }

        return results
    }

    private func visionQRCodeStrings(from image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? [])
            .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func coreImageQRCodeStrings(from image: UIImage) -> [String] {
        guard let ciImage = CIImage(image: image),
              let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              ) else {
            return []
        }

        return detector.features(in: ciImage)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func qrDecodeImageCandidates(from image: UIImage) -> [UIImage] {
        var candidates: [UIImage] = [image]

        for crop in heuristicQRCrops(from: image) {
            candidates.append(crop)

            if let contrasted = highContrastImage(from: crop) {
                candidates.append(contrasted)
            }

            if let bordered = imageWithWhiteBorder(crop, borderRatio: 0.08) {
                candidates.append(bordered)
            }
        }

        if let contrasted = highContrastImage(from: image) {
            candidates.append(contrasted)
        }

        return candidates
    }

    private func heuristicQRCrops(from image: UIImage) -> [UIImage] {
        guard let cgImage = image.cgImage else { return [] }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return [] }

        let cropSpecs: [(xRatio: CGFloat, yRatio: CGFloat, sizeRatio: CGFloat)] = [
            (0.04, 0.12, 0.92),
            (0.03, 0.10, 0.94),
            (0.02, 0.08, 0.96),
            (0.00, 0.00, 1.00)
        ]

        var crops: [UIImage] = []
        var seenRects = Set<String>()

        for spec in cropSpecs {
            let cropSize = min(width * spec.sizeRatio, height)
            let originX = min(max(0, width * spec.xRatio), max(0, width - cropSize))
            let originY = min(max(0, height * spec.yRatio), max(0, height - cropSize))
            let rect = CGRect(
                x: originX.rounded(.down),
                y: originY.rounded(.down),
                width: cropSize.rounded(.down),
                height: cropSize.rounded(.down)
            )

            let key = "\(Int(rect.origin.x)):\(Int(rect.origin.y)):\(Int(rect.width)):\(Int(rect.height))"
            guard seenRects.insert(key).inserted,
                  rect.width > 120,
                  rect.height > 120,
                  let crop = cgImage.cropping(to: rect) else {
                continue
            }

            crops.append(UIImage(cgImage: crop, scale: image.scale, orientation: .up))
        }

        return crops
    }

    private func highContrastImage(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let filtered = ciImage
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 2.8,
                    kCIInputBrightnessKey: 0
                ]
            )
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.8])

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private func imageWithWhiteBorder(_ image: UIImage, borderRatio: CGFloat) -> UIImage? {
        guard borderRatio > 0 else { return image }

        let border = max(16, min(image.size.width, image.size.height) * borderRatio)
        let canvasSize = CGSize(
            width: image.size.width + border * 2,
            height: image.size.height + border * 2
        )

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: CGRect(
                x: border,
                y: border,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    private func updateNormalizedRequest(from raw: String) {
        statusMessage = nil

        let normalized = normalizePaymentRequest(from: raw)
        let hadLockedAmount = isAmountLocked
        normalizedRequest = normalized ?? ""
        presetAmountSats = nil
        isAmountLocked = false
        if hadLockedAmount {
            amountText = ""
            isSendMaxAmount = false
        }

        guard let normalized, !normalized.isEmpty else {
            return
        }

        if activeSpendWalletStore.isLndActive {
            guard LNDLightningPaymentResolver.isBolt11(normalized) else {
                return
            }

            Task {
                if !lndWalletManager.isConnected {
                    try? await lndWalletManager.restoreActiveNode()
                }

                let decoded = try? await lndWalletManager.decodeInvoice(normalized)
                let sats: UInt64? = {
                    guard let amountSats = decoded?.amountSats, amountSats > 0 else {
                        return nil
                    }

                    return UInt64(amountSats)
                }()

                await MainActor.run {
                    guard self.normalizedRequest == normalized else { return }

                    self.presetAmountSats = sats
                    if let sats, sats > 0 {
                        self.isAmountLocked = true
                        self.isSendMaxAmount = false
                        self.syncLockedAmountDisplay()
                    } else {
                        self.isAmountLocked = false
                    }
                }
            }
            return
        }

        if activeSpendWalletStore.isCoreLightningActive {
            guard LNDLightningPaymentResolver.isBolt11(normalized) else {
                return
            }

            Task {
                if !coreLightningWalletManager.isConnected {
                    try? await coreLightningWalletManager.restoreActiveNode()
                }

                let decoded = try? await coreLightningWalletManager.decodeInvoice(normalized)
                let sats: UInt64? = {
                    guard let amountSats = decoded?.amountSats, amountSats > 0 else {
                        return nil
                    }

                    return UInt64(amountSats)
                }()

                await MainActor.run {
                    guard self.normalizedRequest == normalized else { return }

                    self.presetAmountSats = sats
                    if let sats, sats > 0 {
                        self.isAmountLocked = true
                        self.isSendMaxAmount = false
                        self.syncLockedAmountDisplay()
                    } else {
                        self.isAmountLocked = false
                    }
                }
            }
            return
        }

        if activeSpendWalletStore.isEclairActive {
            guard LNDLightningPaymentResolver.isBolt11(normalized) else {
                return
            }

            Task {
                if !eclairWalletManager.isConnected {
                    try? await eclairWalletManager.restoreActiveNode()
                }

                let decoded = try? await eclairWalletManager.decodeInvoice(normalized)
                let sats: UInt64? = {
                    guard let amountSats = decoded?.amountSats, amountSats > 0 else {
                        return nil
                    }

                    return UInt64(amountSats)
                }()

                await MainActor.run {
                    guard self.normalizedRequest == normalized else { return }

                    self.presetAmountSats = sats
                    if let sats, sats > 0 {
                        self.isAmountLocked = true
                        self.isSendMaxAmount = false
                        self.syncLockedAmountDisplay()
                    } else {
                        self.isAmountLocked = false
                    }
                }
            }
            return
        }

        if activeSpendWalletStore.isSparkSubwalletActive {
            Task {
                if !sparkSubwalletManager.isConnected {
                    try? await sparkSubwalletManager.restoreWalletIfNeeded()
                }

                let sats = await walletManager.presetAmountSatsIfBolt11(normalized)
                await MainActor.run {
                    guard self.normalizedRequest == normalized else { return }

                    self.presetAmountSats = sats
                    if let sats, sats > 0 {
                        self.isAmountLocked = true
                        self.isSendMaxAmount = false
                        self.syncLockedAmountDisplay()
                    } else {
                        self.isAmountLocked = false
                    }
                }
            }
            return
        }

        Task {
            let sats = await walletManager.presetAmountSatsIfBolt11(normalized)
            await MainActor.run {
                guard self.normalizedRequest == normalized else { return }

                self.presetAmountSats = sats
                if let sats, sats > 0 {
                    self.isAmountLocked = true
                    self.isSendMaxAmount = false
                    self.syncLockedAmountDisplay()
                } else {
                    self.isAmountLocked = false
                }
            }
        }
    }

    private func handleScannedContactPayload(_ payload: SplitContactPayload) {
        do {
            if let verifiedBinding = try payload.verifiedIdentityBindingPayload() {
                try MessageRecipientTrustStore.enforceOrPin(verifiedBinding)
            }

            statusMessage = nil
            scannedContactPayload = payload
        } catch {
            statusMessage = error.localizedDescription
            scannedContactPayload = nil
        }
    }

    private func syncLockedAmountDisplay() {
        guard let sats = presetAmountSats, sats > 0 else { return }
        let btc = Double(sats) / 100_000_000.0

        switch amountUnit {
        case .sats:
            amountText = "\(sats)"
        case .usd:
            if let rate = walletManager.btcUsdRate, rate > 0 {
                amountText = formatUSD(btc * rate)
            } else {
                amountText = "\(sats)"
            }
        }
    }

    private func applySendMaxAmount() {
        let balanceSats = activeSpendableBalanceSats
        guard balanceSats > 0 else {
            statusMessage = "No spendable balance available."
            return
        }

        dismissKeyboard()
        statusMessage = nil
        isSendMaxAmount = true
        syncSendMaxAmountDisplay()
    }

    private func syncSendMaxAmountDisplay() {
        let balanceSats = activeSpendableBalanceSats
        guard balanceSats > 0 else {
            amountText = ""
            return
        }

        switch amountUnit {
        case .sats:
            amountText = "\(balanceSats)"
        case .usd:
            let balanceBTC = Double(balanceSats) / 100_000_000.0
            if activeSpendWalletStore.isSparkActive,
               let fiatBalanceUSD = walletManager.fiatBalanceUSD,
               fiatBalanceUSD > 0 {
                amountText = formatUSD(fiatBalanceUSD)
            } else if let rate = walletManager.btcUsdRate, rate > 0 {
                amountText = formatUSD(balanceBTC * rate)
            } else {
                amountUnit = .sats
                amountText = "\(balanceSats)"
            }
        }
    }

    private var activeSpendableBalanceSats: UInt64 {
        if activeSpendWalletStore.isLndActive {
            guard let spendableSats = lndWalletManager.balanceSummary?.spendableSats,
                  spendableSats > 0 else {
                return 0
            }

            return UInt64(spendableSats)
        }

        if activeSpendWalletStore.isCoreLightningActive {
            guard let spendableSats = coreLightningWalletManager.balanceSummary?.spendableSats,
                  spendableSats > 0 else {
                return 0
            }

            return UInt64(spendableSats)
        }

        if activeSpendWalletStore.isEclairActive {
            guard let spendableSats = eclairWalletManager.balanceSummary?.spendableSats,
                  spendableSats > 0 else {
                return 0
            }

            return UInt64(spendableSats)
        }

        if activeSpendWalletStore.isSparkSubwalletActive {
            guard let spendableSats = sparkSubwalletManager.balanceSummary?.spendableSats,
                  spendableSats > 0 else {
                return 0
            }

            return spendableSats
        }

        return walletManager.balanceSats
    }

    private func normalizePaymentRequest(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("lightning:") {
            let withoutScheme = String(trimmed.dropFirst("lightning:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizePaymentRequest(from: withoutScheme) ?? withoutScheme
        }

        if isDirectLightningPaymentRequest(trimmed) {
            return trimmed
        }

        if lower.hasPrefix("bitcoin:") {
            if let components = URLComponents(string: trimmed),
               let queryItems = components.queryItems,
               let lnItem = queryItems.first(where: { $0.name.lowercased() == "lightning" }),
               let value = lnItem.value,
               !value.isEmpty {
                return normalizePaymentRequest(from: value) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return trimmed
            }
        }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            let invoiceKeys = Set(["lightning", "invoice", "bolt11", "paymentrequest", "payment_request", "pr"])
            if let value = queryItems
                .first(where: { invoiceKeys.contains($0.name.lowercased()) })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return normalizePaymentRequest(from: value) ?? value
            }
        }

        if trimmed.contains("@") && !trimmed.contains(" ") {
            return trimmed
        }

        return trimmed
    }

    private func isDirectLightningPaymentRequest(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("lnbc") ||
            lower.hasPrefix("lntb") ||
            lower.hasPrefix("lnbcrt") ||
            lower.hasPrefix("lnurl")
    }

    private func shouldOpenEntryFirstSendFlow(for paymentRequest: String) -> Bool {
        let trimmed = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if isBitcoinURIWithoutAmount(trimmed) {
            return true
        }

        if lower.hasPrefix("lnurl") {
            return true
        }

        if trimmed.contains("@") && !trimmed.contains(" ") {
            return true
        }

        return isAmountlessBolt11PaymentRequest(trimmed) || isPlainBitcoinAddress(trimmed)
    }

    private func isAmountlessBolt11PaymentRequest(_ paymentRequest: String) -> Bool {
        let lower = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard LNDLightningPaymentResolver.isBolt11(lower),
              let separatorIndex = lower.lastIndex(of: "1") else {
            return false
        }

        let humanReadablePart = String(lower[..<separatorIndex])
        let networkPrefixes = ["lnbcrt", "lnbc", "lntb"]

        guard let networkPrefix = networkPrefixes.first(where: { humanReadablePart.hasPrefix($0) }) else {
            return false
        }

        let amountPart = humanReadablePart.dropFirst(networkPrefix.count)
        return amountPart.isEmpty
    }

    private func isBitcoinURIWithoutAmount(_ paymentRequest: String) -> Bool {
        let trimmed = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bitcoin:") else {
            return false
        }

        guard let components = URLComponents(string: trimmed),
              let queryItems = components.queryItems else {
            return true
        }

        let amount = queryItems
            .first { $0.name.caseInsensitiveCompare("amount") == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !amount.isEmpty,
              let numericAmount = Decimal(string: amount),
              numericAmount > 0 else {
            return true
        }

        return false
    }

    private func isPlainBitcoinAddress(_ paymentRequest: String) -> Bool {
        let trimmed = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        guard !trimmed.contains(" "),
              !trimmed.contains(":"),
              !trimmed.contains("@") else {
            return false
        }

        if lower.hasPrefix("bc1") || lower.hasPrefix("tb1") || lower.hasPrefix("bcrt1") {
            return true
        }

        guard let first = trimmed.first else { return false }
        return first == "1" || first == "3" || first == "m" || first == "n" || first == "2"
    }

    private func continueTapped() {
        statusMessage = nil
        dismissKeyboard()

        let request = normalizedRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            statusMessage = "Enter a destination to send to."
            return
        }

        if isAmountLocked {
            preparePaymentForReview(paymentRequest: request, amountSatsOverride: nil, allowEntryFallback: false)
            return
        }

        if isSendMaxAmount {
            let balanceSats = activeSpendableBalanceSats
            guard balanceSats > 0 else {
                statusMessage = "No spendable balance available."
                return
            }

            preparePaymentForReview(
                paymentRequest: request,
                amountSatsOverride: balanceSats,
                feesIncluded: true,
                allowEntryFallback: false
            )
            return
        }

        Task {
            guard let overrideSats = await amountOverrideSatsForEntry() else { return }
            preparePaymentForReview(paymentRequest: request, amountSatsOverride: overrideSats, allowEntryFallback: false)
        }
    }

    @MainActor
    private func amountOverrideSatsForEntry() async -> UInt64? {
        let cleaned = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusMessage = "Enter an amount."
            return nil
        }

        let normalizedNumber = cleaned
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        switch amountUnit {
        case .sats:
            guard let sats = UInt64(normalizedNumber), sats > 0 else {
                statusMessage = "Enter a valid sats amount."
                return nil
            }
            return sats

        case .usd:
            guard let value = Double(normalizedNumber), value > 0 else {
                statusMessage = "Enter a valid amount."
                return nil
            }

            guard let btc = await walletManager.convertUsdToBtc(usdAmount: value), btc > 0 else {
                statusMessage = "Couldn’t convert USD to sats. Try again."
                return nil
            }

            let satsDouble = btc * 100_000_000.0
            guard satsDouble.isFinite, satsDouble > 0 else {
                statusMessage = "Enter a valid amount."
                return nil
            }

            return UInt64(max(1, Int64(satsDouble.rounded())))
        }
    }

    private func preparePaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool = false,
        allowEntryFallback: Bool
    ) {
        if activeSpendWalletStore.isLndActive {
            prepareLNDPaymentForReview(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                allowEntryFallback: allowEntryFallback
            )
            return
        }

        if activeSpendWalletStore.isNWCActive {
            prepareNWCPaymentForReview(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                allowEntryFallback: allowEntryFallback
            )
            return
        }

        if activeSpendWalletStore.isCoreLightningActive {
            prepareCoreLightningPaymentForReview(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                allowEntryFallback: allowEntryFallback
            )
            return
        }

        if activeSpendWalletStore.isEclairActive {
            prepareEclairPaymentForReview(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                allowEntryFallback: allowEntryFallback
            )
            return
        }

        if activeSpendWalletStore.isSparkSubwalletActive {
            prepareSparkSubwalletPaymentForReview(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                allowEntryFallback: allowEntryFallback
            )
            return
        }

        statusMessage = nil
        isPreparing = true

        Task {
            let resolvedLnurlComment = await resolvedLnurlComment()
            let preview = await walletManager.preparePayment(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                feesIncluded: feesIncluded,
                lnurlComment: resolvedLnurlComment
            )

            await MainActor.run {
                isPreparing = false

                if let preview {
                    if preview.amountSats == 0 && allowEntryFallback {
                        showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                    } else {
                        showReviewStage(with: preview)
                    }
                } else {
                    let lastError = walletManager.lastErrorMessage ?? "Couldn’t prepare payment."
                    if allowEntryFallback && lastError == "Enter an amount in sats." {
                        showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                    } else {
                        statusMessage = lastError
                    }
                }
            }
        }
    }

    private func prepareLNDPaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            do {
                if !lndWalletManager.isConnected {
                    try await lndWalletManager.restoreActiveNode()
                }

                if walletManager.btcUsdRate == nil {
                    await walletManager.refreshBtcUsdRate()
                }

                let trimmedRequest = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                let invoice: String

                if LNDLightningPaymentResolver.isBolt11(trimmedRequest) {
                    invoice = trimmedRequest
                } else {
                    guard let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) else {
                        await MainActor.run {
                            self.isPreparing = false
                            if allowEntryFallback {
                                self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                            } else {
                                self.statusMessage = "Enter a valid amount."
                            }
                        }
                        return
                    }

                    let resolved = try await LNDLightningPaymentResolver.resolveInvoice(
                        from: trimmedRequest,
                        amountSats: amountSats,
                        comment: await resolvedLnurlComment()
                    )
                    invoice = resolved.invoice
                }

                let decoded = try await lndWalletManager.decodeInvoice(invoice)
                let invoiceAmountSats = decoded.amountSats ?? 0
                let resolvedAmountSats: UInt64
                let lndAmountOverrideSats: Int64?

                if invoiceAmountSats > 0 {
                    resolvedAmountSats = UInt64(invoiceAmountSats)
                    lndAmountOverrideSats = nil
                } else if let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) {
                    resolvedAmountSats = amountSatsOverride
                    lndAmountOverrideSats = amountSats
                } else {
                    await MainActor.run {
                        self.isPreparing = false
                        if allowEntryFallback {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.statusMessage = "Enter an amount for this invoice."
                        }
                    }
                    return
                }

                let estimatedRouteFeeSats = await estimateLNDRouteFee(
                    destinationPubkey: decoded.destination,
                    amountSats: resolvedAmountSats
                )

                let preview = WalletManager.PaymentPreview(
                    id: UUID(),
                    backend: .lnd,
                    paymentRequest: invoice,
                    amountSats: resolvedAmountSats,
                    amountFiatUSD: fiatUSD(for: resolvedAmountSats),
                    routingFeeSats: estimatedRouteFeeSats,
                    feesIncluded: feesIncluded,
                    recipientName: decoded.description?.nilIfBlank,
                    lndAmountOverrideSats: lndAmountOverrideSats,
                    destinationPubkey: decoded.destination?.nilIfBlank,
                    paymentHash: decoded.paymentHash?.nilIfBlank
                )

                await MainActor.run {
                    self.isPreparing = false
                    self.showReviewStage(with: preview)
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func int64Sats(_ sats: UInt64) -> Int64? {
        guard sats <= UInt64(Int64.max) else { return nil }
        return Int64(sats)
    }

    private func prepareNWCPaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            do {
                if !nwcWalletManager.isConnected {
                    try await nwcWalletManager.restoreActiveWallet()
                }

                guard nwcWalletManager.connectedWallet?.capabilities?.supportsPayments != false else {
                    throw NWCWalletError.unsupportedMethod("pay_invoice")
                }

                if walletManager.btcUsdRate == nil {
                    await walletManager.refreshBtcUsdRate()
                }

                let trimmedRequest = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                let invoice: String

                if LNDLightningPaymentResolver.isBolt11(trimmedRequest) {
                    invoice = trimmedRequest
                } else {
                    guard let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) else {
                        await MainActor.run {
                            self.isPreparing = false
                            if allowEntryFallback {
                                self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                            } else {
                                self.statusMessage = "Enter a valid amount."
                            }
                        }
                        return
                    }

                    let resolved = try await LNDLightningPaymentResolver.resolveInvoice(
                        from: trimmedRequest,
                        amountSats: amountSats,
                        comment: await resolvedLnurlComment()
                    )
                    invoice = resolved.invoice
                }

                let localMetadata = NWCBolt11MetadataDecoder.decode(invoice)
                let walletMetadata = try? await nwcWalletManager.lookupInvoice(invoice)
                let sparkDecodedAmountSats = await walletManager.presetAmountSatsIfBolt11(invoice)
                let invoicePresetSats = localMetadata?.amountSats ?? sparkDecodedAmountSats ?? 0
                let resolvedAmountSats: UInt64
                let nwcAmountOverrideSats: Int64?

                if invoicePresetSats > 0 {
                    resolvedAmountSats = invoicePresetSats
                    nwcAmountOverrideSats = nil
                } else if let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) {
                    resolvedAmountSats = amountSatsOverride
                    nwcAmountOverrideSats = amountSats
                } else {
                    await MainActor.run {
                        self.isPreparing = false
                        if allowEntryFallback {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.statusMessage = "Enter an amount for this invoice."
                        }
                    }
                    return
                }

                guard localMetadata?.destinationPubkey?.nilIfBlank != nil,
                      (walletMetadata?.paymentHash?.nilIfBlank ?? localMetadata?.paymentHash?.nilIfBlank) != nil else {
                    throw NWCWalletError.rewardsMetadataUnavailable
                }

                let preview = WalletManager.PaymentPreview(
                    id: UUID(),
                    backend: .nwc,
                    paymentRequest: invoice,
                    amountSats: resolvedAmountSats,
                    amountFiatUSD: fiatUSD(for: resolvedAmountSats),
                    routingFeeSats: walletMetadata?.feesPaidSats.flatMap { $0 >= 0 ? UInt64($0) : nil },
                    feesIncluded: feesIncluded,
                    recipientName: walletMetadata?.description?.nilIfBlank ?? localMetadata?.description?.nilIfBlank,
                    lndAmountOverrideSats: nwcAmountOverrideSats,
                    destinationPubkey: localMetadata?.destinationPubkey?.nilIfBlank,
                    paymentHash: walletMetadata?.paymentHash?.nilIfBlank ?? localMetadata?.paymentHash?.nilIfBlank
                )

                await MainActor.run {
                    self.isPreparing = false
                    self.showReviewStage(with: preview)
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func estimateLNDRouteFee(
        destinationPubkey: String?,
        amountSats: UInt64
    ) async -> UInt64? {
        guard let destinationPubkey = destinationPubkey?.nilIfBlank,
              let amountSats = int64Sats(amountSats) else {
            return nil
        }

        do {
            let estimatedFeeSats = try await lndWalletManager.estimateRouteFee(
                destinationPubkey: destinationPubkey,
                amountSats: amountSats
            )

            guard estimatedFeeSats >= 0 else { return nil }
            return UInt64(estimatedFeeSats)
        } catch {
            return nil
        }
    }

    private func prepareCoreLightningPaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            do {
                if !coreLightningWalletManager.isConnected {
                    try await coreLightningWalletManager.restoreActiveNode()
                }

                if walletManager.btcUsdRate == nil {
                    await walletManager.refreshBtcUsdRate()
                }

                let trimmedRequest = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                let invoice: String

                if LNDLightningPaymentResolver.isBolt11(trimmedRequest) {
                    invoice = trimmedRequest
                } else {
                    guard let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) else {
                        await MainActor.run {
                            self.isPreparing = false
                            if allowEntryFallback {
                                self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                            } else {
                                self.statusMessage = "Enter a valid amount."
                            }
                        }
                        return
                    }

                    let resolved = try await LNDLightningPaymentResolver.resolveInvoice(
                        from: trimmedRequest,
                        amountSats: amountSats,
                        comment: await resolvedLnurlComment()
                    )
                    invoice = resolved.invoice
                }

                let decoded = try await coreLightningWalletManager.decodeInvoice(invoice)
                let invoiceAmountSats = decoded.amountSats ?? 0
                let resolvedAmountSats: UInt64
                let amountOverrideSats: Int64?

                if invoiceAmountSats > 0 {
                    resolvedAmountSats = UInt64(invoiceAmountSats)
                    amountOverrideSats = nil
                } else if let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) {
                    resolvedAmountSats = amountSatsOverride
                    amountOverrideSats = amountSats
                } else {
                    await MainActor.run {
                        self.isPreparing = false
                        if allowEntryFallback {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.statusMessage = "Enter an amount for this invoice."
                        }
                    }
                    return
                }

                let preview = WalletManager.PaymentPreview(
                    id: UUID(),
                    backend: .coreLightning,
                    paymentRequest: invoice,
                    amountSats: resolvedAmountSats,
                    amountFiatUSD: fiatUSD(for: resolvedAmountSats),
                    routingFeeSats: nil,
                    feesIncluded: feesIncluded,
                    recipientName: decoded.description?.nilIfBlank,
                    lndAmountOverrideSats: amountOverrideSats,
                    destinationPubkey: decoded.payee?.nilIfBlank,
                    paymentHash: decoded.paymentHash?.nilIfBlank
                )

                await MainActor.run {
                    self.isPreparing = false
                    self.showReviewStage(with: preview)
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareEclairPaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            do {
                if !eclairWalletManager.isConnected {
                    try await eclairWalletManager.restoreActiveNode()
                }

                if walletManager.btcUsdRate == nil {
                    await walletManager.refreshBtcUsdRate()
                }

                let trimmedRequest = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                let invoice: String

                if LNDLightningPaymentResolver.isBolt11(trimmedRequest) {
                    invoice = trimmedRequest
                } else {
                    guard let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) else {
                        await MainActor.run {
                            self.isPreparing = false
                            if allowEntryFallback {
                                self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                            } else {
                                self.statusMessage = "Enter a valid amount."
                            }
                        }
                        return
                    }

                    let resolved = try await LNDLightningPaymentResolver.resolveInvoice(
                        from: trimmedRequest,
                        amountSats: amountSats,
                        comment: await resolvedLnurlComment()
                    )
                    invoice = resolved.invoice
                }

                let decoded = try await eclairWalletManager.decodeInvoice(invoice)
                let invoiceAmountSats = decoded.amountSats ?? 0
                let resolvedAmountSats: UInt64
                let amountOverrideSats: Int64?

                if invoiceAmountSats > 0 {
                    resolvedAmountSats = UInt64(invoiceAmountSats)
                    amountOverrideSats = nil
                } else if let amountSatsOverride,
                          amountSatsOverride > 0,
                          let amountSats = int64Sats(amountSatsOverride) {
                    resolvedAmountSats = amountSatsOverride
                    amountOverrideSats = amountSats
                } else {
                    await MainActor.run {
                        self.isPreparing = false
                        if allowEntryFallback {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.statusMessage = "Enter an amount for this invoice."
                        }
                    }
                    return
                }

                let preview = WalletManager.PaymentPreview(
                    id: UUID(),
                    backend: .eclair,
                    paymentRequest: invoice,
                    amountSats: resolvedAmountSats,
                    amountFiatUSD: fiatUSD(for: resolvedAmountSats),
                    routingFeeSats: nil,
                    feesIncluded: feesIncluded,
                    recipientName: decoded.description?.nilIfBlank,
                    lndAmountOverrideSats: amountOverrideSats,
                    destinationPubkey: decoded.nodeId?.nilIfBlank,
                    paymentHash: decoded.paymentHash?.nilIfBlank
                )

                await MainActor.run {
                    self.isPreparing = false
                    self.showReviewStage(with: preview)
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareSparkSubwalletPaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        feesIncluded: Bool,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            do {
                if !sparkSubwalletManager.isConnected {
                    try await sparkSubwalletManager.restoreWalletIfNeeded()
                }

                if walletManager.btcUsdRate == nil {
                    await walletManager.refreshBtcUsdRate()
                }

                let resolvedLnurlComment = await resolvedLnurlComment()
                let preview = await sparkSubwalletManager.preparePayment(
                    paymentRequest: paymentRequest,
                    amountSatsOverride: amountSatsOverride,
                    feesIncluded: feesIncluded,
                    lnurlComment: resolvedLnurlComment,
                    btcUsdRate: walletManager.btcUsdRate
                )

                await MainActor.run {
                    self.isPreparing = false

                    if let preview {
                        if preview.amountSats == 0 && allowEntryFallback {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.showReviewStage(with: preview)
                        }
                    } else {
                        let lastError = sparkSubwalletManager.lastErrorMessage ?? "Couldn’t prepare payment."
                        if allowEntryFallback && lastError == "Enter an amount in sats." {
                            self.showEntryStage(with: paymentRequest, resetAmount: true, focusedField: .amount)
                        } else {
                            self.statusMessage = lastError
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolvedLnurlComment() async -> String? {
        prefilledLnurlComment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private func fiatUSD(for sats: UInt64) -> Double? {
        guard let rate = walletManager.btcUsdRate, rate > 0, sats > 0 else {
            return nil
        }

        return (Double(sats) / 100_000_000.0) * rate
    }

    private func formatUSD(_ usd: Double) -> String {
        String(format: "%.2f", usd)
    }
}

private struct SendContactPickerSheet: View {
    let contacts: [WalletManager.WalletContact]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (WalletManager.WalletContact) -> Void
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading contacts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.72))
                        }
                    } else if let errorMessage {
                        VStack(spacing: 14) {
                            Text("Unable to load contacts")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                            Button("Try Again", action: onRetry)
                                .buttonStyle(.borderedProminent)
                                .tint(Color.splitBrandPink)
                        }
                        .padding(24)
                    } else if contacts.isEmpty {
                        VStack(spacing: 8) {
                            Text("No contacts yet")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Saved contacts will appear here.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.68))
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(contacts) { contact in
                                    Button {
                                        onSelect(contact)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(Color.splitBrandPink.opacity(0.24))
                                                .frame(width: 34, height: 34)
                                                .overlay(
                                                    Text(contact.name.prefix(1).uppercased())
                                                        .font(.subheadline.weight(.bold))
                                                        .foregroundColor(.white)
                                                )

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(contact.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(contact.paymentIdentifier)
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.58))
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            Spacer()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
