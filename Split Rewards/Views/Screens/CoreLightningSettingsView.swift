//
//  CoreLightningSettingsView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/9/26.
//

import SwiftUI

struct CoreLightningSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    let showsDismissButton: Bool
    let showsSavedWallets: Bool
    let onWalletAdded: (() -> Void)?

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var connectionString = ""
    @State private var walletName = ""
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var isScanningQRCode = false
    @State private var statusMessage: String?
    @State private var renamingNode: CoreLightningNodeCredentials?
    @State private var renameText = ""
    @State private var connectedNodeConfirmation: CoreLightningNodeCredentials?

    init(showsDismissButton: Bool = false, showsSavedWallets: Bool = true, onWalletAdded: (() -> Void)? = nil) {
        self.showsDismissButton = showsDismissButton
        self.showsSavedWallets = showsSavedWallets
        self.onWalletAdded = onWalletAdded
    }

    private var hasStoredNode: Bool {
        !coreLightningWalletManager.storedNodes().isEmpty
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            if isScanningQRCode {
                scannerContent
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if showsSavedWallets && hasStoredNode {
                            connectedContent
                        }

                        if let connectedNodeConfirmation, !showsSavedWallets {
                            successContent(for: connectedNodeConfirmation)
                        } else {
                            connectContent
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white.opacity(0.70))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("Core Lightning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .sheet(item: $renamingNode) { node in
            RenameExternalWalletSheet(
                title: "Rename Wallet",
                initialName: node.displayName,
                text: $renameText,
                onSave: {
                    renameNode(node)
                }
            )
            .presentationDetents([.fraction(0.32)])
            .presentationDragIndicator(.visible)
        }
        .task {
            if showsSavedWallets {
                await restoreNodeIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Core Lightning")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text(showsSavedWallets && hasStoredNode ? "Manage your REST connection" : "Connect a Core Lightning node to Split")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            compatibilityCopy

            walletNameField

            Button(action: openQRScanner) {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.headline)

                    Text("Scan QR Code")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(blue))
            }
            .disabled(isConnecting)

            Text("Core Lightning REST Connection")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            TextField("clnrest+https://", text: $connectionString, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(4...8)
                .foregroundColor(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))

            Button(action: {
                Task { await connectNode() }
            }) {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.headline)
                    }

                    Text(isConnecting ? connectingStatusText : "Connect Node")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(canConnect ? blue : Color.white.opacity(0.14)))
            }
            .disabled(!canConnect)
        }
        .padding(16)
        .background(cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func successContent(for node: CoreLightningNodeCredentials) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Core Lightning node connected")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(node.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }

            detailRow("Node ID", value: abbreviated(node.nodeId))
            detailRow("Host", value: "\(node.host):\(node.port)")
            detailRow("Connection", value: node.usesTor ? "Tor" : "Direct")

            Button {
                onWalletAdded?()
            } label: {
                Text("Done")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(blue))
            }

            Button {
                connectedNodeConfirmation = nil
                statusMessage = nil
            } label: {
                Text("Connect another")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var compatibilityCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.headline)
                    .foregroundColor(blue)

                Text("Before You Connect")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            Text("Split supports Core Lightning nodes using CLN REST connection details from your node.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                compatibilityRow(
                    icon: "network",
                    text: "Use a private LAN or VPN hostname/IP, a .local hostname, a Tailscale .ts.net host, or a Tor .onion service."
                )
                compatibilityRow(
                    icon: "key.fill",
                    text: "Your rune stays in this device's keychain."
                )
                compatibilityRow(
                    icon: "checkmark.seal.fill",
                    text: "Split uses REST for node info, balance, invoices, payments, and history."
                )
            }
        }
    }

    private var walletNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Name")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            TextField("Required", text: $walletName)
                .textInputAutocapitalization(.words)
                .foregroundColor(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
        }
    }

    private func compatibilityRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 18, height: 18)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scannerContent: some View {
        ZStack(alignment: .topLeading) {
            QRCodeScannerView(preferredZoomFactor: 1.6, onCodeScanned: handleScannedCode)
                .ignoresSafeArea()

            Button(action: closeQRScanner) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close scanner")
            .padding(.top, 14)
            .padding(.leading, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved Nodes")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            ForEach(coreLightningWalletManager.storedNodes()) { node in
                savedNodeRow(node)
            }
        }
    }

    private func savedNodeRow(_ node: CoreLightningNodeCredentials) -> some View {
        let isActive = (coreLightningWalletManager.connectedNode ?? CoreLightningCredentialStore.shared.activeNode())?.id == node.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(blue)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(isActive ? statusText : "Saved on this device")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(pink)
                }
            }

            detailRow("Node ID", value: abbreviated(node.nodeId))
            detailRow("Host", value: "\(node.host):\(node.port)")

            HStack(spacing: 10) {
                Button {
                    Task { await selectNode(node) }
                } label: {
                    Text(isActive ? "Selected" : "Use")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(blue.opacity(isActive ? 0.45 : 1)))
                }
                .disabled(isActive)

                Button {
                    renameText = node.displayName
                    renamingNode = node
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                }

                Button(role: .destructive) {
                    forgetNode(node)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pink))
                }
            }
        }
        .padding(16)
        .background(cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var canConnect: Bool {
        !isConnecting
        && !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !connectionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch coreLightningWalletManager.state {
        case .ready:
            return "Connected"
        case .connecting:
            return connectingStatusText
        case .error:
            return "Needs attention"
        case .disconnected:
            return "Saved on this device"
        }
    }

    private var connectingStatusText: String {
        let normalizedHost = (try? CoreLightningConnectParser.parse(connectionString).host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedHost?.hasSuffix(".onion") == true {
            return "Starting Tor"
        }

        return "Connecting"
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.58))

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func restoreNodeIfNeeded() async {
        guard CoreLightningCredentialStore.shared.activeNode() != nil else { return }

        do {
            try await coreLightningWalletManager.restoreActiveNode()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connectNode() async {
        await connectNode(using: connectionString)
    }

    private func connectNode(using rawConnectionString: String) async {
        let normalized = rawConnectionString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            statusMessage = "Enter a Core Lightning REST connection string."
            return
        }

        let label = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            statusMessage = "Name this wallet before connecting."
            return
        }

        isConnecting = true
        statusMessage = usesTor(rawConnectionString: normalized) ? "Starting Tor..." : "Checking Core Lightning node..."

        do {
            let node = try await coreLightningWalletManager.connect(connectionString: normalized, label: label)
            statusMessage = "Saving wallet..."
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .coreLightning, id: node.id)
            connectionString = ""
            walletName = ""
            connectedNodeConfirmation = node
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func forgetNode(_ node: CoreLightningNodeCredentials) {
        coreLightningWalletManager.forgetNode(id: node.id)
        activeSpendWalletStore.reconcileWithStoredWallets()
        statusMessage = nil
    }

    private func selectNode(_ node: CoreLightningNodeCredentials) async {
        do {
            try await coreLightningWalletManager.setActiveStoredNode(id: node.id)
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .coreLightning, id: node.id)
            _ = try? await coreLightningWalletManager.refreshBalance()
            statusMessage = "Selected \(node.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func renameNode(_ node: CoreLightningNodeCredentials) {
        coreLightningWalletManager.renameNode(id: node.id, label: renameText)
        renamingNode = nil
        renameText = ""
    }

    private func openQRScanner() {
        statusMessage = nil
        isScanningQRCode = true
    }

    private func closeQRScanner() {
        isScanningQRCode = false
    }

    private func handleScannedCode(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionString = normalized
        isScanningQRCode = false

        if walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = "Name this wallet, then connect."
        } else {
            Task {
                await connectNode(using: normalized)
            }
        }
    }

    private func abbreviated(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "Not available"
        }

        guard value.count > 14 else {
            return value
        }

        let prefix = value.prefix(8)
        let suffix = value.suffix(6)
        return "\(prefix)...\(suffix)"
    }

    private func usesTor(rawConnectionString: String) -> Bool {
        (try? CoreLightningConnectParser.parse(rawConnectionString).host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasSuffix(".onion") == true
    }
}

#Preview {
    NavigationStack {
        CoreLightningSettingsView()
            .environmentObject(CoreLightningWalletManager())
            .environmentObject(ActiveSpendWalletStore())
    }
}
