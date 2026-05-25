//
//  LightningNodeSettingsView.swift
//  Split Rewards
//
//  Created by TeeVee on 4/21/26.
//

import SwiftUI

struct LightningNodeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    let showsDismissButton: Bool
    let showsSavedWallets: Bool
    let onWalletAdded: (() -> Void)?

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var lndConnectString = ""
    @State private var walletName = ""
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var isScanningQRCode = false
    @State private var statusMessage: String?
    @State private var renamingNode: LNDNodeCredentials?
    @State private var renameText = ""
    @State private var connectedNodeConfirmation: LNDNodeCredentials?

    init(showsDismissButton: Bool = false, showsSavedWallets: Bool = true, onWalletAdded: (() -> Void)? = nil) {
        self.showsDismissButton = showsDismissButton
        self.showsSavedWallets = showsSavedWallets
        self.onWalletAdded = onWalletAdded
    }

    private var hasStoredNode: Bool {
        !lndWalletManager.storedNodes().isEmpty
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
        .navigationTitle("Lightning Node")
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
            Text("Lightning Node")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text(showsSavedWallets && hasStoredNode ? "Manage your connection" : "Connect a lightning node to Split")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            lndCompatibilityCopy

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
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(blue)
                )
            }
            .disabled(isConnecting)

            Text("LND Connect")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            TextField("lndconnect://", text: $lndConnectString, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(4...8)
                .foregroundColor(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )

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
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canConnect ? blue : Color.white.opacity(0.14))
                )
            }
            .disabled(!canConnect)
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func successContent(for node: LNDNodeCredentials) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("LND node connected")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(node.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }

            nodeDetailRow("Node Pubkey", value: abbreviated(node.nodePubkey))
            nodeDetailRow("Host", value: "\(node.host):\(node.port)")
            nodeDetailRow("Connection", value: node.usesTor ? "Tor" : "Direct")

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
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var lndCompatibilityCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.headline)
                    .foregroundColor(blue)

                Text("Before You Connect")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            Text("Split currently supports LND nodes using an LND Connect QR or lndconnect:// string.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                compatibilityRow(
                    icon: "network",
                    text: "Use a private LAN or VPN hostname/IP, a .local hostname, a Tailscale .ts.net host, or a Tor .onion service."
                )
                compatibilityRow(
                    icon: "lock.shield.fill",
                    text: "Clearnet connections must resolve privately. Tor .onion connections are routed through Tor."
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
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
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

            ForEach(lndWalletManager.storedNodes()) { node in
                savedNodeRow(node)
            }
        }
    }

    private func savedNodeRow(_ node: LNDNodeCredentials) -> some View {
        let isActive = (lndWalletManager.connectedNode ?? LNDCredentialStore.shared.activeNode())?.id == node.id

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

            nodeDetailRow("Node Pubkey", value: abbreviated(node.nodePubkey))
            nodeDetailRow("Host", value: "\(node.host):\(node.port)")

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
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var nodeSummaryCard: some View {
        let node = lndWalletManager.connectedNode ?? LNDCredentialStore.shared.activeNode()

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
                    Text(node?.displayName ?? "Lightning Node")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            nodeDetailRow("Node Pubkey", value: abbreviated(node?.nodePubkey))
            nodeDetailRow("Host", value: node.map { "\($0.host):\($0.port)" } ?? "Not available")

            if let balanceSummary = lndWalletManager.balanceSummary {
                nodeDetailRow("Channel Balance", value: "\(balanceSummary.spendableSats) sats")
                nodeDetailRow("On-chain Balance", value: "\(balanceSummary.onChainBalanceSats) sats")
            }
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var canConnect: Bool {
        !isConnecting
        && !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !lndConnectString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch lndWalletManager.state {
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
        let normalizedHost = (try? LNDConnectParser.parse(lndConnectString).host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedHost?.hasSuffix(".onion") == true {
            return "Starting Tor"
        }

        return "Connecting"
    }

    private func nodeDetailRow(_ title: String, value: String) -> some View {
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
        guard LNDCredentialStore.shared.activeNode() != nil else { return }

        do {
            try await lndWalletManager.restoreActiveNode()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connectNode() async {
        await connectNode(using: lndConnectString)
    }

    private func connectNode(using rawLndConnectString: String) async {
        let normalized = rawLndConnectString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            statusMessage = "Enter an LND Connect string."
            return
        }

        let label = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            statusMessage = "Name this wallet before connecting."
            return
        }

        isConnecting = true
        statusMessage = usesTor(rawLndConnectString: normalized) ? "Starting Tor..." : "Checking LND node..."

        do {
            let node = try await lndWalletManager.connect(lndConnectString: normalized, label: label)
            statusMessage = "Saving wallet..."
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .lnd, id: node.id)
            lndConnectString = ""
            walletName = ""
            connectedNodeConfirmation = node
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func refreshConnection() async {
        isRefreshing = true
        statusMessage = nil

        do {
            _ = try await lndWalletManager.refreshNodeInfo()
            _ = try await lndWalletManager.refreshBalance()
            statusMessage = "Connection refreshed"
        } catch {
            statusMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    private func forgetNode(_ node: LNDNodeCredentials) {
        lndWalletManager.forgetNode(id: node.id)
        activeSpendWalletStore.reconcileWithStoredNode()
        statusMessage = nil
    }

    private func selectNode(_ node: LNDNodeCredentials) async {
        do {
            try await lndWalletManager.setActiveStoredNode(id: node.id)
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .lnd, id: node.id)
            _ = try? await lndWalletManager.refreshBalance()
            statusMessage = "Selected \(node.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func renameNode(_ node: LNDNodeCredentials) {
        lndWalletManager.renameNode(id: node.id, label: renameText)
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

        guard normalized.lowercased().hasPrefix("lndconnect://") else {
            isScanningQRCode = false
            statusMessage = "Scan an LND Connect QR code."
            return
        }

        lndConnectString = normalized
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

    private func usesTor(rawLndConnectString: String) -> Bool {
        (try? LNDConnectParser.parse(rawLndConnectString).host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasSuffix(".onion") == true
    }
}

#Preview {
    NavigationStack {
        LightningNodeSettingsView()
            .environmentObject(LNDWalletManager())
            .environmentObject(ActiveSpendWalletStore())
    }
}
