//
//  LightningConnectionsView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import SwiftUI

struct LightningConnectionsView: View {
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue

    @State private var wallets: [ExternalWalletRecord] = []
    @State private var showAddWallet = false
    @State private var selectedWallet: ExternalWalletRecord?

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if wallets.isEmpty {
                            emptyState
                        } else {
                            ForEach(wallets) { wallet in
                                walletCard(wallet)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }

                addWalletButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .navigationTitle("Lightning")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshWallets)
        .fullScreenCover(isPresented: $showAddWallet, onDismiss: refreshWallets) {
            NavigationStack {
                AddLightningWalletView(onWalletAdded: {
                    showAddWallet = false
                    refreshWallets()
                })
            }
            .environmentObject(eclairWalletManager)
            .environmentObject(sparkSubwalletManager)
        }
        .fullScreenCover(item: $selectedWallet, onDismiss: refreshWallets) { wallet in
            LightningWalletDetailView(
                wallet: wallet,
                onWalletChanged: refreshWallets
            )
            .environmentObject(lndWalletManager)
            .environmentObject(nwcWalletManager)
            .environmentObject(coreLightningWalletManager)
            .environmentObject(eclairWalletManager)
            .environmentObject(sparkSubwalletManager)
            .environmentObject(activeSpendWalletStore)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lightning Wallets")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("Manage external Lightning wallets and nodes.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        Text("Connect any Lightning node or wallet.")
            .font(.headline.weight(.semibold))
            .foregroundColor(.white.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var addWalletButton: some View {
        Button {
            showAddWallet = true
        } label: {
            HStack(spacing: 12) {
                Text("Add Wallet")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)

                Image(systemName: "plus.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(blue)

                Spacer()
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func walletCard(_ wallet: ExternalWalletRecord) -> some View {
        Button {
            selectedWallet = wallet
        } label: {
            HStack(spacing: 14) {
                walletIcon(for: wallet.kind)

                VStack(alignment: .leading, spacing: 4) {
                    Text(wallet.label)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(wallet.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func walletIcon(for kind: ExternalWalletKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)

            switch kind {
            case .lnd, .coreLightning, .eclair, .sparkSubwallet:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(blue)
            case .nwc:
                NWCSymbol()
                    .frame(width: 32, height: 32)
            }
        }
        .frame(width: 50, height: 50)
    }

    private func refreshWallets() {
        wallets = ExternalWalletStore.shared.loadWallets()
    }
}

private struct AddLightningWalletView: View {
    @Environment(\.dismiss) private var dismiss

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    let onWalletAdded: () -> Void

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    connectionCard(
                        icon: {
                            NWCSymbol()
                                .frame(width: 30, height: 30)
                        },
                        title: "NWC Wallet or Node",
                        subtitle: "Connect an NWC-compatible Lightning wallet or node",
                        destination: NostrWalletConnectSettingsView(showsDismissButton: false, showsSavedWallets: false, onWalletAdded: onWalletAdded)
                    )

                    connectionCard(
                        icon: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(blue)
                        },
                        title: "LND Lightning Node",
                        subtitle: "Connect an LND lightning node",
                        destination: LightningNodeSettingsView(showsDismissButton: false, showsSavedWallets: false, onWalletAdded: onWalletAdded)
                    )

                    connectionCard(
                        icon: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(blue)
                        },
                        title: "Core Lightning Node",
                        subtitle: "Connect a Core Lightning node using REST",
                        destination: CoreLightningSettingsView(showsDismissButton: false, showsSavedWallets: false, onWalletAdded: onWalletAdded)
                    )

                    connectionCard(
                        icon: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(blue)
                        },
                        title: "Eclair Node",
                        subtitle: "Connect an Eclair node using its API",
                        destination: EclairSettingsView(showsDismissButton: false, showsSavedWallets: false, onWalletAdded: onWalletAdded)
                    )

                    connectionCard(
                        icon: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(blue)
                        },
                        title: "Spark Wallet",
                        subtitle: "Create or load a Spark wallet as a sub-wallet",
                        destination: SparkSubwalletSetupView(onWalletAdded: onWalletAdded)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Add Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Wallet")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("Choose how you want to connect a Lightning wallet or node.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionCard<Icon: View, Destination: View>(
        @ViewBuilder icon: @escaping () -> Icon,
        title: String,
        subtitle: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    icon()
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct LightningWalletDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    let wallet: ExternalWalletRecord
    let onWalletChanged: () -> Void

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let pink = Color.splitBrandPink

    @State private var name: String
    @State private var draftName: String
    @State private var isEditingName = false
    @State private var showDeleteConfirmation = false

    init(wallet: ExternalWalletRecord, onWalletChanged: @escaping () -> Void) {
        self.wallet = wallet
        self.onWalletChanged = onWalletChanged
        _name = State(initialValue: wallet.label)
        _draftName = State(initialValue: wallet.label)
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                walletDetails

                Spacer(minLength: 0)

                deleteButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete Wallet?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWallet()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("Wallet name", text: $draftName)
                            .textInputAutocapitalization(.words)
                            .foregroundColor(.white)
                            .font(.system(size: 28, weight: .bold))
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text(name)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }

                    Button {
                        if isEditingName {
                            saveName()
                        } else {
                            draftName = name
                            isEditingName = true
                        }
                    } label: {
                        Image(systemName: isEditingName ? "checkmark" : "pencil")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .disabled(isEditingName && draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(isEditingName ? "Save wallet name" : "Edit wallet name")
                }

                if isEditingName {
                    Button("Cancel") {
                        draftName = name
                        isEditingName = false
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.70))
                }

                Text(wallet.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.60))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var walletDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            detailRow("Wallet Name", value: name)
            detailRow(pubkeyTitle, value: abbreviated(pubkey))
            detailRow(hostTitle, value: host)
            if let transportLabel {
                detailRow("Connection", value: transportLabel)
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

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .font(.headline.weight(.bold))

                Text("Delete Wallet")
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(pink)
            )
        }
    }

    private var pubkey: String? {
        switch wallet.payload {
        case let .lnd(node):
            return node.nodePubkey
        case let .nwc(nwcWallet):
            return nwcWallet.walletPubkey
        case let .coreLightning(node):
            return node.nodeId
        case let .eclair(node):
            return node.nodeId
        case let .sparkSubwallet(wallet):
            return wallet.identityPubkey
        }
    }

    private var pubkeyTitle: String {
        switch wallet.kind {
        case .nwc:
            return "Wallet Pubkey"
        case .lnd, .coreLightning, .eclair, .sparkSubwallet:
            return "Node Pubkey"
        }
    }

    private var hostTitle: String {
        switch wallet.kind {
        case .nwc:
            return "Relay"
        case .lnd, .coreLightning, .eclair:
            return "Host"
        case .sparkSubwallet:
            return "Address"
        }
    }

    private var host: String {
        switch wallet.payload {
        case let .lnd(node):
            return "\(node.host):\(node.port)"
        case let .nwc(nwcWallet):
            return nwcWallet.primaryRelayHost
        case let .coreLightning(node):
            return "\(node.scheme)://\(node.host):\(node.port)"
        case let .eclair(node):
            return "\(node.scheme)://\(node.host):\(node.port)"
        case let .sparkSubwallet(wallet):
            return wallet.sparkAddress ?? "Not available"
        }
    }

    private var transportLabel: String? {
        switch wallet.payload {
        case let .lnd(node):
            return node.usesTor ? "Tor" : "Direct"
        case let .coreLightning(node):
            return node.usesTor ? "Tor" : "Direct"
        case let .eclair(node):
            return node.usesTor ? "Tor" : "Direct"
        case let .nwc(nwcWallet):
            return nwcWallet.usesTor ? "Tor" : "Direct"
        case .sparkSubwallet:
            return nil
        }
    }

    private var deleteConfirmationMessage: String {
        if wallet.kind == .sparkSubwallet {
            return "This removes \(name), its local seed, and its local wallet data from this device. You must have the recovery phrase to restore funds."
        }

        return "This removes \(name) from this device."
    }

    private func detailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.58))

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch wallet.kind {
        case .lnd:
            lndWalletManager.renameNode(id: wallet.id, label: trimmed)
        case .nwc:
            nwcWalletManager.renameWallet(id: wallet.id, label: trimmed)
        case .coreLightning:
            coreLightningWalletManager.renameNode(id: wallet.id, label: trimmed)
        case .eclair:
            eclairWalletManager.renameNode(id: wallet.id, label: trimmed)
        case .sparkSubwallet:
            sparkSubwalletManager.renameWallet(id: wallet.id, label: trimmed)
        }

        name = trimmed
        isEditingName = false
        onWalletChanged()
    }

    private func deleteWallet() {
        switch wallet.kind {
        case .lnd:
            lndWalletManager.forgetNode(id: wallet.id)
        case .nwc:
            nwcWalletManager.forgetWallet(id: wallet.id)
        case .coreLightning:
            coreLightningWalletManager.forgetNode(id: wallet.id)
        case .eclair:
            eclairWalletManager.forgetNode(id: wallet.id)
        case .sparkSubwallet:
            sparkSubwalletManager.forgetWallet(id: wallet.id)
        }

        activeSpendWalletStore.reconcileWithStoredWallets()
        onWalletChanged()
        dismiss()
    }

    private func abbreviated(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "Not available"
        }

        guard value.count > 18 else {
            return value
        }

        return "\(value.prefix(10))...\(value.suffix(8))"
    }
}
